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
        VStack(alignment: .leading, spacing: 12) {
            PageTitle("Permissions")
            SettingsCard { ForEach(Permission.allCases, id: \.self) { row($0) } }
            Text("Nothing is requested at launch. A permission is asked for only when you use a tool that needs it.").hint()
        }
        .task { await model.refresh() }
    }

    private func row(_ p: Permission) -> some View {
        let users = model.activeUsers(of: p)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                StatusText(p.title)
                Spacer()
                statusLabel(model.status(p)).font(.callout)
                Button("Open Settings") { open(p.settingsURL) }.buttonStyle(ChipStyle()).frame(width: 120)
            }
            Text(p.reason).hint()
            Text(users.isEmpty ? "No tool you turned on uses this." : "Used by: " + users.map(\.title).joined(separator: ", ")).hint()
            if model.isUnused(p) {
                Text("Granted but unused. You can turn it off in System Settings.").font(.callout).foregroundStyle(Palette.accent)
            }
        }
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
