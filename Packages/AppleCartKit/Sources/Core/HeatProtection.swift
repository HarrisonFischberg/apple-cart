import Foundation

/// Heat protection timing, pure and clock-injected. Above the max temperature charging pauses for at least
/// `pauseFor`; if the battery is still too warm when that runs out, it pauses for another `pauseFor`. Once it has
/// cooled, charging is allowed for at least `minChargeFor`, even if the temperature rises again in that time.
/// Off, on battery or with no temperature: no heat action, and any pause ends.
public struct HeatGuard: Equatable, Sendable {
    public static let pauseFor: TimeInterval = 5 * 60
    public static let minChargeFor: TimeInterval = 5 * 60

    public private(set) var pausedUntil: Date?
    public private(set) var mustChargeUntil: Date?

    public init() {}

    public var isPaused: Bool { pausedUntil != nil }

    /// Feed every reading in; returns whether charging should be paused for heat now.
    @discardableResult
    public mutating func update(temperatureC: Double?, maxC: Double, enabled: Bool, pluggedIn: Bool, now: Date) -> Bool {
        guard enabled, pluggedIn, let t = temperatureC else { self = HeatGuard(); return false }
        let hot = t > maxC
        if let until = pausedUntil {
            if now < until { return true }
            if hot { pausedUntil = now.addingTimeInterval(Self.pauseFor); return true }
            pausedUntil = nil
            mustChargeUntil = now.addingTimeInterval(Self.minChargeFor)
            return false
        }
        if let m = mustChargeUntil, now < m { return false }
        mustChargeUntil = nil
        if hot { pausedUntil = now.addingTimeInterval(Self.pauseFor); return true }
        return false
    }
}

/// What the MagSafe light shows, read from the SMC (read only: Apple Cart never sets it). Measured on an M5 (Mac17,2):
/// key ACLC reads 3 while the light is green and 4 while it is orange. Anything else is not guessed at.
public enum MagSafeLight: Equatable, Sendable {
    case green, orange, unknown
    /// This Mac has no light key (for example no MagSafe port).
    case notAvailable

    public init(smcValue: UInt8?) {
        switch smcValue {
        case nil: self = .notAvailable
        case 3: self = .green
        case 4: self = .orange
        default: self = .unknown
        }
    }

    /// The row value. Unplugged there is nothing lit, whatever the key still says.
    public func text(pluggedIn: Bool) -> String {
        guard pluggedIn else { return "Off" }
        switch self {
        case .green: return "Green"
        case .orange: return "Orange"
        case .unknown, .notAvailable: return "Unknown"
        }
    }

    public static let orangeWhileHeldNote = "The light is orange because macOS shows orange below 100%, even while your limit holds charging."
    public static let greenNotChargingNote = "The light is green because macOS treats the battery as full for now. Charging starts again when macOS allows it."

    /// One honest line when the light and Apple Cart's state could look like they disagree; nil when they agree.
    public static func note(light: MagSafeLight, pluggedIn: Bool, held: Bool, charging: Bool, percent: Int) -> String? {
        guard pluggedIn, percent < 100 else { return nil }
        if light == .orange && held { return orangeWhileHeldNote }
        if light == .green && !charging && !held { return greenNotChargingNote }
        return nil
    }
}
