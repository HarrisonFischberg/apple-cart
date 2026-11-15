import Foundation
import Observation

@MainActor
public protocol LoginItem: AnyObject {
    var isEnabled: Bool { get }
    func set(_ on: Bool) throws
}

@MainActor @Observable
public final class LaunchAtLogin {
    public private(set) var isOn: Bool
    public private(set) var error: String?
    @ObservationIgnored private let item: LoginItem

    public init(item: LoginItem) { self.item = item; isOn = item.isEnabled }

    public func refresh() { isOn = item.isEnabled }

    public func set(_ on: Bool) {
        do { try item.set(on); error = nil }
        catch { self.error = "macOS did not allow this. Move Apple Cart to the Applications folder and try again." }
        isOn = item.isEnabled // show what macOS says, not what was asked
    }
}

/// The text of a Send Debug Logs mail. It holds versions and switch states only: no file names,
/// no clipboard, no screen content, no account or device identifiers beyond the Mac model.
public struct DebugReport: Sendable {
    public var appVersion: String, build: String, macOS: String, model: String
    public var enabledTools: [String], permissions: [String: String]

    public init(appVersion: String, build: String, macOS: String, model: String, enabledTools: [String], permissions: [String: String]) {
        self.appVersion = appVersion; self.build = build; self.macOS = macOS; self.model = model
        self.enabledTools = enabledTools; self.permissions = permissions
    }

    public var text: String {
        """
        (Tell us what went wrong above this line.)
        --------------------------------------------
        Apple Cart \(appVersion) (\(build))
        macOS \(macOS)
        Mac model: \(model)
        Tools on: \(enabledTools.isEmpty ? "none" : enabledTools.sorted().joined(separator: ", "))
        Permissions: \(permissions.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        """
    }

    /// A mail draft the user reads and sends themselves.
    public func mailto(_ address: String) -> URL? {
        var c = URLComponents(); c.scheme = "mailto"; c.path = address
        c.queryItems = [URLQueryItem(name: "subject", value: "Apple Cart debug info"), URLQueryItem(name: "body", value: text)]
        return c.url
    }
}

/// Delete all app data: settings and every local store. Folders are passed in so tests use temporary ones.
public struct AppDataEraser {
    public let defaultsDomain: String, folders: [URL]
    public init(defaultsDomain: String, folders: [URL]) { self.defaultsDomain = defaultsDomain; self.folders = folders }

    @discardableResult
    public func eraseAll(defaults: UserDefaults = .standard) -> [String] {
        var removed: [String] = []
        defaults.removePersistentDomain(forName: defaultsDomain)
        removed.append("Settings")
        for f in folders where FileManager.default.fileExists(atPath: f.path) {
            if (try? FileManager.default.removeItem(at: f)) != nil { removed.append(f.lastPathComponent) }
        }
        return removed
    }
}
