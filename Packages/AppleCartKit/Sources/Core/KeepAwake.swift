import Foundation
import IOKit.pwr_mgt
import Observation

/// Holds a power assertion. The real one talks to IOKit; tests use a fake.
@MainActor
public protocol PowerAssertions: AnyObject {
    /// Returns a token for `release`, or nil when macOS refused.
    func create(keepDisplayOn: Bool, reason: String) -> UInt32?
    func release(_ token: UInt32)
}

@MainActor
public final class IOKitAssertions: PowerAssertions {
    public init() {}

    public func create(keepDisplayOn: Bool, reason: String) -> UInt32? {
        let type = keepDisplayOn ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id: IOPMAssertionID = 0
        let ok = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
        return ok == kIOReturnSuccess ? id : nil
    }

    public func release(_ token: UInt32) { IOPMAssertionRelease(token) }
}

public struct KeepAwakeOptions: Sendable, Equatable {
    public var duration: TimeInterval?   // nil = until turned off
    public var stopBelowPercent: Int?    // only counts while on battery
    public var keepDisplayOn: Bool
    public var stopOnUnplug = false      // ends when the charger is removed (after it was seen plugged in)
    public var stopAtChargeLimit = false // ends once plugged in and the charge reaches the charge limit

    public init(duration: TimeInterval? = nil, stopBelowPercent: Int? = nil, keepDisplayOn: Bool = false,
                stopOnUnplug: Bool = false, stopAtChargeLimit: Bool = false) {
        self.duration = duration
        self.stopBelowPercent = stopBelowPercent
        self.keepDisplayOn = keepDisplayOn
        self.stopOnUnplug = stopOnUnplug
        self.stopAtChargeLimit = stopAtChargeLimit
    }

    public static let levelRange = 5...95
    public static let defaultLevel = 20
    /// Longest custom time: one week.
    public static let maxCustomSeconds: TimeInterval = 7 * 24 * 3600

    /// Seconds for a typed amount, or nil when it is not a positive number. Over a week is capped.
    public static func customSeconds(_ amount: Int, hours: Bool) -> TimeInterval? {
        guard amount > 0 else { return nil }
        return min(Double(amount) * (hours ? 3600 : 60), maxCustomSeconds)
    }

    /// The options saved in Settings, with the given duration from the panel.
    public static func stored(duration: TimeInterval?, defaults: UserDefaults = .standard) -> KeepAwakeOptions {
        let level = min(max(defaults.object(forKey: "keepAwake.level") as? Int ?? defaultLevel, levelRange.lowerBound), levelRange.upperBound)
        return .init(duration: duration,
                     stopBelowPercent: defaults.bool(forKey: "keepAwake.useLevel") ? level : nil,
                     keepDisplayOn: defaults.bool(forKey: "keepAwake.displayOn"),
                     stopOnUnplug: defaults.bool(forKey: "keepAwake.endOnUnplug"),
                     stopAtChargeLimit: defaults.bool(forKey: "keepAwake.untilLimit"))
    }
}

@MainActor @Observable
public final class KeepAwake {
    public static let assertionName = "Apple Cart keep awake"

    public private(set) var options: KeepAwakeOptions?
    public private(set) var endDate: Date?
    public private(set) var failed = false
    public private(set) var lastStopReason: String?
    public var isActive: Bool { options != nil }

    @ObservationIgnored private let assertions: PowerAssertions
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let readBattery: @Sendable () -> BatteryReading?
    @ObservationIgnored private let checkEvery: Duration
    @ObservationIgnored private let chargeLimit: @MainActor () -> Int
    @ObservationIgnored private var sawCharger = false
    @ObservationIgnored private var token: UInt32?
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(assertions: PowerAssertions = IOKitAssertions(),
                now: @escaping @Sendable () -> Date = Date.init,
                readBattery: @escaping @Sendable () -> BatteryReading? = BatteryReader.read,
                checkEvery: Duration = .seconds(10),
                chargeLimit: @escaping @MainActor () -> Int = { 100 }) {
        self.chargeLimit = chargeLimit
        self.assertions = assertions
        self.now = now
        self.readBattery = readBattery
        self.checkEvery = checkEvery
    }

    /// Starting again replaces the current session.
    public func start(_ o: KeepAwakeOptions) {
        stop(reason: nil)
        failed = false
        guard let t = assertions.create(keepDisplayOn: o.keepDisplayOn, reason: Self.assertionName) else { failed = true; return }
        token = t
        options = o
        lastStopReason = nil
        sawCharger = false
        endDate = o.duration.map { now().addingTimeInterval($0) }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.shouldStop() { return }
                let wait = self.sleepLength()
                try? await Task.sleep(for: wait)
            }
        }
    }

    /// Swaps the assertion for one with or without the display, keeping the timer and end conditions of the running session.
    public func setKeepDisplayOn(_ on: Bool) {
        guard var o = options, o.keepDisplayOn != on else { return }
        guard let t = assertions.create(keepDisplayOn: on, reason: Self.assertionName) else { return }
        if let token { assertions.release(token) }
        token = t
        o.keepDisplayOn = on
        options = o
    }

    public func stop(reason: String? = nil) {
        task?.cancel(); task = nil
        if let token { assertions.release(token) }
        token = nil
        if options != nil { lastStopReason = reason }
        options = nil
        endDate = nil
    }

    /// True (and stops) when the timer ran out or the battery fell to the chosen level.
    private func shouldStop() -> Bool {
        if let end = endDate, now() >= end { stop(reason: "Timer finished"); return true }
        guard let o = options, let r = readBattery() else { return false }
        // A held charge limit reads as battery power while the charger is in; adapter details still show it.
        let plugged = r.isPluggedIn || r.adapterWatts != nil
        if plugged { sawCharger = true }
        if let level = o.stopBelowPercent, !plugged, r.percent <= level {
            stop(reason: "Battery reached \(level)%"); return true
        }
        if o.stopOnUnplug, sawCharger, !plugged { stop(reason: "Charger unplugged"); return true }
        if o.stopAtChargeLimit, plugged, r.percent >= chargeLimit() { stop(reason: "Charge limit reached"); return true }
        return false
    }

    private func sleepLength() -> Duration {
        let level = options.map { $0.stopBelowPercent != nil || $0.stopOnUnplug || $0.stopAtChargeLimit } ?? false
        guard let end = endDate else { return checkEvery }
        let left = Duration.seconds(max(0.01, end.timeIntervalSince(now())))
        return level ? min(left, checkEvery) : left
    }
}
