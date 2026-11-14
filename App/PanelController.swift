import AppKit
import Core
import SwiftUI
import UI

/// Non-activating panel: clicking inside never closes it, Esc and outside clicks do (unless Keep open).
final class PanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    init(content: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: PanelView.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor
final class PanelController {
    let launcher: LauncherModel
    let panel = PanelModel()
    private var window: PanelWindow?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var anchor: NSStatusBarButton?
    private let openSettings: () -> Void

    init(registry: FeatureRegistry, store: SettingsStore, anchor: NSStatusBarButton?, openSettings: @escaping () -> Void) {
        launcher = LauncherModel(registry: registry, store: store)
        self.anchor = anchor
        self.openSettings = openSettings
    }

    var isShown: Bool { window?.isVisible == true }

    func toggle() { isShown ? close() : show() }

    func show() {
        let win = window ?? makeWindow()
        window = win
        position(win)
        win.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func close() {
        guard isShown else { return }
        window?.orderOut(nil)
        removeMonitors()
        panel.panelDidClose(launcher: launcher)
    }

    private func makeWindow() -> PanelWindow {
        let view = PanelView(launcher: launcher, panel: panel,
                             openSettings: { [weak self] in self?.close(); self?.openSettings() },
                             collapse: { [weak self] in self?.close() },
                             quit: { NSApp.terminate(nil) })
        let win = PanelWindow(content: NSHostingView(rootView: view))
        win.onCancel = { [weak self] in self?.close() }
        return win
    }

    /// Centered under the status item, clamped to the screen it is on.
    private func position(_ win: NSWindow) {
        let size = PanelView.size
        guard let button = anchor, let bw = button.window else { win.center(); return }
        let rect = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (bw.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = rect.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        win.setFrame(NSRect(x: x, y: rect.minY - size.height - 6, width: size.width, height: size.height), display: true)
    }

    private func installMonitors() {
        removeMonitors()
        // Clicks in other apps.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.outsideClick() }
        }
        // Clicks in this app's other windows (the status item button handles its own toggle).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window !== self.window, event.window !== self.anchor?.window { self.outsideClick() }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func outsideClick() {
        if !panel.keepOpen { close() }
    }
}
