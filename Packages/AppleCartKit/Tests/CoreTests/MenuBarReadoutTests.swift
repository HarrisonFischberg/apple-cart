import Foundation
import Testing
@testable import Core

private func reading(percent: Int, amps: Int64 = 0, charging: Bool = false) -> BatteryReading {
    BatteryReading(properties: ["CurrentCapacity": percent, "IsCharging": charging ? 1 : 0, "Voltage": 12000,
                                "InstantAmperage": NSNumber(value: UInt64(bitPattern: amps))])!
}

@MainActor
@Suite struct MenuBarReadoutTests {
    @Test func textFollowsTheChosenStyle() {
        let r = reading(percent: 80, amps: -1500)
        #expect(MenuBarReadout.off.text(for: r) == "")
        #expect(MenuBarReadout.percent.text(for: r) == "80%")
        #expect(MenuBarReadout.power.text(for: r) == "80% −18 W")
        #expect(MenuBarReadout.power.text(for: reading(percent: 80)) == "80%")
        #expect(MenuBarReadout.percent.text(for: nil) == "")
    }

    @Test func hardwarePercentIsOptionalAndShowsDashesWhenUnreadable() throws {
        let known = try #require(BatteryReading(properties: ["CurrentCapacity": 99,
            "BatteryData": ["AppleRawCurrentCapacity": 497, "AppleRawMaxCapacity": 500]]))
        #expect(MenuBarReadout.hardwarePercentText(known) == "99.4%")
        #expect(MenuBarReadout.percent.text(for: known, showHardwarePercent: true) == "99% (99.4%)")
        #expect(MenuBarReadout.hardwarePercentText(reading(percent: 99)) == "--")
        #expect(MenuBarReadout.hardwarePercentText(nil) == "--")
        #expect(MenuBarReadout.percent.text(for: reading(percent: 99), showHardwarePercent: true) == "99% (--)")
        #expect(MenuBarReadout.percent.text(for: reading(percent: 99), showHardwarePercent: false) == "99%")
        #expect(MenuBarReadout.power.text(for: reading(percent: 80, amps: -1500), showHardwarePercent: true) == "80% (--) −18 W")
        #expect(MenuBarReadout.off.text(for: known, showHardwarePercent: true) == "")
    }

    @Test func iconFollowsChargeAndState() {
        #expect(MenuBarReadout.symbol(for: reading(percent: 5)) == "battery.0percent")
        #expect(MenuBarReadout.symbol(for: reading(percent: 50)) == "battery.50percent")
        #expect(MenuBarReadout.symbol(for: reading(percent: 50, charging: true)) == "battery.100percent.bolt")
    }

    @Test func firstRunIsTwoScreensAndSkippableInOneClick() {
        let store = MemoryStore()
        let m = FirstRunModel(store: store)
        #expect(!m.isDone)
        m.next(); #expect(m.step == 1 && !m.isDone)
        m.next(); #expect(m.isDone && store.firstRun)

        let skipped = FirstRunModel(store: MemoryStore())
        skipped.finish()
        #expect(skipped.isDone)
        #expect(FirstRunModel(store: store).isDone)
    }

    @Test func readoutChoiceIsSaved() {
        let store = MemoryStore()
        ReadoutSettings(store: store).readout = .power
        #expect(store.readout == .power)
    }
}

private func full(percent: Int = 80, amps: Int64 = 0, plugged: Bool = true, charging: Bool = false,
                  system: Int? = 14655, adapter: Int? = 94) -> BatteryReading {
    var p: [String: Any] = ["CurrentCapacity": percent, "ExternalConnected": plugged ? 1 : 0, "IsCharging": charging ? 1 : 0,
                            "Voltage": 12000, "InstantAmperage": NSNumber(value: UInt64(bitPattern: amps))]
    if let system { p["PowerTelemetryData"] = ["SystemLoad": system] }
    if let adapter { p["AdapterDetails"] = ["Watts": adapter] }
    return BatteryReading(properties: p)!
}

@Suite struct BatteryGlyphTests {
    @Test func badgeFollowsPowerState() {
        #expect(MenuBarReadout.glyph(for: full(plugged: false)).badge == .discharge)
        #expect(MenuBarReadout.glyph(for: full()).badge == .plugPaused)
        #expect(MenuBarReadout.glyph(for: full(charging: true)).badge == .plugBolt)
        #expect(MenuBarReadout.glyph(for: full(charging: true), chargeHeld: true).badge == .plugPaused)
        #expect(MenuBarReadout.glyph(for: full(plugged: false), chargeHeld: true).badge == .discharge)
        // plugged in but running from the battery (a held charge): the drain arrow, not the pause bars
        #expect(MenuBarReadout.glyph(for: full(amps: -1500), chargeHeld: true).badge == .plugDrain)
        #expect(MenuBarReadout.glyph(for: full(amps: -1500)).badge == .plugDrain)
        #expect(BatteryBadge.plugDrain.single == .drain && BatteryBadge.plugDrain.isWide)
    }

    @Test func levelAndNoDataAreHonest() {
        #expect(MenuBarReadout.glyph(for: full(percent: 40)).level == 0.4)
        #expect(MenuBarReadout.glyph(for: full(percent: 140)).level == 1)
        #expect(MenuBarReadout.glyph(for: nil) == BatteryGlyph(level: 0, badge: .none))
    }

    @Test func wattsFormatAndNil() {
        #expect(PowerFlow.watts(25.44) == "25.4 W")
        #expect(PowerFlow.watts(-14.2) == "14.2 W")
        #expect(PowerFlow.watts(nil) == "—")
    }

    @Test func flowWhenChargingOnAC() {
        let f = PowerFlow(full(amps: 1300, charging: true))
        #expect(f.adapter == "94 W" && f.system == "14.7 W" && f.battery == "15.6 W" && f.batteryNote == "Charging")
    }

    @Test func flowOnBatteryHasNoAdapterAndDischarges() {
        let f = PowerFlow(full(amps: -1500, plugged: false))
        #expect(f.adapter == "—" && f.adapterNote == "Not connected" && f.battery == "18.0 W" && f.batteryNote == "Discharging")
    }

    @Test func missingValuesShowDashes() {
        let f = PowerFlow(full(system: nil, adapter: nil))
        #expect(f.adapter == "—" && f.system == "—" && f.batteryNote == "Idle")
        #expect(PowerFlow(nil).battery == "—" && PowerFlow(nil).batteryNote == "No data")
    }
}

@Suite struct ShownPercentTests {
    private func r(percent: Int, amps: Int64, raw: Int, max: Int) -> BatteryReading {
        BatteryReading(properties: ["CurrentCapacity": percent, "ExternalConnected": 1, "IsCharging": 0, "Voltage": 12000,
                                    "InstantAmperage": NSNumber(value: UInt64(bitPattern: amps)),
                                    "BatteryData": ["AppleRawCurrentCapacity": raw, "AppleRawMaxCapacity": max]])!
    }

    @Test func showsTheBatterysOwnFigureWhileItDrainsAndHundredWhenFullOnTheCharger() {
        let draining = r(percent: 88, amps: -1400, raw: 4841, max: 5789) // macOS still says 88 during a hold
        #expect(draining.shownPercentText == "83.6%")
        #expect(MenuBarReadout.percent.text(for: draining, showHardwarePercent: false) == "84%")
        let full = r(percent: 100, amps: 0, raw: 5650, max: 5773)
        #expect(full.shownPercentText == "100%")
    }

    @Test func appleIsTheDefaultLookAndCarriesThePercent() throws {
        let defaults = try #require(UserDefaults(suiteName: "glyph-style-\(UUID().uuidString)"))
        let settings = GlyphStyleSettings(defaults: defaults)
        let first = settings.style
        #expect(first == .apple)
        #expect(MenuBarGlyphStyle.apple.showsPercentInside)
        #expect(!MenuBarGlyphStyle.classic.showsPercentInside)
        settings.style = .ring
        let reloaded = GlyphStyleSettings(defaults: defaults).style
        #expect(reloaded == .ring)
    }
}
