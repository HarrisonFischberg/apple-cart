import Foundation
import Observation

/// What the panel and Settings show about the charge limit. `holdingAt` is set only after the helper
/// confirmed a cut, so the UI never claims a limit that is not being held.
public struct ChargeLimitState: Equatable, Sendable {
    public var helperStatus: ChargeHelperStatus = .notInstalled
    public var holdingAt: Int?
    /// The confirmed cut is a discharge down to `holdingAt` (Automatic Discharge, battery above the limit).
    public var discharging = false
    public var chargingNotResumed = false
    public var commandFailed = false
    /// The limit the runner is working towards (100 while Top Up is on).
    public var target = 100

    public init() {}

    public static let notResumedText = "Charging has not resumed. Unplug and replug the charger."

    public var reasonText: String {
        if chargingNotResumed { return Self.notResumedText }
        switch helperStatus {
        case .notInstalled: return "Install the charging helper in Settings to use this."
        case .needsApproval: return "Approve Apple Cart in Login Items."
        case .outdated: return "The charging helper is out of date. Repair it in Settings."
        case .unreachable: return "The charging helper is not answering. Repair it in Settings."
        case .ready:
            if let n = holdingAt { return discharging ? "Discharging to \(n)%" : "Holding at \(n)%" }
            if commandFailed { return "Could not reach the charging helper. Trying again." }
            return "Charging up to \(target)%"
        }
    }
}

/// The single writer to the helper. While the Battery tool is on it turns each battery reading into
/// ChargePolicy decisions: cut the adapter (renewed every 30 s on a 90 s helper lease) while holding,
/// restore it when allowed, then check that charging really resumed (the spike saw it stall until a replug).
@MainActor @Observable
public final class ChargeLimiter {
    public static let renewEvery: TimeInterval = 30
    public static let verifyWindow: TimeInterval = 180
    /// Re-send the restore at these points if charging has not resumed.
    public static let retryAt: [TimeInterval] = [60, 120]
    /// Right after a restore macOS can still report battery power for a few seconds.
    public static let unplugGrace: TimeInterval = 30
    public static let statusEvery: TimeInterval = 30
    /// The helper's own lease; past this a cut has certainly been undone by the helper.
    public static let leaseSeconds: TimeInterval = 90

    public private(set) var state = ChargeLimitState()
    @ObservationIgnored private let settings: ChargeLimitSettings
    @ObservationIgnored private let controller: ChargeController
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var toolEnabled = false
    @ObservationIgnored private var lastCut: Date?        // non-nil: the helper confirmed the adapter is cut
    @ObservationIgnored private var restoredAt: Date?     // non-nil: checking that charging resumed
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var statusCheckedAt: Date?
    @ObservationIgnored private var lastReading: BatteryReading?
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var again = false

    public init(settings: ChargeLimitSettings, controller: ChargeController, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.controller = controller
        self.now = now
    }

    /// Whether the app should keep the battery sampler running for this runner.
    public var wantsReadings: Bool {
        toolEnabled && (settings.limit < 100 || settings.topUpActive || lastCut != nil || restoredAt != nil)
    }

    public func setToolEnabled(_ on: Bool) async {
        toolEnabled = on
        if on {
            await refreshHelperStatus()
            await evaluate(lastReading)
        } else {
            lastCut = nil; restoredAt = nil
            state.holdingAt = nil; state.chargingNotResumed = false; state.commandFailed = false
            _ = await controller.resetAll()
        }
    }

    /// After install, repair or approval: ask the helper again right away.
    public func refreshHelperStatus() async {
        statusCheckedAt = now()
        state.helperStatus = await controller.status()
    }

    /// Re-run the policy now (Top Up or the limit changed).
    public func reevaluate() async { await evaluate(lastReading) }

    /// Feed every battery reading and power event in. Calls are serialized; a call that arrives while one is
    /// running is folded into one more pass with the newest reading.
    public func evaluate(_ reading: BatteryReading?) async {
        if let reading { lastReading = reading }
        guard !busy else { again = true; return }
        busy = true
        defer { busy = false }
        repeat {
            again = false
            await step(lastReading)
        } while again
    }

    /// Before quit or delete-all: adapter on, whatever state we were in.
    public func shutdown() async { await setToolEnabled(false) }

    private func step(_ r: BatteryReading?) async {
        guard toolEnabled else { return }
        if statusCheckedAt.map({ now().timeIntervalSince($0) >= Self.statusEvery }) ?? true { await refreshHelperStatus() }
        let cut = lastCut != nil
        // Our own cut (or its aftermath) makes macOS report battery power, so only a plugged reading may end Top Up then.
        if let r, (!cut && restoredAt == nil) || r.isPluggedIn { settings.observe(r) }
        state.target = settings.effectiveLimit
        guard state.helperStatus == .ready else {
            // Nothing can be commanded; any cut is undone by the helper's lease.
            lastCut = nil; restoredAt = nil
            state.holdingAt = nil; state.chargingNotResumed = false; state.commandFailed = false
            return
        }
        var seen = r
        // shortcut: while our cut is active an unplugged reading is assumed to be the cut itself, because macOS
        // reports battery power either way; holding is harmless with no charger, and it still ends at limit - band.
        if cut, var x = r, !x.isPluggedIn { x.isPluggedIn = true; seen = x }
        let decision = ChargePolicy.decide(reading: seen, settings: settings)
        switch decision {
        case .holdCharging(let at), .discharge(to: let at):
            // On this Mac both are the same adapter cut; only the wording differs.
            let discharging = decision != .holdCharging(at: at)
            if let last = lastCut, now().timeIntervalSince(last) < Self.renewEvery {
                state.holdingAt = at; state.discharging = discharging; return
            }
            let result = await controller.apply(decision)
            guard toolEnabled else { _ = await controller.resetAll(); return } // turned off while the cut was in flight
            if result == .applied {
                lastCut = now(); restoredAt = nil
                state.holdingAt = at; state.discharging = discharging; state.chargingNotResumed = false; state.commandFailed = false
            } else {
                // The helper restores on any failed cut; show the truth and ask again next pass.
                lastCut = nil; state.holdingAt = nil; state.commandFailed = true
                await refreshHelperStatus()
            }
        case .allowCharging:
            state.holdingAt = nil
            if let last = lastCut {
                let result = await controller.apply(.allowCharging)
                if result == .applied || now().timeIntervalSince(last) >= Self.leaseSeconds {
                    lastCut = nil; restoredAt = now(); retries = 0; state.commandFailed = false
                } else {
                    state.commandFailed = true // keep lastCut so the next pass sends the restore again
                }
            } else if let start = restoredAt {
                await verifyResume(r, since: start)
            }
        }
    }

    private func verifyResume(_ r: BatteryReading?, since start: Date) async {
        guard let r else { return }
        let elapsed = now().timeIntervalSince(start)
        let resumed = (r.isPluggedIn && r.isCharging) || r.percent >= settings.effectiveLimit
        let reallyUnplugged = !r.isPluggedIn && elapsed >= Self.unplugGrace
        if resumed || reallyUnplugged {
            restoredAt = nil; state.chargingNotResumed = false
            return
        }
        if elapsed >= Self.verifyWindow { state.chargingNotResumed = true; return }
        if retries < Self.retryAt.count, elapsed >= Self.retryAt[retries] {
            retries += 1
            _ = await controller.apply(.allowCharging)
        }
    }
}
