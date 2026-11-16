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
        case .flushDNS: "network"
        }
    }
}

/// Fixed-size panel: brand header, a strip of icons for the tools that are on, the chosen tool, a footer.
public struct PanelView: View {
    public static let size = CGSize(width: 380, height: 540)
    public static let appName = "Apple Cart"

    let launcher: LauncherModel
    let panel: PanelModel
    let openSettings: () -> Void
    let collapse: () -> Void
    let quit: () -> Void
    let toolView: (FeatureID) -> AnyView?
    let firstRun: FirstRunModel?
    let readout: ReadoutSettings?
    let chargeLimit: ChargeLimitSettings?
    let chargeLimiter: ChargeLimiter?

    @FocusState private var focused: FeatureID?

    public init(launcher: LauncherModel, panel: PanelModel,
                openSettings: @escaping () -> Void, collapse: @escaping () -> Void, quit: @escaping () -> Void,
                toolView: @escaping (FeatureID) -> AnyView? = { _ in nil },
                firstRun: FirstRunModel? = nil, readout: ReadoutSettings? = nil,
                chargeLimit: ChargeLimitSettings? = nil, chargeLimiter: ChargeLimiter? = nil) {
        self.chargeLimit = chargeLimit
        self.chargeLimiter = chargeLimiter
        self.firstRun = firstRun
        self.readout = readout
        self.launcher = launcher
        self.panel = panel
        self.openSettings = openSettings
        self.collapse = collapse
        self.quit = quit
        self.toolView = toolView
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        let tiles = launcher.allTiles
        VStack(spacing: 0) {
            header
            if let firstRun, let readout, !firstRun.isDone {
                FirstRunView(model: firstRun, readout: readout, openSettings: openSettings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tiles.isEmpty {
                EmptyLauncher(hiddenCount: launcher.hiddenCount, openSettings: openSettings, showHidden: launcher.showAllHidden)
            } else {
                strip(tiles)
                if let route = panel.route {
                    HStack(spacing: 12) {
                        Text(route.title.uppercased())
                            .font(.system(size: 12, weight: .semibold)).tracking(0.6)
                            .foregroundStyle(Palette.secondary)
                            .accessibilityAddTraits(.isHeader)
                        if route == .battery { batteryEditButtons }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 28)
                    .padding(.horizontal, 20).padding(.top, 14)
                    (toolView(route) ?? AnyView(ToolPlaceholder(id: route)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Spacer()
                }
            }
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Palette.ground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: panel.route, initial: true) { selectFirstIfNone() }
        .onChange(of: launcher.allTiles) { selectFirstIfNone() }
        .onExitCommand { collapse() }
    }

    /// Edit sits in the section header, not inside the card. Reset appears while editing.
    private var batteryEditButtons: some View {
        let widgets = BatteryWidgetSettings.shared
        return HStack(spacing: 14) {
            if widgets.editing { Button("Reset") { widgets.update { $0.reset() } }.buttonStyle(.plain).foregroundStyle(Palette.accent) }
            Button(widgets.editing ? "Done" : "Edit") { withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { widgets.editing.toggle() } }
                .buttonStyle(.plain).foregroundStyle(Palette.accent)
                .accessibilityLabel(widgets.editing ? "Done editing widgets" : "Edit widgets")
        }
        .font(.callout.weight(.medium))
        .frame(minHeight: 44)
    }

    /// A tool is always chosen while any tool is on; closing the panel clears it, so reselect.
    private func selectFirstIfNone() {
        let tiles = launcher.allTiles
        if let r = panel.route, tiles.contains(r) { return }
        if let first = tiles.first { panel.open(first) }
    }

    @ViewBuilder private var header: some View {
        if let chargeLimit, launcher.allTiles.contains(.battery) {
            ChargeHeader(settings: chargeLimit, limiter: chargeLimiter, openSettings: openSettings)
        } else {
            HStack {
                Color.clear.frame(width: 44, height: 44) // balances the Settings button so the name stays centered
                Spacer()
                Text(Self.appName).font(.system(size: 15, weight: .semibold))
                Spacer()
                SettingsGlyphButton(action: openSettings)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
        }
    }

    private func strip(_ tiles: [FeatureID]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tiles, id: \.self) { id in
                    Button { panel.open(id) } label: {
                        Image(systemName: id.symbol).font(.system(size: 17))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(panel.route == id ? Palette.accent : Palette.secondary)
                            .background(panel.route == id ? Palette.accent.opacity(0.16) : .clear,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focused($focused, equals: id)
                    .onKeyPress(.leftArrow) { step(id, -1, tiles) }
                    .onKeyPress(.rightArrow) { step(id, 1, tiles) }
                    .help(id.title)
                    .accessibilityLabel(id.title)
                    .accessibilityAddTraits(panel.route == id ? [.isButton, .isSelected] : .isButton)
                    .draggable(id.rawValue)
                    .dropDestination(for: String.self) { items, _ in
                        guard let raw = items.first, let dragged = FeatureID(rawValue: raw) else { return false }
                        launcher.move(dragged, before: id)
                        return true
                    }
                    .contextMenu {
                        Button("Hide from the strip") { launcher.hide(id) }
                    }
                }
                Button(action: openSettings) {
                    Image(systemName: "plus").font(.system(size: 15))
                        .frame(width: 44, height: 44).foregroundStyle(Palette.secondary).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add tools")
                .accessibilityLabel("Add tools")
            }
            .padding(4)
        }
        .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.06)))
        .padding(.horizontal, 16)
    }

    private func step(_ id: FeatureID, _ by: Int, _ tiles: [FeatureID]) -> KeyPress.Result {
        guard let i = tiles.firstIndex(of: id), tiles.indices.contains(i + by) else { return .handled }
        focused = tiles[i + by]
        panel.open(tiles[i + by])
        return .handled
    }

    private var footer: some View {
        HStack(spacing: 12) {
            footerButton("Quit", symbol: "power", action: quit)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func footerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Palette.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
