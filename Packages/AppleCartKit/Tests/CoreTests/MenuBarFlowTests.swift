import Foundation
import Testing
@testable import Core

private func reading(percent: Int = 80, amps: Int64 = 0, plugged: Bool = false, extra: [String: Any] = [:]) -> BatteryReading {
    var d: [String: Any] = ["CurrentCapacity": percent, "ExternalConnected": plugged ? 1 : 0, "Voltage": 12000,
                            "InstantAmperage": NSNumber(value: UInt64(bitPattern: amps))]
    d.merge(extra) { $1 }
    return BatteryReading(properties: d)!
}

@MainActor
@Suite struct MenuBarFlowTests {
    @Test func segmentsFollowCatalogOrderAndSkipWhatIsNotReported() {
        let r = reading(amps: -1500, extra: ["TimeRemaining": 125])
        #expect(MenuBarItem.segments([.watts, .percent, .timeLeft], for: r) == ["80%", "−18 W", "2:05"])
        #expect(MenuBarItem.segments([.temperature], for: r).isEmpty)           // no temperature key: nothing shown
        #expect(MenuBarItem.segments([.temperature], for: reading(extra: ["Temperature": 3050])) == ["31°"])
        #expect(MenuBarItem.segments([.watts], for: reading()).isEmpty)          // idle
        #expect(MenuBarItem.segments([], for: r).isEmpty && MenuBarItem.segments([.percent], for: nil).isEmpty)
    }

    @Test func specAndAdapterItemsOnlyShowWhenTheyApply() {
        let r = reading(plugged: true, extra: ["TimeRemaining": 70, "IsCharging": 1, "CycleCount": 212,
                                              "AdapterDetails": ["Watts": 94, "AdapterVoltage": 20000, "Current": 4690],
                                              "BatteryData": ["AppleRawCurrentCapacity": 4000, "AppleRawMaxCapacity": 5000, "DesignCapacity": 5500]])
        #expect(MenuBarItem.segments([.timeToFull, .timeLeft, .adapterWatts, .adapterVolts, .adapterAmps, .cycles, .maxCapacity, .hardwarePercent], for: r)
                == ["1:10", "80.0%", "91%", "212 cycles", "94 W", "20 V", "4.7 A"])
        #expect(MenuBarItem.segments([.adapterWatts, .timeToFull], for: reading()).isEmpty)
        #expect(Set(MenuBarItem.allCases.map(\.group)) == Set(MenuBarItemGroup.allCases))
    }

    @Test func resetAndClearAll() {
        let s = ReadoutSettings(store: MemoryStore(), defaults: UserDefaults(suiteName: "mb-\(UUID())")!)
        s.items = [.cycles, .watts]; s.spacing = 12; s.showGlyph = false
        s.clearAll(); #expect(s.items.isEmpty)
        s.reset(); #expect(s.items == [.percent] && s.spacing == 4 && s.showGlyph)
    }

    @Test func limitsClamp() {
        #expect(MenuBarLimits.clampedSpacing(-3) == 0 && MenuBarLimits.clampedSpacing(99) == 20)
        #expect(MenuBarLimits.clampedUpdate(0) == 2 && MenuBarLimits.clampedUpdate(60) == 20 && MenuBarLimits.clampedUpdate(7) == 7)
    }

    @Test func settingsClampAndPersist() {
        let defaults = UserDefaults(suiteName: "menubar-\(UUID())")!
        let s = ReadoutSettings(store: MemoryStore(), defaults: defaults)
        #expect(s.updateSeconds == 5 && s.spacing == 4 && s.items == [.percent] && s.rightClick == [.checkForUpdates])
        s.updateSeconds = 500; s.spacing = -4
        #expect(s.updateSeconds == 20 && s.spacing == 0)
        s.readout = .power
        #expect(s.items == [.percent, .watts])
        s.items = [.timeLeft]; s.rightClick = [.copyStatus]
        let again = ReadoutSettings(store: MemoryStore(), defaults: defaults)
        #expect(again.updateSeconds == 20 && again.items == [.timeLeft] && again.rightClick == [.copyStatus])
    }

    @Test func breakdownHidesSmallStreamsAndNeverInvents() {
        let none = reading(plugged: true)
        #expect(PowerFlows.streams(none).map(\.title) == ["SoC", "USB", "Other", "Charger loss"])
        #expect(PowerFlows.streams(none).allSatisfy { $0.watts == nil })          // nothing reported: dashes
        let r = reading(plugged: true, extra: ["PowerOutDetails": [["Watts": 2178], ["Watts": 500]],
                                               "PowerTelemetryData": ["AdapterEfficiencyLoss": 400]])
        #expect(r.usbOutWatts == 2.678)
        #expect(PowerFlows.streams(r) == [PowerStream(title: "SoC", watts: nil), PowerStream(title: "USB", watts: 2.678),
                                          PowerStream(title: "Other", watts: nil)]) // 0.4 W loss hidden
        #expect(PowerFlows.streams(r, socWatts: 0.5, otherWatts: 3).map(\.title) == ["USB", "Other"]) // SoC under 1 W hidden
        #expect(PowerFlows.streams(nil).isEmpty)
    }

    @Test func weakChargerMeansBatteryGivesWhilePluggedIn() {
        #expect(PowerFlows.chargerTooWeak(reading(amps: -2000, plugged: true)))
        #expect(!PowerFlows.chargerTooWeak(reading(amps: -2000, plugged: false)))
        #expect(!PowerFlows.chargerTooWeak(reading(amps: 2000, plugged: true)))
        #expect(!PowerFlows.chargerTooWeak(nil))
    }

    @Test func widgetLayoutReordersHidesAndResets() {
        var l = BatteryWidgetLayout.standard
        l.move(.history, to: 0)
        #expect(l.order.first == .history && l.order.count == 5)
        l.setVisible(.details, false)
        #expect(!l.visible.contains(.details) && l.order.contains(.details))
        l.move(.history, to: 99); #expect(l.order.last == .history)
        l.reset(); #expect(l == .standard)
    }

    @Test func widgetLayoutHandlesUnknownAndNewIds() {
        let l = BatteryWidgetLayout(storedOrder: ["details", "gone", "details", "charge"], storedHidden: ["gone", "charge"])
        #expect(l.order == [.details, .charge, .powerFlow, .history, .energyApps]) // new widgets append, unknown dropped
        #expect(l.hidden == [.charge])
        #expect(BatteryWidgetLayout(storedOrder: [], storedHidden: []) == .standard)
    }

    @Test func widgetSettingsPersist() {
        let defaults = UserDefaults(suiteName: "widgets-\(UUID())")!
        let s = BatteryWidgetSettings(defaults: defaults)
        s.update { $0.move(.details, to: 0); $0.setVisible(.history, false) }
        let again = BatteryWidgetSettings(defaults: defaults)
        #expect(again.showPercentage && !again.openInEditMode && !again.showOnStartup)
        #expect(again.layout.order.first == .details && again.layout.hidden == [.history])
    }

    /// Shaped like the registry on the owner's M5 Mac with an iPhone charging from a USB-C port (values measured on 2026-11-18).
    @Test func phoneOnUSBGivesItsBatteryLevelOnlyWhenItIsUnambiguous() {
        let fed: [[String: Any]] = [["FedDesignCapacity": 0, "FedStateOfCharge": 0], ["FedDesignCapacity": 0, "FedStateOfCharge": 0],
                                    ["FedVendorID": 1452, "FedDesignCapacity": 160, "FedRemainingCapacity": 24, "FedStateOfCharge": 15],
                                    ["FedExternalConnected": 1, "FedDesignCapacity": 0, "FedStateOfCharge": 0]]
        var r = reading(plugged: true, extra: ["PowerOutDetails": [["Watts": 15504]], "FedDetails": fed])
        #expect(r.usbOutWatts == 15.504 && r.usbPoweredPorts == 1 && r.usbDeviceCharge == 15)
        #expect(r.usbLabel == "USB" && r.usbCaption == "USB 15%") // no name until the USB tree gives one
        r.usbDeviceName = "iPhone"
        #expect(r.usbCaption == "iPhone 15%")
        let e = FlowExplain.make(.stream("USB"), reading: r, pausedAt: nil, streams: PowerFlows.streams(r))
        #expect(e.title == "iPhone" && e.value == "15.5 W" && e.facts == ["iPhone battery: 15%"])
        #expect(FlowSummary.text(r, streams: PowerFlows.streams(r), rest: nil).contains("Charging iPhone at 15.5 watts, its battery at 15 percent."))

        // Two ports giving power: no level, since it could belong to either device.
        let two = reading(plugged: true, extra: ["PowerOutDetails": [["Watts": 15000], ["Watts": 4000]], "FedDetails": fed])
        #expect(two.usbPoweredPorts == 2 && two.usbDeviceCharge == nil && two.usbCaption == "USB")
        // Nothing drawing power: no level either, and the plain tile wording stays.
        let idle = reading(plugged: true, extra: ["PowerOutDetails": [["Watts": 0]], "FedDetails": fed])
        #expect(idle.usbDeviceCharge == nil)
        #expect(FlowExplain.make(.stream("USB"), reading: idle, pausedAt: nil, streams: []).title == "USB")
    }

    @Test func stateText() {
        #expect(reading(plugged: false).stateText == "On battery")
        #expect(reading(plugged: true).stateText == "Plugged in, not charging")
    }
}
