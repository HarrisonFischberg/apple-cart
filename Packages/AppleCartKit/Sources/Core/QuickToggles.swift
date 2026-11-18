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

    /// Where the state is read: the app that uses the key. Reading an app's domain falls through to the
    /// global domain, so this is the value the app actually sees.
    public var domain: String {
        switch self {
        case .hiddenFiles, .desktopIcons, .fileExtensions: "com.apple.finder"
        case .dockAutoHide: "com.apple.dock"
        }
    }

    /// Where a change is written. File extensions live in the global domain, but a copy in Finder's own domain
    /// (Finder settings writes one) overrides it, so both get the new value or turning it off does nothing.
    public var writeDomains: [String] {
        switch self {
        case .fileExtensions: [globalPreferenceDomain, "com.apple.finder"]
        default: [domain]
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

/// Stands for the global domain (`defaults write -g`); `SystemPreferences` maps it to `kCFPreferencesAnyApplication`.
public let globalPreferenceDomain = "NSGlobalDomain"

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
        for d in t.writeDomains { prefs.write(domain: d, key: t.key, value: on) }
        prefs.restart(t.restarts)
        refresh() // show what the system holds, not what we meant
    }
}
