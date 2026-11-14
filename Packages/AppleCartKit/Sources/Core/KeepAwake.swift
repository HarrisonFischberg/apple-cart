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

    public init(duration: TimeInterval? = nil, stopBelowPercent: Int? = nil, keepDisplayOn: Bool = false) {
        self.duration = duration
        self.stopBelowPercent = stopBelowPercent
        self.keepDisplayOn = keepDisplayOn
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
    @ObservationIgnored private var token: UInt32?
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(assertions: PowerAssertions = IOKitAssertions(),
                now: @escaping @Sendable () -> Date = Date.init,
                readBattery: @escaping @Sendable () -> BatteryReading? = BatteryReader.read,
                checkEvery: Duration = .seconds(30)) {
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
        if let level = options?.stopBelowPercent, let r = readBattery(), !r.isPluggedIn, r.percent <= level {
            stop(reason: "Battery reached \(level)%"); return true
        }
        return false
    }

    private func sleepLength() -> Duration {
        let level = options?.stopBelowPercent != nil
        guard let end = endDate else { return checkEvery }
        let left = Duration.seconds(max(0.01, end.timeIntervalSince(now())))
        return level ? min(left, checkEvery) : left
    }
}
