import Foundation
import Observation

/// What the owner picked: leave the fans to macOS, or one manual speed.
public enum FanControlMode: String, Codable, CaseIterable, Sendable {
    case system, manual
    public var title: String { switch self { case .system: "System"; case .manual: "Manual" } }
}

/// Temperatures in Celsius from the read-only readers; nil when a sensor could not be read.
public struct FanTemperatures: Equatable, Sendable {
    /// CPU and GPU averages (for display).
    public var cpu: Double?
    public var gpu: Double?
    public var battery: Double?
    /// The hottest single plausible CPU or GPU sensor (ChipTemperatures.hottest). Every safety rule uses this.
    public var hottestSensor: Double?

    /// `hottestSensor` defaults to the hotter average, for callers that only have averages (tests, previews).
    public init(cpu: Double? = nil, gpu: Double? = nil, battery: Double? = nil, hottestSensor: Double? = nil) {
        self.cpu = cpu; self.gpu = gpu; self.battery = battery
        self.hottestSensor = hottestSensor ?? [cpu, gpu].compactMap { $0 }.max()
    }

    /// The "Hottest SoC" sensor: the hottest single CPU or GPU sensor.
    public var hottestSoC: Double? { hottestSensor }
}

/// A fan's running range from the SMC (F0Mn, F0Mx). Below `minRPM` a fan does not run steadily, so nothing is ever set there.
public struct FanRange: Equatable, Sendable {
    public var minRPM: Int
    public var maxRPM: Int
    public init(minRPM: Int, maxRPM: Int) { self.minRPM = minRPM; self.maxRPM = maxRPM }

    /// 0% = the minimum running speed, 100% = maximum, rounded to 50 rpm and kept inside the range.
    public func rpm(percent: Double) -> Int {
        let raw = Double(minRPM) + min(max(percent, 0), 100) / 100 * Double(maxRPM - minRPM)
        return min(max(Int((raw / 50).rounded()) * 50, minRPM), maxRPM)
    }

    /// Where an rpm sits in the range, 0-100.
    public func percent(rpm: Int) -> Int {
        guard maxRPM > minRPM else { return 0 }
        return Int((Double(rpm - minRPM) / Double(maxRPM - minRPM) * 100).rounded()).clamped(to: 0...100)
    }
}

extension Int {
    func clamped(to r: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, r.lowerBound), r.upperBound) }
}

public enum FanPreset: CaseIterable, Sendable {
    case min, medium, max
    public var title: String { switch self { case .min: "Min"; case .medium: "Medium"; case .max: "Max" } }
    public var percent: Int { switch self { case .min: 0; case .medium: 50; case .max: 100 } }
}

/// Why macOS has the fans.
public enum FanSystemReason: Equatable, Sendable {
    /// The owner chose System.
    case chosen
    /// No fan range known yet (no reading from the SMC).
    case noRange
    /// A temperature the decision needs could not be read.
    case noTemperature
    /// The hottest SoC sensor reached `FanPolicy.releaseAtC`: macOS has the fans for the lockout.
    case hot(Double)
    /// macOS reports serious or critical thermal pressure.
    case thermalPressure
    /// Still inside the 2-minute lockout after a hot or thermal release.
    case coolingDown
}

public enum FanDecision: Equatable, Sendable {
    case system(FanSystemReason)
    case hold(rpm: Int)
}

/// What the policy remembers between passes: the safety lockout and the last target, for smoothing.
public struct FanPolicyState: Equatable, Sendable {
    public var releasedUntil: Date?
    /// Set by a heat or thermal-pressure release; cleared only once the hottest sensor is below `FanPolicy.resumeBelowC`.
    public var heatLatched = false
    public var lastTarget: Int?        // nil = system
    public var lastChange: Date?
    public init() {}
}

/// Pure decision for one pass. Safety comes first and holds for every mode, always on the hottest single SoC sensor
/// (never an average): no reading, 90 C or more, or serious thermal pressure all give the fans to macOS (the last two for
/// at least 2 minutes, and then until the hottest sensor is below 80 C, so a Mac sitting at 89 C cannot flap between
/// macOS and a manual speed). Manual targets are smoothed so the fan does not hunt: a new target is taken when
/// it differs by more than 100 rpm or 10 s after the last change; switching between macOS and a manual speed also waits
/// the 10 s (except safety releases, which are immediate).
public enum FanPolicy {
    public static let releaseAtC = 90.0
    public static let resumeBelowC = 80.0
    public static let lockout: TimeInterval = 120
    public static let smoothingRPM = 100
    public static let smoothingSeconds: TimeInterval = 10

    public static func decide(mode: FanControlMode, manualPercent: Int, temperatures t: FanTemperatures,
                              thermalPressure: Bool, range: FanRange?, now: Date, state: inout FanPolicyState) -> FanDecision {
        func release(_ r: FanSystemReason) -> FanDecision {
            if state.lastTarget != nil { state.lastTarget = nil; state.lastChange = now }
            return .system(r)
        }
        guard mode != .system else { return release(.chosen) }
        guard let hottest = t.hottestSensor else { return release(.noTemperature) }
        if hottest >= releaseAtC || thermalPressure {
            state.releasedUntil = now.addingTimeInterval(lockout)
            state.heatLatched = true
            return release(thermalPressure ? .thermalPressure : .hot(hottest))
        }
        if let until = state.releasedUntil {
            if now < until { return release(.coolingDown) }
            state.releasedUntil = nil
        }
        if state.heatLatched {
            guard hottest < resumeBelowC else { return release(.coolingDown) }
            state.heatLatched = false
        }
        guard let range else { return release(.noRange) }
        let wanted: Int? = range.rpm(percent: Double(manualPercent))
        let settled = state.lastChange.map { now.timeIntervalSince($0) >= smoothingSeconds } ?? true
        let take: Bool
        switch (state.lastTarget, wanted) {
        case let (a?, b?): take = a != b && (abs(a - b) > smoothingRPM || settled)
        case (nil, nil): take = false
        default: take = settled
        }
        if take { state.lastTarget = wanted; state.lastChange = now }
        return state.lastTarget.map { .hold(rpm: $0) } ?? .system(.chosen)
    }
}

/// The saved fan choices. Saving never means it is applied: only the FanRunner, after the helper confirmed it, says so.
@MainActor @Observable
public final class FanSettings {
    /// The mode that is applied (Apply pressed); System until then.
    public private(set) var active: FanControlMode
    public private(set) var manualPercent: Int
    /// Re-apply the saved mode after a restart or wake. Off: every restart and sleep hands the fans back to macOS for good.
    public private(set) var resume: Bool
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let resume = defaults.bool(forKey: "fan.resume")
        self.resume = resume
        manualPercent = (defaults.object(forKey: "fan.manualPercent") as? Int ?? 50).clamped(to: 0...100)
        let saved = FanControlMode(rawValue: defaults.string(forKey: "fan.active") ?? "") ?? .system
        active = resume ? saved : .system
        if active != saved { defaults.set(active.rawValue, forKey: "fan.active") }
    }

    public func applyManual(percent: Int) {
        manualPercent = percent.clamped(to: 0...100)
        defaults.set(manualPercent, forKey: "fan.manualPercent")
        setActive(.manual)
    }

    public func setActive(_ m: FanControlMode) { active = m; defaults.set(m.rawValue, forKey: "fan.active") }
    public func setResume(_ on: Bool) { resume = on; defaults.set(on, forKey: "fan.resume") }
}

/// What the helper says about the fans.
public struct FanHelperReport: Equatable, Sendable {
    public var status: ChargeHelperStatus
    /// True when a fan reads manual mode; nil when it could not tell.
    public var manual: Bool?
    public var targetRPM: Int
    public init(_ status: ChargeHelperStatus, manual: Bool? = nil, targetRPM: Int = 0) {
        self.status = status; self.manual = manual; self.targetRPM = targetRPM
    }
}

/// Whatever can set the fans: the root helper over XPC, or nothing.
public protocol FanController: Sendable {
    func status() async -> FanHelperReport
    /// Manual at `rpm` on the helper's lease; the helper clamps it to each fan's range.
    func setFan(rpm: Int) async -> ChargeApplyResult
    /// Fans back to macOS, lease cancelled.
    func resetFan() async -> ChargeApplyResult
}

public struct NoopFanController: FanController {
    public init() {}
    public func status() async -> FanHelperReport { FanHelperReport(.notInstalled) }
    public func setFan(rpm: Int) async -> ChargeApplyResult { .unavailable }
    public func resetFan() async -> ChargeApplyResult { .unavailable }
}

/// Per-fan readings from the SMC, read only and unprivileged.
public struct FanReading: Equatable, Sendable {
    /// Actual rpm per fan (F0Ac, F1Ac, ...); nil where unreadable. Empty on a Mac with no fan.
    public var rpms: [Double?]
    /// Highest fan minimum and lowest fan maximum, so one target fits every fan.
    public var range: FanRange?
    public init(rpms: [Double?], range: FanRange?) { self.rpms = rpms; self.range = range }
}
