import Foundation
import Observation

/// What the MagSafe light should show: a forced colour, or `.system` (macOS decides, nothing forced).
public enum LEDColor: Equatable, Sendable {
    case green, orange, system
}

/// Whatever can force the light: the root helper over XPC (version 4), or nothing.
public protocol LEDController: Sendable {
    /// `.ready` only for a helper that has the light calls and a light key.
    func status() async -> ChargeHelperStatus
    /// Force green or orange on the helper's lease.
    func setLED(_ color: LEDColor) async -> ChargeApplyResult
    /// Stop forcing, lease cancelled.
    func resetLED() async -> ChargeApplyResult
}

/// AlDente's public "Indicate Charge Limit" rules (docs/battery-parity.md), for the states this app has.
/// Stop-charging-in-sleep and app-closed pauses are not built here, so they have no rule.
public enum LEDPolicy {
    public static func decide(indicate: Bool, toolEnabled: Bool, state: ChargeLimitState, topUpActive: Bool) -> LEDColor {
        guard indicate, toolEnabled, state.helperStatus == .ready else { return .system }
        if state.holdingAt != nil, state.heatPausedAtC != nil { return .orange } // paused by heat protection
        if topUpActive { return (state.level ?? 0) >= 100 ? .green : .system }
        // At or above the limit (holding, sailing, discharging to it). Charging toward it: macOS already shows orange.
        return state.holdingAt != nil ? .green : .system
    }
}

/// The single writer of light commands. While the Battery tool is on and "Indicate charge limit" is set, it follows the
/// charge limiter's confirmed state: forces the colour (renewed every 30 s on a 90 s helper lease) or hands the light back.
@MainActor @Observable
public final class LEDRunner {
    public static let renewEvery: TimeInterval = 30
    public static let statusEvery: TimeInterval = 30
    /// The helper's own lease; past this a forced colour has certainly been handed back by the helper.
    public static let leaseSeconds: TimeInterval = 90

    /// The colour the helper confirmed it is forcing; `.system` when nothing is.
    public private(set) var forced: LEDColor = .system
    @ObservationIgnored private let settings: ChargeLimitSettings
    @ObservationIgnored private let limiter: ChargeLimiter
    @ObservationIgnored private let controller: LEDController
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var toolEnabled = false
    public private(set) var helperStatus: ChargeHelperStatus = .notInstalled
    @ObservationIgnored private var statusCheckedAt: Date?
    @ObservationIgnored private var sentAt: Date?
    @ObservationIgnored private var maybeForcedUntil: Date?
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var again = false

    public init(settings: ChargeLimitSettings, limiter: ChargeLimiter, controller: LEDController, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.limiter = limiter
        self.controller = controller
        self.now = now
    }

    private var mayBeForced: Bool { maybeForcedUntil.map { now() < $0 } ?? false }

    public func setToolEnabled(_ on: Bool) async {
        toolEnabled = on
        statusCheckedAt = nil
        await evaluate()
    }

    /// The helper handed the light back before sleep: send the colour again now instead of waiting for the renewal.
    public func systemDidWake() async {
        sentAt = nil
        forced = .system
        statusCheckedAt = nil
        await evaluate()
    }

    /// Before quit, delete-all or helper removal: hand the light back.
    public func shutdown() async {
        toolEnabled = false
        await evaluate()
    }

    /// Calls are serialized like the other runners; one that arrives mid-pass becomes one more pass.
    public func evaluate() async {
        guard !busy else { again = true; return }
        busy = true
        defer { busy = false }
        repeat {
            again = false
            await step()
        } while again
    }

    private func step() async {
        let wanted = LEDPolicy.decide(indicate: settings.indicateChargeLimit, toolEnabled: toolEnabled, state: limiter.state,
                                      topUpActive: settings.topUpActive)
        guard wanted != .system else { await release(); return }
        if statusCheckedAt.map({ now().timeIntervalSince($0) >= Self.statusEvery }) ?? true {
            statusCheckedAt = now()
            helperStatus = await controller.status()
        }
        guard helperStatus == .ready else { await release(); return }
        if forced == wanted, let at = sentAt, now().timeIntervalSince(at) < Self.renewEvery { return }
        maybeForcedUntil = now().addingTimeInterval(Self.leaseSeconds)
        let result = await controller.setLED(wanted)
        if result == .applied {
            forced = wanted; sentAt = now()
        } else {
            // Not forced (sleeping, failed or timed out). It may still have landed: hand it back and try again next pass.
            forced = .system; sentAt = nil
            if result != .sleeping, await controller.resetLED() == .applied { maybeForcedUntil = nil }
            statusCheckedAt = nil
        }
    }

    private func release() async {
        forced = .system; sentAt = nil
        guard mayBeForced else { return }
        if await controller.resetLED() == .applied { maybeForcedUntil = nil }
    }
}
