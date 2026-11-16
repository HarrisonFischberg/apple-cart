import AppKit
import Core
import SwiftUI
import UI
import os

/// Non-activating panel: clicking inside never closes it, Esc and outside clicks do (unless Keep open).
final class PanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    init(content: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: PanelView.size),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = content
        contentMinSize = PanelView.size
        contentMaxSize = NSSize(width: 900, height: 1400)
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

    init(registry: FeatureRegistry, store: SettingsStore, anchor: NSStatusBarButton?, openSettings: @escaping () -> Void,
         firstRun: FirstRunModel, readout: ReadoutSettings,
         chargeLimit: ChargeLimitSettings, chargeLimiter: ChargeLimiter,
         toolView: @escaping (FeatureID, PanelModel) -> AnyView?) {
        self.chargeLimit = chargeLimit
        self.chargeLimiter = chargeLimiter
        self.firstRun = firstRun
        self.readout = readout
        launcher = LauncherModel(registry: registry, store: store)
        self.anchor = anchor
        self.openSettings = openSettings
        self.toolViewFactory = toolView
    }
    private let firstRun: FirstRunModel
    private let chargeLimit: ChargeLimitSettings
    private let chargeLimiter: ChargeLimiter
    private let readout: ReadoutSettings
    private let toolViewFactory: (FeatureID, PanelModel) -> AnyView?

    var isShown: Bool { window?.isVisible == true }

    private let log = Logger(subsystem: "app.rarecreatures.applecart", category: "panel")

    func toggle() { log.debug("toggle, shown=\(self.isShown)"); isShown ? close() : show() }

    func show() {
        let win = window ?? makeWindow()
        window = win
        position(win)
        panel.expanded = win.frame.width > PanelView.size.width + 40
        if launcher.allTiles.contains(.battery) { panel.open(.battery) } // Battery is the opening screen every time
        win.makeKeyAndOrderFront(nil)
        panel.isOpen = true
        installMonitors()
    }

    func close() {
        guard isShown else { return }
        window?.orderOut(nil)
        removeMonitors()
        panel.panelDidClose(launcher: launcher)
    }

    /// The size the owner last left the panel at, never below the normal size.
    private func savedSize() -> CGSize {
        let d = UserDefaults.standard
        let w = d.double(forKey: "panel.width"), h = d.double(forKey: "panel.height")
        guard w > 0, h > 0 else { return PanelView.size }
        let visible = (anchor?.window?.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1200, height: 900)
        return CGSize(width: min(max(w, PanelView.size.width), visible.width - 16), height: min(max(h, PanelView.size.height), visible.height - 16))
    }

    /// Normal size and large size, keeping the top edge where it is.
    private func toggleSize() {
        guard let win = window else { return }
        let visible = (win.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let target = panel.expanded ? PanelView.size
            : CGSize(width: min(PanelView.expandedSize.width, visible.width - 16), height: min(PanelView.expandedSize.height, visible.height - 16))
        var frame = win.frame
        frame.origin.y = frame.maxY - target.height
        frame.size = target
        frame.origin.x = min(max(frame.origin.x - (target.width - win.frame.width) / 2, visible.minX + 8), visible.maxX - target.width - 8)
        frame.origin.y = max(frame.origin.y, visible.minY + 8)
        win.setFrame(frame, display: true, animate: false) // an animated resize relays the whole panel every frame
    }

    private func makeWindow() -> PanelWindow {
        let view = PanelView(launcher: launcher, panel: panel,
                             openSettings: { [weak self] in self?.close(); self?.openSettings() },
                             collapse: { [weak self] in self?.close() },
                             quit: { NSApp.terminate(nil) },
                             toggleSize: { [weak self] in self?.toggleSize() },
                             toolView: { [panel, toolViewFactory] in toolViewFactory($0, panel) },
                             firstRun: firstRun, readout: readout,
                             chargeLimit: chargeLimit, chargeLimiter: chargeLimiter)
        let win = PanelWindow(content: NSHostingView(rootView: view))
        win.onCancel = { [weak self] in self?.close() }
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: win, queue: .main) { [weak self, weak win] _ in
            MainActor.assumeIsolated {
                guard let self, let win, win.isVisible else { return }
                UserDefaults.standard.set(win.frame.width, forKey: "panel.width")
                UserDefaults.standard.set(win.frame.height, forKey: "panel.height")
                self.panel.expanded = win.frame.width > PanelView.size.width + 40
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willStartLiveResizeNotification, object: win, queue: .main) { _ in
            MainActor.assumeIsolated { LiveResize.shared.active = true }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: win, queue: .main) { _ in
            MainActor.assumeIsolated { LiveResize.shared.active = false }
        }
        return win
    }

    /// Centered under the status item, clamped to the screen it is on.
    private func position(_ win: NSWindow) {
        let size = savedSize()
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
            if let self, event.window !== self.window, event.window !== self.anchor?.window, !self.isPartOfPanel(event.window) { self.outsideClick() }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    /// A SwiftUI popover opened from the panel (the Limit chooser) lives in its own window. Clicks inside it are clicks in the panel.
    private func isPartOfPanel(_ w: NSWindow?) -> Bool {
        guard let w else { return false }
        return w.className.contains("Popover") || w.parent === window || (window?.childWindows?.contains(w) ?? false)
    }

    private func outsideClick() {
        log.debug("outsideClick at \(NSStringFromPoint(NSEvent.mouseLocation))")
        // A click on our own status item is handled by its button (it toggles). Closing here too made the
        // button reopen the panel right after, which looked like a flash.
        if let button = anchor, let bw = button.window {
            let rect = bw.convertToScreen(button.convert(button.bounds, to: nil))
            if rect.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) { return }
        }
        if !panel.keepOpen { close() }
    }
}
