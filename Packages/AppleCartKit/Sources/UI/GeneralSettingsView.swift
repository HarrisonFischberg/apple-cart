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
        VStack(alignment: .leading, spacing: 16) {
            PageTitle("General")
            SettingsCard("Startup") {
                SettingsRow("Open Apple Cart at login", detail: login.error) {
                    Toggle("Open Apple Cart at login", isOn: Binding(get: { login.isOn }, set: { login.set($0) })).toggleStyle(.switch).labelsHidden()
                }
            }
            SettingsCard("Apple Cart updates") {
                if actions.updatesConfigured {
                    SettingsRow("Check for updates automatically") {
                        Toggle("Check for updates automatically", isOn: Binding(get: { automatic }, set: { automatic = $0; actions.setAutomaticChecks($0) }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                    SettingsRow("Check for updates now") { Button("Check now", action: actions.checkForUpdates).buttonStyle(ChipStyle()).frame(width: 120) }
                } else {
                    SettingsRow("Updates are not set up in this build yet.") { EmptyView() }
                }
            }
            Text("A check contacts only this app's update list on GitHub, which sees your IP address and the app version.").hint()
            SettingsCard("Your data") {
                SettingsRow("Delete all app data", detail: "Removes every setting and saved item (clipboard history, battery history) from this Mac, then quits.") {
                    Button("Delete…", role: .destructive, action: actions.deleteAllData).buttonStyle(ChipStyle()).frame(width: 120)
                }
            }
        }
        .onAppear { login.refresh() }
    }
}

struct MenuBarSettingsView: View {
    let readout: ReadoutSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle("Menu bar")
            SettingsCard("Battery readout") { ReadoutRow(readout: readout) }
            Text("Click the icon to open the panel. Right-click it for Settings and Quit.").hint()
        }
    }
}

struct AboutSettingsView: View {
    let actions: GeneralActions

    var body: some View {
        let info = Bundle.main.infoDictionary
        VStack(alignment: .leading, spacing: 16) {
            PageTitle("About")
            SettingsCard("Apple Cart") {
                SettingsRow("Version", value: info?["CFBundleShortVersionString"] as? String ?? "Development build")
                SettingsRow("Build", value: info?["CFBundleVersion"] as? String ?? "none")
                SettingsRow("Made by", value: "Rare Creatures LLC")
            }
            SettingsCard("Help") {
                SettingsRow("Send debug info", detail: "Opens an email draft with the app and macOS version, your Mac model, and which tools and permissions are on. Nothing is sent until you press Send.") {
                    Button("Send…", action: actions.sendDebugLogs).buttonStyle(ChipStyle()).frame(width: 120)
                }
            }
            SettingsCard("Privacy") {
                Text("Apple Cart has no account and no tracking. Everything stays on this Mac. An update check contacts only this app's update list on GitHub, and debug info is an email draft you send yourself.")
                    .foregroundStyle(Palette.secondary)
            }
        }
    }
}
