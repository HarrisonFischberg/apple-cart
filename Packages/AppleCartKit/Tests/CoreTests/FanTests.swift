import Foundation
import Testing
@testable import Core

private let range = FanRange(minRPM: 2317, maxRPM: 6550)
private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func decide(_ mode: FanControlMode, percent: Int = 50, curve: FanCurve = .default, soc: Double? = 60, battery: Double? = nil,
                    thermal: Bool = false, range: FanRange? = range, at: Date = t0, _ state: inout FanPolicyState) -> FanDecision {
    FanPolicy.decide(mode: mode, manualPercent: percent, curve: curve, temperatures: FanTemperatures(cpu: soc, gpu: soc.map { $0 - 5 }, battery: battery),
                     thermalPressure: thermal, range: range, now: at, state: &state)
}

@Suite struct FanPolicyTests {
    @Test func percentMapsMinToMaxInFiftyRpmSteps() {
        #expect(range.rpm(percent: 0) == 2317) // never below the minimum running speed, even after rounding
        #expect(range.rpm(percent: 50) == 4450) // midpoint 4433.5 rounded to 50
        #expect(range.rpm(percent: 100) == 6550)
        #expect(range.rpm(percent: 150) == 6550 && range.rpm(percent: -10) == 2317)
        #expect(FanPreset.allCases.map(\.percent) == [0, 50, 100])
    }

    @Test func modes() {
        var s = FanPolicyState()
        #expect(decide(.system, &s) == .system(.chosen))
        s = FanPolicyState()
        #expect(decide(.manual, percent: 0, &s) == .hold(rpm: 2317))
        s = FanPolicyState()
        #expect(decide(.manual, percent: 100, &s) == .hold(rpm: 6550))
        s = FanPolicyState()
        #expect(decide(.curve, soc: 75, &s) == .hold(rpm: range.rpm(percent: 40)))
    }

    @Test func curveInterpolatesAndZeroMeansSystem() {
        let c = FanCurve.default
        #expect(c.percent(at: 40) == 0 && c.percent(at: 60) == 0)
        #expect(c.percent(at: 64) == 7.5)
        #expect(c.percent(at: 78.5) == 55)
        #expect(c.percent(at: 99) == 100)
        var s = FanPolicyState()
        #expect(decide(.curve, soc: 50, &s) == .system(.belowCurve(50))) // macOS keeps the fan off at idle
        let high = FanCurve(points: [FanCurvePoint(50, 20), FanCurvePoint(70, 100)])
        s = FanPolicyState()
        #expect(decide(.curve, curve: high, soc: 45, &s) == .hold(rpm: range.rpm(percent: 20))) // below the first point: its speed
    }

    @Test func curveValidationKeepsTheRules() {
        let v = FanCurve(points: [FanCurvePoint(30, 150), FanCurvePoint(30, -5), FanCurvePoint(120, 50)] + (0..<6).map { FanCurvePoint(60 + $0, 10) },
                         sensors: [.cpu, .cpu, .gpu, .battery]).validated
        #expect(v.points.count <= FanCurve.maxPoints)
        #expect(zip(v.points, v.points.dropFirst()).allSatisfy { $0.tempC < $1.tempC })
        #expect(v.points.allSatisfy { FanCurve.tempRange.contains($0.tempC) && FanCurve.percentRange.contains($0.percent) })
        #expect(v.sensors == [.cpu, .gpu])
        #expect(FanCurve(points: [FanCurvePoint(50, 10)]).validated.points == FanCurve.default.points)
    }

    @Test func secondSensorTakesTheHotterAndAnUnknownOneReleases() {
        let c = FanCurve(points: [FanCurvePoint(40, 0), FanCurvePoint(80, 100)], sensors: [.hottestSoC, .battery])
        #expect(c.temperature(FanTemperatures(cpu: 50, battery: 60)) == 60)
        #expect(c.temperature(FanTemperatures(cpu: 50, battery: nil)) == nil)
        var s = FanPolicyState()
        #expect(decide(.curve, curve: c, soc: 50, battery: nil, &s) == .system(.noTemperature))
    }

    @Test func unknownTemperatureNeverHoldsAManualSpeed() {
        for mode in [FanControlMode.manual, .curve] {
            var s = FanPolicyState()
            #expect(decide(mode, soc: nil, &s) == .system(.noTemperature))
        }
        var s = FanPolicyState()
        #expect(decide(.manual, range: nil, &s) == .system(.noRange))
    }

    @Test func ninetyDegreesReleasesForTwoMinutes() {
        var s = FanPolicyState()
        #expect(decide(.manual, percent: 100, soc: 90, &s) == .system(.hot(90)))
        #expect(decide(.manual, percent: 100, soc: 60, at: t0 + 60, &s) == .system(.coolingDown))
        #expect(decide(.manual, percent: 100, soc: 60, at: t0 + 119, &s) == .system(.coolingDown))
        #expect(decide(.manual, percent: 100, soc: 60, at: t0 + 120, &s) == .hold(rpm: 6550))
    }

    @Test func thermalPressureReleasesForTwoMinutes() {
        var s = FanPolicyState()
        #expect(decide(.manual, thermal: true, &s) == .system(.thermalPressure))
        #expect(decide(.manual, at: t0 + 100, &s) == .system(.coolingDown))
        #expect(decide(.manual, at: t0 + 121, &s) == .hold(rpm: 4450))
    }

    @Test func safetyWatchesTheHottestSensorNotTheAverage() {
        // Averages 85 C, one P-core cluster at 104 C: released.
        var s = FanPolicyState()
        let t = FanTemperatures(cpu: 85, gpu: 70, hottestSensor: 104)
        #expect(FanPolicy.decide(mode: .manual, manualPercent: 50, curve: .default, temperatures: t, thermalPressure: false,
                                 range: range, now: t0, state: &s) == .system(.hot(104)))
        // The reader takes the hottest plausible sensor, leaving out the 0.0 of sensors that are off.
        #expect(ChipTemperatures.hottest(["Tp01": 84, "Tp02": 104, "Te01": 67]) == 104)
        #expect(ChipTemperatures.average(["Tp01": 84, "Tp02": 104, "Te01": 67]) == 85)
        let withZero = ["Tp01": 61.0, "Tz00": 0.0, "Tg01": 58.0]
        #expect(ChipTemperatures.hottest(withZero) == 61) // a 0.0 is neither hot nor makes it unknown
        var z = FanPolicyState()
        #expect(FanPolicy.decide(mode: .manual, manualPercent: 50, curve: .default, temperatures: FanTemperatures(cpu: 60, gpu: 58, hottestSensor: ChipTemperatures.hottest(withZero)),
                                 thermalPressure: false, range: range, now: t0, state: &z) == .hold(rpm: 4450))
        #expect(ChipTemperatures.hottest(["Tp01": 0, "Tp02": 140]) == nil) // nothing plausible: unknown
    }

    @Test func afterAHeatReleaseManualWaitsForBelow80() {
        var s = FanPolicyState()
        #expect(decide(.manual, soc: 91, &s) == .system(.hot(91)))
        #expect(decide(.manual, soc: 89, at: t0 + 121, &s) == .system(.coolingDown)) // lockout over, but still hot
        #expect(decide(.manual, soc: 80, at: t0 + 200, &s) == .system(.coolingDown))
        #expect(decide(.manual, soc: 79, at: t0 + 210, &s) == .hold(rpm: 4450))
        #expect(decide(.manual, soc: 85, at: t0 + 220, &s) == .hold(rpm: 4450)) // latch cleared: 85 C is fine again
        var p = FanPolicyState()
        _ = decide(.curve, thermal: true, &p)
        #expect(decide(.curve, soc: 82, at: t0 + 130, &p) == .system(.coolingDown)) // same rule after thermal pressure
    }

    @Test func smoothingStopsHunting() {
        let c = FanCurve(points: [FanCurvePoint(40, 0), FanCurvePoint(100, 100)])
        var s = FanPolicyState()
        guard case .hold(let first) = decide(.curve, curve: c, soc: 70, &s) else { Issue.record("no hold"); return }
        // A small rise within 10 s keeps the old target.
        #expect(decide(.curve, curve: c, soc: 71, at: t0 + 5, &s) == .hold(rpm: first))
        // After 10 s it follows.
        #expect(decide(.curve, curve: c, soc: 71, at: t0 + 10, &s) != .hold(rpm: first))
        // A big jump (> 100 rpm) is taken at once.
        guard case .hold(let now) = decide(.curve, curve: c, soc: 71, at: t0 + 11, &s) else { return }
        #expect(decide(.curve, curve: c, soc: 85, at: t0 + 12, &s) != .hold(rpm: now))
        // Dropping to 0% waits the 10 s too, but a safety release does not.
        var z = FanPolicyState()
        _ = decide(.curve, curve: c, soc: 70, &z)
        #expect(decide(.curve, curve: c, soc: 30, at: t0 + 3, &z) != .system(.belowCurve(30)))
        #expect(decide(.curve, curve: c, soc: 30, at: t0 + 10, &z) == .system(.belowCurve(30)))
        var h = FanPolicyState()
        _ = decide(.curve, curve: c, soc: 70, &h)
        #expect(decide(.curve, curve: c, soc: 95, at: t0 + 1, &h) == .system(.hot(95)))
    }

    @MainActor @Test func settingsStartInSystemUnlessResumeIsOn() {
        let d = UserDefaults(suiteName: "fan-" + UUID().uuidString)!
        let s = FanSettings(defaults: d)
        #expect(s.active == .system && !s.resume && s.curve == .default && s.manualPercent == 50)
        s.applyManual(percent: 60)
        #expect(FanSettings(defaults: d).active == .system) // relaunch without Resume: macOS
        s.applyManual(percent: 60)
        s.setResume(true)
        let again = FanSettings(defaults: d)
        #expect(again.active == .manual && again.manualPercent == 60)
    }
}

final class FakeFanController: FanController, @unchecked Sendable {
    enum Call: Equatable { case set(Int), reset }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var report = FanHelperReport(.ready, manual: false)
    var result: ChargeApplyResult = .applied
    var resetResult: ChargeApplyResult = .applied
    /// What a fan that obeys would be turning at now (0 after a reset).
    var commandedRPM = 0.0
    /// Runs inside setFan, to simulate a status poll racing the set.
    var duringSet: (@MainActor () async -> Void)?
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
    func clear() { lock.lock(); _calls = []; lock.unlock() }
    private func record(_ c: Call) { lock.lock(); _calls.append(c); lock.unlock() }
    func status() async -> FanHelperReport { report }
    func setFan(rpm: Int) async -> ChargeApplyResult {
        record(.set(rpm))
        if let duringSet { await duringSet() }
        if result == .applied { commandedRPM = Double(rpm) }
        return result
    }
    func resetFan() async -> ChargeApplyResult { record(.reset); commandedRPM = 0; return resetResult }
}

@MainActor
private final class FanRig {
    var clock = t0
    let settings = FanSettings(defaults: UserDefaults(suiteName: "fanrunner-" + UUID().uuidString)!)
    let controller = FakeFanController()
    lazy var runner = FanRunner(settings: settings, controller: controller, now: { [unowned self] in self.clock })
    /// False: the fan ignores the helper and stays where it is (stopped).
    var fanObeys = true

    func sample(soc: Double? = 60, thermal: Bool = false, fans: Int = 1, hottest: Double? = nil) -> FanSample {
        FanSample(reading: FanReading(rpms: Array(repeating: fanObeys ? controller.commandedRPM : 0, count: fans), range: fans > 0 ? range : nil),
                  temperatures: FanTemperatures(cpu: soc, gpu: soc, hottestSensor: hottest), thermalPressure: thermal)
    }

    func feed(soc: Double? = 60, thermal: Bool = false, hottest: Double? = nil, after seconds: TimeInterval = 0) async {
        clock += seconds
        await runner.evaluate(sample(soc: soc, thermal: thermal, hottest: hottest))
    }

    /// Tool on, Manual 50% applied and confirmed, calls cleared.
    func holding() async {
        await runner.setToolEnabled(true)
        settings.applyManual(percent: 50)
        await feed()
        #expect(runner.state.holdingRPM == 4450)
        controller.clear()
    }
}

@MainActor
@Suite struct FanRunnerTests {
    @Test func systemByDefaultWritesNothing() async {
        let rig = FanRig()
        await rig.runner.setToolEnabled(true)
        rig.controller.clear()
        await rig.feed()
        #expect(rig.controller.calls.isEmpty)
        #expect(rig.runner.state.statusText == "macOS is controlling the fans.")
        #expect(rig.runner.state.subtitle == "System")
    }

    @Test func manualIsRenewedEvery30Seconds() async {
        let rig = FanRig()
        await rig.holding()
        #expect(rig.runner.state.subtitle == "Manual 50%" && rig.runner.state.statusText == "Holding 4,450 rpm")
        await rig.feed(after: 5); await rig.feed(after: 5); await rig.feed(after: 5)
        #expect(rig.controller.calls.isEmpty)
        await rig.feed(after: 15)
        #expect(rig.controller.calls == [.set(4450)])
    }

    @Test func toolOffQuitAndWakeRestore() async {
        let rig = FanRig()
        await rig.holding()
        await rig.runner.setToolEnabled(false)
        #expect(rig.controller.calls == [.reset] && rig.settings.active == .system)
        let rig2 = FanRig()
        await rig2.holding()
        await rig2.runner.shutdown()
        #expect(rig2.controller.calls == [.reset])
        let rig3 = FanRig()
        await rig3.holding()
        await rig3.runner.systemDidWake()
        #expect(rig3.controller.calls == [.reset])
        #expect(rig3.settings.active == .system && rig3.runner.state.holdingRPM == nil) // no Resume: stays with macOS
    }

    @Test func wakeWithResumeReappliesOnceTheTemperatureIsKnown() async {
        let rig = FanRig()
        await rig.holding()
        rig.settings.setResume(true)
        await rig.runner.systemDidWake()
        #expect(rig.settings.active == .manual)
        rig.controller.clear()
        await rig.feed(soc: nil, after: 5)
        #expect(rig.controller.calls.isEmpty) // never while the temperature is unknown
        await rig.feed(soc: 60, after: 5)
        #expect(rig.controller.calls == [.set(4450)])
    }

    @Test func failureRestores() async {
        let rig = FanRig()
        await rig.holding()
        rig.controller.result = .failed("x")
        await rig.feed(after: 30)
        #expect(rig.controller.calls == [.set(4450), .reset], "\(rig.controller.calls)")
        #expect(rig.runner.state.commandFailed && rig.runner.state.holdingRPM == nil)
        #expect(rig.runner.state.subtitle == "System")
    }

    @Test func unknownTemperatureAndHeatRelease() async {
        let rig = FanRig()
        await rig.holding()
        await rig.feed(soc: nil, after: 5)
        #expect(rig.controller.calls == [.reset])
        rig.controller.clear()
        await rig.feed(soc: 60, after: 15)
        #expect(rig.controller.calls == [.set(4450)])
        rig.controller.clear()
        await rig.feed(soc: 92, after: 5)
        #expect(rig.controller.calls == [.reset])
        rig.controller.clear()
        await rig.feed(soc: 60, after: 60)
        #expect(rig.controller.calls.isEmpty) // locked out for 2 minutes
        await rig.feed(soc: 60, after: 61)
        #expect(rig.controller.calls == [.set(4450)])
        rig.controller.clear()
        await rig.feed(soc: 60, thermal: true, after: 5)
        #expect(rig.controller.calls == [.reset])
    }

    @Test func helperUndidItOrIsNotReady() async {
        let rig = FanRig()
        await rig.holding()
        rig.controller.report = FanHelperReport(.ready, manual: false) // lease or sleep ended it
        await rig.feed(after: 31)
        #expect(rig.controller.calls == [.set(4450)]) // re-sent at once, not left claiming a hold
        rig.controller.clear()
        rig.controller.report = FanHelperReport(.outdated)
        await rig.feed(after: 31)
        #expect(rig.controller.calls == [.reset] && rig.runner.state.holdingRPM == nil)
        #expect(rig.runner.state.statusText.contains("out of date"))
    }

    @Test func noFanIsAnHonestEmptyState() async {
        let rig = FanRig()
        await rig.runner.setToolEnabled(true)
        rig.settings.applyManual(percent: 100)
        rig.controller.clear()
        await rig.runner.evaluate(rig.sample(fans: 0))
        #expect(rig.controller.calls.isEmpty)
        #expect(rig.runner.state.statusText == "This Mac has no fan.")
    }

    @Test func unknownManualFromAHelperIsHandedBack() async {
        let rig = FanRig()
        rig.controller.report = FanHelperReport(.ready, manual: true, targetRPM: 3000)
        await rig.runner.setToolEnabled(true)
        #expect(rig.controller.calls == [.reset]) // handed back as soon as the tool starts
        rig.controller.report = FanHelperReport(.ready, manual: false)
        rig.controller.clear()
        await rig.feed(after: 31)
        #expect(rig.controller.calls.isEmpty)
    }

    @Test func curveStatusNamesTheCurveTemperatureInCelsius() async {
        let rig = FanRig()
        await rig.runner.setToolEnabled(true)
        rig.settings.applyCurve(.default)
        await rig.feed(soc: 75)
        #expect(rig.runner.state.subtitle == "Curve")
        #expect(rig.runner.state.statusText == "Curve: 75 °C → \(FanText.rpm(range.rpm(percent: 40)))")
    }

    @Test func shutdownKeepsTheModeOnlyWithResume() async {
        let rig = FanRig()
        await rig.holding()
        await rig.runner.shutdown()
        #expect(rig.controller.calls == [.reset] && rig.settings.active == .system) // Resume off: forgotten
        let rig2 = FanRig()
        await rig2.holding()
        rig2.settings.setResume(true)
        await rig2.runner.shutdown()
        #expect(rig2.controller.calls == [.reset]) // fans always go back to macOS on quit
        #expect(rig2.settings.active == .manual) // but the next launch re-applies Manual 50%
        // Relaunch: nothing before the helper is ready and a temperature is known.
        let next = FanRunner(settings: rig2.settings, controller: rig2.controller, now: { [rig2] in rig2.clock })
        rig2.controller.clear()
        await next.setToolEnabled(true)
        await next.evaluate(FanSample(reading: FanReading(rpms: [0], range: range), temperatures: FanTemperatures(), thermalPressure: false))
        #expect(rig2.controller.calls.isEmpty)
        await next.evaluate(rig2.sample())
        #expect(rig2.controller.calls == [.set(4450)])
    }

    @Test func fanThatDoesNotRespondIsHandedBackOnce() async {
        let rig = FanRig()
        rig.fanObeys = false
        await rig.runner.setToolEnabled(true)
        rig.settings.applyManual(percent: 0)
        await rig.runner.applyChanged()
        await rig.feed()
        #expect(rig.controller.calls.last == .set(2317))
        rig.controller.clear()
        await rig.feed(after: 5); await rig.feed(after: 5)
        #expect(rig.controller.calls.isEmpty) // spin-up time
        await rig.feed(after: 5)
        #expect(rig.controller.calls == [.reset])
        #expect(rig.runner.state.statusText == FanState.notRespondingText && rig.runner.state.holdingRPM == nil)
        rig.controller.clear()
        await rig.feed(after: 30); await rig.feed(after: 30)
        #expect(rig.controller.calls.isEmpty) // no automatic retry
        rig.fanObeys = true
        await rig.runner.applyChanged() // the owner applies again
        await rig.feed(after: 5)
        #expect(rig.controller.calls == [.set(2317)])
        #expect(!rig.runner.state.fanNotResponding)
    }

    @Test func watchdogWindowRestartsWhenTheCurveMovesTheTarget() async {
        let rig = FanRig()
        rig.fanObeys = false // still spinning up: reads below either target
        await rig.runner.setToolEnabled(true)
        rig.settings.applyCurve(.default)
        await rig.feed(soc: 75)
        guard case .set(let first)? = rig.controller.calls.last else { Issue.record("no first apply"); return }
        await rig.feed(soc: 85, after: 10) // warming up: the curve raises the target 10 s in
        guard case .set(let second)? = rig.controller.calls.last, second != first else { Issue.record("target did not move"); return }
        rig.controller.clear()
        await rig.feed(soc: 85, after: 5) // 15 s after the first target, 5 s after the new one
        #expect(!rig.controller.calls.contains(.reset) && !rig.runner.state.fanNotResponding)
        await rig.feed(soc: 85, after: 10) // a full window on the new target and still nothing
        #expect(rig.controller.calls.contains(.reset) && rig.runner.state.fanNotResponding)
    }

    @Test func fanThatRespondsPassesTheWatchdog() async {
        let rig = FanRig()
        await rig.holding()
        for _ in 0..<6 { await rig.feed(after: 5) }
        #expect(rig.runner.state.holdingRPM == 4450 && !rig.runner.state.fanNotResponding)
        #expect(!rig.controller.calls.contains(.reset))
    }

    @Test func anotherAppIsHandedBackOnceThenLeftAlone() async {
        let rig = FanRig()
        rig.controller.report = FanHelperReport(.ready, manual: true, targetRPM: 3000)
        await rig.runner.setToolEnabled(true)
        #expect(rig.controller.calls == [.reset]) // once
        rig.controller.clear()
        await rig.feed(after: 31) // it set manual again
        await rig.feed(after: 31); await rig.feed(after: 31)
        #expect(rig.controller.calls.isEmpty)
        #expect(rig.runner.state.statusText == FanState.otherAppText)
        rig.settings.applyManual(percent: 50)
        await rig.runner.applyChanged() // the owner takes over on purpose
        #expect(rig.controller.calls == [.set(4450)])
        #expect(!rig.runner.state.otherAppControls)
    }

    @Test func ourOwnApplyIsNeverTakenForAnotherApp() async {
        let rig = FanRig()
        await rig.runner.setToolEnabled(true)
        rig.controller.clear()
        // Our set's reply is lost (it may still have landed) and the reset after it succeeds, so nothing of ours is
        // "live" any more; a status poll racing that set still sees manual mode.
        rig.controller.report = FanHelperReport(.ready, manual: true, targetRPM: 4450)
        rig.controller.result = .failed("timeout")
        rig.controller.duringSet = { [runner = rig.runner] in await runner.refreshHelperStatus() }
        rig.settings.applyManual(percent: 50)
        await rig.feed()
        rig.controller.duringSet = nil
        #expect(rig.controller.calls == [.set(4450), .reset])
        rig.settings.setActive(.system) // the owner gives up; only the helper's stale "manual" is left
        rig.clock += 5
        await rig.runner.refreshHelperStatus()
        rig.clock += 10
        await rig.runner.refreshHelperStatus()
        #expect(!rig.runner.state.otherAppControls) // within 20 s of our own apply: ours, not another app's
        rig.controller.clear()
        await rig.feed()
        #expect(rig.controller.calls.isEmpty) // and no "hand back" reset fired at it either
        rig.clock += 10
        await rig.runner.refreshHelperStatus() // 25 s later it is someone else's: handed back once
        rig.controller.clear()
        await rig.feed()
        #expect(rig.controller.calls == [.reset])
        rig.clock += 31
        await rig.runner.refreshHelperStatus()
        #expect(rig.runner.state.otherAppControls)
    }

    @Test func systemNeedsApplyLikeTheOtherModes() async {
        let rig = FanRig()
        await rig.runner.setToolEnabled(true)
        rig.settings.applyManual(percent: FanPreset.max.percent)
        await rig.runner.applyChanged()
        await rig.feed()
        #expect(rig.runner.state.holdingRPM == 6550 && rig.runner.state.subtitle == "Manual 100%")
        rig.controller.clear()
        // Selecting the System segment is view state only (FanSpeedView.choose touches neither settings nor the runner):
        // the next passes keep Max and send nothing new.
        await rig.feed(after: 5); await rig.feed(after: 5)
        #expect(rig.controller.calls.isEmpty && rig.settings.active == .manual)
        #expect(rig.runner.state.subtitle == "Manual 100%") // confirmed state, not the selected segment
        await rig.runner.applySystem() // "Apply system control"
        #expect(rig.controller.calls == [.reset])
        #expect(rig.settings.active == .system && rig.runner.state.holdingRPM == nil && rig.runner.state.subtitle == "System")
        rig.controller.clear()
        await rig.feed(after: 5)
        #expect(rig.controller.calls.isEmpty)
        // Applying System with nothing of ours held still sends the reset (the owner asked for it).
        await rig.runner.applySystem()
        #expect(rig.controller.calls == [.reset])
    }

    @Test func fanTextShowsFanOff() {
        #expect(FanText.current(0) == "Fan off")
        #expect(FanText.current(1840) == "Current 1,840 RPM")
    }
}
