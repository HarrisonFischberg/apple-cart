import Foundation

/// How much CPU an app must use before it is listed. macOS's own list uses "energy impact", which
/// no public API exposes, so these are plain CPU shares measured in percent of one core.
public enum EnergyThreshold: String, CaseIterable, Sendable {
    case low, medium, high

    public static let storageKey = "energy.threshold"
    public static let backgroundKey = "energy.includeBackground"
    public static let maxRows = 5

    public var title: String { switch self { case .low: "Low"; case .medium: "Medium"; case .high: "High" } }

    /// Low 5%, Medium 20% (the default), High 40% of one core.
    public var cpuPercent: Double { switch self { case .low: 5; case .medium: 20; case .high: 40 } }
}

public enum EnergyApps {
    /// Users at or above the threshold, busiest first, at most `limit`. Without `includeBackground`
    /// only apps with a bundle are kept; with it, helpers and system processes count too.
    public static func filter(_ users: [EnergyUser], threshold: EnergyThreshold, includeBackground: Bool,
                              limit: Int = EnergyThreshold.maxRows) -> [EnergyUser] {
        users.filter { $0.cpu >= threshold.cpuPercent && (includeBackground || $0.isApp) }
            .sorted { $0.cpu > $1.cpu }.prefix(limit).map { $0 }
    }

    /// Apps the Quit button is never offered for: Finder, the Dock and Apple Cart itself.
    public static func neverQuit(bundleID: String?, ownBundleID: String? = Bundle.main.bundleIdentifier) -> Bool {
        guard let bundleID else { return true } // unknown app: do not offer to quit it
        return bundleID == "com.apple.finder" || bundleID == "com.apple.dock" || bundleID == ownBundleID
    }
}
