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

/// The chosen readout, observable so the status item follows changes at once.
@MainActor @Observable
public final class ReadoutSettings {
    public var readout: MenuBarReadout { didSet { store.setMenuBarReadout(readout) } }
    @ObservationIgnored private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
        readout = store.menuBarReadout()
    }
}
