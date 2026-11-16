import Core
import SwiftUI

/// Settings window content: a sidebar of pages on the left, the chosen page on the right.
public struct SettingsView: View {
    let registry: FeatureRegistry
    let permissions: PermissionsModel
    let readout: ReadoutSettings
    let open: (URL) -> Void
    let login: LaunchAtLogin
    let general: GeneralActions
    let tools: SettingsTools
    let glyphStyle: GlyphStyleSettings?
    @State private var page: SettingsPage?
    private let selection = SettingsSelection()

    public init(registry: FeatureRegistry, permissions: PermissionsModel, readout: ReadoutSettings, login: LaunchAtLogin,
                general: GeneralActions, tools: SettingsTools, glyphStyle: GlyphStyleSettings? = nil, initialPage: SettingsPage? = nil, open: @escaping (URL) -> Void) {
        self.login = login
        self.general = general
        self.registry = registry
        self.readout = readout
        self.permissions = permissions
        self.tools = tools
        self.glyphStyle = glyphStyle
        self.open = open
        _page = State(initialValue: initialPage ?? SettingsSelection().load())
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Divider()
            detail
        }
        .onChange(of: page) { _, new in if let new { selection.save(new) } }
    }

    private var sidebar: some View {
        List(selection: $page) {
            ForEach(SettingsSidebar.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.pages, id: \.self) { p in
                        row(p).tag(p as SettingsPage?).selectionDisabled(!isSelectable(p))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Settings pages")
    }

    private func isSelectable(_ p: SettingsPage) -> Bool {
        if case .tool(let f) = p { return registry.isAvailable(f) }
        return true
    }

    private func row(_ p: SettingsPage) -> some View {
        var on = false
        if case .tool(let f) = p { on = registry.isEnabled(f) }
        let built = isSelectable(p)
        return HStack(spacing: 6) {
            Label(p.title, systemImage: p.symbol)
            Spacer(minLength: 4)
            if on { Circle().fill(.green).frame(width: 7, height: 7).accessibilityHidden(true) }
        }
        .overlay(alignment: .bottomLeading) {
            if !built { Text("Not built yet").font(.caption2).foregroundStyle(Palette.secondary).padding(.leading, 28).offset(y: 8) }
        }
        .padding(.bottom, built ? 0 : 8)
        .foregroundStyle(built ? Color.primary : Palette.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(built ? (on ? "\(p.title), on" : p.title) : "\(p.title), not built yet")
    }

    private var detail: some View {
        ScrollView {
            content(page ?? .general)
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(page)
        .background(Palette.ground)
    }

    @ViewBuilder private func content(_ p: SettingsPage) -> some View {
        switch p {
        case .general: GeneralSettingsView(login: login, actions: general)
        case .menuBar: MenuBarSettingsView(readout: readout, glyphStyle: glyphStyle)
        case .permissions: PermissionsView(model: permissions, open: open)
        case .about: AboutSettingsView(actions: general)
        case .tool(let f): ToolSettingsPage(id: f, registry: registry, permissions: permissions, readout: readout, tools: tools, open: open)
        }
    }
}
