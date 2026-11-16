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
        s.setLimit(10); #expect(s.limit == 50)
        s.setLimit(150); #expect(s.limit == 100)
        s.setLimit(83); #expect(s.limit == 85)
        s.setLimit(72); #expect(s.limit == 70)
    }

    @Test func persistsAcrossInstancesWithDefaultOfOneHundred() {
        let d = UserDefaults(suiteName: "chargelimit-" + UUID().uuidString)!
        #expect(ChargeLimitSettings(defaults: d).limit == 100)
        let a = ChargeLimitSettings(defaults: d)
        a.setLimit(80); a.setTopUp(true)
        let b = ChargeLimitSettings(defaults: d)
        #expect(b.limit == 80 && b.topUpActive)
        d.set(7, forKey: "chargeLimit")
        #expect(ChargeLimitSettings(defaults: d).limit == 50) // a bad stored value is clamped
    }

    @Test func noopControllerIsUnavailableAndCaptionIsHonest() async {
        let c = NoopChargeController()
        #expect(!c.isAvailable)
        #expect(await c.apply(.holdCharging(at: 80)) == .unavailable)
        let text = settings().caption(controllerAvailable: c.isAvailable)
        #expect(text == "Saved. It takes effect once the charging helper is installed.")
        #expect(!text.localizedCaseInsensitiveContains("active"))
    }
}
