import AppKit
import Core
import SwiftUI

/// "Using the most energy": apps over the chosen CPU threshold, with a Quit button per row.
struct EnergyAppsSection: View {
    let users: [EnergyUser]
    @AppStorage(EnergyThreshold.storageKey) private var thresholdRaw = EnergyThreshold.medium.rawValue
    @AppStorage(EnergyThreshold.backgroundKey) private var includeBackground = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        let shown = EnergyApps.filter(users, threshold: EnergyThreshold(rawValue: thresholdRaw) ?? .medium, includeBackground: includeBackground)
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Using the most energy")
            if users.isEmpty {
                Text("Measuring…").hint()
            } else if shown.isEmpty {
                Text("No apps using significant energy").hint()
            }
            ForEach(shown) { u in
                HStack(spacing: 8) {
                    Text(u.name).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f%% CPU", u.cpu)).monospacedDigit().foregroundStyle(Palette.secondary)
                    if let app = Self.quittable(u) {
                        Button("Quit") { quit(app, u.name) }
                            .buttonStyle(ChipStyle()).frame(width: 60)
                            .accessibilityLabel("Quit \(u.name)")
                    }
                }
                .font(.callout)
            }
            if let toast { Text(toast).hint().accessibilityAddTraits(.updatesFrequently) }
        }
    }

    /// The running app for this row, unless it is one we never quit. Matches the bundle name `ps` showed.
    private static func quittable(_ u: EnergyUser) -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.activationPolicy != .prohibited && $0.bundleURL?.deletingPathExtension().lastPathComponent == u.name
        }), !EnergyApps.neverQuit(bundleID: app.bundleIdentifier) else { return nil }
        return app
    }

    /// A polite quit request only; the app may still ask to save first.
    private func quit(_ app: NSRunningApplication, _ name: String) {
        app.terminate()
        toast = "Asked \(name) to quit"
        toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { toast = nil } }
    }
}
