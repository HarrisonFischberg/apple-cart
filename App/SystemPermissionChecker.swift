import ApplicationServices
import Core
import CoreGraphics
import Foundation
import UserNotifications

/// Read-only checks. None of these prompt.
struct SystemPermissionChecker: PermissionChecker {
    func status(of permission: Permission) async -> PermissionStatus {
        switch permission {
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notGranted
        case .fullDiskAccess:
            // Protected file: readable only with Full Disk Access.
            let probe = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Safari/CloudTabs.db")
            guard FileManager.default.fileExists(atPath: probe.path) else { return .unknown }
            return (try? FileHandle(forReadingFrom: probe)) != nil ? .granted : .notGranted
        case .notifications:
            let s = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            return s == .authorized || s == .provisional ? .granted : .notGranted
        }
    }
}
