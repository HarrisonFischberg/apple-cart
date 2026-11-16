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
        await rig.feed(reading(79), after: 15) // 30 s since the cut
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

    @Test func aCutThatHidesThePlugIsLearnedOnce() async {
        let rig = Rig()
        await rig.holding()
        await rig.feed(reading(80, plugged: false), after: 2)
        await rig.feed(reading(80, plugged: false), after: 10) // released as an unplug
        await rig.feed(reading(80), after: 5) // the plug came straight back: the cut hid it
        #expect(rig.limiter.cutHidesPlug)
        #expect(rig.controller.calls == [.allow, .hold(80)])
        rig.controller.clear()
        await rig.feed(reading(80, plugged: false), after: 15)
        await rig.feed(reading(80, plugged: false), after: 15) // now held through the cut's "unplugged" readings
        #expect(rig.controller.calls == [.hold(80)])
        #expect(rig.limiter.state.holdingAt == 80)
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

    @Test func helperSideRestoreEndsTheHoldClaimAndChecksResume() async {
        let rig = Rig()
        await rig.holding()
        rig.controller.adapterCut = false // e.g. restored before sleep or on lease expiry
        await rig.limiter.refreshHelperStatus()
        #expect(rig.limiter.state.holdingAt == nil)
        #expect(rig.limiter.wantsReadings)
    }

    @Test func unknownCutReportedByTheHelperIsRestoredWhenAllowed() async {
        let rig = Rig()
        rig.controller.adapterCut = true
        await rig.on()
        await rig.feed(reading(60, charging: false))
        #expect(rig.controller.calls == [.allow])
    }

    @Test func stalledChargingAfterLaunchStartsTheResumeCheck() async {
        let rig = Rig()
        await rig.on()
        await rig.feed(reading(60))            // plugged, not charging, well below the limit
        await rig.feed(reading(60), after: 59)
        #expect(rig.controller.calls.isEmpty)
        await rig.feed(reading(60), after: 1)  // 60 s: retry 1 right away
        #expect(rig.controller.calls == [.allow])
        await rig.feed(reading(60), after: 60)
        #expect(rig.controller.calls == [.allow, .allow])
        await rig.feed(reading(60), after: 60)
        #expect(rig.limiter.state.chargingNotResumed)
    }

    @Test func stallCheckOnlyAfterLaunchOrWakeAndNotNearFull() async {
        let rig = Rig(limit: 100)
        await rig.on()
        await rig.feed(reading(98), after: 0)   // near full macOS often shows "not charging": not a stall
        await rig.feed(reading(98), after: 120)
        #expect(rig.controller.calls.isEmpty)
        await rig.feed(reading(60), after: 400) // watch window over
        await rig.feed(reading(60), after: 120)
        #expect(rig.controller.calls.isEmpty)
        await rig.limiter.systemDidWake()
        await rig.feed(reading(60), after: 1)
        await rig.feed(reading(60), after: 60)
        #expect(rig.controller.calls == [.allow])
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
}
