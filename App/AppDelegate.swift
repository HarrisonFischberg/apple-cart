import AppKit
import Carbon.HIToolbox
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
        r.register(.battery) { [chargeLimiter, battery] in BatteryTool(limiter: chargeLimiter, battery: battery) }
        r.register(.system) { SystemTool() }
        r.register(.keepAwake) { [keepAwake] in KeepAwakeTool(keepAwake) }
        r.register(.quickToggles) { QuickTogglesTool() }
        r.register(.volumeGuard) { [volumeGuard] in volumeGuard }
        r.register(.uninstaller) { OnDemandTool() }
        r.register(.clipboard) { [clipboard, hotKeys] in ClipboardTool(clipboard, keys: hotKeys) }
        r.register(.copyText) { [screenReader, hotKeys] in ScreenReadTool(screenReader, keys: hotKeys, id: 2, key: kVK_ANSI_T, mode: .text) }
        r.register(.readQR) { [screenReader, hotKeys] in ScreenReadTool(screenReader, keys: hotKeys, id: 3, key: kVK_ANSI_Q, mode: .qr) }
        r.register(.breakReminders) { [breaks] in breaks }
        r.register(.cleaningMode) { OnDemandTool() }
        r.register(.cleaner) { OnDemandTool() }
        r.register(.diskMap) { OnDemandTool() }
        r.register(.updates) { OnDemandTool() }
        r.register(.flushDNS) { OnDemandTool() }
        return r
    }()
    private let battery = BatterySampler()
    private let chargeLimit = ChargeLimitSettings()
    private let chargeController: ChargeController = HelperChargeController()
    /// The single writer to the root helper.
    private lazy var chargeLimiter = ChargeLimiter(settings: chargeLimit, controller: chargeController)
    private let systemSampler = SystemSampler()
    private let keepAwake = KeepAwake()
    private let quickToggles = QuickToggles(prefs: SystemPreferences())
    private let volumeGuard = VolumeGuard(audio: CoreAudioOutput(),
                                          maxPercent: { UserDefaults.standard.object(forKey: "volumeGuard.max") as? Int ?? 70 })
    private let updateChecker = UpdateChecker(runner: ProcessRunner())
    private let uninstaller = UninstallerModel(running: WorkspaceRunningApps(),
                                                hasFullDiskAccess: { await SystemPermissionChecker().status(of: .fullDiskAccess) == .granted })
    private let updater = Updater()
    private let launchAtLogin = LaunchAtLogin(item: SMLoginItem())
    /// Provisional until the public name and support inbox are chosen (launch blockers).
    private static let supportAddress = "support@rarecreatures.app"
    private let hotKeys = HotKeyCenter()
    private let toast = Toast()
    private lazy var screenReader = ScreenReader(picker: RegionPicker(), capturer: ScreenCapturer(), pasteboard: SystemPasteboard(),
                                                 toast: { [toast] in toast.show($0) })
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
    let glyphStyle = GlyphStyleSettings()
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
        statusReadout = StatusReadout(button: item.button, sampler: battery, registry: registry, settings: readoutSettings, glyphStyle: glyphStyle)
        panelController = PanelController(registry: registry, store: store, anchor: item.button,
                                          openSettings: { [weak self] in self?.openSettings() },
                                          firstRun: FirstRunModel(store: store), readout: readoutSettings,
                                          chargeLimit: chargeLimit, chargeLimiter: chargeLimiter,
                                          toolView: { [weak self, battery, chargeLimit, chargeLimiter, systemSampler, keepAwake, quickToggles, volumeGuard, updateChecker, flushDNS, uninstaller, cleaner, diskMap, breaks, cleaningMode, clipboard, screenReader] id, panel in
            switch id {
            case .battery: AnyView(BatteryView(sampler: battery, active: panel.isOpen && panel.route == .battery, limiter: chargeLimiter, chargeLimit: chargeLimit))
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
            case .cleaningMode: AnyView(CleaningModeView(mode: cleaningMode, openAccessibility: { if !requestAccessibility() { NSWorkspace.shared.open(Permission.accessibility.settingsURL) } }))
            case .clipboard: AnyView(ClipboardView(history: clipboard, close: { [weak self] in self?.panelController?.close() }))
            case .copyText: AnyView(ScreenReadView(reader: screenReader, mode: .text, start: { [weak self] in self?.panelController?.close(); Task { await self?.screenReader.run(.text) } },
                                                   openSettings: { NSWorkspace.shared.open(Permission.screenRecording.settingsURL) }))
            case .readQR: AnyView(ScreenReadView(reader: screenReader, mode: .qr, start: { [weak self] in self?.panelController?.close(); Task { await self?.screenReader.run(.qr) } },
                                                 openSettings: { NSWorkspace.shared.open(Permission.screenRecording.settingsURL) }))
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
            if updater.isConfigured { menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Apple Cart", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil // keep left click as the panel toggle
        } else {
            panelController?.toggle()
        }
    }

    @objc private func checkForUpdates() { updater.checkForUpdates() }

    /// Put the charger back on before quitting instead of waiting for the helper's lease to run out.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await chargeLimiter.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func sendDebugLogs() {
        Task {
            let checker = SystemPermissionChecker()
            var perms: [String: String] = [:]
            for p in Permission.allCases { perms[p.title] = await checker.status(of: p) == .granted ? "granted" : "not granted" }
            let info = Bundle.main.infoDictionary
            var size = 0; sysctlbyname("hw.model", nil, &size, nil, 0)
            var model = [CChar](repeating: 0, count: max(size, 1)); sysctlbyname("hw.model", &model, &size, nil, 0)
            let report = DebugReport(appVersion: info?["CFBundleShortVersionString"] as? String ?? "?", build: info?["CFBundleVersion"] as? String ?? "?",
                                     macOS: ProcessInfo.processInfo.operatingSystemVersionString, model: String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self),
                                     enabledTools: registry.enabled.map(\.title), permissions: perms)
            if let url = report.mailto(Self.supportAddress) { NSWorkspace.shared.open(url) }
        }
    }

    private func deleteAllData() {
        let alert = NSAlert()
        alert.messageText = "Delete all Apple Cart data?"
        alert.informativeText = "This removes every setting and saved item, such as clipboard history and battery history, from this Mac. It cannot be undone, and Apple Cart will quit."
        alert.addButton(withTitle: "Delete and Quit"); alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for id in registry.enabled { registry.setEnabled(false, for: id) } // stop every tool first so nothing rewrites its data
        Task {
            await chargeLimiter.shutdown() // charger back to normal (resetAll) before the data goes
            let fm = FileManager.default
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Apple Cart")
            let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "app.rarecreatures.applecart")
            AppDataEraser(defaultsDomain: Bundle.main.bundleIdentifier ?? "app.rarecreatures.applecart", folders: [support, caches]).eraseAll()
            NSApp.terminate(nil)
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Apple Cart Settings"
            window.contentMinSize = NSSize(width: 680, height: 460)
            window.contentView = NSHostingView(rootView: SettingsView(
                registry: registry,
                permissions: PermissionsModel(checker: SystemPermissionChecker(), registry: registry),
                readout: readoutSettings,
                login: launchAtLogin,
                general: GeneralActions(updatesConfigured: updater.isConfigured, checkForUpdates: { [updater] in updater.checkForUpdates() },
                                        automaticChecks: { [updater] in updater.automaticChecks }, setAutomaticChecks: { [updater] in updater.automaticChecks = $0 },
                                        sendDebugLogs: { [weak self] in self?.sendDebugLogs() }, deleteAllData: { [weak self] in self?.deleteAllData() }),
                tools: SettingsTools(clipboard: clipboard, breaks: breaks, quickToggles: quickToggles, updateChecker: updateChecker,
                                     chargeLimit: chargeLimit, chargeLimiter: chargeLimiter,
                                     chargeHelper: ChargeHelperActions(
                                        install: { await ChargeHelperInstaller.install() },
                                        repair: { await ChargeHelperInstaller.repair() },
                                        remove: { [chargeController] in await ChargeHelperInstaller.remove(controller: chargeController) },
                                        openLoginItems: { ChargeHelperInstaller.openLoginItems() }),
                                     battery: battery),
                glyphStyle: glyphStyle,
                open: { NSWorkspace.shared.open($0) }))
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("AppleCartSettings") // remembers size and place between launches
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
