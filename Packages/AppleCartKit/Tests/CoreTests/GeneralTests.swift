import Foundation
import Testing
@testable import Core

@MainActor private final class FakeLogin: LoginItem {
    var isEnabled = false, refuse = false
    func set(_ on: Bool) throws { if refuse { throw CocoaError(.fileWriteNoPermission) }; isEnabled = on }
}

@MainActor
@Suite struct GeneralTests {
    @Test func launchAtLoginShowsWhatMacOSSays() {
        let f = FakeLogin(); let l = LaunchAtLogin(item: f)
        l.set(true); #expect(l.isOn && l.error == nil)
        f.refuse = true; l.set(false)
        #expect(l.isOn && l.error != nil) // still on: macOS refused
    }

    @Test func debugReportHasVersionsAndSwitchesOnly() throws {
        let r = DebugReport(appVersion: "0.1", build: "7", macOS: "27.2", model: "Mac15,6", enabledTools: ["Battery", "Clipboard"],
                            permissions: ["Accessibility": "granted", "Screen Recording": "not granted"])
        #expect(r.text.contains("Apple Cart 0.1 (7)") && r.text.contains("Tools on: Battery, Clipboard"))
        #expect(!r.text.contains(NSHomeDirectory()) && !r.text.contains(NSUserName()))
        let url = try #require(r.mailto("support@example.com"))
        #expect(url.scheme == "mailto" && url.absoluteString.hasPrefix("mailto:support@example.com?"))
        #expect(url.absoluteString.count < 2000)
    }

    @Test func eraseAllRemovesSettingsAndEveryFolder() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("erase-" + UUID().uuidString)
        let a = tmp.appendingPathComponent("A"), b = tmp.appendingPathComponent("B"), keep = tmp.appendingPathComponent("Keep")
        for d in [a, b, keep] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); try Data("x".utf8).write(to: d.appendingPathComponent("f")) }
        defer { try? FileManager.default.removeItem(at: tmp) }
        let suite = "erase-" + UUID().uuidString, d = UserDefaults(suiteName: suite)!
        d.set(true, forKey: "k")
        let done = AppDataEraser(defaultsDomain: suite, folders: [a, b, tmp.appendingPathComponent("missing")]).eraseAll(defaults: d)
        #expect(done == ["Settings", "A", "B"])
        #expect(d.object(forKey: "k") == nil)
        #expect(!FileManager.default.fileExists(atPath: a.path) && !FileManager.default.fileExists(atPath: b.path) && FileManager.default.fileExists(atPath: keep.path))
    }
}
