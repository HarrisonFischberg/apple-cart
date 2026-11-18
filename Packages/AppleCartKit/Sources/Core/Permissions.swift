import Foundation
import Observation

public enum Permission: String, CaseIterable, Sendable {
    case screenRecording, fullDiskAccess, accessibility, notifications

    public var title: String {
        switch self {
        case .screenRecording: "Screen Recording"
        case .fullDiskAccess: "Full Disk Access"
        case .accessibility: "Accessibility"
        case .notifications: "Notifications"
        }
    }

    /// Tools that need it. Nothing is requested until one of them is turned on and used.
    public var usedBy: [FeatureID] {
        switch self {
        case .screenRecording: [.copyText, .readQR]
        case .fullDiskAccess: [.uninstaller, .cleaner, .diskMap]
        case .accessibility: [.clipboard, .cleaningMode]
        case .notifications: [.breakReminders, .notifications, .keepAwake]
        }
    }

    public var reason: String {
        switch self {
        case .screenRecording: "Reads text and QR codes from the screen region you pick. Nothing is recorded or kept."
        case .fullDiskAccess: "Lets the cleaner and uninstaller see leftover files in protected folders."
        case .accessibility: "Lets the paste-as-plain-text shortcut paste for you, and lets cleaning mode lock the keyboard."
        case .notifications: "Tells you when a break, timer or limit is reached."
        }
    }

    /// System Settings pane to open.
    public var settingsURL: URL {
        let pane = switch self {
        case .screenRecording: "Privacy_ScreenCapture"
        case .fullDiskAccess: "Privacy_AllFiles"
        case .accessibility: "Privacy_Accessibility"
        case .notifications: "Privacy_Notifications"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }
}

public enum PermissionStatus: Sendable { case granted, notGranted, unknown }

/// Reads status only. It never asks: a request is made by the tool that needs it, naming that tool.
public protocol PermissionChecker: Sendable {
    func status(of permission: Permission) async -> PermissionStatus
}

@MainActor @Observable
public final class PermissionsModel {
    public private(set) var statuses: [Permission: PermissionStatus] = [:]
    @ObservationIgnored private let checker: PermissionChecker
    @ObservationIgnored private let registry: FeatureRegistry

    public init(checker: PermissionChecker, registry: FeatureRegistry) {
        self.checker = checker
        self.registry = registry
    }

    public func refresh() async {
        for p in Permission.allCases { statuses[p] = await checker.status(of: p) }
    }

    public func status(_ p: Permission) -> PermissionStatus { statuses[p] ?? .unknown }

    /// Tools that are on and need this permission.
    public func activeUsers(of p: Permission) -> [FeatureID] { p.usedBy.filter { registry.isEnabled($0) } }

    /// Granted but no tool that is on uses it: offer to revoke in System Settings.
    public func isUnused(_ p: Permission) -> Bool { status(p) == .granted && activeUsers(of: p).isEmpty }
}
