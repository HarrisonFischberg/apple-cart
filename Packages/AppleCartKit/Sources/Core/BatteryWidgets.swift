import Foundation
import Observation

/// Blocks on the Battery screen the user can reorder and hide.
public enum BatteryWidget: String, CaseIterable, Sendable, Identifiable {
    case charge, powerFlow, details, history, energyApps
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .charge: "Charge"
        case .powerFlow: "Power flow"
        case .details: "Details"
        case .history: "Last 24 hours"
        case .energyApps: "Using the most energy"
        }
    }
}

/// Order and visibility, pure. Every known widget is always in `order`, so a widget added in a later
/// version shows up at the end instead of vanishing.
public struct BatteryWidgetLayout: Equatable, Sendable {
    public private(set) var order: [BatteryWidget]
    public private(set) var hidden: Set<BatteryWidget>

    public static let standard = BatteryWidgetLayout(order: BatteryWidget.allCases, hidden: [])

    private init(order: [BatteryWidget], hidden: Set<BatteryWidget>) { self.order = order; self.hidden = hidden }

    /// Stored ids from any build: unknown ones are dropped, repeats ignored, missing widgets appended.
    public init(storedOrder: [String], storedHidden: [String]) {
        var seen: [BatteryWidget] = []
        for w in storedOrder.compactMap(BatteryWidget.init(rawValue:)) where !seen.contains(w) { seen.append(w) }
        order = seen + BatteryWidget.allCases.filter { !seen.contains($0) }
        hidden = Set(storedHidden.compactMap(BatteryWidget.init(rawValue:)))
    }

    public var visible: [BatteryWidget] { order.filter { !hidden.contains($0) } }

    public mutating func move(_ w: BatteryWidget, to index: Int) {
        guard let from = order.firstIndex(of: w) else { return }
        order.remove(at: from)
        order.insert(w, at: min(max(index, 0), order.count))
    }

    public mutating func setVisible(_ w: BatteryWidget, _ on: Bool) {
        if on { hidden.remove(w) } else { hidden.insert(w) }
    }

    public mutating func reset() { self = .standard }
}

@MainActor @Observable
public final class BatteryWidgetSettings {
    /// The one instance the panel and Settings share.
    public static let shared = BatteryWidgetSettings()
    public private(set) var layout: BatteryWidgetLayout
    public var showPercentage: Bool { didSet { defaults.set(showPercentage, forKey: "popover.showPercentage") } }
    public var openInEditMode: Bool { didSet { defaults.set(openInEditMode, forKey: "popover.openInEditMode") } }
    public var showOnStartup: Bool { didSet { defaults.set(showOnStartup, forKey: Self.startupKey) } }
    public nonisolated static let startupKey = "popover.showOnStartup"
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showPercentage = defaults.object(forKey: "popover.showPercentage") as? Bool ?? true
        openInEditMode = defaults.bool(forKey: "popover.openInEditMode")
        showOnStartup = defaults.bool(forKey: Self.startupKey)
        layout = BatteryWidgetLayout(storedOrder: defaults.stringArray(forKey: "battery.widgetOrder") ?? [],
                                     storedHidden: defaults.stringArray(forKey: "battery.widgetHidden") ?? [])
    }

    public func update(_ change: (inout BatteryWidgetLayout) -> Void) {
        change(&layout)
        defaults.set(layout.order.map(\.rawValue), forKey: "battery.widgetOrder")
        defaults.set(layout.hidden.map(\.rawValue).sorted(), forKey: "battery.widgetHidden")
    }
}
