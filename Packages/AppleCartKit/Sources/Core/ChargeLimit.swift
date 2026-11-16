import Foundation
import Observation

/// The saved upper charge limit and the Top Up choice. Saving a limit never means it is enforced:
/// only a `ChargeController` that is available and applied a decision does that.
@MainActor @Observable
public final class ChargeLimitSettings {
    public static let range = 50...100
    public static let step = 5
    /// What the limit pill and popover offer.
    public static let choices = [50, 60, 70, 80, 90, 100]

    public private(set) var limit: Int
    public private(set) var topUpActive: Bool
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        limit = Self.clamped(defaults.object(forKey: "chargeLimit") as? Int ?? 100)
        topUpActive = defaults.bool(forKey: "chargeTopUp")
    }

    /// Nearest multiple of 5 inside 50...100.
    public static func clamped(_ percent: Int) -> Int {
        let stepped = Int((Double(percent) / Double(step)).rounded()) * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    public func setLimit(_ percent: Int) {
        limit = Self.clamped(percent)
        defaults.set(limit, forKey: "chargeLimit")
    }

    /// Top Up lifts the limit to 100 until it is cancelled, the battery is full or the Mac unplugs.
    public var effectiveLimit: Int { topUpActive ? 100 : limit }

    public func setTopUp(_ on: Bool) {
        topUpActive = on
        defaults.set(on, forKey: "chargeTopUp")
    }

    /// Feed every new reading in. No reading is not "unplugged", so it leaves Top Up alone.
    public func observe(_ reading: BatteryReading?) {
        guard topUpActive, let r = reading else { return }
        if !r.isPluggedIn || r.percent >= 100 { setTopUp(false) }
    }

    /// Honest one-liner for the popover: never says the limit is active.
    public func caption(controllerAvailable: Bool) -> String {
        controllerAvailable ? "Applies while the Mac is plugged in." : "Saved. It takes effect once the charging helper is installed."
    }
}

public enum ChargeDecision: Equatable, Sendable {
    case allowCharging
    case holdCharging(at: Int)
}

public enum ChargePolicy {
    /// Charging resumes this many percent below the limit, so it does not flap at the edge.
    public static let hysteresis = 3

    /// At or above the limit: hold. Below `limit - hysteresis`: charge. Between: keep doing what the
    /// battery is doing now (`isCharging`). Unplugged or no reading: nothing to hold.
    @MainActor
    public static func decide(reading: BatteryReading?, settings: ChargeLimitSettings) -> ChargeDecision {
        decide(reading: reading, limit: settings.effectiveLimit)
    }

    public static func decide(reading: BatteryReading?, limit: Int) -> ChargeDecision {
        guard let r = reading, r.isPluggedIn, limit < 100 else { return .allowCharging }
        if r.percent >= limit { return .holdCharging(at: limit) }
        if r.percent <= limit - hysteresis { return .allowCharging }
        return r.isCharging ? .allowCharging : .holdCharging(at: limit)
    }
}

public enum ChargeApplyResult: Equatable, Sendable {
    case applied
    case unavailable
    case failed(String)
}

/// Whatever can actually stop and start charging. Today nothing can: there is no root helper yet.
public protocol ChargeController: Sendable {
    var isAvailable: Bool { get }
    func apply(_ decision: ChargeDecision) async -> ChargeApplyResult
}

public struct NoopChargeController: ChargeController {
    public init() {}
    public var isAvailable: Bool { false }
    public func apply(_ decision: ChargeDecision) async -> ChargeApplyResult { .unavailable }
}
