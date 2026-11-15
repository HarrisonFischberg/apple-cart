import Core
import SwiftUI

/// What the General tab needs from the app; the actions stay in the app target.
public struct GeneralActions {
    public var updatesConfigured: Bool
    public var checkForUpdates: () -> Void
    public var automaticChecks: () -> Bool
    public var setAutomaticChecks: (Bool) -> Void
    public var sendDebugLogs: () -> Void
    public var deleteAllData: () -> Void
    public init(updatesConfigured: Bool, checkForUpdates: @escaping () -> Void, automaticChecks: @escaping () -> Bool,
                setAutomaticChecks: @escaping (Bool) -> Void, sendDebugLogs: @escaping () -> Void, deleteAllData: @escaping () -> Void) {
        self.updatesConfigured = updatesConfigured; self.checkForUpdates = checkForUpdates; self.automaticChecks = automaticChecks
        self.setAutomaticChecks = setAutomaticChecks; self.sendDebugLogs = sendDebugLogs; self.deleteAllData = deleteAllData
    }
}

public struct GeneralSettingsView: View {
    let login: LaunchAtLogin
    let actions: GeneralActions
    @State private var automatic: Bool

    public init(login: LaunchAtLogin, actions: GeneralActions) {
        self.login = login; self.actions = actions; _automatic = State(initialValue: actions.automaticChecks())
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Open Apple Cart at login", isOn: Binding(get: { login.isOn }, set: { login.set($0) }))
                if let e = login.error { Text(e).font(.callout).foregroundStyle(.secondary) }
            }
            Section {
                if actions.updatesConfigured {
                    Toggle("Check for updates automatically", isOn: Binding(get: { automatic }, set: { automatic = $0; actions.setAutomaticChecks($0) }))
                    Button("Check for updates now", action: actions.checkForUpdates)
                } else {
                    Text("Updates are not set up in this build yet.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("A check contacts only this app's update list on GitHub, which sees your IP address and the app version.")
            }
            Section("Help") {
                Button("Send debug info…", action: actions.sendDebugLogs)
                Text("Opens an email draft with the app and macOS version, your Mac model, and which tools and permissions are on. Nothing is sent until you press Send.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Your data") {
                Button("Delete all app data…", role: .destructive, action: actions.deleteAllData)
                Text("Removes every setting and saved item (clipboard history, battery history) from this Mac, then quits.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { login.refresh() }
    }
}
