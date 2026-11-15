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
        r.register(.uninstaller) { OnDemandTool() }
        r.register(.clipboard) { [clipboard, plainPasteKey] in ClipboardTool(clipboard, hotKey: plainPasteKey) }
        r.register(.breakReminders) { [breaks] in breaks }
        r.register(.cleaningMode) { OnDemandTool() }
        r.register(.cleaner) { OnDemandTool() }
        r.register(.diskMap) { OnDemandTool() }
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
    private let uninstaller = UninstallerModel(running: WorkspaceRunningApps(),
                                                hasFullDiskAccess: { await SystemPermissionChecker().status(of: .fullDiskAccess) == .granted })
    private let plainPasteKey = PlainPasteHotKey()
    private lazy var clipboard = ClipboardHistory(
        pasteboard: SystemPasteboard(),
        folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Apple Cart/Clipboard"))
    private let breakBanners = BreakBanners()
    private lazy var breaks = BreakReminders(notifier: breakBanners)
    private let cleaningMode = CleaningMode(blocker: EventTapBlocker())
    private let cleaningOverlay = CleaningOverlay()
    private let cleaner = CleanerModel()
    private let diskMap = DiskMapModel()
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
        breakBanners.onSnooze = { [breaks] in breaks.snooze($0) }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [breaks] _ in MainActor.assumeIsolated { breaks.pause() } }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [breaks] _ in MainActor.assumeIsolated { breaks.resume() } }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [clipboard] _ in
            MainActor.assumeIsolated { clipboard.screenLocked() }
        }
        cleaningMode.onChange = { [weak self] on in
            guard let self else { return }
            if on { self.panelController?.close(); self.cleaningOverlay.show(mode: self.cleaningMode) } else { self.cleaningOverlay.hide() }
        }
        statusReadout = StatusReadout(button: item.button, sampler: battery, registry: registry, settings: readoutSettings)
        panelController = PanelController(registry: registry, store: store, anchor: item.button,
                                          openSettings: { [weak self] in self?.openSettings() },
                                          firstRun: FirstRunModel(store: store), readout: readoutSettings,
                                          toolView: { [weak self, battery, systemSampler, keepAwake, quickToggles, volumeGuard, updateChecker, flushDNS, uninstaller, cleaner, diskMap, breaks, cleaningMode, clipboard] id, panel in
            switch id {
            case .battery: AnyView(BatteryView(sampler: battery, active: panel.isOpen && panel.route == .battery))
            case .system: AnyView(SystemView(sampler: systemSampler, active: panel.isOpen && panel.route == .system))
            case .keepAwake: AnyView(KeepAwakeView(keepAwake: keepAwake))
            case .quickToggles: AnyView(QuickTogglesView(toggles: quickToggles))
            case .volumeGuard: AnyView(VolumeGuardView(guardTool: volumeGuard))
            case .updates: AnyView(UpdatesView(checker: updateChecker))
            case .flushDNS: AnyView(FlushDNSView(tool: flushDNS))
            case .uninstaller: AnyView(UninstallerView(model: uninstaller, openFullDiskAccess: { NSWorkspace.shared.open(Permission.fullDiskAccess.settingsURL) }))
            case .cleaner: AnyView(CleanerView(model: cleaner))
            case .diskMap: AnyView(DiskMapView(model: diskMap))
            case .breakReminders: AnyView(BreaksView(reminders: breaks))
            case .cleaningMode: AnyView(CleaningModeView(mode: cleaningMode, openAccessibility: { NSWorkspace.shared.open(Permission.accessibility.settingsURL) }))
            case .clipboard: AnyView(ClipboardView(history: clipboard, close: { [weak self] in self?.panelController?.close() }))
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
