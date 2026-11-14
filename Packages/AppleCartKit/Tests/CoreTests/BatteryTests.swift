import Foundation
import Testing
@testable import Core

private func props(percent: Int = 80, amps: Int64 = 0, plugged: Int = 1) -> [String: Any] {
    ["CurrentCapacity": percent, "ExternalConnected": plugged, "IsCharging": 0, "CycleCount": 98,
     "Voltage": 12000, "InstantAmperage": NSNumber(value: UInt64(bitPattern: amps)), "TimeRemaining": 65535,
     "PowerTelemetryData": ["SystemLoad": 14655], "AdapterDetails": ["Watts": 94],
     "BatteryData": ["AppleRawCurrentCapacity": 4545, "AppleRawMaxCapacity": 5751, "DesignCapacity": 6249]]
}

@MainActor
@Suite struct BatteryTests {
    @Test func readsTheValuesTheSystemReports() throws {
        let r = try #require(BatteryReading(properties: props()))
        #expect(r.percent == 80 && r.isPluggedIn && r.cycleCount == 98 && r.adapterWatts == 94)
        #expect(abs(r.measuredPercent! - 79.03) < 0.01)
        #expect(abs(r.capacityVsDesign! - 0.9202) < 0.001)
        #expect(r.systemWatts == 14.655)
        #expect(r.temperatureC == nil && r.minutesRemaining == nil)
    }

    @Test func dischargingAmperageIsNegativeWatts() throws {
        let r = try #require(BatteryReading(properties: props(amps: -1500, plugged: 0)))
        #expect(abs(r.batteryWatts - -18) < 0.001)
    }

    @Test func noBatteryDataMeansNoReading() {
        #expect(BatteryReading(properties: [:]) == nil)
    }

    @Test func historyKeepsOnlyTheLast24Hours() throws {
        var h = BatteryHistory()
        let now = Date()
        for hoursAgo in [30, 25, 23, 1, 0] {
            h.add(try #require(BatteryReading(properties: props(), date: now.addingTimeInterval(Double(-hoursAgo) * 3600))))
        }
        #expect(h.samples.count == 3)
    }

    @Test func psOutputSumsAppsAndSortsBusiestFirst() {
        let out = """
          10 50.0 /Applications/Foo.app/Contents/MacOS/Foo
          11 30.0 /Applications/Foo.app/Contents/Frameworks/Foo Helper.app/Contents/MacOS/Foo Helper
          12 70.0 /usr/sbin/WindowServer
          13 bad line
        """
        let u = EnergyUsers.parse(out)
        #expect(u.map(\.name) == ["Foo", "WindowServer"])
        #expect(u[0].cpu == 80)
    }

    @Test func samplerRunsOnlyWhileSomeoneHoldsIt() async {
        let s = BatterySampler(interval: .milliseconds(5)) { BatteryReading(properties: props()) }
        #expect(!s.isSampling)
        s.hold("panel"); s.hold("menubar")
        #expect(s.isSampling && s.latest != nil)
        s.release("panel")
        #expect(s.isSampling)
        s.release("menubar")
        #expect(!s.isSampling)
    }
}
