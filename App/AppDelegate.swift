import AppKit
import Core

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "battery.75percent", accessibilityDescription: "Apple Cart")
        // Placeholder menu until the panel (T004) replaces it.
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Apple Cart", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}
