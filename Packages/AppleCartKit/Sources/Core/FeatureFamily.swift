/// Groups for Settings > Features (recon screen S06).
public enum FeatureFamily: String, CaseIterable, Sendable {
    case battery, system, clean, clipboard, tools

    public var title: String {
        switch self {
        case .battery: "Battery"
        case .system: "System"
        case .clean: "Clean"
        case .clipboard: "Clipboard"
        case .tools: "Tools"
        }
    }

    public var features: [FeatureID] { FeatureID.allCases.filter { $0.family == self } }
}

public extension FeatureID {
    var family: FeatureFamily {
        switch self {
        case .battery: .battery
        case .system, .keepAwake, .quickToggles, .volumeGuard, .fanSafeMode: .system
        case .uninstaller, .cleaner, .diskMap, .updates: .clean
        case .clipboard, .copyText, .readQR: .clipboard
        case .breakReminders, .cleaningMode, .notifications: .tools
        }
    }
}
