import Foundation
import Testing
@testable import Core

@Suite struct HeatGuardTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func pausesAboveTheMaxForFiveMinutes() {
        var g = HeatGuard()
        let p1 = g.update(temperatureC: 35, maxC: 35, enabled: true, pluggedIn: true, now: t0)
        #expect(!p1) // at the max is not above it
        let p2 = g.update(temperatureC: 35.5, maxC: 35, enabled: true, pluggedIn: true, now: t0)
        #expect(p2)
        #expect(g.pausedUntil == t0 + 300)
        let p3 = g.update(temperatureC: 30, maxC: 35, enabled: true, pluggedIn: true, now: t0 + 299)
        #expect(p3) // cool, but not yet 5 min
    }

    @Test func staysPausedAnotherFiveMinutesWhenStillHot() {
        var g = HeatGuard()
        g.update(temperatureC: 40, maxC: 35, enabled: true, pluggedIn: true, now: t0)
        let p4 = g.update(temperatureC: 36, maxC: 35, enabled: true, pluggedIn: true, now: t0 + 300)
        #expect(p4)
        #expect(g.pausedUntil == t0 + 600)
    }

    @Test func resumesThenChargesAtLeastFiveMinutes() {
        var g = HeatGuard()
        g.update(temperatureC: 40, maxC: 35, enabled: true, pluggedIn: true, now: t0)
        let p5 = g.update(temperatureC: 34, maxC: 35, enabled: true, pluggedIn: true, now: t0 + 300)
        #expect(!p5)
        #expect(g.mustChargeUntil == t0 + 600)
        let p6 = g.update(temperatureC: 40, maxC: 35, enabled: true, pluggedIn: true, now: t0 + 599)
        #expect(!p6) // hot again: still charges
        let p7 = g.update(temperatureC: 40, maxC: 35, enabled: true, pluggedIn: true, now: t0 + 600)
        #expect(p7)
    }

    @Test func offUnknownOrUnpluggedEndsEverything() {
        for (enabled, temp, plugged) in [(false, 40.0 as Double?, true), (true, nil, true), (true, 40.0, false)] {
            var g = HeatGuard()
            g.update(temperatureC: 40, maxC: 35, enabled: true, pluggedIn: true, now: t0)
            let p8 = g.update(temperatureC: temp, maxC: 35, enabled: enabled, pluggedIn: plugged, now: t0 + 10)
            #expect(!p8)
            #expect(g == HeatGuard())
        }
    }

    @Test func batteryTemperatureIsTheWarmestPlausibleSensor() {
        #expect(BatterySensors.temperature([33.2, 32.9, 33.4]) == 33.4)
        #expect(BatterySensors.temperature([0, 33.0]) == 33.0) // an off sensor reads 0
        #expect(BatterySensors.temperature([]) == nil)
        #expect(BatterySensors.temperature([0, 200]) == nil)
    }
}

@Suite struct MagSafeLightTests {
    @Test func mapsOnlyTheMeasuredValues() {
        #expect(MagSafeLight(smcValue: 3) == .green)
        #expect(MagSafeLight(smcValue: 4) == .orange)
        #expect(MagSafeLight(smcValue: nil) == .notAvailable)
        for v: UInt8 in [0, 1, 2, 5, 7, 255] { #expect(MagSafeLight(smcValue: v) == .unknown) }
    }

    @Test func rowTextIsOffUnplugged() {
        #expect(MagSafeLight.orange.text(pluggedIn: false) == "Off")
        #expect(MagSafeLight.orange.text(pluggedIn: true) == "Orange")
        #expect(MagSafeLight.green.text(pluggedIn: true) == "Green")
        #expect(MagSafeLight.unknown.text(pluggedIn: true) == "Unknown")
    }

    @Test func explainsOnlyWhenTheLightCouldSurprise() {
        #expect(MagSafeLight.note(light: .orange, pluggedIn: true, held: true, charging: false, percent: 80) == MagSafeLight.orangeWhileHeldNote)
        #expect(MagSafeLight.note(light: .green, pluggedIn: true, held: false, charging: false, percent: 95) == MagSafeLight.greenNotChargingNote)
        #expect(MagSafeLight.note(light: .orange, pluggedIn: true, held: false, charging: true, percent: 60) == nil) // charging: agrees
        #expect(MagSafeLight.note(light: .green, pluggedIn: true, held: false, charging: false, percent: 100) == nil) // full: agrees
        #expect(MagSafeLight.note(light: .orange, pluggedIn: false, held: false, charging: false, percent: 80) == nil) // no light
        #expect(MagSafeLight.note(light: .unknown, pluggedIn: true, held: true, charging: false, percent: 80) == nil)  // never guessed
    }
}
