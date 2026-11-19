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

    @Test func releaseRequirementsAlsoDemandDeveloperID() {
        let devID = "certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]"
        #expect(CodeSigningRequirement.app(teamID: "KTV2G3Z883", developerIDOnly: true)
                == "anchor apple generic and identifier \"app.rarecreatures.applecart\" and certificate leaf[subject.OU] = \"KTV2G3Z883\" and \(devID)")
        #expect(CodeSigningRequirement.helper(teamID: "KTV2G3Z883", developerIDOnly: true)
                == "anchor apple generic and identifier \"app.rarecreatures.applecart.helper\" and certificate leaf[subject.OU] = \"KTV2G3Z883\" and \(devID)")
        // Debug keeps today's string, so Apple Development builds still work on the owner's Mac.
        #expect(CodeSigningRequirement.app(teamID: "KTV2G3Z883", developerIDOnly: false) == CodeSigningRequirement.app(teamID: "KTV2G3Z883"))
        #expect(CodeSigningRequirement.app(teamID: "KTV2G3Z883")?.contains("6.1.13") == false)
        // Still fails closed without a valid team ID.
        #expect(CodeSigningRequirement.app(teamID: nil, developerIDOnly: true) == nil)
        #expect(CodeSigningRequirement.helper(teamID: "bad", developerIDOnly: true) == nil)
    }

    @Test func onlyReleaseBuildsAreDeveloperIDOnly() {
        #expect(CodeSigningRequirement.developerIDOnly(debugBuild: false))
        #expect(!CodeSigningRequirement.developerIDOnly(debugBuild: true))
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

    @Test func versionFourAddsTheLightAndOlderHelpersKeepWhatTheyHad() {
        #expect(HelperIdentity.version == 4)
        #expect((2...4).allSatisfy { HelperIdentity.supportsCharging(helperVersion: $0) })
        #expect(!HelperIdentity.supportsCharging(helperVersion: 1) && !HelperIdentity.supportsCharging(helperVersion: 5))
        #expect(HelperIdentity.supportsFans(helperVersion: 3) && HelperIdentity.supportsFans(helperVersion: 4))
        #expect(!HelperIdentity.supportsFans(helperVersion: 2) && !HelperIdentity.supportsFans(helperVersion: 5))
        #expect(HelperIdentity.supportsLED(helperVersion: 4))
        #expect(!HelperIdentity.supportsLED(helperVersion: 3) && !HelperIdentity.supportsLED(helperVersion: 5))
    }
}
