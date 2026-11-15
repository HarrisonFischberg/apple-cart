import AppKit
import Core
import SwiftUI
import UI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var panelController: PanelController?
    private let store = UserDefaultsSettingsStore()
    private lazy var registry: FeatureRegistry = {
        let r = FeatureRegistry(store: store)
        r.register(.battery) { BatteryTool() } // the readout only runs while a view holds the sampler
        r.register(.system) { SystemTool() }
        r.register(.keepAwake) { [keepAwake] in KeepAwakeTool(keepAwake) }
        r.register(.quickToggles) { QuickTogglesTool() }
        r.register(.volumeGuard) { [volumeGuard] in volumeGuard }
        r.register(.updates) { OnDemandTool() }
        r.register(.flushDNS) { OnDemandTool() }
        return r
    }()
    private let battery = BatterySampler()
    private let systemSampler = SystemSampler()
    private let keepAwake = KeepAwake()
    private let quickToggles = QuickToggles(prefs: SystemPreferences())
    private let volumeGuard = VolumeGuard(audio: CoreAudioOutput(),
                                          maxPercent: { UserDefaults.standard.object(forKey: "volumeGuard.max") as? Int ?? 70 })
    private let updateChecker = UpdateChecker(runner: ProcessRunner())
    private let flushDNS = FlushDNS(runner: AdminPromptRunner())
    private lazy var readoutSettings = ReadoutSettings(store: store)
    private var statusReadout: StatusReadout?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "battery.75percent", accessibilityDescription: "Apple Cart")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        statusReadout = StatusReadout(button: item.button, sampler: battery, registry: registry, settings: readoutSettings)
        panelController = PanelController(registry: registry, store: store, anchor: item.button,
                                          openSettings: { [weak self] in self?.openSettings() },
                                          firstRun: FirstRunModel(store: store), readout: readoutSettings,
                                          toolView: { [battery, systemSampler, keepAwake, quickToggles, volumeGuard, updateChecker, flushDNS] id, panel in
            switch id {
            case .battery: AnyView(BatteryView(sampler: battery, active: panel.isOpen && panel.route == .battery))
            case .system: AnyView(SystemView(sampler: systemSampler, active: panel.isOpen && panel.route == .system))
            case .keepAwake: AnyView(KeepAwakeView(keepAwake: keepAwake))
            case .quickToggles: AnyView(QuickTogglesView(toggles: quickToggles))
            case .volumeGuard: AnyView(VolumeGuardView(guardTool: volumeGuard))
            case .updates: AnyView(UpdatesView(checker: updateChecker))
            case .flushDNS: AnyView(FlushDNSView(tool: flushDNS))
            default: nil
            }
        })
    }

    @objc private func statusItemClicked() {
        guard let item = statusItem else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            panelController?.close()
            let menu = NSMenu()
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Apple Cart", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil // keep left click as the panel toggle
        } else {
            panelController?.toggle()
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Features"
            window.contentView = NSHostingView(rootView: SettingsView(
                registry: registry,
                permissions: PermissionsModel(checker: SystemPermissionChecker(), registry: registry),
                readout: readoutSettings,
                open: { NSWorkspace.shared.open($0) }))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
