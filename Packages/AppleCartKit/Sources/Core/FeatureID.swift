/// Every tool the owner picked. Each is a switch, off by default (blueprint section 2).
public enum FeatureID: String, CaseIterable, Sendable, Codable {
    case battery, system, keepAwake, clipboard, copyText, readQR, breakReminders
    case uninstaller, cleaner, diskMap, updates, quickToggles, volumeGuard
    case fanSafeMode, cleaningMode, notifications

    public var title: String {
        switch self {
        case .battery: "Battery"
        case .system: "System"
        case .keepAwake: "Keep awake"
        case .clipboard: "Clipboard"
        case .copyText: "Copy text from screen"
        case .readQR: "Read QR code"
        case .breakReminders: "Break reminders"
        case .uninstaller: "Uninstaller"
        case .cleaner: "Cleaner"
        case .diskMap: "Disk map"
        case .updates: "Updates"
        case .quickToggles: "Quick toggles"
        case .volumeGuard: "Volume guard"
        case .fanSafeMode: "Fan safe mode"
        case .cleaningMode: "Cleaning mode"
        case .notifications: "Notifications"
        }
    }
}
