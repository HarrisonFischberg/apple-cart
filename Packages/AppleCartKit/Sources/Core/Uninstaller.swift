import Foundation
import Observation

public struct AppInfo: Equatable, Sendable {
    public let url: URL, name: String, bundleID: String
    public init(url: URL, name: String, bundleID: String) { self.url = url; self.name = name; self.bundleID = bundleID }

    public static func read(_ url: URL) -> AppInfo? {
        guard url.pathExtension == "app", let b = Bundle(url: url), let id = b.bundleIdentifier else { return nil }
        let name = b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? b.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return AppInfo(url: url, name: name, bundleID: id)
    }
}

public enum UninstallRefusal: Equatable, Sendable {
    case notAnApp, appleApp, thisApp, outsideApplications

    public var message: String {
        switch self {
        case .notAnApp: "That is not an app this tool can read."
        case .appleApp: "Apps that come with macOS cannot be removed."
        case .thisApp: "Apple Cart cannot remove itself."
        case .outsideApplications: "Only apps in your Applications folders can be removed."
        }
    }
}

public struct Leftover: Identifiable, Equatable, Sendable {
    public let url: URL, bytes: Int64, isApp: Bool
    public var id: URL { url }
}

public struct UninstallPlan: Equatable, Sendable {
    public let app: AppInfo
    public let items: [Leftover]
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

/// The only paths this tool may ever touch: the app, and files named for its bundle ID inside fixed user Library folders.
public struct UninstallPolicy: Sendable {
    public let home: URL, applicationRoots: [URL], selfBundleID: String

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                applicationRoots: [URL]? = nil, selfBundleID: String = "app.rarecreatures.applecart") {
        self.home = home.resolvingSymlinksInPath()
        self.applicationRoots = (applicationRoots ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]).map { $0.resolvingSymlinksInPath() }
        self.selfBundleID = selfBundleID
    }

    static let libraryFolders = ["Application Support", "Caches", "Containers", "Group Containers", "Saved Application State",
                                 "HTTPStorages", "WebKit", "Preferences", "Application Scripts", "Logs", "Cookies"]

    private var library: URL { home.appendingPathComponent("Library") }

    public func refusal(for app: AppInfo) -> UninstallRefusal? {
        if app.bundleID.hasPrefix("com.apple.") { return .appleApp }
        if app.bundleID == selfBundleID { return .thisApp }
        return applicationRoots.contains { isInside(app.url.resolvingSymlinksInPath(), $0) } ? nil : .outsideApplications
    }

    /// Strictly inside an allowed folder, symlinks resolved so nothing can point out of it.
    public func allows(_ url: URL) -> Bool {
        let u = url.resolvingSymlinksInPath()
        if u.pathExtension == "app" { return applicationRoots.contains { isInside(u, $0) } }
        return Self.libraryFolders.contains { isInside(u, library.appendingPathComponent($0)) }
    }

    private func isInside(_ url: URL, _ folder: URL) -> Bool {
        let f = folder.standardizedFileURL.pathComponents, u = url.standardizedFileURL.pathComponents
        return u.count > f.count && Array(u.prefix(f.count)) == f && !u.contains("..")
    }

    func candidates(for app: AppInfo) -> [URL] {
        let id = app.bundleID, fm = FileManager.default
        func lib(_ parts: String...) -> URL { parts.reduce(library) { $0.appendingPathComponent($1) } }
        var urls = [lib("Application Support", id), lib("Caches", id), lib("Containers", id), lib("Saved Application State", id + ".savedState"),
                    lib("HTTPStorages", id), lib("HTTPStorages", id + ".binarycookies"), lib("WebKit", id), lib("Preferences", id + ".plist"),
                    lib("Application Scripts", id), lib("Logs", id), lib("Cookies", id + ".binarycookies")]
        func entries(_ folder: URL, where match: (String) -> Bool) -> [URL] {
            ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter(match).map { folder.appendingPathComponent($0) }
        }
        urls += entries(lib("Group Containers")) { $0 == "group." + id || $0.hasSuffix("." + id) }
        urls += entries(lib("Preferences", "ByHost")) { $0.hasPrefix(id + ".") }
        return urls.filter { fm.fileExists(atPath: $0.path) && allows($0) }
    }
}

public enum DiskSize {
    public static func bytes(at url: URL, isCancelled: () -> Bool = { false }) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        var total = Int64((try? url.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0)
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let f = e?.nextObject() as? URL {
            if isCancelled() { break }
            if let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true { total += Int64(v.totalFileAllocatedSize ?? 0) }
        }
        return total
    }
}

public protocol Trasher: Sendable {
    func trash(_ url: URL) throws -> URL
    func restore(_ trashed: URL, to original: URL) throws
}

public struct FinderTrasher: Trasher {
    public init() {}
    public func trash(_ url: URL) throws -> URL {
        var out: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &out)
        return (out as URL?) ?? url
    }
    public func restore(_ trashed: URL, to original: URL) throws { try FileManager.default.moveItem(at: trashed, to: original) }
}

@MainActor
public protocol RunningApps: AnyObject {
    func isRunning(_ bundleID: String) -> Bool
    func quit(_ bundleID: String)
}

public struct UninstallReport: Equatable, Sendable {
    public var moved: [(original: URL, trashed: URL)] = []
    public var failed: [(url: URL, reason: String)] = []
    public var undone = false
    public static func == (a: Self, b: Self) -> Bool { a.moved.map(\.original) == b.moved.map(\.original) && a.failed.map(\.url) == b.failed.map(\.url) && a.undone == b.undone }
}

@MainActor @Observable
public final class UninstallerModel {
    public enum Phase: Equatable { case idle, scanning, preview(UninstallPlan), refused(UninstallRefusal), done(UninstallReport) }
    public private(set) var phase: Phase = .idle
    public var selected: Set<URL> = []
    public private(set) var appIsRunning = false
    public private(set) var protectedFoldersHidden = false
    @ObservationIgnored private let policy: UninstallPolicy
    @ObservationIgnored private let trasher: Trasher
    @ObservationIgnored private let running: RunningApps
    @ObservationIgnored private let hasFullDiskAccess: @Sendable () async -> Bool

    public init(policy: UninstallPolicy = UninstallPolicy(), trasher: Trasher = FinderTrasher(), running: RunningApps,
                hasFullDiskAccess: @escaping @Sendable () async -> Bool) {
        self.policy = policy; self.trasher = trasher; self.running = running; self.hasFullDiskAccess = hasFullDiskAccess
    }

    public func reset() { phase = .idle; selected = [] }

    public func choose(_ url: URL) async {
        guard let app = AppInfo.read(url) else { phase = .refused(.notAnApp); return }
        if let r = policy.refusal(for: app) { phase = .refused(r); return }
        phase = .scanning
        let policy = policy
        let found = await Task.detached { () -> [Leftover] in
            let appItem = Leftover(url: app.url, bytes: DiskSize.bytes(at: app.url), isApp: true)
            return [appItem] + policy.candidates(for: app).map { Leftover(url: $0, bytes: DiskSize.bytes(at: $0), isApp: false) }
        }.value
        appIsRunning = running.isRunning(app.bundleID)
        protectedFoldersHidden = !(await hasFullDiskAccess())
        selected = Set(found.map(\.url))
        phase = .preview(UninstallPlan(app: app, items: found))
    }

    public func quitApp() {
        guard case .preview(let plan) = phase else { return }
        running.quit(plan.app.bundleID)
        Task { // give the app a moment to close, then re-check
            try? await Task.sleep(for: .seconds(2))
            appIsRunning = running.isRunning(plan.app.bundleID)
        }
    }

    public func moveToTrash() {
        guard case .preview(let plan) = phase, !appIsRunning else { return }
        var report = UninstallReport()
        // The app goes first so a failure there leaves its files in place.
        for item in plan.items.sorted(by: { $0.isApp && !$1.isApp }) where selected.contains(item.url) {
            guard policy.allows(item.url) else { report.failed.append((item.url, "Not allowed")); continue }
            do { report.moved.append((item.url, try trasher.trash(item.url))) }
            catch { report.failed.append((item.url, "macOS would not move it")); if item.isApp { break } }
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
