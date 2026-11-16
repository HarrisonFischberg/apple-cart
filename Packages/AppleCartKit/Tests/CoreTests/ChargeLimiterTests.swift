import Foundation
import Testing
@testable import Core

final class FakeController: ChargeController, @unchecked Sendable {
    enum Call: Equatable { case hold(Int), discharge(Int), allow, reset }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var helperStatus: ChargeHelperStatus = .ready
    /// What the helper reports about the charger (nil = unknown).
    var adapterCut: Bool?
    var result: ChargeApplyResult = .applied
    var resetResult: ChargeApplyResult = .applied
    /// Runs inside apply, to simulate things that happen while a command is in flight.
    var duringApply: (@MainActor () async -> Void)?

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
    func clear() { lock.lock(); _calls = []; lock.unlock() }
    private func record(_ c: Call) { lock.lock(); _calls.append(c); lock.unlock() }

    func status() async -> ChargeHelperReport { ChargeHelperReport(helperStatus, adapterCut: adapterCut) }
    func apply(_ decision: ChargeDecision) async -> ChargeApplyResult {
        switch decision { case .holdCharging(let at): record(.hold(at)); case .discharge(let at): record(.discharge(at)); case .allowCharging: record(.allow) }
        if let duringApply { await duringApply() }
        return result
    }
    func resetAll() async -> ChargeApplyResult { record(.reset); return resetResult }
}

private func reading(_ percent: Int, plugged: Bool = true, charging: Bool = false) -> BatteryReading {
    BatteryReading(properties: ["CurrentCapacity": percent, "ExternalConnected": plugged ? 1 : 0, "IsCharging": charging ? 1 : 0])!
}

@MainActor
private final class Rig {
    var clock = Date(timeIntervalSince1970: 1_000_000)
    let settings = ChargeLimitSettings(defaults: UserDefaults(suiteName: "limiter-" + UUID().uuidString)!)
    let controller = FakeController()
    lazy var limiter = ChargeLimiter(settings: settings, controller: controller, now: { [unowned self] in self.clock })

    init(limit: Int = 80, status: ChargeHelperStatus = .ready) {
        settings.setLimit(limit)
        controller.helperStatus = status
    }

    func on() async { await limiter.setToolEnabled(true) }
    /// Readings are stamped with the rig clock, as the sampler stamps them with the time read.
    func feed(_ r: BatteryReading?, after seconds: TimeInterval = 0) async {
        clock += seconds
        var r = r
        r?.date = clock
        await limiter.evaluate(r)
    }
    /// The rig is holding at the limit with a fresh cut, calls cleared.
    func holding() async {
        await on()
        await feed(reading(80))
        #expect(limiter.state.holdingAt == 80)
        controller.clear()
    }
}

@MainActor
@Suite struct ChargeLimiterTests {
    @Test func limitReachedCutsAndSaysHolding() async {
        let rig = Rig()
        await rig.on()
        await rig.feed(reading(80))
        #expect(rig.controller.calls == [.hold(80)])
        #expect(rig.limiter.state.holdingAt == 80)
        #expect(rig.limiter.state.reasonText == "Holding at 80%")
    }

    @Test func holdIsRenewedEveryThirtySecondsNotEverySample() async {
        let rig = Rig()
        await rig.holding()
        await rig.feed(reading(80), after: 5)
        await rig.feed(reading(80), after: 10)
        #expect(rig.controller.calls.isEmpty)
        await rig.feed(reading(80), after: 15) // 30 s since the cut
        #expect(rig.controller.calls == [.hold(80)])
        #expect(rig.limiter.state.holdingAt == 80)
    }

    @Test func belowTheBandReleasesAndNeverHolds() async {
        let rig = Rig()
        await rig.on()
        await rig.feed(reading(60))
        await rig.feed(reading(77))
        #expect(rig.controller.calls.isEmpty)
        #expect(rig.limiter.state.reasonText == "Charging up to 80%")

        await rig.holding()
        await rig.feed(reading(77, plugged: false), after: 30)
        #expect(rig.controller.calls == [.allow])
        #expect(rig.limiter.state.holdingAt == nil)
    }

    @Test func inTheBandKeepsHoldingUntilLimitMinusThree() async {
        let rig = Rig()
        rig.settings.setSailing(true); rig.settings.setSailingDifference(3) // band 3 (was the default before 2026-11-15)
        await rig.holding()
        await rig.feed(reading(78, plugged: false), after: 30)
        #expect(rig.controller.calls == [.hold(80)])
        rig.controller.clear()
        await rig.feed(reading(77, plugged: false), after: 30)
        #expect(rig.controller.calls == [.allow])
    }

    @Test func topUpReleasesAtOnceAndIsNotCancelledByTheCutsUnpluggedReading() async {
        let rig = Rig()
        await rig.holding()
        rig.settings.setTopUp(true)
        await rig.feed(reading(80, plugged: false), after: 1) // stale reading from during the cut
        #expect(rig.controller.calls == [.allow])
        #expect(rig.settings.topUpActive)
        #expect(rig.limiter.state.reasonText == "Charging up to 100%")
        rig.controller.clear()
        await rig.feed(reading(85, charging: true), after: 40)
        #expect(rig.controller.calls.isEmpty) // Top Up never holds
        rig.settings.setTopUp(false)
        await rig.limiter.reevaluate()
        #expect(rig.controller.calls == [.hold(80)])
    }

    @Test func unpluggedWithoutACutNeverHoldsAndEndsTopUp() async {
        let rig = Rig()
        await rig.on()
        await rig.feed(reading(95, plugged: false))
        #expect(rig.controller.calls.isEmpty)
        rig.settings.setTopUp(true)
        await rig.feed(reading(90, plugged: false), after: 5)
        #expect(!rig.settings.topUpActive)
        #expect(rig.controller.calls.isEmpty)
    }

    @Test func batteryToolOffResetsAndStopsCommanding() async {
        let rig = Rig()
        await rig.holding()
        await rig.limiter.setToolEnabled(false)
        #expect(rig.controller.calls == [.reset])
        #expect(rig.limiter.state.holdingAt == nil)
        #expect(!rig.limiter.wantsReadings)
        await rig.feed(reading(90), after: 60)
        #expect(rig.controller.calls == [.reset])
    }

    @Test func toolTurnedOffWhileACutIsInFlightResetsAfterIt() async {
        let rig = Rig()
        await rig.on()
        rig.controller.duringApply = { [limiter = rig.limiter] in await limiter.setToolEnabled(false) }
        await rig.feed(reading(85))
        #expect(rig.controller.calls == [.hold(80), .reset, .reset])
        #expect(rig.limiter.state.holdingAt == nil)
    }

    @Test func helperMissingNeverCommandsAndSaysWhy() async {
        for (status, text) in [(ChargeHelperStatus.notInstalled, "Install the charging helper in Settings to use this."),
                               (.needsApproval, "Approve Apple Cart in Login Items."),
                               (.outdated, "The charging helper is out of date. Repair it in Settings."),
                               (.unreachable, "The charging helper is not answering. Repair it in Settings.")] {
            let rig = Rig(status: status)
            await rig.on()
            await rig.feed(reading(90))
            #expect(rig.controller.calls.isEmpty)
            #expect(rig.limiter.state.holdingAt == nil)
            #expect(rig.limiter.state.reasonText == text)
        }
    }

    @Test func helperLostWhileHoldingDropsTheHoldClaim() async {
        let rig = Rig()
        await rig.holding()
        rig.controller.helperStatus = .unreachable
        await rig.feed(reading(80, plugged: false), after: 30)
        #expect(rig.limiter.state.holdingAt == nil)
        #expect(rig.controller.calls == [.reset]) // the cut may still be live: ask for the restore anyway
    }

    @Test func failedCutIsNotShownAsHolding() async {
        let rig = Rig()
        await rig.on()
        rig.controller.result = .failed("smcFailed")
        await rig.feed(reading(85))
        #expect(rig.limiter.state.holdingAt == nil)
        #expect(rig.limiter.state.reasonText == "Could not reach the charging helper. Trying again.")
    }

    @Test func resumeVerifiedWhenChargingStarts() async {
        let rig = Rig()
        await rig.holding()
        await rig.feed(reading(77, plugged: false), after: 30)
        rig.controller.clear()
        await rig.feed(reading(77, charging: true), after: 45)
        #expect(!rig.limiter.state.chargingNotResumed)
        await rig.feed(reading(77), after: 300) // check is over; no warning later
        #expect(!rig.limiter.state.chargingNotResumed)
        #expect(rig.controller.calls.isEmpty)
    }

    @Test func resumeFailureRetriesTwiceThenWarns() async {
        let rig = Rig()
        await rig.holding()
        await rig.feed(reading(77, plugged: false), after: 30) // release
        rig.controller.clear()
        await rig.feed(reading(77), after: 30)  // 30 s, plugged, not charging
        #expect(rig.controller.calls.isEmpty)
        await rig.feed(reading(77), after: 30)  // 60 s: retry 1
        await rig.feed(reading(77), after: 60)  // 120 s: retry 2
        #expect(rig.controller.calls == [.allow, .allow])
        #expect(!rig.limiter.state.chargingNotResumed)
        await rig.feed(reading(76), after: 60)  // 180 s
        #expect(rig.limiter.state.chargingNotResumed)
        #expect(rig.limiter.state.reasonText == "Charging has not resumed. Unplug and replug the charger.")
        #expect(rig.controller.calls == [.allow, .allow])
        // Replug: unplugged then charging clears it.
        await rig.feed(reading(76, plugged: false), after: 10)
        #expect(!rig.limiter.state.chargingNotResumed)
    }

    @Test func unplugAfterRestoreEndsTheCheckOnlyAfterTheGrace() async {
        let rig = Rig()
        await rig.holding()
        await rig.feed(reading(77, plugged: false), after: 30)
        rig.controller.clear()
        await rig.feed(reading(77, plugged: false), after: 10) // could still be the cut's aftermath
        #expect(rig.limiter.wantsReadings)
        await rig.feed(reading(77, plugged: false), after: 25)
        rig.settings.setLimit(100)
        await rig.feed(reading(77, plugged: false), after: 300) // past the post-launch stall watch too
        #expect(!rig.limiter.wantsReadings)
    }

    @Test func limitRaisedToOneHundredReleases() async {
        let rig = Rig()
        await rig.holding()
        rig.settings.setLimit(100)
        await rig.limiter.reevaluate()
        #expect(rig.controller.calls == [.allow])
        #expect(rig.limiter.state.holdingAt == nil)
    }

    @Test func failedReleaseIsRetriedUntilTheLeaseHasSurelyExpired() async {
        let rig = Rig()
        await rig.holding()
        rig.controller.result = .failed("x")
        await rig.feed(reading(70, plugged: false), after: 30)
        await rig.feed(reading(70, plugged: false), after: 30)
        #expect(rig.controller.calls == [.allow, .allow])
        await rig.feed(reading(70, plugged: false), after: 30) // 90 s since the cut: the helper has restored on its own
        rig.controller.clear()
        await rig.feed(reading(70, plugged: false), after: 5)
        #expect(rig.controller.calls.isEmpty)
    }

    @Test func automaticDischargeCutsAndSaysDischarging() async {
        let rig = Rig()
        rig.settings.setAutoDischarge(true)
        await rig.on()
        await rig.feed(reading(90))
        #expect(rig.controller.calls == [.discharge(80)])
        #expect(rig.limiter.state.reasonText == "Discharging to 80%")
        await rig.feed(reading(80, plugged: false), after: 30)
        #expect(rig.controller.calls == [.discharge(80), .hold(80)])
        #expect(rig.limiter.state.reasonText == "Holding at 80%")
    }

    @Test func sailingHoldsDownToTheDifference() async {
        let rig = Rig()
        rig.settings.setSailing(true); rig.settings.setSailingDifference(10)
        await rig.holding()
        await rig.feed(reading(75, plugged: false), after: 30)
        #expect(rig.controller.calls == [.hold(80)])
        rig.controller.clear()
        await rig.feed(reading(70, plugged: false), after: 30)
        #expect(rig.controller.calls == [.allow])
    }

    @Test func staleReadingNeverStartsOrRenewsACut() async {
        let rig = Rig()
        await rig.on()
        await rig.limiter.evaluate(reading(85)) // stamped "now" by the real clock, far from the rig clock
        #expect(rig.controller.calls.isEmpty)
        await rig.feed(reading(85))
        #expect(rig.controller.calls == [.hold(80)])
        rig.controller.clear()
        rig.clock += 40
        await rig.limiter.reevaluate() // the last reading is now 40 s old: no renewal
        #expect(rig.controller.calls.isEmpty)
    }

    @Test func realUnplugDuringACutReleasesAfterTheGrace() async {
        let rig = Rig()
        await rig.holding()
        await rig.feed(reading(80, plugged: false), after: 2)
        #expect(rig.controller.calls.isEmpty && rig.limiter.state.holdingAt == 80) // could be the cut itself
        await rig.feed(reading(80, plugged: false), after: 10)
        #expect(rig.controller.calls == [.allow])
        #expect(rig.limiter.state.holdingAt == nil) // no "Holding" on battery
        rig.controller.clear()
        await rig.feed(reading(79, plugged: false), after: 30) // still unplugged: it was real
        await rig.feed(reading(79, plugged: false), after: 30)
        #expect(rig.controller.calls.isEmpty)
        #expect(!rig.limiter.cutHidesPlug)
    }

    @Test func timedOutCutIsRestoredEvenWhenTopUpFollows() async {
        let rig = Rig()
        await rig.on()
        rig.controller.result = .failed("timeout")   // the cut may have reached the helper anyway
        rig.controller.resetResult = .failed("timeout")
        await rig.feed(reading(85))
        #expect(rig.controller.calls == [.hold(80), .reset])
        #expect(rig.limiter.state.holdingAt == nil)
        rig.controller.clear()
        rig.controller.result = .applied
        rig.settings.setTopUp(true)
        await rig.limiter.reevaluate()
        #expect(rig.controller.calls == [.allow]) // a cut may be live, so the restore is sent
        rig.controller.clear()
        await rig.feed(reading(85, charging: true), after: 5)
        #expect(rig.controller.calls.isEmpty)
    }

    @Test func leavingReadyAsksForARestoreWhileACutMayBeLive() async {
        let rig = Rig()
        await rig.on()
        rig.controller.result = .failed("timeout")
        rig.controller.resetResult = .failed("timeout")
        await rig.feed(reading(85))
        rig.controller.clear()
        rig.controller.helperStatus = .unreachable
        await rig.limiter.refreshHelperStatus()
        await rig.feed(reading(85), after: 1)
        #expect(rig.controller.calls == [.reset])
        rig.controller.clear()
        await rig.feed(reading(85), after: 100) // past the lease: nothing can be live any more
        #expect(rig.controller.calls.isEmpty)
    }

    @Test func unknownCutReportedByTheHelperIsRestoredWhenAllowed() async {
        let rig = Rig()
        rig.controller.adapterCut = true
        await rig.on()
        await rig.feed(reading(60, charging: false))
        #expect(rig.controller.calls == [.allow])
    }

    /// One release for an "unplug" whose plug came straight back.
    private func releaseAndReplug(_ rig: Rig) async {
        await rig.feed(reading(80, plugged: false), after: 30) // renewal pass sees "unplugged"
        await rig.feed(reading(80, plugged: false), after: 10) // past the grace: released
        await rig.feed(reading(80), after: 5)                  // plugged again within 30 s: cut again
    }

    @Test func aCutThatHidesThePlugIsLearnedAfterTwoSightings() async {
        let rig = Rig()
        await rig.holding()
        await releaseAndReplug(rig)
        #expect(!rig.limiter.cutHidesPlug) // once could be a real quick unplug and replug
        await releaseAndReplug(rig)
        #expect(rig.limiter.cutHidesPlug)
        rig.controller.clear()
        await rig.feed(reading(80, plugged: false), after: 30)
        await rig.feed(reading(80, plugged: false), after: 15) // now held through the cut's "unplugged" readings
        #expect(rig.controller.calls == [.hold(80)])
        #expect(rig.limiter.state.holdingAt == 80)
    }

    @Test func aRealQuickReplugDoesNotTeachAndALongUnplugForgets() async {
        let rig = Rig()
        await rig.holding()
        await releaseAndReplug(rig) // a real unplug, replugged within 30 s
        #expect(!rig.limiter.cutHidesPlug)
        await releaseAndReplug(rig)
        #expect(rig.limiter.cutHidesPlug) // learned (rightly or not)
        // A real unplug now: the hold lasts only until the band (77%), then the restore; minutes of "unplugged"
        // with no cut forget what was learned, so the next real unplug is caught after 10 s again.
        await rig.feed(reading(78, plugged: false), after: 30)
        await rig.feed(reading(76, plugged: false), after: 30)
        #expect(rig.limiter.state.holdingAt == nil)
        for _ in 0..<8 { await rig.feed(reading(75, plugged: false), after: 30) }
        #expect(!rig.limiter.cutHidesPlug)
    }

    @Test func helperSideRestoreEndsTheHoldClaimAndChecksResume() async {
        let rig = Rig()
        await rig.holding()
        rig.controller.adapterCut = false // e.g. restored on lease expiry
        await rig.limiter.refreshHelperStatus()
        #expect(rig.limiter.state.holdingAt == nil)
        await rig.feed(reading(76), after: 1)  // below the band, not charging
        await rig.feed(reading(76), after: 60) // the resume check retries the restore
        #expect(rig.controller.calls == [.allow])
        await rig.feed(reading(76), after: 120)
        #expect(rig.limiter.state.chargingNotResumed)
    }

    @Test func macOSHoldingAtEightyWithLimitOneHundredNeverWarns() async {
        let rig = Rig(limit: 100)
        await rig.on()
        rig.controller.helperStatus = .unreachable
        await rig.limiter.refreshHelperStatus()
        rig.controller.helperStatus = .ready
        await rig.limiter.refreshHelperStatus() // not ready -> ready
        await rig.limiter.systemDidWake()
        for _ in 0..<20 { await rig.feed(reading(80), after: 30) } // Optimized Battery Charging: plugged, not charging
        #expect(rig.controller.calls.isEmpty)
        #expect(!rig.limiter.state.chargingNotResumed)
        #expect(!rig.limiter.wantsReadings)
    }

    @Test func wakeAfterOurCutChecksThatChargingResumes() async {
        let rig = Rig()
        await rig.holding()
        rig.clock += 20 // asleep; the last reading is now stale, so wake does not cut again from it
        await rig.limiter.systemDidWake() // the helper restored before sleep
        #expect(rig.limiter.state.holdingAt == nil)
        await rig.feed(reading(76), after: 1)
        await rig.feed(reading(76), after: 60)
        await rig.feed(reading(76), after: 60)
        #expect(rig.controller.calls == [.allow, .allow])
        await rig.feed(reading(76), after: 60)
        #expect(rig.limiter.state.chargingNotResumed)
    }

    @Test func cutOutstandingWhenTheHelperWentAwayIsCheckedWhenItIsBack() async {
        let rig = Rig()
        await rig.holding()
        rig.controller.helperStatus = .unreachable
        await rig.feed(reading(80), after: 30)
        rig.controller.helperStatus = .ready
        await rig.feed(reading(76), after: 30)
        rig.controller.clear()
        await rig.feed(reading(76), after: 60)
        #expect(rig.controller.calls == [.allow])
    }

    @Test func sleepingRefusalSaysWaitingForWake() async {
        let rig = Rig()
        await rig.on()
        rig.controller.result = .sleeping
        await rig.feed(reading(85))
        #expect(rig.limiter.state.reasonText == "Waiting for the Mac to wake.")
        #expect(rig.controller.calls == [.hold(80)]) // nothing was written, so no reset is needed
        rig.controller.result = .applied
        await rig.feed(reading(85), after: 5)
        #expect(rig.limiter.state.reasonText == "Holding at 80%")
    }

    @Test func unsupportedMacNeverCuts() async {
        let rig = Rig(status: .unsupported)
        await rig.on()
        await rig.feed(reading(95))
        #expect(rig.controller.calls.isEmpty)
        #expect(rig.limiter.state.reasonText == "Not supported on this Mac.")
    }

    @Test func noopControllerIsNotAvailable() async {
        let c = NoopChargeController()
        #expect(await !c.isAvailable)
        #expect(await c.apply(.holdCharging(at: 80)) == .unavailable)
    }

    @Test func sailingHoldSaysTheRangeAndPlainHoldSaysTheLevel() async {
        let rig = Rig()
        await rig.holding()
        #expect(rig.limiter.state.reasonText == "Holding at 80%")
        rig.settings.setSailing(true); rig.settings.setSailingDifference(5)
        await rig.feed(reading(80), after: 30)
        #expect(rig.limiter.state.reasonText == "Sailing 75–80%")
        rig.settings.setTopUp(true) // Sailing is off during Top Up; at 80 it now charges
        await rig.feed(reading(80), after: 30)
        #expect(rig.limiter.state.holdingAt == nil)
    }

    @Test func heatPausesChargingBelowTheLimitWithTheSameCutAndSaysWhy() async {
        let rig = Rig()
        rig.settings.setHeatProtection(true); rig.settings.setHeatMaxC(35)
        await rig.on()
        await rig.feed(warm(60, 36))
        #expect(rig.controller.calls == [.hold(80)])
        #expect(rig.limiter.state.heatPausedAtC == 36)
        #expect(rig.limiter.state.reasonText.hasPrefix("Paused: battery is "))
        rig.controller.clear()
        await rig.feed(warm(60, 34), after: 120)  // cooled, but the 5 minute pause is not over: renewed, still paused
        #expect(rig.controller.calls == [.hold(80)])
        rig.controller.clear()
        await rig.feed(warm(60, 34), after: 181)  // past 5 minutes and cool: charging resumes
        #expect(rig.controller.calls == [.allow])
        #expect(rig.limiter.state.holdingAt == nil)
        rig.controller.clear()
        await rig.feed(warm(60, 37, charging: true), after: 30) // hot again inside the 5 minute minimum charge: no cut
        await rig.feed(warm(61, 37, charging: true), after: 240)
        #expect(rig.controller.calls.isEmpty)
        #expect(rig.limiter.state.reasonText == "Charging up to 80%")
        await rig.feed(warm(62, 37, charging: true), after: 31) // minimum charge over and still hot: paused again
        #expect(rig.controller.calls == [.hold(80)])
    }

    @Test func heatStaysPausedAnotherFiveMinutesIfStillHot() async {
        let rig = Rig()
        rig.settings.setHeatProtection(true)
        await rig.on()
        await rig.feed(warm(60, 36))
        for _ in 0..<10 { await rig.feed(warm(60, 36), after: 30) } // 300 s: still hot, so a fresh 5 minutes
        rig.controller.clear()
        for _ in 0..<9 { await rig.feed(warm(60, 34), after: 30) }  // cool now, but inside the second pause
        #expect(!rig.controller.calls.contains(.allow))
        #expect(rig.limiter.state.heatPausedAtC != nil)
        await rig.feed(warm(60, 34), after: 31)
        #expect(rig.controller.calls.last == .allow)
    }

    @Test func heatAppliesDuringTopUpButNotWhenOffUnknownOrAtTheFloor() async {
        let rig = Rig()
        rig.settings.setHeatProtection(true)
        rig.settings.setTopUp(true)
        await rig.on()
        await rig.feed(warm(90, 36))
        #expect(rig.controller.calls == [.hold(100)]) // protects the battery, also while topping up
        #expect(rig.limiter.state.reasonText.hasPrefix("Paused: battery is "))

        let off = Rig()
        await off.on()
        await off.feed(warm(60, 44)) // setting off
        let unknown = Rig()
        unknown.settings.setHeatProtection(true)
        await unknown.on()
        await unknown.feed(reading(60)) // no temperature
        let floor = Rig()
        floor.settings.setHeatProtection(true)
        await floor.on()
        await floor.feed(warm(ChargePolicy.emergencyFloor, 40))
        #expect(off.controller.calls.isEmpty && unknown.controller.calls.isEmpty && floor.controller.calls.isEmpty)
    }

    @Test func heatNeverDrainsTheBatteryBelowItsFloor() async {
        let low = Rig(limit: 100)
        low.settings.setHeatProtection(true)
        await low.on()
        await low.feed(warm(ChargePolicy.heatFloor, 40))
        #expect(low.controller.calls.isEmpty) // too low to run on the battery while it cools
        let ok = Rig(limit: 100)
        ok.settings.setHeatProtection(true)
        await ok.on()
        await ok.feed(warm(ChargePolicy.heatFloor + 5, 40))
        #expect(ok.controller.calls == [.hold(100)])
    }

    @Test func aHeatCutIsReleasedWhenTheSettingIsTurnedOff() async {
        let rig = Rig(limit: 100)
        rig.settings.setHeatProtection(true)
        await rig.on()
        await rig.feed(warm(90, 38))
        #expect(rig.controller.calls == [.hold(100)])
        rig.settings.setHeatProtection(false)
        await rig.feed(warm(90, 38), after: 30)
        #expect(rig.controller.calls == [.hold(100), .allow])
    }

    @Test func aNewCutIsHeldForAMinuteBeforeAOnePointWobbleReleasesIt() async {
        let rig = Rig()
        await rig.on()
        await rig.feed(reading(80))
        #expect(rig.controller.calls == [.hold(80)])
        await rig.feed(reading(79), after: 10) // a wobble: still held, nothing sent
        #expect(rig.controller.calls == [.hold(80)])
        await rig.feed(reading(79), after: ChargeLimiter.minHold) // a minute on, it is released
        #expect(rig.controller.calls.last == .allow)
    }

    @Test func theEmergencyFloorIsNotHeldByTheMinuteHold() async {
        let rig = Rig(limit: 0) // the owner's 0-100% slider allows it
        await rig.on()
        await rig.feed(reading(6))
        #expect(rig.controller.calls == [.hold(0)])
        await rig.feed(reading(5), after: 10) // at the floor inside the first minute: charge now
        #expect(rig.controller.calls.last == .allow)
    }

    @Test func heatAtTheLimitKeepsTheLimitWordingAndWantsReadingsAtOneHundred() async {
        let rig = Rig()
        rig.settings.setHeatProtection(true)
        await rig.on()
        await rig.feed(warm(80, 36)) // the limit holds anyway; heat did not change the decision
        #expect(rig.limiter.state.reasonText == "Holding at 80%")
        let full = Rig(limit: 100)
        await full.on()
        #expect(!full.limiter.wantsReadings)
        full.settings.setHeatProtection(true)
        #expect(full.limiter.wantsReadings)
    }
}

private func warm(_ percent: Int, _ c: Double, charging: Bool = false) -> BatteryReading {
    BatteryReading(properties: ["CurrentCapacity": percent, "ExternalConnected": 1, "IsCharging": charging ? 1 : 0, "Temperature": Int(c * 100)])!
}
