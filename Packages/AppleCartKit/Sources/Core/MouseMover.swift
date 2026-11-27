import CoreGraphics
import Foundation
import Observation

/// Reads and moves the pointer. The real one uses Quartz; tests use a fake.
/// Coordinates are global display points with the origin at the top left of the main display.
@MainActor
public protocol PointerDriver: AnyObject {
    var location: CGPoint { get }
    func warp(to point: CGPoint)
    /// Bounds of each active display.
    func displays() -> [CGRect]
    /// Seconds since the last key press, click or pointer move from real hardware (moves made by `warp` don't count).
    func secondsSinceInput() -> TimeInterval
}

public struct MouseMoverOptions: Sendable, Equatable {
    public enum Speed: String, CaseIterable, Sendable {
        case slow, medium, fast
        public var title: String { rawValue.capitalized }
        /// Points per second.
        public var pointsPerSecond: Double {
            switch self {
            case .slow: 80
            case .medium: 160
            case .fast: 320
            }
        }
    }

    /// Starts by itself after this many idle minutes; nil means only the Start button starts it.
    public var idleMinutes: Int?
    public var speed: Speed
    /// Black windows over every screen while it moves, so nothing static stays lit.
    public var blackout: Bool

    public init(idleMinutes: Int? = 5, speed: Speed = .medium, blackout: Bool = true) {
        self.idleMinutes = idleMinutes; self.speed = speed; self.blackout = blackout
    }

    public static let idleChoices = [0, 2, 5, 10, 15, 30] // 0 = never by itself
    public static let defaultIdleMinutes = 5

    public static func stored(_ defaults: UserDefaults = .standard) -> MouseMoverOptions {
        let idle = defaults.object(forKey: "mouseMover.idleMinutes") as? Int ?? defaultIdleMinutes
        return .init(idleMinutes: idle > 0 ? idle : nil,
                     speed: defaults.string(forKey: "mouseMover.speed").flatMap(Speed.init(rawValue:)) ?? .medium,
                     blackout: defaults.object(forKey: "mouseMover.blackout") as? Bool ?? true)
    }
}

/// A ball bouncing inside a rectangle: the path the pointer takes.
public enum BouncePath {
    public static func step(_ p: CGPoint, _ v: CGVector, in r: CGRect, dt: Double) -> (CGPoint, CGVector) {
        var x = p.x + v.dx * dt, y = p.y + v.dy * dt, dx = v.dx, dy = v.dy
        if x < r.minX { x = 2 * r.minX - x; dx = abs(dx) }
        if x > r.maxX { x = 2 * r.maxX - x; dx = -abs(dx) }
        if y < r.minY { y = 2 * r.minY - y; dy = abs(dy) }
        if y > r.maxY { y = 2 * r.maxY - y; dy = -abs(dy) }
        return (CGPoint(x: min(max(x, r.minX), r.maxX), y: min(max(y, r.minY), r.maxY)), CGVector(dx: dx, dy: dy))
    }

    /// Where the pointer may go on a display: a few points in from the edges, so it never pushes into the Dock or a hot corner.
    public static func area(_ display: CGRect) -> CGRect { display.insetBy(dx: 4, dy: 4) }
}

/// Moves the pointer around the screen like a screensaver, optionally over a black screen, to spread wear on the pixels.
/// Starts from the panel or after the Mac has been idle for a while. Any real key press, click or pointer move ends it.
@MainActor @Observable
public final class MouseMover {
    public enum Phase: Equatable { case off, waiting, countdown(until: Date), moving }

    public static let countdownSeconds: TimeInterval = 3
    /// Seconds on one display before moving to the next.
    public static let secondsPerDisplay: TimeInterval = 30

    public private(set) var phase: Phase = .off
    public private(set) var lastStopReason: String?
    public var isMoving: Bool { phase == .moving }
    /// Overlay windows follow this. The Bool is true while moving with the black screen on.
    @ObservationIgnored public var onBlackoutChange: (@MainActor (Bool) -> Void)?

    @ObservationIgnored private let driver: PointerDriver
    @ObservationIgnored private let options: @MainActor () -> MouseMoverOptions
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let tick: Duration
    @ObservationIgnored private let watchEvery: Duration
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var blackedOut = false
    @ObservationIgnored private var watchedIdle: Int?
    // Moving state
    @ObservationIgnored private var displays: [CGRect] = []
    @ObservationIgnored private var displayIndex = 0
    @ObservationIgnored private var onDisplaySince = Date.distantPast
    @ObservationIgnored private var startedAt = Date.distantPast
    @ObservationIgnored private var lastStep = Date.distantPast
    @ObservationIgnored private var position = CGPoint.zero
    @ObservationIgnored private var velocity = CGVector.zero

    public init(driver: PointerDriver,
                options: @escaping @MainActor () -> MouseMoverOptions = { .stored() },
                now: @escaping () -> Date = Date.init,
                tick: Duration = .milliseconds(16),
                watchEvery: Duration = .seconds(5)) {
        self.driver = driver; self.options = options; self.now = now; self.tick = tick; self.watchEvery = watchEvery
    }

    /// The tool was turned on: watch for idle time.
    public func enable() {
        guard !enabled else { return }
        enabled = true
        phase = .waiting
        watch()
    }

    /// The tool was turned off: stop moving and stop watching.
    public func disable() {
        enabled = false
        end(reason: nil)
        loop?.cancel(); loop = nil
        phase = .off
    }

    /// From the panel: a short countdown so the hand that clicked Start can let go of the mouse.
    public func startSoon() {
        guard phase != .moving else { return }
        loop?.cancel()
        lastStopReason = nil
        let delay = Self.countdownSeconds
        phase = .countdown(until: now().addingTimeInterval(delay))
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.begin()
        }
    }

    /// Ends a run or a countdown. Watching for idle time goes on while the tool is on.
    public func stop(reason: String? = nil) {
        guard phase == .moving || isCountingDown else { return }
        end(reason: reason)
        if enabled { phase = .waiting; watch() } else { loop?.cancel(); loop = nil; phase = .off }
    }

    private var isCountingDown: Bool { if case .countdown = phase { true } else { false } }

    private func watch() {
        loop?.cancel()
        watchedIdle = options().idleMinutes
        guard watchedIdle != nil else { loop = nil; return }
        loop = Task { [weak self, watchEvery] in
            while !Task.isCancelled {
                try? await Task.sleep(for: watchEvery)
                guard let self, !Task.isCancelled else { return }
                if self.checkIdle() { return }
            }
        }
    }

    /// Starts moving when the Mac has been idle long enough. True when it started.
    @discardableResult
    func checkIdle() -> Bool {
        guard enabled, phase == .waiting, let minutes = options().idleMinutes,
              driver.secondsSinceInput() >= Double(minutes * 60) else { return false }
        begin()
        return phase == .moving
    }

    /// Applies changed settings: a new idle choice restarts the watch, the black screen follows its switch.
    /// Called on every defaults change, so it only acts when one of its own settings moved.
    public func settingsChanged() {
        let o = options()
        if o.idleMinutes != watchedIdle, enabled, phase == .waiting { watch() }
        if phase == .moving { setBlackout(o.blackout) }
    }

    func begin() {
        let found = driver.displays().filter { $0.width > 16 && $0.height > 16 }
        guard !found.isEmpty else { lastStopReason = "No screen found"; phase = enabled ? .waiting : .off; return }
        displays = found
        let here = driver.location
        displayIndex = displays.firstIndex { $0.contains(here) } ?? 0
        let area = BouncePath.area(displays[displayIndex])
        position = CGPoint(x: min(max(here.x, area.minX), area.maxX), y: min(max(here.y, area.minY), area.maxY))
        // An angle that isn't a simple fraction of the screen, so the path doesn't repeat quickly and covers the screen.
        let speed = options().speed.pointsPerSecond
        velocity = CGVector(dx: speed * 0.832, dy: speed * 0.555)
        let t = now()
        startedAt = t; lastStep = t; onDisplaySince = t
        lastStopReason = nil
        driver.warp(to: position)
        phase = .moving
        setBlackout(options().blackout)
        loop?.cancel()
        loop = Task { [weak self, tick] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tick)
                guard let self, !Task.isCancelled, self.step() else { return }
            }
        }
    }

    /// One frame. False when the run ended.
    @discardableResult
    func step() -> Bool {
        guard phase == .moving else { return false }
        if userActed() { stop(reason: "Stopped when you used the mouse or keyboard"); return false }
        let t = now()
        let dt = min(max(t.timeIntervalSince(lastStep), 0), 0.1) // a stall (sleep, busy main thread) never makes it jump
        lastStep = t
        if displays.count > 1, t.timeIntervalSince(onDisplaySince) >= Self.secondsPerDisplay {
            displayIndex = (displayIndex + 1) % displays.count
            let a = BouncePath.area(displays[displayIndex])
            position = CGPoint(x: a.midX, y: a.midY)
            onDisplaySince = t
        }
        (position, velocity) = BouncePath.step(position, velocity, in: BouncePath.area(displays[displayIndex]), dt: dt)
        driver.warp(to: position)
        return true
    }

    /// The pointer is not where it was put, or real input came in after the run began.
    private func userActed() -> Bool {
        let here = driver.location
        if hypot(here.x - position.x, here.y - position.y) > 3 { return true }
        let running = now().timeIntervalSince(startedAt)
        return running > 0.5 && driver.secondsSinceInput() + 0.25 < running
    }

    private func end(reason: String?) {
        if phase == .moving || isCountingDown { lastStopReason = reason }
        setBlackout(false)
        displays = []
    }

    private func setBlackout(_ on: Bool) {
        guard blackedOut != on else { return }
        blackedOut = on
        onBlackoutChange?(on)
    }
}
