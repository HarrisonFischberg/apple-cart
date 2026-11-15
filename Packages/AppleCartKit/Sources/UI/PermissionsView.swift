import Core
import SwiftUI

public struct PermissionsView: View {
    let model: PermissionsModel
    let open: (URL) -> Void

    public init(model: PermissionsModel, open: @escaping (URL) -> Void) {
        self.model = model
        self.open = open
    }

    public var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases, id: \.self) { p in row(p) }
            } footer: {
                Text("Nothing is requested at launch. A permission is asked for only when you use a tool that needs it.")
            }
        }
        .formStyle(.grouped)
        .task { await model.refresh() }
    }

    private func row(_ p: Permission) -> some View {
        let users = model.activeUsers(of: p)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(p.title)
                Spacer()
                statusLabel(model.status(p))
                Button("Open Settings") { open(p.settingsURL) }
            }
            Text(p.reason).font(.callout).foregroundStyle(.secondary)
            Text(users.isEmpty ? "No tool you turned on uses this." : "Used by: " + users.map(\.title).joined(separator: ", "))
                .font(.callout).foregroundStyle(.secondary)
            if model.isUnused(p) {
                Text("Granted but unused. You can turn it off in System Settings.").font(.callout).foregroundStyle(Palette.accent)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func statusLabel(_ s: PermissionStatus) -> some View {
        switch s {
        case .granted: Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.primary).symbolRenderingMode(.multicolor)
        case .notGranted: Label("Not granted", systemImage: "circle").foregroundStyle(.secondary)
        case .unknown: Text("Checking…").foregroundStyle(.secondary)
        }
    }
}

/// Settings window content: Features and Permissions.
public struct SettingsView: View {
    let registry: FeatureRegistry
    let permissions: PermissionsModel
    let readout: ReadoutSettings
    let open: (URL) -> Void
    let login: LaunchAtLogin
    let general: GeneralActions

    public init(registry: FeatureRegistry, permissions: PermissionsModel, readout: ReadoutSettings, login: LaunchAtLogin,
                general: GeneralActions, open: @escaping (URL) -> Void) {
        self.login = login
        self.general = general
        self.registry = registry
        self.readout = readout
        self.permissions = permissions
        self.open = open
    }

    public var body: some View {
        TabView {
            GeneralSettingsView(login: login, actions: general).tabItem { Label("General", systemImage: "gearshape") }
            FeaturesSettingsView(registry: registry).tabItem { Label("Features", systemImage: "square.grid.2x2") }
            Form { ReadoutPicker(readout: readout) }.formStyle(.grouped)
                .tabItem { Label("Menu bar", systemImage: "menubar.rectangle") }
            PermissionsView(model: permissions, open: open).tabItem { Label("Permissions", systemImage: "hand.raised") }
        }
    }
}
