import Testing
@testable import HelperProtocol

@Suite struct LimitsTests {
    @Test func chargeLimitStaysInProductRange() {
        #expect(ChargeLimits.clamped(5) == 20)
        #expect(ChargeLimits.clamped(80) == 80)
        #expect(ChargeLimits.clamped(150) == 100)
    }

    @Test func codeSigningRequirementsNameBundleAndTeam() {
        #expect(CodeSigningRequirement.app(teamID: "KTV2G3Z883")
                == "anchor apple generic and identifier \"app.rarecreatures.applecart\" and certificate leaf[subject.OU] = \"KTV2G3Z883\"")
        #expect(CodeSigningRequirement.helper(teamID: "KTV2G3Z883")
                == "anchor apple generic and identifier \"app.rarecreatures.applecart.helper\" and certificate leaf[subject.OU] = \"KTV2G3Z883\"")
        #expect(CodeSigningRequirement.app(teamID: nil) == nil)
        #expect(CodeSigningRequirement.app(teamID: "KTV2G3Z883\" or anchor apple") == nil) // no injection into the requirement
        #expect(CodeSigningRequirement.make(identifier: "a\" or true", teamID: "KTV2G3Z883") == nil)
    }

    @Test func leaseIsClamped() {
        #expect(AdapterLease.clamped(0) == 10)
        #expect(AdapterLease.clamped(90) == 90)
        #expect(AdapterLease.clamped(10_000) == 300)
    }

    @Test func fansNeverGoBelowSystemMinimum() {
        #expect(FanLimits.clampedMinimum(requested: 500, systemMinimum: 1200, hardwareMaximum: 6000) == 1200)
        #expect(FanLimits.clampedMinimum(requested: 3000, systemMinimum: 1200, hardwareMaximum: 6000) == 3000)
        #expect(FanLimits.clampedMinimum(requested: 9000, systemMinimum: 1200, hardwareMaximum: 6000) == 6000)
    }
}
