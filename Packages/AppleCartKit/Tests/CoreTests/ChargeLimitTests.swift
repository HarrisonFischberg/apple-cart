import Foundation
import Testing
@testable import Core

private func reading(_ percent: Int, plugged: Bool = true, charging: Bool = false) -> BatteryReading {
    BatteryReading(properties: ["CurrentCapacity": percent, "ExternalConnected": plugged ? 1 : 0, "IsCharging": charging ? 1 : 0])!
}

@MainActor
private func settings(limit: Int = 100) -> ChargeLimitSettings {
    let s = ChargeLimitSettings(defaults: UserDefaults(suiteName: "chargelimit-" + UUID().uuidString)!)
    s.setLimit(limit)
    return s
}

@MainActor
@Suite struct ChargeLimitTests {
    @Test func holdsAtAndAboveTheLimit() {
        let s = settings(limit: 80)
        #expect(ChargePolicy.decide(reading: reading(80), settings: s) == .holdCharging(at: 80))
        #expect(ChargePolicy.decide(reading: reading(85, charging: true), settings: s) == .holdCharging(at: 80))
    }

    @Test func allowsWellBelowTheLimit() {
        #expect(ChargePolicy.decide(reading: reading(60), settings: settings(limit: 80)) == .allowCharging)
        #expect(ChargePolicy.decide(reading: reading(77), settings: settings(limit: 80)) == .allowCharging) // limit - 3
    }

    @Test func hysteresisKeepsTheCurrentStateInTheBand() {
        let s = settings(limit: 80)
        #expect(ChargePolicy.decide(reading: reading(78, charging: true), settings: s) == .allowCharging)
        #expect(ChargePolicy.decide(reading: reading(78, charging: false), settings: s) == .holdCharging(at: 80))
    }

    @Test func fullLimitNeverHolds() {
        #expect(ChargePolicy.decide(reading: reading(100), settings: settings()) == .allowCharging)
    }

    @Test func topUpLiftsTheLimitToOneHundred() {
        let s = settings(limit: 80)
        s.setTopUp(true)
        #expect(s.effectiveLimit == 100)
        #expect(ChargePolicy.decide(reading: reading(85, charging: true), settings: s) == .allowCharging)
    }

    @Test func unpluggedOrNoReadingHasNothingToHold() {
        let s = settings(limit: 60)
        #expect(ChargePolicy.decide(reading: reading(90, plugged: false), settings: s) == .allowCharging)
        #expect(ChargePolicy.decide(reading: nil, settings: s) == .allowCharging)
    }

    @Test func topUpEndsWhenFullOrUnplugged() {
        let s = settings(limit: 80)
        s.setTopUp(true)
        s.observe(reading(95, charging: true)); #expect(s.topUpActive)
        s.observe(nil); #expect(s.topUpActive) // no data is not unplugged
        s.observe(reading(100)); #expect(!s.topUpActive)
        s.setTopUp(true)
        s.observe(reading(90, plugged: false)); #expect(!s.topUpActive)
        s.setTopUp(true); s.setTopUp(false); #expect(s.effectiveLimit == 80) // cancel
    }

    @Test func limitClampsAndSnapsToFive() {
        let s = settings()
        s.setLimit(-10); #expect(s.limit == 0)
        s.setLimit(150); #expect(s.limit == 100)
        s.setLimit(83); #expect(s.limit == 85)
        s.setLimit(72); #expect(s.limit == 70)
    }

    @Test func persistsAcrossInstancesWithDefaultOfOneHundred() {
        let d = UserDefaults(suiteName: "chargelimit-" + UUID().uuidString)!
        #expect(ChargeLimitSettings(defaults: d).limit == 100)
        let a = ChargeLimitSettings(defaults: d)
        a.setLimit(80); a.setTopUp(true); a.setSailing(true); a.setSailingDifference(7); a.setAutoDischarge(true)
        let b = ChargeLimitSettings(defaults: d)
        #expect(b.limit == 80 && b.topUpActive && b.sailing && b.sailingDifference == 7 && b.autoDischarge)
        d.set(7, forKey: "chargeLimit")
        #expect(ChargeLimitSettings(defaults: d).limit == 5) // a stored value snaps to a multiple of 5
        d.set(-20, forKey: "chargeLimit")
        #expect(ChargeLimitSettings(defaults: d).limit == 0)
    }

    @Test func anyLimitFromZeroIsAllowedButTheChargerIsNeverHeldAtFiveOrBelow() {
        let s = settings(limit: 0)
        #expect(s.limit == 0)
        #expect(ChargePolicy.decide(reading: reading(40), settings: s) == .holdCharging(at: 0))
        #expect(ChargePolicy.decide(reading: reading(5), settings: s) == .allowCharging)
    }

    @Test func oneShotDischargeRunsDownToTheLimitThenTurnsItselfOff() {
        let s = settings(limit: 80)
        #expect(ChargePolicy.decide(reading: reading(90), settings: s) == .holdCharging(at: 80))
        s.setDischarge(true)
        #expect(ChargePolicy.decide(reading: reading(90), settings: s) == .discharge(to: 80))
        s.observe(reading(85)); #expect(s.dischargeActive)
        s.observe(reading(80)); #expect(!s.dischargeActive)
        s.setDischarge(true); s.observe(reading(90, plugged: false)); #expect(!s.dischargeActive)
    }

    @Test func sailingWidensTheResumeBand() {
        let s = settings(limit: 80)
        #expect(s.resumeBand == 3 && s.sailFloor == 77)
        s.setSailing(true); s.setSailingDifference(10)
        #expect(s.sailFloor == 70)
        #expect(ChargePolicy.decide(reading: reading(75), settings: s) == .holdCharging(at: 80)) // in the sail range, not charging
        #expect(ChargePolicy.decide(reading: reading(75, charging: true), settings: s) == .allowCharging)
        #expect(ChargePolicy.decide(reading: reading(70), settings: s) == .allowCharging)
        s.setSailingDifference(99); #expect(s.sailingDifference == 15)
        s.setSailingDifference(-1); #expect(s.sailingDifference == 0)
        #expect(ChargePolicy.decide(reading: reading(79), settings: s) == .allowCharging) // difference 0: charge right below the limit
    }

    @Test func automaticDischargeOnlyAboveTheLimitWhilePlugged() {
        let s = settings(limit: 80)
        #expect(ChargePolicy.decide(reading: reading(90), settings: s) == .holdCharging(at: 80))
        s.setAutoDischarge(true)
        #expect(ChargePolicy.decide(reading: reading(90), settings: s) == .discharge(to: 80))
        #expect(ChargePolicy.decide(reading: reading(80), settings: s) == .holdCharging(at: 80))
        #expect(ChargePolicy.decide(reading: reading(90, plugged: false), settings: s) == .allowCharging)
        s.setTopUp(true)
        #expect(ChargePolicy.decide(reading: reading(90), settings: s) == .allowCharging)
    }

    @Test func heatSettingsAreStoredInCelsiusAndClamped() {
        let s = settings()
        s.setHeatMaxC(60); #expect(s.heatMaxC == 45)
        s.setHeatMaxC(10); #expect(s.heatMaxC == 30)
    }
}
