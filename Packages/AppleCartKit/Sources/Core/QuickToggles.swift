import Foundation
import Observation

/// A system switch backed by one preference key. "On" may mean the stored value is true or false (`invert`).
public enum QuickToggle: String, CaseIterable, Sendable {
    case hiddenFiles, fileExtensions, dockAutoHide, desktopIcons

    public var title: String {
        switch self {
        case .hiddenFiles: "Show hidden files"
        case .fileExtensions: "Show all file extensions"
        case .dockAutoHide: "Hide the Dock automatically"
        case .desktopIcons: "Show desktop icons"
        }
    }

    public var symbol: String {
        switch self {
        case .hiddenFiles: "eye"
        case .fileExtensions: "doc.text"
        case .dockAutoHide: "dock.rectangle"
        case .desktopIcons: "menubar.dock.rectangle"
        }
    }

    public var domain: String {
        switch self {
        case .hiddenFiles, .desktopIcons: "com.apple.finder"
        case .fileExtensions: "kCFPreferencesAnyApplication"
        case .dockAutoHide: "com.apple.dock"
        }
    }

    public var key: String {
        switch self {
        case .hiddenFiles: "AppleShowAllFiles"
        case .fileExtensions: "AppleShowAllExtensions"
        case .dockAutoHide: "autohide"
        case .desktopIcons: "CreateDesktop"
        }
    }

    /// What macOS assumes when the key was never written.
    var valueWhenMissing: Bool { self == .desktopIcons }

    /// The app that must restart for the change to show.
    public var restarts: String {
        switch self {
        case .dockAutoHide: "Dock"
        default: "Finder"
        }
    }
}

@MainActor
public protocol PreferenceAccess: AnyObject {
    func read(domain: String, key: String) -> Bool?
    func write(domain: String, key: String, value: Bool)
    func restart(_ processName: String)
}

@MainActor @Observable
public final class QuickToggles {
    public private(set) var states: [QuickToggle: Bool] = [:]
    @ObservationIgnored private let prefs: PreferenceAccess

    public init(prefs: PreferenceAccess) {
        self.prefs = prefs
        refresh()
    }

    /// Re-reads what the system says now.
    public func refresh() {
        for t in QuickToggle.allCases { states[t] = prefs.read(domain: t.domain, key: t.key) ?? t.valueWhenMissing }
    }

    public func set(_ t: QuickToggle, on: Bool) {
        prefs.write(domain: t.domain, key: t.key, value: on)
        prefs.restart(t.restarts)
        refresh() // show what the system holds, not what we meant
    }
}
