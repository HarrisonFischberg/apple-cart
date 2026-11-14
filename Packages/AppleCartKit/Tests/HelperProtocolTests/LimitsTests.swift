import Testing
@testable import HelperProtocol

@Suite struct LimitsTests {
    @Test func chargeLimitStaysInProductRange() {
        #expect(ChargeLimits.clamped(5) == 20)
        #expect(ChargeLimits.clamped(80) == 80)
        #expect(ChargeLimits.clamped(150) == 100)
    }

    @Test func fansNeverGoBelowSystemMinimum() {
        #expect(FanLimits.clampedMinimum(requested: 500, systemMinimum: 1200, hardwareMaximum: 6000) == 1200)
        #expect(FanLimits.clampedMinimum(requested: 3000, systemMinimum: 1200, hardwareMaximum: 6000) == 3000)
        #expect(FanLimits.clampedMinimum(requested: 9000, systemMinimum: 1200, hardwareMaximum: 6000) == 6000)
    }
}
