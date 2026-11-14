import Testing
@testable import Core

private struct Fixed: PermissionChecker {
    var granted: Set<Permission>
    func status(of p: Permission) async -> PermissionStatus { granted.contains(p) ? .granted : .notGranted }
}

@MainActor
@Suite struct PermissionsTests {
    private func model(enabled: Set<FeatureID>, granted: Set<Permission>) -> PermissionsModel {
        let store = MemoryStore(); store.ids = enabled
        let reg = FeatureRegistry(store: store)
        for id in FeatureID.allCases { reg.register(id) { FakeTool() } }
        return PermissionsModel(checker: Fixed(granted: granted), registry: reg)
    }

    @Test func nothingIsAskedOrKnownBeforeRefresh() {
        let m = model(enabled: [], granted: [])
        #expect(Permission.allCases.allSatisfy { m.status($0) == .unknown })
    }

    @Test func refreshReadsEveryStatus() async {
        let m = model(enabled: [], granted: [.accessibility])
        await m.refresh()
        #expect(m.status(.accessibility) == .granted)
        #expect(m.status(.screenRecording) == .notGranted)
    }

    @Test func usersAreOnlyToolsThatAreOn() {
        let m = model(enabled: [.readQR, .battery], granted: [])
        #expect(m.activeUsers(of: .screenRecording) == [.readQR])
        #expect(m.activeUsers(of: .fullDiskAccess).isEmpty)
    }

    @Test func grantedWithNoActiveToolIsUnused() async {
        let m = model(enabled: [.readQR], granted: [.screenRecording, .fullDiskAccess])
        await m.refresh()
        #expect(!m.isUnused(.screenRecording))
        #expect(m.isUnused(.fullDiskAccess))
    }

    @Test func everyPermissionNamesATool() {
        #expect(Permission.allCases.allSatisfy { !$0.usedBy.isEmpty })
    }
}
