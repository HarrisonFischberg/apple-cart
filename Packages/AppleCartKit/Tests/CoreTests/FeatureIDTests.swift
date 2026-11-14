import Testing
@testable import Core

@Suite struct FeatureIDTests {
    @Test func idsAreUniqueAndTitled() {
        let ids = FeatureID.allCases.map(\.rawValue)
        #expect(Set(ids).count == ids.count)
        #expect(FeatureID.allCases.allSatisfy { !$0.title.isEmpty })
    }

    @Test func sixteenToolsPicked() {
        #expect(FeatureID.allCases.count == 16)
    }
}
