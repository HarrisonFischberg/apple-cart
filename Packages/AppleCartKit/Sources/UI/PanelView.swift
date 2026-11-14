import Core
import SwiftUI

extension FeatureID {
    var symbol: String {
        switch self {
        case .battery: "battery.75percent"
        case .system: "cpu"
        case .keepAwake: "cup.and.saucer"
        case .clipboard: "doc.on.clipboard"
        case .copyText: "text.viewfinder"
        case .readQR: "qrcode.viewfinder"
        case .breakReminders: "figure.walk"
        case .uninstaller: "trash"
        case .cleaner: "sparkles"
        case .diskMap: "chart.pie"
        case .updates: "arrow.triangle.2.circlepath"
        case .quickToggles: "switch.2"
        case .volumeGuard: "speaker.wave.2"
        case .fanSafeMode: "fan"
        case .cleaningMode: "keyboard"
        case .notifications: "bell"
        }
    }
}

/// Fixed-size panel: header plus either the launcher grid or one tool's view.
public struct PanelView: View {
    public static let size = CGSize(width: 420, height: 560)

    let launcher: LauncherModel
    let panel: PanelModel
    let openSettings: () -> Void
    let collapse: () -> Void
    let quit: () -> Void
    let toolView: (FeatureID) -> AnyView?
    let firstRun: FirstRunModel?
    let readout: ReadoutSettings?

    @State private var searching = false
    @FocusState private var searchFocused: Bool

    public init(launcher: LauncherModel, panel: PanelModel,
                openSettings: @escaping () -> Void, collapse: @escaping () -> Void, quit: @escaping () -> Void,
                toolView: @escaping (FeatureID) -> AnyView? = { _ in nil },
                firstRun: FirstRunModel? = nil, readout: ReadoutSettings? = nil) {
        self.firstRun = firstRun
        self.readout = readout
        self.launcher = launcher
        self.panel = panel
        self.openSettings = openSettings
        self.collapse = collapse
        self.quit = quit
        self.toolView = toolView
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if searching && panel.route == nil { searchField }
            Group {
                if let firstRun, let readout, !firstRun.isDone {
                    FirstRunView(model: firstRun, readout: readout, openSettings: openSettings)
                } else if let route = panel.route {
                    toolView(route) ?? AnyView(ToolPlaceholder(id: route))
                } else {
                    LauncherGrid(launcher: launcher, panel: panel, openSettings: openSettings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Palette.ground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onExitCommand { if searching { closeSearch() } else { collapse() } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if panel.route != nil {
                Button { panel.back() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Back")
                    .keyboardShortcut("[", modifiers: .command)
            }
            Text(panel.route?.title ?? "Apple Cart").font(.headline)
            Spacer()
            if panel.route == nil {
                Button { searching ? closeSearch() : openSearch() } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search tools")
                    .keyboardShortcut("f", modifiers: .command)
            }
            Menu {
                Toggle("Keep open", isOn: Binding(get: { panel.keepOpen }, set: { panel.keepOpen = $0 }))
                Button("Settings…", action: openSettings)
                Button("Collapse", action: collapse)
                Divider()
                Button("Quit Apple Cart", action: quit)
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More")
        }
        .buttonStyle(HeaderButtonStyle())
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var searchField: some View {
        TextField("Search tools", text: Bindable(launcher).searchText)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }

    private func openSearch() { searching = true; searchFocused = true }
    private func closeSearch() { searching = false; launcher.searchText = "" }
}

private struct HeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Palette.secondary)
            .frame(width: 44, height: 44) // 44 pt target
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

struct ToolPlaceholder: View {
    let id: FeatureID
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: id.symbol).font(.system(size: 28)).foregroundStyle(Palette.secondary)
            Text("\(id.title) is coming soon").font(.body)
            Text("This tool is turned on but its view isn't built yet.").font(.callout).foregroundStyle(Palette.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
    }
}

struct LauncherGrid: View {
    let launcher: LauncherModel
    let panel: PanelModel
    let openSettings: () -> Void

    private static let columns = 4
    private let grid = Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    @FocusState private var focused: FeatureID?

    var body: some View {
        let tiles = launcher.tiles
        if launcher.allTiles.isEmpty {
            EmptyLauncher(hiddenCount: launcher.hiddenCount, openSettings: openSettings, showHidden: launcher.showAllHidden)
        } else if tiles.isEmpty {
            VStack(spacing: 6) {
                Text("No tool matches “\(launcher.searchText)”").font(.body)
                Button("Clear search") { launcher.searchText = "" }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: grid, spacing: 12) {
                    ForEach(tiles, id: \.self) { id in
                        ToolTile(id: id)
                            .focusable()
                            .focused($focused, equals: id)
                            .onTapGesture { panel.open(id) }
                            .onKeyPress(.return) { panel.open(id); return .handled }
                            .onKeyPress(.space) { panel.open(id); return .handled }
                            .onKeyPress(.leftArrow) { move(id, .left) }
                            .onKeyPress(.rightArrow) { move(id, .right) }
                            .onKeyPress(.upArrow) { move(id, .up) }
                            .onKeyPress(.downArrow) { move(id, .down) }
                            .draggable(id.rawValue)
                            .dropDestination(for: String.self) { items, _ in
                                guard let raw = items.first, let dragged = FeatureID(rawValue: raw) else { return false }
                                launcher.move(dragged, before: id)
                                return true
                            }
                            .contextMenu {
                                Button("Open") { panel.open(id) }
                                Button("Hide from launcher") { launcher.hide(id) }
                            }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction(named: "Hide from launcher") { launcher.hide(id) }
                    }
                    AddToolsTile(action: openSettings)
                }
                .padding(16)
            }
        }
    }

    private func move(_ id: FeatureID, _ dir: GridDirection) -> KeyPress.Result {
        if let next = launcher.neighbor(of: id, columns: Self.columns, dir) { focused = next }
        return .handled
    }
}

struct ToolTile: View {
    let id: FeatureID
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: id.symbol).font(.system(size: 22)).foregroundStyle(Palette.accent)
            Text(id.title).font(.caption).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(.horizontal, 4)
        .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct AddToolsTile: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 22))
                Text("Add tools").font(.caption)
            }
            .foregroundStyle(Palette.secondary)
            .frame(maxWidth: .infinity, minHeight: 84)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct EmptyLauncher: View {
    let hiddenCount: Int
    let openSettings: () -> Void
    let showHidden: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hiddenCount > 0 ? "eye.slash" : "square.grid.2x2").font(.system(size: 30)).foregroundStyle(Palette.secondary)
            if hiddenCount > 0 {
                Text("All your tools are hidden").font(.body)
                Button("Show \(hiddenCount) hidden", action: showHidden)
            } else {
                Text("No tools are on yet").font(.body)
                Text("Pick the ones you want. Everything is off until you turn it on.")
                    .font(.callout).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                Button("Add tools", action: openSettings).buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
