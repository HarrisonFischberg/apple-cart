import AppKit
import Core
import SwiftUI
import UI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var panelController: PanelController?
    // No tools are registered yet (they arrive with their tasks), so every switch shows "Not built yet".
    private let store = UserDefaultsSettingsStore()
    private lazy var registry = FeatureRegistry(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "battery.75percent", accessibilityDescription: "Apple Cart")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        panelController = PanelController(registry: registry, store: store, anchor: item.button,
                                          openSettings: { [weak self] in self?.openSettings() })
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
                open: { NSWorkspace.shared.open($0) }))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
