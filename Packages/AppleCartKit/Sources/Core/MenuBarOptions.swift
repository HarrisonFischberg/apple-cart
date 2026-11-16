import Foundation

/// Groups in the Menu bar settings catalog.
public enum MenuBarItemGroup: String, CaseIterable, Sendable {
    case icon, specs, health, adapter

    public var title: String {
        switch self {
        case .icon: "Icon options"
        case .specs: "Battery specs"
        case .health: "Battery health"
        case .adapter: "Power adapter"
        }
    }
}

/// One live value that can sit beside the menu bar glyph. "None" is simply an empty selection.
public enum MenuBarItem: String, CaseIterable, Sendable {
    case percent, watts, timeLeft, temperature
    case timeToFull, hardwarePercent, maxCapacity, cycles, adapterWatts, adapterVolts, adapterAmps

    public var title: String {
        switch self {
        case .percent: "Show percentage"
        case .watts: "Watts in or out"
        case .timeLeft: "Time left"
        case .temperature: "Temperature"
        case .timeToFull: "Time to full"
        case .hardwarePercent: "Hardware percentage"
        case .maxCapacity: "Maximum capacity"
        case .cycles: "Cycles"
        case .adapterWatts: "Adapter power"
        case .adapterVolts: "Adapter voltage"
        case .adapterAmps: "Adapter current"
        }
    }

    public var group: MenuBarItemGroup {
        switch self {
        case .percent, .watts: .icon
        case .timeLeft, .temperature, .timeToFull, .hardwarePercent: .specs
        case .maxCapacity, .cycles: .health
        case .adapterWatts, .adapterVolts, .adapterAmps: .adapter
        }
    }

    /// nil when this Mac does not report the value, it does not apply right now, or it is idle: nothing is invented.
    public func text(for r: BatteryReading) -> String? {
        switch self {
        case .percent: return "\(Int(r.shownPercent.rounded()))%"
        case .watts:
            guard abs(r.batteryWatts) >= 0.05 else { return nil }
            return "\(r.batteryWatts > 0 ? "+" : "−")\(Int(abs(r.batteryWatts).rounded())) W"
        case .timeLeft: return r.isCharging ? nil : Self.clock(r.minutesRemaining)
        case .timeToFull: return r.isCharging ? Self.clock(r.minutesRemaining) : nil
        case .temperature: return r.temperatureC.map { "\(Int($0.rounded()))°" }
        case .hardwarePercent: return r.measuredPercent.map { String(format: "%.1f%%", $0) }
        case .maxCapacity: return r.capacityVsDesign.map { String(format: "%.0f%%", $0 * 100) }
        case .cycles: return r.cycleCount.map { "\($0) cycles" }
        case .adapterWatts: return r.isPluggedIn ? r.adapterWatts.map { "\($0) W" } : nil
        case .adapterVolts: return r.isPluggedIn ? r.adapterVolts.map { String(format: "%.0f V", $0) } : nil
        case .adapterAmps: return r.isPluggedIn ? r.adapterAmps.map { String(format: "%.1f A", $0) } : nil
        }
    }

    private static func clock(_ minutes: Int?) -> String? { minutes.map { "\($0 / 60):" + String(format: "%02d", $0 % 60) } }

    /// The chosen values in catalog order, as separate pieces so the status item can space them.
    public static func segments(_ items: Set<MenuBarItem>, for r: BatteryReading?) -> [String] {
        guard let r else { return [] }
        return allCases.filter(items.contains).compactMap { $0.text(for: r) }
    }

    /// What the older three-way readout choice stands for.
    public static func preset(_ readout: MenuBarReadout) -> Set<MenuBarItem> {
        switch readout {
        case .off: []
        case .percent: [.percent]
        case .power: [.percent, .watts]
        }
    }
}

/// Extra right-click entries. Settings and Quit are always there; these need no helper.
public enum RightClickAction: String, CaseIterable, Sendable {
    case checkForUpdates, copyStatus, openMacBatterySettings

    public var title: String {
        switch self {
        case .checkForUpdates: "Check for Updates"
        case .copyStatus: "Copy battery status"
        case .openMacBatterySettings: "Open macOS Battery settings"
        }
    }
}

/// Spacing and refresh limits, in one place so the UI and the stored values agree.
public enum MenuBarLimits {
    public static let spacing = 0...20
    public static let updateSeconds = 2...20
    public static let defaultSpacing = 4
    public static let defaultUpdateSeconds = 5

    public static func clampedSpacing(_ v: Int) -> Int { min(max(v, spacing.lowerBound), spacing.upperBound) }
    public static func clampedUpdate(_ v: Int) -> Int { min(max(v, updateSeconds.lowerBound), updateSeconds.upperBound) }
}
