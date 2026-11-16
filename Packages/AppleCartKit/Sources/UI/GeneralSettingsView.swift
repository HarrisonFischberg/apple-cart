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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Open Apple Cart at login", isOn: Binding(get: { login.isOn }, set: { login.set($0) }))
                    if let e = login.error { Text(e).hint() }
                }
                .toolCard()
                SectionLabel("Updates")
                VStack(alignment: .leading, spacing: 10) {
                    if actions.updatesConfigured {
                        Toggle("Check for updates automatically", isOn: Binding(get: { automatic }, set: { automatic = $0; actions.setAutomaticChecks($0) }))
                        Button("Check for updates now", action: actions.checkForUpdates).buttonStyle(ChipStyle()).frame(width: 220)
                    } else {
                        Text("Updates are not set up in this build yet.").hint()
                    }
                    Text("A check contacts only this app's update list on GitHub, which sees your IP address and the app version.").hint()
                }
                .toolCard()
                SectionLabel("Help")
                VStack(alignment: .leading, spacing: 10) {
                    Button("Send debug info…", action: actions.sendDebugLogs).buttonStyle(ChipStyle()).frame(width: 220)
                    Text("Opens an email draft with the app and macOS version, your Mac model, and which tools and permissions are on. Nothing is sent until you press Send.").hint()
                }
                .toolCard()
                SectionLabel("Your data")
                VStack(alignment: .leading, spacing: 10) {
                    Button("Delete all app data…", role: .destructive, action: actions.deleteAllData).buttonStyle(ChipStyle()).frame(width: 220)
                    Text("Removes every setting and saved item (clipboard history, battery history) from this Mac, then quits.").hint()
                }
                .toolCard()
            }
            .toolPage()
        }
        .background(Palette.ground)
        .onAppear { login.refresh() }
    }
}
