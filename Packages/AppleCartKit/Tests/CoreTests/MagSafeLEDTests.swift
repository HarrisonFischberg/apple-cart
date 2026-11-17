import Foundation
import Testing
@testable import Core

final class FakeLEDController: LEDController, @unchecked Sendable {
    enum Call: Equatable { case set(LEDColor), reset }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var helperStatus: ChargeHelperStatus = .ready
    var result: ChargeApplyResult = .applied
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
    func clear() { lock.lock(); _calls = []; lock.unlock() }
    private func record(_ c: Call) { lock.lock(); _calls.append(c); lock.unlock() }
    func status() async -> ChargeHelperStatus { helperStatus }
    func setLED(_ color: LEDColor) async -> ChargeApplyResult { record(.set(color)); return result }
    func resetLED() async -> ChargeApplyResult { record(.reset); return .applied }
}

private func state(holding: Int? = nil, heat: Double? = nil, level: Int? = 80, helper: ChargeHelperStatus = .ready, sailFloor: Int? = nil,
                   discharging: Bool = false) -> ChargeLimitState {
    var s = ChargeLimitState()
    s.helperStatus = helper; s.holdingAt = holding; s.heatPausedAtC = heat; s.level = level; s.sailFloor = sailFloor; s.discharging = discharging
    return s
}

@Suite struct LEDPolicyTests {
    private func decide(_ s: ChargeLimitState, indicate: Bool = true, tool: Bool = true, topUp: Bool = false) -> LEDColor {
        LEDPolicy.decide(indicate: indicate, toolEnabled: tool, state: s, topUpActive: topUp)
    }

    @Test func atTheLimitSailingOrDischargingIsGreen() {
        #expect(decide(state(holding: 80)) == .green)
        #expect(decide(state(holding: 80, level: 77, sailFloor: 75)) == .green)
        #expect(decide(state(holding: 80, level: 90, discharging: true)) == .green)
    }

    @Test func heatPauseIsOrange() {
        #expect(decide(state(holding: 80, heat: 41)) == .orange)
        #expect(decide(state(holding: 100, heat: 41, level: 60), topUp: true) == .orange)
        #expect(decide(state(holding: nil, heat: 41)) == .system) // a stale temperature without a hold is not a pause
    }

    @Test func topUpIsGreenOnlyAtFull() {
        #expect(decide(state(level: 95), topUp: true) == .system)
        #expect(decide(state(level: 100), topUp: true) == .green)
    }

    @Test func chargingTowardTheLimitIsLeftToMacOS() {
        #expect(decide(state(level: 60)) == .system)
    }

    @Test func nothingForcedWhenOffOrHelperNotReady() {
        #expect(decide(state(holding: 80), indicate: false) == .system)
        #expect(decide(state(holding: 80), tool: false) == .system)
        for h: ChargeHelperStatus in [.notInstalled, .needsApproval, .outdated, .unreachable, .unsupported] {
            #expect(decide(state(holding: 80, helper: h)) == .system)
        }
    }
}

private func reading(_ percent: Int) -> BatteryReading {
    BatteryReading(properties: ["CurrentCapacity": percent, "ExternalConnected": 1, "IsCharging": 0])!
}

@MainActor
private final class LEDRig {
    var clock = Date(timeIntervalSince1970: 1_000_000)
    let settings = ChargeLimitSettings(defaults: UserDefaults(suiteName: "led-" + UUID().uuidString)!)
    let charge = FakeController()
    let led = FakeLEDController()
    lazy var limiter = ChargeLimiter(settings: settings, controller: charge, now: { [unowned self] in self.clock })
    lazy var runner = LEDRunner(settings: settings, limiter: limiter, controller: led, now: { [unowned self] in self.clock })

    /// Limit 80, battery at 80: the limiter confirms a hold.
    func holding(indicate: Bool = true) async {
        settings.setLimit(80)
        settings.setIndicateChargeLimit(indicate)
        await limiter.setToolEnabled(true)
        var r = reading(80); r.date = clock
        await limiter.evaluate(r)
        #expect(limiter.state.holdingAt == 80)
        await runner.setToolEnabled(true)
    }
}

@MainActor
@Suite struct LEDRunnerTests {
    @Test func offByDefaultAndForcesNothing() async {
        let rig = LEDRig()
        #expect(!rig.settings.indicateChargeLimit)
        await rig.holding(indicate: false)
        #expect(rig.led.calls.isEmpty && rig.runner.forced == .system)
    }

    @Test func settingPersists() {
        let d = UserDefaults(suiteName: "led-persist-" + UUID().uuidString)!
        ChargeLimitSettings(defaults: d).setIndicateChargeLimit(true)
        #expect(ChargeLimitSettings(defaults: d).indicateChargeLimit)
    }

    @Test func holdForcesGreenAndRenewsEvery30s() async {
        let rig = LEDRig()
        await rig.holding()
        #expect(rig.led.calls == [.set(.green)] && rig.runner.forced == .green)
        rig.clock += 10
        await rig.runner.evaluate()
        #expect(rig.led.calls == [.set(.green)])
        rig.clock += 25
        await rig.runner.evaluate()
        #expect(rig.led.calls == [.set(.green), .set(.green)])
    }

    @Test func turningTheSettingOffResets() async {
        let rig = LEDRig()
        await rig.holding()
        rig.settings.setIndicateChargeLimit(false)
        await rig.runner.evaluate()
        #expect(rig.led.calls == [.set(.green), .reset] && rig.runner.forced == .system)
        await rig.runner.evaluate()
        #expect(rig.led.calls.count == 2) // nothing forced any more: no more calls
    }

    @Test func toolOffAndShutdownReset() async {
        let rig = LEDRig()
        await rig.holding()
        await rig.runner.setToolEnabled(false)
        #expect(rig.led.calls.last == .reset)
        await rig.runner.setToolEnabled(true)
        rig.led.clear()
        await rig.runner.shutdown()
        #expect(rig.led.calls == [.reset])
    }

    @Test func wakeReappliesAtOnce() async {
        let rig = LEDRig()
        await rig.holding()
        rig.clock += 5
        await rig.runner.systemDidWake()
        #expect(rig.led.calls == [.set(.green), .set(.green)])
    }

    @Test func outdatedHelperGetsNothing() async {
        let rig = LEDRig()
        rig.led.helperStatus = .outdated
        await rig.holding()
        #expect(rig.led.calls.isEmpty && rig.runner.forced == .system)
    }

    @Test func failedSetIsNotClaimedAndIsHandedBack() async {
        let rig = LEDRig()
        rig.led.result = .failed("x")
        await rig.holding()
        #expect(rig.led.calls == [.set(.green), .reset] && rig.runner.forced == .system)
        rig.led.result = .applied
        await rig.runner.evaluate()
        #expect(rig.runner.forced == .green)
    }
}
