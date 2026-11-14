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
