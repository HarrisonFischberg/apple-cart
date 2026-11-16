import Foundation
import Testing
@testable import Core

@MainActor
@Suite struct PowerFlowsTests {
    private func reading(plugged: Int, amps: Int64, system: Int?) -> BatteryReading? {
        var p: [String: Any] = ["CurrentCapacity": 50, "ExternalConnected": plugged, "IsCharging": 0, "Voltage": 12000,
                                "InstantAmperage": NSNumber(value: UInt64(bitPattern: amps))]
        if let system { p["PowerTelemetryData"] = ["SystemLoad": system] }
        return BatteryReading(properties: p)
    }

    @Test func chargingSplitsTheChargerBetweenMacAndBattery() {
        let f = PowerFlows(reading(plugged: 1, amps: 1000, system: 10000))
        #expect(f.chargerToMac == 10 && abs(f.chargerToBattery! - 12) < 0.001 && f.batteryToMac == 0)
    }

    @Test func onBatteryOnlyTheBatteryFeedsTheMac() {
        let f = PowerFlows(reading(plugged: 0, amps: -1500, system: 18000))
        #expect(f.chargerToMac == 0 && f.chargerToBattery == 0 && abs(f.batteryToMac! - 18) < 0.001)
    }

    @Test func missingSystemLoadStaysUnknownAndNoReadingIsAllUnknown() {
        #expect(PowerFlows(reading(plugged: 1, amps: 0, system: nil)).chargerToMac == nil)
        #expect(PowerFlows(nil).batteryToMac == nil)
    }
}
