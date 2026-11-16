import AppKit
import Core
import SwiftUI
import UI

// Dev tool: renders the Settings window through a real NSWindow so native
// controls draw. Fake tools stand in so some switches are live. Usage: UIPreview --out <dir>

@MainActor
final class DemoTool: Tool {
    func start() {}
    func stop() {}
}

final class DemoStore: SettingsStore {
    var ids: Set<FeatureID> = [.battery]
    func enabledFeatures() -> Set<FeatureID> { ids }
    func setEnabledFeatures(_ ids: Set<FeatureID>) { self.ids = ids }
    var order: [FeatureID] = []
    var hidden: Set<FeatureID> = []
    func launcherOrder() -> [FeatureID] { order }
    func setLauncherOrder(_ ids: [FeatureID]) { order = ids }
    func hiddenFeatures() -> Set<FeatureID> { hidden }
    func setHiddenFeatures(_ ids: Set<FeatureID>) { hidden = ids }
    var readout: MenuBarReadout = .percent
    var firstRun = false
    func menuBarReadout() -> MenuBarReadout { readout }
    func setMenuBarReadout(_ r: MenuBarReadout) { readout = r }
    func firstRunDone() -> Bool { firstRun }
    func setFirstRunDone(_ done: Bool) { firstRun = done }
}

@MainActor
func render(name: String, size: NSSize, dark: Bool, view: some View, outDir: URL) {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: size)
    let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    win.contentView = host
    win.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    NSApplication.shared.activate(ignoringOtherApps: true)
    win.makeKeyAndOrderFront(nil)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("no rep"); return }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { print("no png"); return }
    let url = outDir.appendingPathComponent(name + ".png")
    try? png.write(to: url)
    print("wrote \(url.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
    win.orderOut(nil)
}

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    var out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("shots")
    if let i = CommandLine.arguments.firstIndex(of: "--out"), i + 1 < CommandLine.arguments.count {
        out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    }
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    let registry = FeatureRegistry(store: DemoStore())
    for id in [FeatureID.battery, .system, .keepAwake] { registry.register(id) { DemoTool() } }
    @MainActor func panelView(_ store: DemoStore, _ ids: [FeatureID]) -> PanelView {
        let reg = FeatureRegistry(store: store)
        for id in FeatureID.allCases { reg.register(id) { DemoTool() } }
        return PanelView(launcher: LauncherModel(registry: reg, store: store), panel: PanelModel(),
                         openSettings: {}, collapse: {}, quit: {})
    }
    /// The whole panel (header, icon strip, footer) with one tool chosen.
    @MainActor func fullPanel(_ route: FeatureID, _ content: AnyView) -> PanelView {
        let st = DemoStore(); st.ids = [.battery, .system, .keepAwake, .clipboard, .quickToggles, .volumeGuard, .updates, .cleaner, route]
        let reg = FeatureRegistry(store: st)
        for id in FeatureID.allCases { reg.register(id) { DemoTool() } }
        let p = PanelModel(); p.open(route)
        return PanelView(launcher: LauncherModel(registry: reg, store: st), panel: p, openSettings: {}, collapse: {}, quit: {},
                         toolView: { _ in content },
                         chargeLimit: ChargeLimitSettings(defaults: UserDefaults(suiteName: "preview-limit-" + UUID().uuidString)!))
    }
    struct DemoChecker: PermissionChecker {
        func status(of p: Permission) async -> PermissionStatus { p == .screenRecording ? .granted : p == .fullDiskAccess ? .granted : .notGranted }
    }
    let permStore = DemoStore(); permStore.ids = [.readQR]
    let permReg = FeatureRegistry(store: permStore)
    for id in FeatureID.allCases { permReg.register(id) { DemoTool() } }
    let permModel = PermissionsModel(checker: DemoChecker(), registry: permReg)
    @MainActor final class PrevLogin: LoginItem { var isEnabled = true; func set(_ on: Bool) throws { isEnabled = on } }
    let settingsStore = DemoStore(); settingsStore.ids = [.battery, .system, .keepAwake, .clipboard, .readQR]
    let settingsReg = FeatureRegistry(store: settingsStore)
    for id in FeatureID.allCases where id != .notifications { settingsReg.register(id) { DemoTool() } }
    let settingsPerms = PermissionsModel(checker: DemoChecker(), registry: settingsReg)
    let readoutSettings = ReadoutSettings(store: settingsStore)
    let sampler = BatterySampler(interval: .seconds(1))
    sampler.hold("preview")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 4))
    if let r = sampler.latest { print("READING percent=\(r.percent) measured=\(r.measuredPercent ?? -1) plugged=\(r.isPluggedIn) charging=\(r.isCharging) cycles=\(r.cycleCount ?? -1) battW=\(r.batteryWatts) sysW=\(r.systemWatts ?? -1)") }
    // Synthetic readings so every battery state renders the same on any Mac.
    func synthetic(percent: Int, plugged: Bool, charging: Bool, amps: Int, system: Int?, adapter: Int?) -> BatteryReading? {
        var p: [String: Any] = ["CurrentCapacity": percent, "ExternalConnected": plugged ? 1 : 0, "IsCharging": charging ? 1 : 0,
                                "Voltage": 12000, "InstantAmperage": NSNumber(value: UInt64(bitPattern: Int64(amps))), "CycleCount": 98,
                                "BatteryData": ["AppleRawCurrentCapacity": 4545, "AppleRawMaxCapacity": 5751, "DesignCapacity": 6249]]
        if let system { p["PowerTelemetryData"] = ["SystemLoad": system] }
        if let adapter { p["AdapterDetails"] = ["Watts": adapter] }
        return BatteryReading(properties: p)
    }
    let batteryStates: [(String, BatterySampler)] = [
        ("charging", synthetic(percent: 62, plugged: true, charging: true, amps: 1300, system: 14200, adapter: 96)),
        ("acfull", synthetic(percent: 100, plugged: true, charging: false, amps: 0, system: 9800, adapter: 96)),
        ("onbattery", synthetic(percent: 41, plugged: false, charging: false, amps: -1500, system: 18000, adapter: nil)),
        ("nodata", synthetic(percent: 77, plugged: false, charging: false, amps: 0, system: nil, adapter: nil)),
    ].map { name, r in
        let s = BatterySampler(interval: .seconds(1), read: { r })
        s.hold("preview-\(name)")
        return (name, s)
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))
    @MainActor func firstRunPanel(step: Int) -> PanelView {
        let st = DemoStore(); let reg = FeatureRegistry(store: st)
        let fr = FirstRunModel(store: st); if step == 1 { fr.next() }
        return PanelView(launcher: LauncherModel(registry: reg, store: st), panel: PanelModel(), openSettings: {},
                         collapse: {}, quit: {}, firstRun: fr, readout: ReadoutSettings(store: st))
    }
    let sysSampler = SystemSampler(interval: .seconds(1))
    sysSampler.hold("preview")
    let awake = KeepAwake()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.5))
    let realToggles = QuickToggles(prefs: SystemPreferences())
    print("TOGGLES", QuickToggle.allCases.map { "\($0.rawValue)=\(realToggles.states[$0] ?? false)" }.joined(separator: " "))
    print("VOLUME", CoreAudioOutput().volume() as Any)
    let checker = UpdateChecker(runner: ProcessRunner())
    Task { await checker.check() }
    let flush = FlushDNS(runner: AdminPromptRunner())
    @MainActor final class NoApps: RunningApps { func isRunning(_ b: String) -> Bool { false }; func quit(_ b: String) {} }
    let unin = UninstallerModel(running: NoApps(), hasFullDiskAccess: { false })
    Task { await unin.choose(URL(fileURLWithPath: "/Applications/Itsycal.app")) } // read-only scan, nothing is moved
    let cleaner = CleanerModel(); cleaner.scan() // read-only scan, nothing is moved
    let diskMap = DiskMapModel(); diskMap.scan()
    @MainActor final class PrevNotifier: BreakNotifier { func prepare() async {}; func send(_ k: BreakKind, everyMinutes: Int) async {} }
    @MainActor final class PrevBlocker: InputBlocker { var canBlock = false; func start(onExitHeld: @escaping @MainActor () -> Void) -> Bool { true }; func stop() {} }
    let breaks = BreakReminders(defaults: UserDefaults(suiteName: "preview-breaks")!, notifier: PrevNotifier())
    breaks.start(); breaks.setEnabled(.eyes, true); breaks.setEnabled(.water, true)
    let blocker = PrevBlocker(); let cleaning = CleaningMode(blocker: blocker)
    cleaning.start(seconds: 120) // no Accessibility in preview: shows the permission message
    let cleaningLive = CleaningMode(blocker: { let b = PrevBlocker(); b.canBlock = true; return b }()); cleaningLive.start(seconds: 120)
    @MainActor final class PrevBoard: PasteboardAccess {
        var changeCount = 1; var text: String?
        func snapshot() -> PasteboardSnapshot { .init(changeCount: changeCount, types: [], text: text, imageData: nil, sourceBundleID: "com.example.notes") }
        func write(text: String) { self.text = text; changeCount += 1 }
        func write(imageData: Data) {}; func clear() {}; func paste() -> Bool { true }
    }
    let board = PrevBoard()
    let clipDir = FileManager.default.temporaryDirectory.appendingPathComponent("prev-clip-" + UUID().uuidString)
    let clip = ClipboardHistory(pasteboard: board, folder: clipDir, defaults: UserDefaults(suiteName: "preview-clip-" + UUID().uuidString)!)
    for t in ["https://developer.apple.com/documentation/swiftui", "Meeting notes: ship the uninstaller preview first, then the cleaner.", "brew upgrade gh gradle helm", "+1 (800) 626-8695"] { board.text = t; board.changeCount += 1; clip.check() }
    clip.togglePin(clip.items.last!)
    @MainActor final class PrevPicker: RegionSelecting { func pickRegion() async -> ScreenRegion? { ScreenRegion(displayID: 1, rect: .init(x: 0, y: 0, width: 20, height: 20)) } }
    @MainActor final class PrevCapture: ScreenCapturing { func capture(_ r: ScreenRegion) async throws -> CGImage { CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()! } }
    struct PrevRec: ImageRecognizing { func text(in i: CGImage) async -> String { "Invoice 2026-114\nTotal due: $48.20" }; func codes(in i: CGImage) async -> [String] { [] } }
    let reader = ScreenReader(picker: PrevPicker(), capturer: PrevCapture(), recognizer: PrevRec(), pasteboard: board, toast: { _ in })
    Task { await reader.run(.text) }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
    let settingsTools = SettingsTools(clipboard: clip, breaks: breaks, quickToggles: realToggles, updateChecker: checker)
    @MainActor func settingsView(_ page: SettingsPage) -> SettingsView {
        SettingsView(registry: settingsReg, permissions: settingsPerms, readout: readoutSettings, login: LaunchAtLogin(item: PrevLogin()),
                     general: GeneralActions(updatesConfigured: true, checkForUpdates: {}, automaticChecks: { true }, setAutomaticChecks: { _ in },
                                             sendDebugLogs: {}, deleteAllData: {}),
                     tools: settingsTools, initialPage: page, open: { _ in })
    }
    let guardTool = VolumeGuard(audio: CoreAudioOutput(), maxPercent: { 70 })
    let full = DemoStore(); full.ids = [.battery, .system, .keepAwake, .clipboard, .copyText, .readQR]
    let empty = DemoStore(); empty.ids = []
    Task { await permModel.refresh(); await settingsPerms.refresh() }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 45))
    if case .preview(let pl) = unin.phase { print("UNINSTALL plan:", pl.items.map { $0.url.path + " " + String($0.bytes) }.joined(separator: " | ")) } else { print("UNINSTALL phase", unin.phase) }
    if case .preview(let ci) = cleaner.phase { print("CLEANER", ci.count, "items", ci.reduce(Int64(0)) { $0 + $1.bytes }, "bytes") } else { print("CLEANER phase", cleaner.phase) }
    print("DISKMAP scanning=\(diskMap.scanning)", diskMap.entries.prefix(4).map { $0.url.lastPathComponent + " " + String($0.bytes) })
    print("UPDATES brew=\(checker.homebrew) macOS=\(checker.macOS)")
    for dark in [false, true] {
        let tag = dark ? "dark" : "light"
        for (key, page) in [("general", SettingsPage.general), ("battery", .tool(.battery)), ("keepawake", .tool(.keepAwake)),
                            ("clipboard", .tool(.clipboard)), ("permissions", .permissions)] {
            render(name: "t030-settings-\(key)-\(tag)", size: NSSize(width: 780, height: 540), dark: dark,
                   view: settingsView(page), outDir: out)
        }
        render(name: "t006-battery-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.battery, AnyView(BatteryView(sampler: sampler, active: true))), outDir: out)
        render(name: "t006-menubar-glyphs-\(tag)", size: NSSize(width: 420, height: 50), dark: dark, view:
            HStack(spacing: 14) {
                ForEach([(0.0, BatteryBadge.none), (0.4, .none), (0.62, .bolt), (1, .plug), (0.8, .paused), (0.1, .plug)], id: \.0) { l, b in
                    Image(nsImage: BatteryGlyphImage.make(BatteryGlyph(level: l, badge: b)))
                }
            }.padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.ground), outDir: out)
        for (state, sam) in batteryStates {
            render(name: "t006-battery-\(state)-\(tag)", size: PanelView.size, dark: dark,
                   view: fullPanel(.battery, AnyView(BatteryView(sampler: sam, active: true))), outDir: out)
        }
        for step in 0...1 { render(name: "t007-firstrun\(step + 1)-\(tag)", size: PanelView.size, dark: dark, view: firstRunPanel(step: step), outDir: out) }
        render(name: "t008-system-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.system, AnyView(SystemView(sampler: sysSampler, active: true))), outDir: out)
        render(name: "t008-keepawake-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.keepAwake, AnyView(KeepAwakeView(keepAwake: awake))), outDir: out)
        render(name: "t024-panel-keepawake-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.keepAwake, AnyView(KeepAwakeView(keepAwake: awake))), outDir: out)
        render(name: "t013-toggles-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.quickToggles, AnyView(QuickTogglesView(toggles: realToggles))), outDir: out)
        render(name: "t013-volume-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.volumeGuard, AnyView(VolumeGuardView(guardTool: guardTool))), outDir: out)
        render(name: "t016-uninstaller-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.uninstaller, AnyView(UninstallerView(model: unin, openFullDiskAccess: {}))), outDir: out)
        render(name: "t017-cleaner-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.cleaner, AnyView(CleanerView(model: cleaner))), outDir: out)
        render(name: "t017-diskmap-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.diskMap, AnyView(DiskMapView(model: diskMap))), outDir: out)
        render(name: "t021-breaks-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.breakReminders, AnyView(BreaksView(reminders: breaks))), outDir: out)
        render(name: "t021-cleaning-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.cleaningMode, AnyView(CleaningModeView(mode: cleaning, openAccessibility: {}))), outDir: out)
        render(name: "t021-overlay-\(tag)", size: NSSize(width: 900, height: 560), dark: dark, view: CleaningOverlayView(mode: cleaningLive), outDir: out)
        render(name: "t019-clipboard-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.clipboard, AnyView(ClipboardView(history: clip, close: {}))), outDir: out)
        render(name: "t020-copytext-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.copyText, AnyView(ScreenReadView(reader: reader, mode: .text, start: {}, openSettings: {}))), outDir: out)
        render(name: "t015-flushdns-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.flushDNS, AnyView(FlushDNSView(tool: flush))), outDir: out)
        render(name: "t018-updates-\(tag)", size: PanelView.size, dark: dark,
               view: fullPanel(.updates, AnyView(UpdatesView(checker: checker))), outDir: out)
        render(name: "t004-launcher-\(tag)", size: PanelView.size, dark: dark, view: panelView(full, []), outDir: out)
        render(name: "t004-empty-\(tag)", size: PanelView.size, dark: dark, view: panelView(empty, []), outDir: out)
    }
}
