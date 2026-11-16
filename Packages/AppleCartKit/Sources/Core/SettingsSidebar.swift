import Foundation

/// One page in the Settings window.
public enum SettingsPage: Hashable, Sendable {
    case general, menuBar, permissions, tool(FeatureID), about

    /// Stable string for remembering the selection between opens.
    public var id: String {
        switch self {
        case .general: "general"
        case .menuBar: "menuBar"
        case .permissions: "permissions"
        case .about: "about"
        case .tool(let f): "tool.\(f.rawValue)"
        }
    }

    /// Only pages that appear in the sidebar can be restored.
    public init?(id: String) {
        guard let page = SettingsSidebar.pages.first(where: { $0.id == id }) else { return nil }
        self = page
    }

    public var title: String {
        switch self {
        case .general: "General"
        case .menuBar: "Menu bar"
        case .permissions: "Permissions"
        case .about: "About"
        case .tool(let f): f.title
        }
    }
}

public struct SettingsGroup: Equatable, Sendable {
    public let title: String
    public let pages: [SettingsPage]
}

/// Sidebar layout. Tool groups follow the panel's families, with Screen and Wellness split out.
public enum SettingsSidebar {
    public static let groups: [SettingsGroup] = [
        SettingsGroup(title: "General", pages: [.general, .menuBar, .permissions]),
        SettingsGroup(title: "Battery", pages: [.tool(.battery)]),
        SettingsGroup(title: "System", pages: [.tool(.system), .tool(.keepAwake), .tool(.quickToggles), .tool(.volumeGuard),
                                               .tool(.flushDNS), .tool(.fanSafeMode)]),
        SettingsGroup(title: "Clean", pages: [.tool(.uninstaller), .tool(.cleaner), .tool(.diskMap), .tool(.updates)]),
        SettingsGroup(title: "Clipboard", pages: [.tool(.clipboard)]),
        SettingsGroup(title: "Screen", pages: [.tool(.copyText), .tool(.readQR)]),
        SettingsGroup(title: "Wellness", pages: [.tool(.breakReminders), .tool(.cleaningMode)]),
        SettingsGroup(title: "About", pages: [.about]),
    ]

    public static var pages: [SettingsPage] { groups.flatMap(\.pages) }
}

/// Remembers the last page between opens.
public struct SettingsSelection {
    private let defaults: UserDefaults
    private let key = "settings.page"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> SettingsPage { defaults.string(forKey: key).flatMap(SettingsPage.init(id:)) ?? .general }
    public func save(_ page: SettingsPage) { defaults.set(page.id, forKey: key) }
}
