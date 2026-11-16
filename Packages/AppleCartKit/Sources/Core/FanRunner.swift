import Foundation
import Observation

/// One pass's inputs: the SMC fan readings, temperatures and macOS's thermal state.
public struct FanSample: Sendable {
    public var reading: FanReading?
    public var temperatures: FanTemperatures
    /// ProcessInfo thermal state is serious or critical.
    public var thermalPressure: Bool
    public init(reading: FanReading?, temperatures: FanTemperatures, thermalPressure: Bool) {
        self.reading = reading; self.temperatures = temperatures; self.thermalPressure = thermalPressure
    }
}

/// What the Fan speed panel shows. `holdingRPM` is set only after the helper confirmed a manual speed.
public struct FanState: Equatable, Sendable {
    public var helperStatus: ChargeHelperStatus = .notInstalled
    public var reading: FanReading?
    public var temperatures = FanTemperatures()
    public var decision: FanDecision?
    public var holdingRPM: Int?
    /// The mode the confirmed hold belongs to.
    public var holdingMode: FanControlMode = .system
    public var holdingPercent: Int?
    /// The temperature the curve followed for the confirmed hold.
    public var holdingTempC: Double?
    public var commandFailed = false
    public var waitingForWake = false
    /// The fan never reached the applied speed: handed back, and nothing manual until the owner applies again.
    public var fanNotResponding = false
    /// Someone else keeps the fans in manual mode: handed back once, then left alone until the owner applies again.
    public var otherAppControls = false

    public init() {}

    public static let notRespondingText = "The fan did not respond. Control returned to macOS."
    public static let otherAppText = "Another app is controlling the fans."

    /// No fan in the SMC (MacBook Air): an honest empty state, whatever the helper says.
    public var noFan: Bool { reading.map { $0.rpms.isEmpty } ?? false }

    /// Header subtitle from confirmed state only: "System", "Manual 60%", "Curve".
    public var subtitle: String {
        guard holdingRPM != nil else { return "System" }
        switch holdingMode {
        case .manual: return "Manual \(holdingPercent ?? 0)%"
        case .curve: return "Curve"
        case .system: return "System"
        }
    }

    public var statusText: String {
        if noFan { return "This Mac has no fan." }
        switch helperStatus {
        case .notInstalled: return "Install the Apple Cart helper in Settings to control the fans."
        case .needsApproval: return "Approve Apple Cart in Login Items."
        case .outdated: return "The helper is out of date. Repair it in Settings to control the fans."
        case .unreachable: return "The helper is not answering. Repair it in Settings."
        case .unsupported: return "Fan control is not supported on this Mac."
        case .ready: break
        }
        if otherAppControls { return Self.otherAppText }
        if fanNotResponding { return Self.notRespondingText }
        if waitingForWake { return "Waiting for the Mac to wake." }
        if commandFailed { return "Could not set the fans. macOS is controlling them." }
        if let rpm = holdingRPM {
            if holdingMode == .curve, let t = holdingTempC { return "Curve: \(FanText.celsius(t)) → \(FanText.rpm(rpm))" }
            return "Holding \(FanText.rpm(rpm))"
        }
        switch decision {
        case .system(.hot(let t))?: return "Hot (\(SystemText.temperature(t))): macOS has the fans for 2 minutes."
        case .system(.thermalPressure)?: return "Thermal pressure: macOS has the fans for 2 minutes."
        case .system(.coolingDown)?: return "Cooling down: macOS has the fans until the chip is below 80 °C."
        case .system(.noTemperature)?: return "Temperature unknown: macOS is controlling the fans."
        case .system(.belowCurve)?: return "Below the curve: macOS is controlling the fans."
        case .hold?: return "Applying…"
        default: return "macOS is controlling the fans."
        }
    }
}

public enum FanText {
    /// "Fan off" for a stopped fan, else "1,840 RPM".
    public static func current(_ rpm: Double?) -> String {
        guard let rpm else { return "Unknown" }
        return rpm < 1 ? "Fan off" : "Current \(Int(rpm.rounded()).formatted()) RPM"
    }

    public static func rpm(_ rpm: Int) -> String { "\(rpm.formatted()) rpm" }

    /// Curves are set in Celsius, so their temperatures are shown in Celsius too, whatever the region uses.
    public static func celsius(_ c: Double) -> String { "\(Int(c.rounded())) °C" }
}

/// The single writer of fan commands. While the Fan speed tool is on it turns each sample into a FanPolicy decision:
/// manual (renewed every 30 s on a 90 s helper lease) or back to macOS. Every failure, tool off, quit, delete-all,
/// wake and unknown temperature hands the fans back to macOS.
@MainActor @Observable
public final class FanRunner {
    public static let evaluateEvery: TimeInterval = 5
    public static let renewEvery: TimeInterval = 30
    public static let statusEvery: TimeInterval = 30
    /// The helper's own lease; past this a manual speed has certainly been undone by the helper.
    public static let leaseSeconds: TimeInterval = 90
    /// After a manual speed starts, every fan must be within `responseTolerance` of the target by then.
    public static let responseWindow: TimeInterval = 15
    public static let responseTolerance = 0.2
    /// A manual mode seen this soon after our own apply (or while it is in flight) is taken as ours, never another app's:
    /// a status poll can race the set.
    public static let ownApplyGrace: TimeInterval = 20

    public private(set) var state = FanState()
    public let settings: FanSettings
    @ObservationIgnored private let controller: FanController
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var toolEnabled = false
    @ObservationIgnored private var policy = FanPolicyState()
    @ObservationIgnored private var sentRPM: Int?
    @ObservationIgnored private var sentAt: Date?
    @ObservationIgnored private var maybeManualUntil: Date?
    @ObservationIgnored private var statusCheckedAt: Date?
    @ObservationIgnored private var lastSample: FanSample?
    /// A manual speed started at this time and its response has not been confirmed yet.
    @ObservationIgnored private var verifySince: Date?
    /// We handed a manual mode we did not set back to macOS once already this session.
    @ObservationIgnored private var handedBackForeign = false
    @ObservationIgnored private var applyInFlight = false
    @ObservationIgnored private var ownApplyAt: Date?
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var again = false

    public init(settings: FanSettings, controller: FanController, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.controller = controller
        self.now = now
    }

    private var manualMayBeLive: Bool { maybeManualUntil.map { now() < $0 } ?? false }

    /// The owner turned the tool on or off. Off also forgets the applied mode (System until Apply is pressed again).
    public func setToolEnabled(_ on: Bool) async {
        if !on { settings.setActive(.system) }
        state.fanNotResponding = false; state.otherAppControls = false; handedBackForeign = false
        await run(on)
    }

    private func run(_ on: Bool) async {
        toolEnabled = on
        if on {
            await refreshHelperStatus()
            await evaluate(lastSample)
        } else {
            clearCommandState()
            if await controller.resetFan() == .applied { maybeManualUntil = nil }
        }
    }

    /// The helper gave the fans back to macOS before sleep. Without Resume, they stay with macOS.
    public func systemDidWake() async {
        if !settings.resume { settings.setActive(.system) }
        if sentRPM != nil || manualMayBeLive, await controller.resetFan() == .applied { maybeManualUntil = nil }
        clearCommandState()
        statusCheckedAt = nil
        lastSample = nil // readings from before sleep are stale: wait for a fresh temperature before anything manual
        await evaluate(nil)
    }

    /// Apply pressed (or System chosen): start from a clean smoothing state and act now. The owner taking control again
    /// also clears "did not respond" and "another app" (the heat lockout and latch stay).
    public func applyChanged() async {
        var fresh = FanPolicyState()
        fresh.releasedUntil = policy.releasedUntil
        fresh.heatLatched = policy.heatLatched
        policy = fresh
        state.fanNotResponding = false; state.otherAppControls = false; handedBackForeign = false; verifySince = nil
        await evaluate(lastSample)
    }

    /// "Apply system control" (or Return to System): the owner hands the fans back on purpose. Always sends resetFan, even
    /// when nothing of ours is held, so a manual mode left by anyone goes back to macOS too.
    public func applySystem() async {
        settings.setActive(.system)
        state.fanNotResponding = false; state.otherAppControls = false; handedBackForeign = false; verifySince = nil
        var fresh = FanPolicyState()
        fresh.releasedUntil = policy.releasedUntil
        fresh.heatLatched = policy.heatLatched
        policy = fresh
        let result = await controller.resetFan()
        if result == .applied {
            sentRPM = nil; sentAt = nil; maybeManualUntil = nil
            state.holdingRPM = nil; state.holdingPercent = nil; state.holdingMode = .system; state.commandFailed = false
        } else if result != .unavailable {
            state.commandFailed = true // the next pass sends the reset again while manual may be live
        }
        await evaluate(lastSample)
    }

    public func refreshHelperStatus() async {
        statusCheckedAt = now()
        let report = await controller.status()
        state.helperStatus = report.status
        guard report.status == .ready else { return }
        if report.manual == false, sentRPM != nil {
            sentRPM = nil; sentAt = nil; state.holdingRPM = nil // lease, sleep or restart undid it; the next pass decides again
        } else if report.manual == true, sentRPM == nil, !manualMayBeLive, !applyInFlight,
                  ownApplyAt.map({ now().timeIntervalSince($0) >= Self.ownApplyGrace }) ?? true {
            // Manual mode we did not set. Hand it back once; if it comes back, another app wants it: leave it alone.
            if handedBackForeign { state.otherAppControls = true } else {
                handedBackForeign = true
                maybeManualUntil = now().addingTimeInterval(Self.leaseSeconds)
            }
        } else if report.manual == false {
            state.otherAppControls = false
        }
    }

    public func evaluate(_ sample: FanSample?) async {
        if let sample { lastSample = sample }
        guard !busy else { again = true; return }
        busy = true
        defer { busy = false }
        repeat {
            again = false
            await step(lastSample)
        } while again
    }

    /// Before quit or delete-all: fans to macOS, always. The applied mode is kept only when Resume is on, so the next
    /// launch can re-apply it (after the helper is ready and a fresh temperature is known).
    public func shutdown() async {
        if !settings.resume { settings.setActive(.system) }
        await run(false)
    }

    private func clearCommandState() {
        sentRPM = nil; sentAt = nil; verifySince = nil
        policy = FanPolicyState()
        state.holdingRPM = nil; state.holdingPercent = nil; state.holdingMode = .system
        state.commandFailed = false; state.waitingForWake = false; state.decision = nil
    }

    private func step(_ s: FanSample?) async {
        guard toolEnabled else { return }
        if statusCheckedAt.map({ now().timeIntervalSince($0) >= Self.statusEvery }) ?? true { await refreshHelperStatus() }
        if let s { state.reading = s.reading; state.temperatures = s.temperatures }
        guard state.helperStatus == .ready, !state.noFan else {
            if sentRPM != nil || manualMayBeLive, await controller.resetFan() == .applied { maybeManualUntil = nil }
            clearCommandState()
            return
        }
        if state.otherAppControls { state.holdingRPM = nil; state.decision = nil; return } // never fight another app
        if state.fanNotResponding { state.decision = nil; await release(); return }
        if await fanDidNotRespond() { return }
        let decision = FanPolicy.decide(mode: settings.active, manualPercent: settings.manualPercent, curve: settings.curve,
                                        temperatures: s?.temperatures ?? FanTemperatures(), thermalPressure: s?.thermalPressure ?? false,
                                        range: s?.reading?.range, now: now(), state: &policy)
        state.decision = decision
        switch decision {
        case .hold(let rpm): await hold(rpm, range: s?.reading?.range)
        case .system: await release()
        }
    }

    private func hold(_ rpm: Int, range: FanRange?) async {
        let mode = settings.active
        let percent = mode == .manual ? settings.manualPercent : range?.percent(rpm: rpm)
        state.holdingTempC = mode == .curve ? settings.curve.temperature(state.temperatures) : nil
        if sentRPM == rpm, let at = sentAt, now().timeIntervalSince(at) < Self.renewEvery {
            state.holdingRPM = rpm; state.holdingMode = mode; state.holdingPercent = percent
            return
        }
        maybeManualUntil = now().addingTimeInterval(Self.leaseSeconds)
        applyInFlight = true
        ownApplyAt = now()
        let result = await controller.setFan(rpm: rpm)
        applyInFlight = false
        ownApplyAt = now()
        guard toolEnabled else { if await controller.resetFan() == .applied { maybeManualUntil = nil }; return }
        switch result {
        case .applied:
            if sentRPM == nil { verifySince = now() } // a fresh start: check the fan really follows
            sentRPM = rpm; sentAt = now()
            state.holdingRPM = rpm; state.holdingMode = mode; state.holdingPercent = percent
            state.commandFailed = false; state.waitingForWake = false
        case .sleeping:
            sentRPM = nil; sentAt = nil; maybeManualUntil = nil; state.holdingRPM = nil; state.waitingForWake = true
        default:
            // Failed or timed out: it may still have landed. Hand the fans back now and keep asking while it may be live.
            sentRPM = nil; sentAt = nil; state.holdingRPM = nil; state.commandFailed = true
            if await controller.resetFan() == .applied { maybeManualUntil = nil }
            await refreshHelperStatus()
        }
    }

    /// Watchdog: once a manual speed has run for `responseWindow`, every fan must read within 20% of the target (a fan
    /// that was stopped must at least be turning). If not, the writes are not working on this Mac: hand back, say so,
    /// and do not retry until the owner presses Apply again.
    private func fanDidNotRespond() async -> Bool {
        guard let since = verifySince, let target = sentRPM, let reading = state.reading else { return false }
        let ok = !reading.rpms.isEmpty && reading.rpms.allSatisfy { rpm in
            guard let rpm else { return false }
            return rpm > 0 && abs(rpm - Double(target)) <= Double(target) * Self.responseTolerance
        }
        if ok { verifySince = nil; return false }
        guard now().timeIntervalSince(since) >= Self.responseWindow else { return false }
        state.fanNotResponding = true
        state.decision = nil
        await release()
        return true
    }

    private func release() async {
        state.holdingRPM = nil; state.holdingPercent = nil; state.holdingMode = .system
        state.waitingForWake = false
        guard sentRPM != nil || manualMayBeLive else { return }
        let result = await controller.resetFan()
        if result == .applied || !manualMayBeLive {
            sentRPM = nil; sentAt = nil; maybeManualUntil = nil; verifySince = nil
            if result == .applied { state.commandFailed = false }
        } else {
            state.commandFailed = true // manual may still be live: send the reset again next pass
        }
    }
}
