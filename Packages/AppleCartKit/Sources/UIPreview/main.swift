import AppKit
import Core
import SwiftUI
import UI

// Dev tool: renders the Settings > Features window through a real NSWindow so native
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
    struct DemoChecker: PermissionChecker {
        func status(of p: Permission) async -> PermissionStatus { p == .screenRecording ? .granted : p == .fullDiskAccess ? .granted : .notGranted }
    }
    let permStore = DemoStore(); permStore.ids = [.readQR]
    let permReg = FeatureRegistry(store: permStore)
    for id in FeatureID.allCases { permReg.register(id) { DemoTool() } }
    let permModel = PermissionsModel(checker: DemoChecker(), registry: permReg)
    let sampler = BatterySampler(interval: .seconds(1))
    sampler.hold("preview")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 4))
    if let r = sampler.latest { print("READING percent=\(r.percent) measured=\(r.measuredPercent ?? -1) plugged=\(r.isPluggedIn) charging=\(r.isCharging) cycles=\(r.cycleCount ?? -1) battW=\(r.batteryWatts) sysW=\(r.systemWatts ?? -1)") }
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
    let guardTool = VolumeGuard(audio: CoreAudioOutput(), maxPercent: { 70 })
    let full = DemoStore(); full.ids = [.battery, .system, .keepAwake, .clipboard, .copyText, .readQR]
    let empty = DemoStore(); empty.ids = []
    Task { await permModel.refresh() }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 45))
    if case .preview(let pl) = unin.phase { print("UNINSTALL plan:", pl.items.map { $0.url.path + " " + String($0.bytes) }.joined(separator: " | ")) } else { print("UNINSTALL phase", unin.phase) }
    if case .preview(let ci) = cleaner.phase { print("CLEANER", ci.count, "items", ci.reduce(Int64(0)) { $0 + $1.bytes }, "bytes") } else { print("CLEANER phase", cleaner.phase) }
    print("DISKMAP scanning=\(diskMap.scanning)", diskMap.entries.prefix(4).map { $0.url.lastPathComponent + " " + String($0.bytes) })
    print("UPDATES brew=\(checker.homebrew) macOS=\(checker.macOS)")
    for dark in [false, true] {
        let tag = dark ? "dark" : "light"
        render(name: "t003-features-\(tag)", size: NSSize(width: 480, height: 760),
               dark: dark, view: FeaturesSettingsView(registry: registry), outDir: out)
        render(name: "t005-permissions-\(tag)", size: NSSize(width: 560, height: 600), dark: dark,
               view: PermissionsView(model: permModel, open: { _ in }), outDir: out)
        render(name: "t006-battery-\(tag)", size: PanelView.size, dark: dark,
               view: BatteryView(sampler: sampler, active: true).frame(width: 420, height: 560).background(Palette.ground), outDir: out)
        for step in 0...1 { render(name: "t007-firstrun\(step + 1)-\(tag)", size: PanelView.size, dark: dark, view: firstRunPanel(step: step), outDir: out) }
        render(name: "t008-system-\(tag)", size: PanelView.size, dark: dark,
               view: SystemView(sampler: sysSampler, active: true).frame(width: 420, height: 560).background(Palette.ground), outDir: out)
        render(name: "t008-keepawake-\(tag)", size: PanelView.size, dark: dark,
               view: KeepAwakeView(keepAwake: awake).frame(width: 420, height: 560).background(Palette.ground), outDir: out)
        render(name: "t013-toggles-\(tag)", size: PanelView.size, dark: dark,
               view: QuickTogglesView(toggles: realToggles).frame(width: 420, height: 560).background(Palette.ground), outDir: out)
        render(name: "t013-volume-\(tag)", size: PanelView.size, dark: dark,
               view: VolumeGuardView(guardTool: guardTool).frame(width: 420, height: 560).background(Palette.ground), outDir: out)
        render(name: "t016-uninstaller-\(tag)", size: PanelView.size, dark: dark,
               view: UninstallerView(model: unin, openFullDiskAccess: {}).frame(width: 420, height: 560).background(Palette.ground), outDir: out)
        render(name: "t017-cleaner-\(tag)", size: PanelView.size, dark: dark,
               view: CleanerView(model: cleaner).frame(width: 420, height: 560).background(Palette.ground), outDir: out)
        render(name: "t017-diskmap-\(tag)", size: PanelView.size, dark: dark,
               view: DiskMapView(model: diskMap).frame(width: 420, height: 560).background(Palette.ground), outDir: out)
        render(name: "t015-flushdns-\(tag)", size: PanelView.size, dark: dark,
               view: FlushDNSView(tool: flush).frame(width: 420, height: 560).background(Palette.ground), outDir: out)
        render(name: "t018-updates-\(tag)", size: PanelView.size, dark: dark,
               view: UpdatesView(checker: checker).frame(width: 420, height: 560).background(Palette.ground), outDir: out)
        render(name: "t004-launcher-\(tag)", size: PanelView.size, dark: dark, view: panelView(full, []), outDir: out)
        render(name: "t004-empty-\(tag)", size: PanelView.size, dark: dark, view: panelView(empty, []), outDir: out)
    }
}
