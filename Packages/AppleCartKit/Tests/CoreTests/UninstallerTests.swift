import Foundation
import Testing
@testable import Core

private final class FakeTrasher: Trasher, @unchecked Sendable {
    let bin: URL
    var failOn: Set<String> = []
    init(_ bin: URL) { self.bin = bin }
    func trash(_ url: URL) throws -> URL {
        if failOn.contains(url.lastPathComponent) { throw CocoaError(.fileWriteNoPermission) }
        let dest = bin.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: dest); return dest
    }
    func restore(_ trashed: URL, to original: URL) throws { try FileManager.default.moveItem(at: trashed, to: original) }
}

@MainActor
private final class FakeRunning: RunningApps {
    var running = false; var quits: [String] = []
    func isRunning(_ id: String) -> Bool { running }
    func quit(_ id: String) { quits.append(id); running = false }
}

@MainActor
private struct Sandbox {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-" + UUID().uuidString)
    var home: URL { root.appendingPathComponent("home") }
    var apps: URL { root.appendingPathComponent("Applications") }
    var bin: URL { root.appendingPathComponent("bin") }
    let id = "com.example.dummy"

    func make() throws -> URL {
        let fm = FileManager.default
        let app = apps.appendingPathComponent("Dummy.app/Contents")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": "Dummy", "CFBundlePackageType": "APPL"]
        try (plist as NSDictionary).write(to: app.appendingPathComponent("Info.plist"))
        for rel in ["Library/Application Support/\(id)/data", "Library/Caches/\(id)/c", "Library/Preferences/\(id).plist",
                    "Library/Group Containers/ABCDE12345.\(id)/g", "Library/Application Support/com.example.dummy2/other",
                    "Library/Documents/keep.txt"] {
            let f = home.appendingPathComponent(rel)
            try fm.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: f)
        }
        return apps.appendingPathComponent("Dummy.app")
    }
    func policy() -> UninstallPolicy { UninstallPolicy(home: home, applicationRoots: [apps]) }
}

@MainActor
@Suite struct UninstallerTests {
    @Test func findsOnlyFilesNamedForTheBundleID() async throws {
        let s = Sandbox(); let app = try s.make(); defer { try? FileManager.default.removeItem(at: s.root) }
        let m = UninstallerModel(policy: s.policy(), trasher: FakeTrasher(s.bin), running: FakeRunning(), hasFullDiskAccess: { true })
        await m.choose(app)
        guard case .preview(let plan) = m.phase else { Issue.record("no preview"); return }
        let names = plan.items.map(\.url.lastPathComponent)
        #expect(names.contains("Dummy.app") && names.contains("com.example.dummy.plist") && names.contains("ABCDE12345.com.example.dummy"))
        #expect(!names.contains("com.example.dummy2") && !names.contains("keep.txt"))
        #expect(plan.items.count == 5)
    }

    @Test func policyAllowsOnlyAppsAndNamedLibraryFolders() {
        let p = UninstallPolicy(home: URL(fileURLWithPath: "/Users/t"), applicationRoots: [URL(fileURLWithPath: "/Applications")])
        #expect(p.allows(URL(fileURLWithPath: "/Applications/X.app")))
        #expect(p.allows(URL(fileURLWithPath: "/Users/t/Library/Caches/com.x")))
        for bad in ["/Users/t/Documents/a", "/Users/t/Library/Caches", "/Users/t/Library", "/System/Applications/Notes.app", "/Applications/notes.txt",
                    "/Users/t/Library/Caches/../Documents/a", "/Users/t/Library/Keychains/login.keychain-db", "/"] {
            #expect(!p.allows(URL(fileURLWithPath: bad)), "\(bad)")
        }
    }

    @Test func refusesAppleAppsSelfAndAppsOutsideApplications() async throws {
        let s = Sandbox(); _ = try s.make(); defer { try? FileManager.default.removeItem(at: s.root) }
        let p = s.policy()
        #expect(p.refusal(for: AppInfo(url: s.apps.appendingPathComponent("Dummy.app"), name: "D", bundleID: "com.apple.Safari")) == .appleApp)
        #expect(p.refusal(for: AppInfo(url: s.apps.appendingPathComponent("Dummy.app"), name: "D", bundleID: "app.rarecreatures.applecart")) == .thisApp)
        #expect(p.refusal(for: AppInfo(url: URL(fileURLWithPath: "/tmp/Foo.app"), name: "F", bundleID: "com.f")) == .outsideApplications)
        let m = UninstallerModel(policy: p, trasher: FakeTrasher(s.bin), running: FakeRunning(), hasFullDiskAccess: { true })
        await m.choose(s.root)
        #expect(m.phase == .refused(.notAnApp))
    }

    @Test func movesSelectedItemsToTrashAndUndoPutsThemBack() async throws {
        let s = Sandbox(); let app = try s.make(); defer { try? FileManager.default.removeItem(at: s.root) }
        let m = UninstallerModel(policy: s.policy(), trasher: FakeTrasher(s.bin), running: FakeRunning(), hasFullDiskAccess: { true })
        await m.choose(app)
        let cache = s.home.appendingPathComponent("Library/Caches/\(s.id)")
        m.selected.remove(cache) // owner unticks one
        m.moveToTrash()
        guard case .done(let r) = m.phase else { Issue.record("not done"); return }
        #expect(r.moved.count == 4 && r.failed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: app.path) && FileManager.default.fileExists(atPath: cache.path))
        m.undo()
        #expect(FileManager.default.fileExists(atPath: app.path))
        guard case .done(let u) = m.phase else { return }
        #expect(u.undone && u.moved.isEmpty)
    }

    @Test func runningAppMustBeQuitFirst() async throws {
        let s = Sandbox(); let app = try s.make(); defer { try? FileManager.default.removeItem(at: s.root) }
        let run = FakeRunning(); run.running = true
        let m = UninstallerModel(policy: s.policy(), trasher: FakeTrasher(s.bin), running: run, hasFullDiskAccess: { false })
        await m.choose(app)
        #expect(m.appIsRunning && m.protectedFoldersHidden)
        m.moveToTrash()
        if case .preview = m.phase {} else { Issue.record("moved while running") }
        #expect(FileManager.default.fileExists(atPath: app.path))
    }

    @Test func appFailureStopsBeforeTouchingItsFiles() async throws {
        let s = Sandbox(); let app = try s.make(); defer { try? FileManager.default.removeItem(at: s.root) }
        let t = FakeTrasher(s.bin); t.failOn = ["Dummy.app"]
        let m = UninstallerModel(policy: s.policy(), trasher: t, running: FakeRunning(), hasFullDiskAccess: { true })
        await m.choose(app); m.moveToTrash()
        guard case .done(let r) = m.phase else { return }
        #expect(r.moved.isEmpty && r.failed.count == 1)
        #expect(FileManager.default.fileExists(atPath: s.home.appendingPathComponent("Library/Caches/\(s.id)").path))
    }
}
