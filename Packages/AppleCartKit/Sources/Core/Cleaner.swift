import Foundation
import Observation

public struct CleanItem: Identifiable, Equatable, Sendable {
    public let url: URL, bytes: Int64, group: String
    public var id: URL { url }
}

/// Cache cleaning touches only direct children of three user folders that apps and Xcode rebuild by themselves.
public struct CleanerPolicy: Sendable {
    public let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home.resolvingSymlinksInPath() }

    public var roots: [(group: String, url: URL)] {
        let lib = home.appendingPathComponent("Library")
        return [("App caches", lib.appendingPathComponent("Caches")), ("Logs", lib.appendingPathComponent("Logs")),
                ("Xcode build files", lib.appendingPathComponent("Developer/Xcode/DerivedData"))]
    }

    public func allows(_ url: URL) -> Bool {
        let u = url.resolvingSymlinksInPath().standardizedFileURL
        guard !url.pathComponents.contains("..") else { return false }
        return roots.contains { $0.url.standardizedFileURL.pathComponents == u.deletingLastPathComponent().pathComponents }
    }
}

@MainActor @Observable
public final class CleanerModel {
    public enum Phase: Equatable { case idle, scanning, preview([CleanItem]), done(UninstallReport) }
    public private(set) var phase: Phase = .idle
    public var selected: Set<URL> = []
    @ObservationIgnored private let policy: CleanerPolicy
    @ObservationIgnored private let trasher: Trasher
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(policy: CleanerPolicy = CleanerPolicy(), trasher: Trasher = FinderTrasher()) { self.policy = policy; self.trasher = trasher }

    public func reset() { cancel(); phase = .idle; selected = [] }

    public func cancel() { task?.cancel(); task = nil; if phase == .scanning { phase = .idle } }

    public func scan() {
        guard phase != .scanning else { return }
        phase = .scanning
        let policy = policy
        task = Task { [weak self] in
            let inner = Task.detached { () -> [CleanItem]? in
                var out: [CleanItem] = []
                for (group, root) in policy.roots {
                    let kids = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
                    for k in kids where policy.allows(k) && !k.lastPathComponent.hasPrefix("com.apple.") { // macOS's own caches stay put
                        if Task.isCancelled { return nil }
                        out.append(CleanItem(url: k, bytes: DiskSize.bytes(at: k, isCancelled: { Task.isCancelled }), group: group))
                    }
                }
                return Task.isCancelled ? nil : out.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
            }
            // Detached work ignores its parent's cancellation, so pass it on by hand.
            let items = await withTaskCancellationHandler { await inner.value } onCancel: { inner.cancel() }
            guard let self, let items, !Task.isCancelled else { return }
            self.selected = Set(items.map(\.url))
            self.phase = .preview(items)
        }
    }

    public func moveToTrash() {
        guard case .preview(let items) = phase else { return }
        var report = UninstallReport()
        for i in items where selected.contains(i.url) {
            guard policy.allows(i.url) else { report.failed.append((i.url, "Not allowed")); continue }
            do { report.moved.append((i.url, try trasher.trash(i.url))) } catch { report.failed.append((i.url, "In use or protected")) }
        }
        phase = .done(report)
    }

    public func undo() {
        guard case .done(var report) = phase, !report.undone else { return }
        var left: [(original: URL, trashed: URL)] = []
        for m in report.moved.reversed() {
            do { try trasher.restore(m.trashed, to: m.original) } catch { left.append(m); report.failed.append((m.original, "Could not put back")) }
        }
        report.moved = left; report.undone = true
        phase = .done(report)
    }
}

public struct DiskEntry: Identifiable, Equatable, Sendable {
    public let url: URL, bytes: Int64, isFolder: Bool
    public var id: URL { url }
}

/// Read-only: shows where space goes, one folder level at a time. Never deletes.
@MainActor @Observable
public final class DiskMapModel {
    public private(set) var path: [URL]
    public private(set) var entries: [DiskEntry] = []
    public private(set) var scanning = false
    @ObservationIgnored private let root: URL
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser) { self.root = root; path = [root] }

    public var current: URL { path.last ?? root }
    public var largest: Int64 { entries.map(\.bytes).max() ?? 0 }

    public func scan() {
        task?.cancel(); entries = []; scanning = true
        let dir = current
        task = Task { [weak self] in
            let kids = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
            for k in kids {
                let inner = Task.detached { () -> DiskEntry? in
                    guard !Task.isCancelled else { return nil }
                    let folder = (try? k.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    return DiskEntry(url: k, bytes: DiskSize.bytes(at: k, isCancelled: { Task.isCancelled }), isFolder: folder)
                }
                let e = await withTaskCancellationHandler { await inner.value } onCancel: { inner.cancel() }
                guard let self, let e, !Task.isCancelled else { return }
                self.entries = (self.entries + [e]).sorted { $0.bytes > $1.bytes }
            }
            self?.scanning = false
        }
    }

    public func stop() { task?.cancel(); scanning = false }
    public func open(_ e: DiskEntry) { guard e.isFolder else { return }; path.append(e.url); scan() }
    public func up() { guard path.count > 1 else { return }; path.removeLast(); scan() }
}
