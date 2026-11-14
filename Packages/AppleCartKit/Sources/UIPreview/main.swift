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
    let full = DemoStore(); full.ids = [.battery, .system, .keepAwake, .clipboard, .copyText, .readQR]
    let empty = DemoStore(); empty.ids = []
    for dark in [false, true] {
        let tag = dark ? "dark" : "light"
        render(name: "t003-features-\(tag)", size: NSSize(width: 480, height: 760),
               dark: dark, view: FeaturesSettingsView(registry: registry), outDir: out)
        render(name: "t004-launcher-\(tag)", size: PanelView.size, dark: dark, view: panelView(full, []), outDir: out)
        render(name: "t004-empty-\(tag)", size: PanelView.size, dark: dark, view: panelView(empty, []), outDir: out)
    }
}
