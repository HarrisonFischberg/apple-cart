import Foundation
import Testing
@testable import Core

private final class BinTrasher: Trasher, @unchecked Sendable {
    let bin: URL
    init(_ b: URL) { bin = b; try? FileManager.default.createDirectory(at: b, withIntermediateDirectories: true) }
    func trash(_ url: URL) throws -> URL { let d = bin.appendingPathComponent(UUID().uuidString); try FileManager.default.moveItem(at: url, to: d); return d }
    func restore(_ t: URL, to o: URL) throws { try FileManager.default.moveItem(at: t, to: o) }
}

@MainActor
private func sandbox() throws -> URL {
    let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("clean-" + UUID().uuidString)
    for rel in ["Library/Caches/com.a/f", "Library/Caches/com.b/f", "Library/Caches/com.apple.helpd/f", "Library/Logs/x.log", "Library/Developer/Xcode/DerivedData/P-1/o", "Documents/keep.txt", "Library/Application Support/s/f"] {
        let f = home.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 5000).write(to: f)
    }
    return home
}

@MainActor
@Suite struct CleanerTests {
    @Test func policyAllowsOnlyDirectChildrenOfTheThreeFolders() {
        let p = CleanerPolicy(home: URL(fileURLWithPath: "/Users/t"))
        #expect(p.allows(URL(fileURLWithPath: "/Users/t/Library/Caches/com.a")))
        #expect(p.allows(URL(fileURLWithPath: "/Users/t/Library/Developer/Xcode/DerivedData/P-1")))
        for bad in ["/Users/t/Library/Caches", "/Users/t/Library/Caches/com.a/deep", "/Users/t/Documents", "/Users/t/Library/Application Support/x",
                    "/Users/t/Library/Caches/../Documents", "/Library/Caches/x", "/"] { #expect(!p.allows(URL(fileURLWithPath: bad)), "\(bad)") }
    }

    @Test func scansPreviewsTrashesAndUndoes() async throws {
        let home = try sandbox(); defer { try? FileManager.default.removeItem(at: home) }
        let m = CleanerModel(policy: CleanerPolicy(home: home), trasher: BinTrasher(home.appendingPathComponent("bin")))
        m.scan()
        for _ in 0..<100 { if case .preview = m.phase { break }; try await Task.sleep(for: .milliseconds(50)) }
        guard case .preview(let items) = m.phase else { Issue.record("no preview"); return }
        #expect(Set(items.map(\.url.lastPathComponent)) == ["com.a", "com.b", "x.log", "P-1"])
        let a = home.appendingPathComponent("Library/Caches/com.a")
        m.selected.remove(items.first { $0.url.lastPathComponent == "com.a" }!.url) // as the UI does
        m.moveToTrash()
        guard case .done(let r) = m.phase else { Issue.record("not done"); return }
        #expect(r.moved.count == 3 && FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Documents/keep.txt").path))
        m.undo()
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/com.b").path))
    }

    @Test func cancellingAScanLeavesNothingToTrash() async throws {
        let home = try sandbox(); defer { try? FileManager.default.removeItem(at: home) }
        let m = CleanerModel(policy: CleanerPolicy(home: home), trasher: BinTrasher(home.appendingPathComponent("bin")))
        m.scan(); m.cancel()
        try await Task.sleep(for: .milliseconds(300))
        #expect(m.phase == .idle)
    }

    @Test func diskMapListsSizesLargestFirstAndDrillsDown() async throws {
        let home = try sandbox(); defer { try? FileManager.default.removeItem(at: home) }
        let m = DiskMapModel(root: home)
        m.scan()
        for _ in 0..<100 { if !m.scanning { break }; try await Task.sleep(for: .milliseconds(50)) }
        #expect(Set(m.entries.map(\.url.lastPathComponent)) == ["Library", "Documents"] && m.entries.first?.url.lastPathComponent == "Library")
        m.open(m.entries[0])
        #expect(m.path.count == 2)
        m.up(); #expect(m.path.count == 1)
    }
}
