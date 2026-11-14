import AppKit
import Core
import SwiftUI
import UI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    // No tools are registered yet (they arrive with their tasks), so every switch shows "Not built yet".
    private let registry = FeatureRegistry(store: UserDefaultsSettingsStore())

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "battery.75percent", accessibilityDescription: "Apple Cart")
        // Placeholder menu until the panel (T004) replaces it.
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Apple Cart", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Features"
            window.contentView = NSHostingView(rootView: FeaturesSettingsView(registry: registry))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
