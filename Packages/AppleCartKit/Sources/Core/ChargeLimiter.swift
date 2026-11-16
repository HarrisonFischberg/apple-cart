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
    /// The charger was just given back and macOS has not started charging yet (it can take a while).
    public var resuming = false
    public var commandFailed = false
    /// The latest battery level the runner saw, so the panel can offer Discharge only when it applies.
    public var level: Int?
    public var waitingForWake = false
    /// The limit the runner is working towards (100 while Top Up is on).
    public var target = 100
    /// Lower edge of the sailing range while a confirmed hold sails; nil without Sailing.
    public var sailFloor: Int?
    /// The confirmed cut is a heat pause (the limit alone would let it charge); the battery temperature that caused it.
    public var heatPausedAtC: Double?

    public init() {}

    public static let notResumedText = "Charging has not resumed. Unplug and replug the charger."

    /// The confirmed hold in words, with its reason: heat, discharge, sailing range or the limit. Nil when nothing is held.
    public var holdText: String? {
        guard let n = holdingAt else { return nil }
        if let t = heatPausedAtC { return "Paused: battery is \(SystemText.temperature(t))" }
        if discharging { return "Discharging to \(n)%" }
        if let f = sailFloor, f < n { return "Sailing \(f)–\(n)%" }
        return "Holding at \(n)%"
    }

    public var reasonText: String {
        if chargingNotResumed { return Self.notResumedText }
        switch helperStatus {
        case .notInstalled: return "Install the charging helper in Settings to use this."
        case .needsApproval: return "Approve Apple Cart in Login Items."
        case .outdated: return "The charging helper is out of date. Repair it in Settings."
        case .unreachable: return "The charging helper is not answering. Repair it in Settings."
        case .unsupported: return "Not supported on this Mac."
        case .ready:
            if let h = holdText { return h }
            if waitingForWake { return "Waiting for the Mac to wake." }
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
    /// A new cut is held at least this long before the limit may release it.
    public static let minHold: TimeInterval = 60
    public static let verifyWindow: TimeInterval = 180
    /// Re-send the restore at these points if charging has not resumed.
    public static let retryAt: [TimeInterval] = [60, 120]
    /// Right after a restore macOS can still report battery power for a few seconds.
    public static let unplugGrace: TimeInterval = 30
    /// During a cut, an unplugged reading longer than this is taken as a real unplug (unless cuts are known to hide the plug).
    public static let unplugDuringCutGrace: TimeInterval = 10
    /// Cuts are only started or renewed from a reading at most this old.
    public static let freshReading: TimeInterval = 15
    /// Released-for-unplug readings that came straight back as plugged before we believe the cut hides the plug.
    public static let hiddenPlugSightings = 2
    /// Unplugged this long with no cut active: it was a real unplug, so forget what we learned.
    public static let forgetHiddenPlugAfter: TimeInterval = 180
    public static let statusEvery: TimeInterval = 30
    /// The helper's own lease; past this a cut has certainly been undone by the helper.
    public static let leaseSeconds: TimeInterval = 90

    public private(set) var state = ChargeLimitState()
    @ObservationIgnored private let settings: ChargeLimitSettings
    @ObservationIgnored private let controller: ChargeController
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var toolEnabled = false
    @ObservationIgnored private var cutStartedAt: Date?     // when the current run of cuts began
    @ObservationIgnored private var lastCut: Date?          // the helper confirmed a cut at this time
    @ObservationIgnored private var maybeCutUntil: Date?    // a cut was sent and may be live until then (even unconfirmed)
    @ObservationIgnored private var restoredAt: Date? { didSet { state.resuming = restoredAt != nil } } // checking that charging resumed since then
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var unpluggedInCutSince: Date?
    @ObservationIgnored private var releasedForUnplugAt: Date?
    /// Learned this session: our cut makes macOS report "unplugged" even with the charger in.
    @ObservationIgnored private(set) var cutHidesPlug = false
    @ObservationIgnored private var plugCameBack = 0
    @ObservationIgnored private var unpluggedWithoutCutSince: Date?
    /// A known cut was outstanding when the helper stopped being ready; check charging when it is back.
    @ObservationIgnored private var cutUndoneWhileAway = false
    @ObservationIgnored private var statusCheckedAt: Date?
    @ObservationIgnored private var lastReading: BatteryReading?
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var again = false
    @ObservationIgnored private var heat = HeatGuard()

    public init(settings: ChargeLimitSettings, controller: ChargeController, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.controller = controller
        self.now = now
    }

    /// Whether the app should keep the battery sampler running for this runner.
    public var wantsReadings: Bool {
        toolEnabled && (settings.limit < 100 || settings.topUpActive || settings.heatProtection || lastCut != nil || cutMayBeLive || restoredAt != nil)
    }

    private var cutMayBeLive: Bool { maybeCutUntil.map { now() < $0 } ?? false }

    public func setToolEnabled(_ on: Bool) async {
        toolEnabled = on
        if on {
            await refreshHelperStatus()
            await evaluate(lastReading)
        } else {
            clearCommandState()
            if await controller.resetAll() == .applied { maybeCutUntil = nil }
        }
    }

    /// The Mac woke. If we had a cut, the helper undid it before sleep: check that charging resumes.
    /// Without a cut of ours nothing is checked, so macOS's own holds (Optimized Battery Charging) never warn.
    public func systemDidWake() async {
        if lastCut != nil || cutMayBeLive { helperUndidCut() }
        statusCheckedAt = nil
        await evaluate(lastReading)
    }

    /// After install, repair or approval: ask the helper again right away.
    public func refreshHelperStatus() async {
        statusCheckedAt = now()
        let report = await controller.status()
        state.helperStatus = report.status
        guard report.status == .ready else { return }
        if cutUndoneWhileAway { cutUndoneWhileAway = false; restoredAt = now(); retries = 0 }
        if report.adapterCut == false, lastCut != nil {
            helperUndidCut() // lease, sleep or restart: stop claiming a hold and check charging resumes
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

    private func helperUndidCut() {
        lastCut = nil; maybeCutUntil = nil; state.holdingAt = nil
        restoredAt = now(); retries = 0
    }

    private func clearCommandState() {
        lastCut = nil; restoredAt = nil; unpluggedInCutSince = nil; releasedForUnplugAt = nil; cutStartedAt = nil
        heat = HeatGuard()
        state.holdingAt = nil; state.chargingNotResumed = false; state.commandFailed = false; state.waitingForWake = false
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
            if lastCut != nil || cutMayBeLive { cutUndoneWhileAway = true }
            if cutMayBeLive, await controller.resetAll() == .applied { maybeCutUntil = nil }
            clearCommandState()
            return
        }
        if !cut, let r { learnPlug(r) }
        let seen = plugAdjusted(r, cut: cut)
        var decision = ChargePolicy.decide(reading: seen, settings: settings)
        // Charging takes a while to start after a restore; "not charging" in that wait must not re-cut below the limit.
        if case .holdCharging = decision, restoredAt != nil, let seen, seen.limitLevel < settings.effectiveLimit { decision = .allowCharging }
        // A cut that has only just begun is not released for a one-point wobble of the reading (the battery's own figure
        // jitters by a point or two): holding for a minute first keeps it from switching on and off every few seconds.
        if decision == .allowCharging, lastCut != nil, let started = cutStartedAt, now().timeIntervalSince(started) < Self.minHold,
           let seen, seen.isPluggedIn, seen.limitLevel > settings.effectiveLimit - 3, settings.effectiveLimit < 100 {
            decision = .holdCharging(at: settings.effectiveLimit)
        }
        let freshReading = r.map { abs(now().timeIntervalSince($0.date)) <= Self.freshReading } ?? false
        let hot = heat.update(temperatureC: freshReading ? seen?.temperatureC : nil, maxC: settings.heatMaxC, enabled: settings.heatProtection,
                              pluggedIn: seen?.isPluggedIn ?? false, now: now())
        let limitDecision = decision
        decision = ChargePolicy.applyingHeat(decision, paused: hot, reading: seen, limit: settings.effectiveLimit)
        let heatC = decision != limitDecision ? seen?.temperatureC : nil
        switch decision {
        case .holdCharging(let at), .discharge(to: let at):
            await hold(decision, at: at, reading: r, heatC: heatC)
        case .allowCharging:
            await allow(r)
        }
    }

    /// We released a cut for an "unplug" and the plug came straight back: our cut probably hides the charger.
    /// A real quick unplug and replug looks the same once, so it takes two sightings; a long real unplug forgets it.
    private func learnPlug(_ r: BatteryReading) {
        if r.isPluggedIn { unpluggedWithoutCutSince = nil } else {
            let since = unpluggedWithoutCutSince ?? now()
            unpluggedWithoutCutSince = since
            if now().timeIntervalSince(since) > Self.forgetHiddenPlugAfter { cutHidesPlug = false; plugCameBack = 0 }
        }
        guard let released = releasedForUnplugAt else { return }
        if r.isPluggedIn {
            if now().timeIntervalSince(released) <= Self.unplugGrace {
                plugCameBack += 1
                if plugCameBack >= Self.hiddenPlugSightings { cutHidesPlug = true }
            }
            releasedForUnplugAt = nil
        } else if now().timeIntervalSince(released) > Self.unplugGrace {
            releasedForUnplugAt = nil
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

    private func hold(_ decision: ChargeDecision, at: Int, reading r: BatteryReading?, heatC: Double?) async {
        // On this Mac hold and discharge are the same adapter cut; only the wording differs.
        let discharging = decision != .holdCharging(at: at)
        let sailFloor = settings.effectiveSailing ? settings.sailFloor : nil
        guard let r, abs(now().timeIntervalSince(r.date)) <= Self.freshReading else {
            // Never start or renew a cut from a stale reading; let the lease lapse instead.
            if let last = lastCut, now().timeIntervalSince(last) >= Self.leaseSeconds { lastCut = nil; state.holdingAt = nil }
            return
        }
        if let last = lastCut, now().timeIntervalSince(last) < Self.renewEvery {
            state.holdingAt = at; state.discharging = discharging; state.sailFloor = sailFloor; state.heatPausedAtC = heatC; return
        }
        let wasCut = lastCut != nil
        if !wasCut { cutStartedAt = now() }
        maybeCutUntil = now().addingTimeInterval(Self.leaseSeconds)
        let result = await controller.apply(decision)
        guard toolEnabled else { if await controller.resetAll() == .applied { maybeCutUntil = nil }; return }
        if result == .applied {
            lastCut = now(); restoredAt = nil
            state.holdingAt = at; state.discharging = discharging; state.sailFloor = sailFloor; state.heatPausedAtC = heatC
            state.chargingNotResumed = false
            state.commandFailed = false; state.waitingForWake = false
        } else if result == .sleeping {
            // Refused before anything was written: the helper restored for sleep and blocks cuts until power-on.
            lastCut = nil; maybeCutUntil = nil; state.holdingAt = nil; state.waitingForWake = true
            if wasCut { restoredAt = now(); retries = 0 } // our cut was undone by the helper: still check charging resumes
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
        state.waitingForWake = false
        if let start = restoredAt { await verifyResume(r, since: start) }
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
