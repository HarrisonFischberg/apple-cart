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
    /// The latest battery level the runner saw, so the panel can offer Discharge only when it applies.
    public var level: Int?
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
        case .unsupported: return "Not supported on this Mac."
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
    /// During a cut, an unplugged reading longer than this is taken as a real unplug (unless cuts are known to hide the plug).
    public static let unplugDuringCutGrace: TimeInterval = 10
    /// Cuts are only started or renewed from a reading at most this old.
    public static let freshReading: TimeInterval = 15
    /// After launch, reconnect or wake: plugged, well below the limit and not charging this long starts the resume check.
    public static let stallAfter: TimeInterval = 60
    public static let stallWatch: TimeInterval = 300
    public static let statusEvery: TimeInterval = 30
    /// The helper's own lease; past this a cut has certainly been undone by the helper.
    public static let leaseSeconds: TimeInterval = 90

    public private(set) var state = ChargeLimitState()
    @ObservationIgnored private let settings: ChargeLimitSettings
    @ObservationIgnored private let controller: ChargeController
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var toolEnabled = false
    @ObservationIgnored private var lastCut: Date?          // the helper confirmed a cut at this time
    @ObservationIgnored private var maybeCutUntil: Date?    // a cut was sent and may be live until then (even unconfirmed)
    @ObservationIgnored private var restoredAt: Date?       // checking that charging resumed since then
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var unpluggedInCutSince: Date?
    @ObservationIgnored private var releasedForUnplugAt: Date?
    /// Learned this session: our cut makes macOS report "unplugged" even with the charger in.
    @ObservationIgnored private(set) var cutHidesPlug = false
    @ObservationIgnored private var stallSince: Date?
    @ObservationIgnored private var stallWatchUntil: Date?
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
        toolEnabled && (settings.limit < 100 || settings.topUpActive || lastCut != nil || cutMayBeLive || restoredAt != nil || watchingForStall)
    }

    private var cutMayBeLive: Bool { maybeCutUntil.map { now() < $0 } ?? false }
    private var watchingForStall: Bool { stallWatchUntil.map { now() < $0 } ?? false }

    public func setToolEnabled(_ on: Bool) async {
        toolEnabled = on
        if on {
            stallWatchUntil = now().addingTimeInterval(Self.stallWatch) // launch: a helper-side restore may not have resumed charging
            await refreshHelperStatus()
            await evaluate(lastReading)
        } else {
            clearCommandState()
            stallWatchUntil = nil
            if await controller.resetAll() == .applied { maybeCutUntil = nil }
        }
    }

    /// The Mac woke: the helper restored the charger before sleep, so check the helper and watch for a stall.
    public func systemDidWake() async {
        stallWatchUntil = now().addingTimeInterval(Self.stallWatch)
        statusCheckedAt = nil
        await evaluate(lastReading)
    }

    /// After install, repair or approval: ask the helper again right away.
    public func refreshHelperStatus() async {
        statusCheckedAt = now()
        let report = await controller.status()
        if state.helperStatus != .ready && report.status == .ready { stallWatchUntil = now().addingTimeInterval(Self.stallWatch) }
        state.helperStatus = report.status
        guard report.status == .ready else { return }
        if report.adapterCut == false, lastCut != nil {
            // The helper restored on its own (lease, sleep, restart): stop claiming a hold and check charging resumes.
            lastCut = nil; maybeCutUntil = nil; state.holdingAt = nil
            restoredAt = now(); retries = 0
        } else if report.adapterCut == true, lastCut == nil, !cutMayBeLive {
            maybeCutUntil = now().addingTimeInterval(Self.leaseSeconds) // a cut we do not know about: restore it if not holding
        }
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

    private func clearCommandState() {
        lastCut = nil; restoredAt = nil; unpluggedInCutSince = nil; releasedForUnplugAt = nil; stallSince = nil
        state.holdingAt = nil; state.chargingNotResumed = false; state.commandFailed = false
    }

    private func step(_ r: BatteryReading?) async {
        guard toolEnabled else { return }
        if statusCheckedAt.map({ now().timeIntervalSince($0) >= Self.statusEvery }) ?? true { await refreshHelperStatus() }
        let cut = lastCut != nil
        // Our own cut (or its aftermath) makes macOS report battery power, so only a plugged reading may end Top Up then.
        if let r, (!cut && restoredAt == nil) || r.isPluggedIn { settings.observe(r) }
        state.target = settings.effectiveLimit
        if let r { state.level = r.percent }
        guard state.helperStatus == .ready else {
            // Nothing can be commanded safely. If a cut may still be live, ask for the restore anyway.
            if cutMayBeLive, await controller.resetAll() == .applied { maybeCutUntil = nil }
            clearCommandState()
            return
        }
        if !cut, let released = releasedForUnplugAt, let r {
            if r.isPluggedIn {
                // We released for an "unplug" and the plug came straight back: our cut hides the charger on this Mac.
                if now().timeIntervalSince(released) <= Self.unplugGrace { cutHidesPlug = true }
                releasedForUnplugAt = nil
            } else if now().timeIntervalSince(released) > Self.unplugGrace {
                releasedForUnplugAt = nil
            }
        }
        let seen = plugAdjusted(r, cut: cut)
        var decision = ChargePolicy.decide(reading: seen, settings: settings)
        // Charging takes a while to start after a restore; "not charging" in that wait must not re-cut below the limit.
        if case .holdCharging = decision, restoredAt != nil, let seen, seen.limitLevel < settings.effectiveLimit { decision = .allowCharging }
        switch decision {
        case .holdCharging(let at), .discharge(to: let at):
            await hold(decision, at: at, reading: r)
        case .allowCharging:
            await allow(r)
        }
    }

    /// While our cut is active macOS may report battery power. AdapterDetails (already folded into isPluggedIn by the
    /// sampler) is the first signal; failing that, an unplugged reading is given a short grace, then taken as real.
    private func plugAdjusted(_ r: BatteryReading?, cut: Bool) -> BatteryReading? {
        guard cut, var x = r, !x.isPluggedIn else { unpluggedInCutSince = nil; return r }
        if cutHidesPlug { x.isPluggedIn = true; return x }
        let since = unpluggedInCutSince ?? now()
        unpluggedInCutSince = since
        if now().timeIntervalSince(since) < Self.unplugDuringCutGrace { x.isPluggedIn = true; return x }
        releasedForUnplugAt = now()
        return r
    }

    private func hold(_ decision: ChargeDecision, at: Int, reading r: BatteryReading?) async {
        // On this Mac hold and discharge are the same adapter cut; only the wording differs.
        let discharging = decision != .holdCharging(at: at)
        guard let r, abs(now().timeIntervalSince(r.date)) <= Self.freshReading else {
            // Never start or renew a cut from a stale reading; let the lease lapse instead.
            if let last = lastCut, now().timeIntervalSince(last) >= Self.leaseSeconds { lastCut = nil; state.holdingAt = nil }
            return
        }
        if let last = lastCut, now().timeIntervalSince(last) < Self.renewEvery {
            state.holdingAt = at; state.discharging = discharging; return
        }
        let wasCut = lastCut != nil
        maybeCutUntil = now().addingTimeInterval(Self.leaseSeconds)
        let result = await controller.apply(decision)
        guard toolEnabled else { if await controller.resetAll() == .applied { maybeCutUntil = nil }; return }
        if result == .applied {
            lastCut = now(); restoredAt = nil
            state.holdingAt = at; state.discharging = discharging; state.chargingNotResumed = false; state.commandFailed = false
        } else {
            // Failed or timed out: the cut may still have landed. Ask for the restore now, and keep asking while it may be live.
            lastCut = nil; state.holdingAt = nil; state.commandFailed = true
            if await controller.resetAll() == .applied { maybeCutUntil = nil }
            if wasCut { restoredAt = now(); retries = 0 }
            await refreshHelperStatus()
        }
    }

    private func allow(_ r: BatteryReading?) async {
        state.holdingAt = nil
        if lastCut != nil || cutMayBeLive {
            let result = await controller.apply(.allowCharging)
            if result == .applied || !cutMayBeLive {
                lastCut = nil; maybeCutUntil = nil; unpluggedInCutSince = nil
                restoredAt = now(); retries = 0; state.commandFailed = false
            } else {
                state.commandFailed = true // a cut may be live: send the restore again next pass
            }
            return
        }
        if let start = restoredAt { await verifyResume(r, since: start); return }
        // After launch, reconnect or wake the helper may have restored the charger without charging resuming.
        if watchingForStall, let r, r.isPluggedIn, !r.isCharging, r.percent <= settings.effectiveLimit - ChargePolicy.hysteresis {
            let since = stallSince ?? now()
            stallSince = since
            if now().timeIntervalSince(since) >= Self.stallAfter {
                stallSince = nil; restoredAt = since; retries = 0
                await verifyResume(r, since: since)
            }
        } else {
            stallSince = nil
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
