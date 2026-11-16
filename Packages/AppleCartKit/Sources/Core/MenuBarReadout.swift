import Foundation
import Observation

public enum MenuBarReadout: String, CaseIterable, Sendable {
    case off, percent, power

    public var title: String {
        switch self {
        case .off: "Icon only"
        case .percent: "Percent"
        case .power: "Percent and watts"
        }
    }

    /// Text next to the menu bar icon. Empty when off or there is no reading.
    public func text(for r: BatteryReading?) -> String {
        guard let r, self != .off else { return "" }
        guard self == .power, abs(r.batteryWatts) >= 0.05 else { return "\(r.percent)%" }
        return "\(r.percent)% \(r.batteryWatts > 0 ? "+" : "−")\(Int(abs(r.batteryWatts).rounded())) W"
    }

    /// SF Symbol for the icon, following charge and plug state.
    public static func symbol(for r: BatteryReading?) -> String {
        guard let r else { return "battery.75percent" }
        if r.isCharging { return "battery.100percent.bolt" }
        switch r.percent {
        case ..<10: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// Two skippable first-run screens: pick tools, pick the menu bar readout.
@MainActor @Observable
public final class FirstRunModel {
    public static let stepCount = 2
    public private(set) var step = 0
    public private(set) var isDone: Bool
    @ObservationIgnored private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
        isDone = store.firstRunDone()
    }

    public func next() { step + 1 >= Self.stepCount ? finish() : (step += 1) }

    /// One click ends it from any screen.
    public func finish() {
        isDone = true
        store.setFirstRunDone(true)
    }
}

/// The chosen menu bar values, spacing, refresh rate and right-click entries, observable so the status item follows at once.
/// The three-way `readout` stays as a quick preset: picking it sets `items`.
@MainActor @Observable
public final class ReadoutSettings {
    public var readout: MenuBarReadout { didSet { store.setMenuBarReadout(readout); items = MenuBarItem.preset(readout) } }
    public var items: Set<MenuBarItem> { didSet { defaults.set(items.map(\.rawValue).sorted(), forKey: "menuBar.items") } }
    public var spacing: Int { didSet { let v = MenuBarLimits.clampedSpacing(spacing); if v != spacing { spacing = v } else { defaults.set(v, forKey: "menuBar.spacing") } } }
    public var updateSeconds: Int { didSet { let v = MenuBarLimits.clampedUpdate(updateSeconds); if v != updateSeconds { updateSeconds = v } else { defaults.set(v, forKey: "menuBar.updateSeconds") } } }
    public var showGlyph: Bool { didSet { defaults.set(showGlyph, forKey: "menuBar.showGlyph") } }
    public var rightClick: Set<RightClickAction> { didSet { defaults.set(rightClick.map(\.rawValue).sorted(), forKey: "menuBar.rightClick") } }
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let defaults: UserDefaults

    public init(store: SettingsStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        let readout = store.menuBarReadout()
        self.readout = readout
        // Unknown names (from another build) are dropped; nothing saved means the readout preset.
        items = defaults.stringArray(forKey: "menuBar.items").map { Set($0.compactMap(MenuBarItem.init(rawValue:))) } ?? MenuBarItem.preset(readout)
        spacing = MenuBarLimits.clampedSpacing(defaults.object(forKey: "menuBar.spacing") as? Int ?? MenuBarLimits.defaultSpacing)
        updateSeconds = MenuBarLimits.clampedUpdate(defaults.object(forKey: "menuBar.updateSeconds") as? Int ?? MenuBarLimits.defaultUpdateSeconds)
        showGlyph = defaults.object(forKey: "menuBar.showGlyph") as? Bool ?? true
        rightClick = defaults.stringArray(forKey: "menuBar.rightClick").map { Set($0.compactMap(RightClickAction.init(rawValue:))) } ?? [.checkForUpdates]
    }

    /// Back to the quick preset, default spacing and the glyph.
    public func reset() { items = MenuBarItem.preset(readout); spacing = MenuBarLimits.defaultSpacing; showGlyph = true }
    public func clearAll() { items = [] }
}
