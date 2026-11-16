import Foundation
import Observation

/// The saved charge-control choices. Saving a limit never means it is enforced: only the ChargeLimiter,
/// after the helper confirmed a command, says a limit is being held.
@MainActor @Observable
public final class ChargeLimitSettings {
    public static let range = 0...100
    public static let step = 5
    /// What the limit popover offers (filtered by `minimum`).
    public static let choices = [0, 20, 50, 70, 80, 100]
    public static let sailingRange = 0...15
    public static let heatRangeC = 30.0...45.0

    public private(set) var limit: Int
    public private(set) var topUpActive: Bool
    public private(set) var autoDischarge: Bool
    /// One-shot Discharge: run from the battery down to the limit, then switch itself off.
    public private(set) var dischargeActive: Bool
    public private(set) var sailing: Bool
    public private(set) var sailingDifference: Int
    /// Stored only; heat protection logic is not built yet.
    public private(set) var heatProtection: Bool
    public private(set) var heatMaxC: Double
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoDischarge = defaults.bool(forKey: "chargeAutoDischarge")
        dischargeActive = defaults.bool(forKey: "chargeDischarge")
        sailing = defaults.bool(forKey: "chargeSailing")
        sailingDifference = Self.clampedSailing(defaults.object(forKey: "chargeSailingDifference") as? Int ?? 5)
        heatProtection = defaults.bool(forKey: "chargeHeatProtection")
        heatMaxC = min(max(defaults.object(forKey: "chargeHeatMaxC") as? Double ?? 35, Self.heatRangeC.lowerBound), Self.heatRangeC.upperBound)
        limit = 100
        topUpActive = defaults.bool(forKey: "chargeTopUp")
        limit = clamped(defaults.object(forKey: "chargeLimit") as? Int ?? 100)
    }

    /// Nearest multiple of 5 inside 0...100.
    public static func clamped(_ percent: Int) -> Int {
        let stepped = Int((Double(percent) / Double(step)).rounded()) * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    public static func clampedSailing(_ n: Int) -> Int { min(max(n, sailingRange.lowerBound), sailingRange.upperBound) }

    public func clamped(_ percent: Int) -> Int { Self.clamped(percent) }

    public func setLimit(_ percent: Int) {
        limit = clamped(percent)
        defaults.set(limit, forKey: "chargeLimit")
    }

    public func setAutoDischarge(_ on: Bool) { autoDischarge = on; defaults.set(on, forKey: "chargeAutoDischarge") }
    public func setDischarge(_ on: Bool) { dischargeActive = on; defaults.set(on, forKey: "chargeDischarge") }
    public func setSailing(_ on: Bool) { sailing = on; defaults.set(on, forKey: "chargeSailing") }
    public func setSailingDifference(_ n: Int) {
        sailingDifference = Self.clampedSailing(n)
        defaults.set(sailingDifference, forKey: "chargeSailingDifference")
    }
    public func setHeatProtection(_ on: Bool) { heatProtection = on; defaults.set(on, forKey: "chargeHeatProtection") }
    public func setHeatMaxC(_ c: Double) {
        heatMaxC = min(max(c, Self.heatRangeC.lowerBound), Self.heatRangeC.upperBound)
        defaults.set(heatMaxC, forKey: "chargeHeatMaxC")
    }

    /// Charging resumes this many percent below the limit: the sailing difference, or the small default band.
    public var resumeBand: Int { sailing ? sailingDifference : ChargePolicy.hysteresis }
    /// The lower edge of the range the battery drifts in ("Will sail to X%").
    public var sailFloor: Int { max(limit - resumeBand, 0) }

    /// Top Up lifts the limit to 100 until it is cancelled, the battery is full or the Mac unplugs.
    public var effectiveLimit: Int { topUpActive ? 100 : limit }

    public func setTopUp(_ on: Bool) {
        topUpActive = on
        defaults.set(on, forKey: "chargeTopUp")
    }

    /// Feed every new reading in. No reading is not "unplugged", so it leaves Top Up alone.
    public func observe(_ reading: BatteryReading?) {
        guard let r = reading else { return }
        if topUpActive, !r.isPluggedIn || r.percent >= 100 { setTopUp(false) }
        if dischargeActive, !r.isPluggedIn || r.limitLevel <= effectiveLimit { setDischarge(false) }
    }
}

public enum ChargeDecision: Equatable, Sendable {
    case allowCharging
    case holdCharging(at: Int)
    /// Above the limit with Automatic Discharge on: run from the battery down to the limit.
    case discharge(to: Int)
}

public enum ChargePolicy {
    /// Default band: charging resumes this many percent below the limit, so it does not flap at the edge.
    public static let hysteresis = 3
    /// Never hold the charger off at or below this level, whatever the limit says: a dead battery shuts the Mac down.
    public static let emergencyFloor = 5

    @MainActor
    public static func decide(reading: BatteryReading?, settings: ChargeLimitSettings) -> ChargeDecision {
        decide(reading: reading, limit: settings.effectiveLimit, band: settings.resumeBand, autoDischarge: settings.autoDischarge || settings.dischargeActive)
    }

    /// Above the limit: discharge (if allowed) or hold. At the limit: hold. At or below `limit - band`: charge.
    /// Between: keep doing what the battery is doing now (`isCharging`). Unplugged or no reading: nothing to hold.
    public static func decide(reading: BatteryReading?, limit: Int, band: Int = hysteresis, autoDischarge: Bool = false) -> ChargeDecision {
        guard let r = reading, r.isPluggedIn, limit < 100, r.limitLevel > emergencyFloor else { return .allowCharging }
        if r.limitLevel > limit && autoDischarge { return .discharge(to: limit) }
        if r.limitLevel >= limit { return .holdCharging(at: limit) }
        if r.limitLevel <= limit - band { return .allowCharging }
        return r.isCharging ? .allowCharging : .holdCharging(at: limit)
    }
}

public enum ChargeApplyResult: Equatable, Sendable {
    case applied
    case unavailable
    /// The helper refuses cuts while the Mac is going to sleep.
    case sleeping
    case failed(String)
}

public enum ChargeHelperStatus: Equatable, Sendable {
    case notInstalled, needsApproval, ready, outdated, unreachable
    /// The helper runs but this Mac has no usable charger key (or SMC).
    case unsupported
}

public struct ChargeHelperReport: Equatable, Sendable {
    public var status: ChargeHelperStatus
    /// What the helper says about the charger right now: true = cut. Nil when it could not tell.
    public var adapterCut: Bool?
    public init(_ status: ChargeHelperStatus, adapterCut: Bool? = nil) { self.status = status; self.adapterCut = adapterCut }
}

/// Whatever can actually stop and start charging: the root helper over XPC, or nothing.
public protocol ChargeController: Sendable {
    func status() async -> ChargeHelperReport
    func apply(_ decision: ChargeDecision) async -> ChargeApplyResult
    /// Adapter back on, any lease cancelled.
    func resetAll() async -> ChargeApplyResult
}

extension ChargeController {
    public var isAvailable: Bool { get async { await status().status == .ready } }
}

public struct NoopChargeController: ChargeController {
    public init() {}
    public func status() async -> ChargeHelperReport { ChargeHelperReport(.notInstalled) }
    public func apply(_ decision: ChargeDecision) async -> ChargeApplyResult { .unavailable }
    public func resetAll() async -> ChargeApplyResult { .unavailable }
}
