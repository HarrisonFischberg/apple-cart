import Foundation
import Testing
@testable import Core

/// macOS's own charge limit, faked: remembers what was set and reads it back like the real one.
final class FakeNative: NativeChargeLimit, @unchecked Sendable {
    private let lock = NSLock()
    var supported = true
    /// What macOS has now (the person's own setting before Apple Cart touches it).
    var limit: NativeLimitReading = .off
    /// Accept writes but read back something else (macOS ignoring the write).
    var ignoreWrites = false
    private var _writes: [Int] = []
    var writes: [Int] { lock.lock(); defer { lock.unlock() }; return _writes }
    func clear() { lock.lock(); _writes = []; lock.unlock() }

    func isSupported() async -> Bool { supported }
    func current() async -> NativeLimitReading? { limit }
    func setLimit(_ percent: Int) async -> NativeLimitReading? {
        lock.lock(); _writes.append(percent); lock.unlock()
        if !ignoreWrites { limit = percent >= 100 ? .off : NativeLimitReading(enabled: true, limit: percent) }
        return limit
    }
}

private func reading(_ percent: Int, plugged: Bool = true, charging: Bool = false, temperature: Double? = nil) -> BatteryReading {
    var d: [String: Any] = ["CurrentCapacity": percent, "ExternalConnected": plugged ? 1 : 0, "IsCharging": charging ? 1 : 0]
    if let temperature { d["Temperature"] = Int(temperature * 100) }
    return BatteryReading(properties: d)!
}

@MainActor
private final class NativeRig {
    var clock = Date(timeIntervalSince1970: 2_000_000)
    let defaults = UserDefaults(suiteName: "native-" + UUID().uuidString)!
    lazy var settings = ChargeLimitSettings(defaults: defaults)
    let controller = FakeController()
    let native = FakeNative()
    lazy var limiter = ChargeLimiter(settings: settings, controller: controller, native: native,
                                     nativeSnapshot: NativeLimitSnapshotStore(defaults: defaults), now: { [unowned self] in self.clock })

    init(limit: Int = 80, status: ChargeHelperStatus = .ready) {
        settings.setLimit(limit)
        controller.helperStatus = status
    }

    func on() async { await limiter.setToolEnabled(true) }
    func feed(_ r: BatteryReading?, after seconds: TimeInterval = 0) async {
        clock += seconds
        var r = r
        r?.date = clock
        await limiter.evaluate(r)
    }
}

@MainActor
@Suite struct NativeChargeLimitTests {
    // MARK: The reported bug: a hold at 80% must not cut the charger (that puts macOS on battery and dims the screen).

    @Test func holdAtEightyUsesMacOSLimitAndNeverCutsTheCharger() async {
        let rig = NativeRig()
        await rig.on()
        await rig.feed(reading(70, charging: true))
        #expect(rig.native.writes == [80])
        #expect(rig.limiter.state.native)
        #expect(rig.limiter.state.reasonText == "Charging up to 80%")
        await rig.feed(reading(80), after: 10)
        #expect(rig.controller.calls.isEmpty) // no CHIE cut, ever
        #expect(rig.native.writes == [80])    // written once, not every sample
        #expect(rig.limiter.state.holdingAt == 80)
        #expect(rig.limiter.state.reasonText == "Holding at 80%")
        #expect(!rig.limiter.state.holdRunsOnBattery)
        #expect(!rig.limiter.state.chargerCut)
    }

    @Test func worksWithoutTheHelper() async {
        let rig = NativeRig(status: .notInstalled)
        await rig.on()
        await rig.feed(reading(80))
        #expect(rig.native.writes == [80])
        #expect(rig.limiter.state.holdingAt == 80)
        #expect(rig.limiter.state.reasonText == "Holding at 80%")
    }

    @Test func doesNotClaimAHoldWhileStillCharging() async {
        let rig = NativeRig(limit: 90)
        await rig.on()
        await rig.feed(reading(85, charging: true))
        #expect(rig.limiter.state.holdingAt == nil)
        #expect(rig.limiter.state.reasonText == "Charging up to 90%")
    }

    // MARK: Sailing

    @Test func sailingFollowsTheBatteryDownThenChargesAtTheFloor() async {
        let rig = NativeRig(limit: 90)
        rig.settings.setSailing(true); rig.settings.setSailingDifference(5) // floor 85
        await rig.on()
        await rig.feed(reading(90))
        #expect(rig.native.writes == [90])
        #expect(rig.limiter.state.reasonText == "Sailing 85–90%")
        // Unplugged use drains it: macOS's limit follows the level so replugging does not top it up.
        await rig.feed(reading(88, plugged: false), after: 600)
        #expect(rig.native.writes == [90, 88])
        await rig.feed(reading(87), after: 600)
        #expect(rig.native.writes == [90, 88, 87])
        #expect(rig.limiter.state.holdingAt == 90)
        #expect(rig.limiter.state.reasonText == "Sailing 85–90%")
        // At the floor the limit goes back up and charging resumes.
        await rig.feed(reading(85), after: 600)
        #expect(rig.native.writes == [90, 88, 87, 90])
        await rig.feed(reading(87, charging: true), after: 60)
        #expect(rig.native.writes == [90, 88, 87, 90]) // keeps charging to the limit
        #expect(rig.controller.calls.isEmpty)
    }

    @Test func sailingNeverAsksMacOSForLessThanEighty() async {
        let rig = NativeRig(limit: 80)
        rig.settings.setSailing(true); rig.settings.setSailingDifference(10) // would be 70
        #expect(rig.settings.nativeSailFloor == 80)
        await rig.on()
        #expect(rig.limiter.shownSailFloor == 80)
        await rig.feed(reading(80))
        await rig.feed(reading(76, plugged: false), after: 600)
        await rig.feed(reading(72), after: 600)
        #expect(rig.native.writes.allSatisfy { $0 >= 80 })
        #expect(rig.controller.calls.isEmpty)
    }

    @Test func planFloorAndTarget() {
        #expect(NativeChargePlan.floor(limit: 90, sailFloor: 85) == 85)
        #expect(NativeChargePlan.floor(limit: 80, sailFloor: 75) == 80)
        #expect(NativeChargePlan.floor(limit: 90, sailFloor: nil) == 90)
        var latched = false
        #expect(NativeChargePlan.target(level: 70, limit: 90, floor: 85, latched: &latched) == 90)
        #expect(NativeChargePlan.target(level: 91, limit: 90, floor: 85, latched: &latched) == 90)
        #expect(latched)
        #expect(NativeChargePlan.target(level: 86, limit: 90, floor: 85, latched: &latched) == 86)
        #expect(NativeChargePlan.target(level: 85, limit: 90, floor: 85, latched: &latched) == 90)
        #expect(!latched)
        #expect(NativeChargePlan.target(level: 50, limit: 100, floor: 85, latched: &latched) == 100)
        #expect(NativeChargePlan.target(level: nil, limit: 85, floor: 80, latched: &latched) == 85)
    }

    // MARK: Other routes still cut the charger

    @Test func limitsBelowEightyStillCutAndShowTheDimmingTip() async {
        let rig = NativeRig(limit: 70)
        await rig.on()
        await rig.feed(reading(70))
        #expect(rig.native.writes.isEmpty)
        #expect(rig.controller.calls == [.hold(70)])
        #expect(!rig.limiter.state.native)
        #expect(rig.limiter.state.holdRunsOnBattery)
        #expect(rig.limiter.state.chargerCut)
    }

    @Test func dischargeStillUsesTheCutAndIsNotADimmingHold() async {
        let rig = NativeRig(limit: 80)
        rig.settings.setAutoDischarge(true)
        await rig.on()
        await rig.feed(reading(90))
        #expect(rig.controller.calls == [.discharge(80)])
        #expect(rig.limiter.state.reasonText == "Discharging to 80%")
        #expect(!rig.limiter.state.holdRunsOnBattery)
        // Back at the limit: the cut is released and macOS's limit holds.
        rig.controller.clear()
        await rig.feed(reading(80), after: 120)
        #expect(rig.controller.calls == [.allow])
        #expect(rig.native.writes.last == 80)
        #expect(rig.limiter.state.native)
    }

    @Test func unsupportedMacFallsBackToTheCut() async {
        let rig = NativeRig()
        rig.native.supported = false
        await rig.on()
        await rig.feed(reading(80))
        #expect(rig.native.writes.isEmpty)
        #expect(rig.controller.calls == [.hold(80)])
        #expect(rig.limiter.state.holdRunsOnBattery)
        #expect(!rig.limiter.usesMacOSLimit)
    }

    @Test func macOSIgnoringTheWriteFallsBackAfterThreeTries() async {
        let rig = NativeRig()
        rig.native.ignoreWrites = true
        await rig.on()
        await rig.feed(reading(80))
        #expect(rig.limiter.state.reasonText == "Could not set the macOS charge limit. Trying again.")
        #expect(rig.limiter.state.holdingAt == nil)
        await rig.feed(reading(80), after: 31)
        await rig.feed(reading(80), after: 31)
        #expect(!rig.limiter.usesMacOSLimit)
        await rig.feed(reading(80), after: 1)
        #expect(rig.controller.calls == [.hold(80)])
    }

    // MARK: Giving the person's own setting back

    @Test func toolOffRestoresThePersonsOwnLimit() async {
        let rig = NativeRig(limit: 85)
        rig.native.limit = NativeLimitReading(enabled: true, limit: 95) // set in System Settings
        await rig.on()
        await rig.feed(reading(85))
        #expect(rig.native.limit == NativeLimitReading(enabled: true, limit: 85))
        await rig.limiter.setToolEnabled(false)
        #expect(rig.native.limit == NativeLimitReading(enabled: true, limit: 95))
        #expect(NativeLimitSnapshotStore(defaults: rig.defaults).load() == nil)
    }

    @Test func limitOffOrBelowEightyTurnsMacOSLimitBackOff() async {
        let rig = NativeRig(limit: 80)
        await rig.on()
        await rig.feed(reading(80))
        #expect(rig.native.limit.enabled)
        rig.settings.setLimit(100)
        await rig.feed(reading(80), after: 5)
        #expect(rig.native.limit == .off)
        rig.settings.setLimit(80)
        await rig.feed(reading(80), after: 40)
        #expect(rig.native.limit.enabled)
        rig.settings.setLimit(60)
        await rig.feed(reading(80), after: 5)
        #expect(rig.native.limit == .off)
    }

    @Test func topUpLiftsMacOSLimitAndPutsItBack() async {
        let rig = NativeRig(limit: 80)
        await rig.on()
        await rig.feed(reading(80))
        rig.settings.setTopUp(true)
        await rig.limiter.reevaluate()
        #expect(rig.native.writes == [80, 100])
        #expect(rig.limiter.state.reasonText == "Charging up to 100%")
        #expect(rig.controller.calls.isEmpty)
        rig.settings.setTopUp(false)
        await rig.limiter.reevaluate()
        #expect(rig.native.writes == [80, 100, 80])
    }

    // MARK: pmset

    @Test func readsTheManualLimitFromPmset() {
        let text = """
        Battery limit:
        {
            chargeSocLimitReason = optimizedBatteryCharging;
            chargeSocLimitSoc = 80;
        }
        {
            chargeSocLimitReason = manualChargeLimit;
            chargeSocLimitSoc = 85;
        }
        """
        #expect(NativeChargeLimits.manualLimit(fromPmset: text) == 85)
        #expect(NativeChargeLimits.manualLimit(fromPmset: "chargeSocLimitReason = manualChargeLimit;\nchargeSocLimitSoc = 90;") == 90)
        #expect(NativeChargeLimits.manualLimit(fromPmset: "{\n chargeSocLimitReason = optimizedBatteryCharging;\n chargeSocLimitSoc = 80;\n}") == nil)
        #expect(NativeChargeLimits.manualLimit(fromPmset: "") == nil)
    }

    @Test func readingConfirms() {
        #expect(NativeLimitReading(enabled: true, limit: 80).confirms(80))
        #expect(!NativeLimitReading(enabled: true, limit: 85).confirms(80))
        #expect(NativeLimitReading.off.confirms(100))
        #expect(!NativeLimitReading(enabled: true, limit: 80).confirms(100))
    }
}
