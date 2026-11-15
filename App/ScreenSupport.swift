import AppKit
import Core
import CoreGraphics
import ScreenCaptureKit

/// Dim overlay on every screen; drag a rectangle, release to confirm, Esc to cancel.
@MainActor
final class RegionPicker: RegionSelecting {
    private var windows: [PickerWindow] = []
    private var continuation: CheckedContinuation<ScreenRegion?, Never>?

    func pickRegion() async -> ScreenRegion? {
        await withCheckedContinuation { c in
            continuation = c
            for screen in NSScreen.screens {
                let w = PickerWindow(screen: screen) { [weak self] region in self?.finish(region) }
                windows.append(w)
                w.makeKeyAndOrderFront(nil)
            }
            NSApp.activate()
            NSCursor.crosshair.push()
        }
    }

    private func finish(_ region: ScreenRegion?) {
        guard let c = continuation else { return }
        continuation = nil
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        // Give the overlay a moment to leave the screen so it is not in the capture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { c.resume(returning: region) }
    }
}

private final class PickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    init(screen: NSScreen, done: @escaping (ScreenRegion?) -> Void) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver; backgroundColor = .clear; isOpaque = false; isReleasedWhenClosed = false; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        contentView = PickerView(frame: NSRect(origin: .zero, size: screen.frame.size), displayID: id, done: done)
        setFrame(screen.frame, display: true)
    }
}

private final class PickerView: NSView {
    let displayID: UInt32, done: (ScreenRegion?) -> Void
    var start: NSPoint?, current: NSPoint?
    init(frame: NSRect, displayID: UInt32, done: @escaping (ScreenRegion?) -> Void) { self.displayID = displayID; self.done = done; super.init(frame: frame) }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    var selection: NSRect? { guard let s = start, let c = current else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y)) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill(); bounds.fill()
        guard let r = selection else { return }
        NSColor.clear.setFill(); r.fill(using: .copy)
        NSColor.white.setStroke(); let p = NSBezierPath(rect: r); p.lineWidth = 1.5; p.stroke()
    }

    override func mouseDown(with e: NSEvent) { start = convert(e.locationInWindow, from: nil); current = start; needsDisplay = true }
    override func mouseDragged(with e: NSEvent) { current = convert(e.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with e: NSEvent) {
        guard let r = selection, r.width >= 10, r.height >= 10 else { done(nil); return }
        // View origin is bottom-left; the capture API wants top-left.
        done(ScreenRegion(displayID: displayID, rect: CGRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height)))
    }
    override func keyDown(with e: NSEvent) { if e.keyCode == 53 { done(nil) } else { super.keyDown(with: e) } }
    override func cancelOperation(_ sender: Any?) { done(nil) }
}

/// ScreenCaptureKit screenshot of one region. Needs Screen Recording; the image stays in memory.
@MainActor
final class ScreenCapturer: ScreenCapturing {
    func capture(_ region: ScreenRegion) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { _ = CGRequestScreenCaptureAccess(); throw CaptureFailure.notAllowed }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else { throw CaptureFailure.failed }
            let scale = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == region.displayID }?.backingScaleFactor ?? 2
            let cfg = SCStreamConfiguration()
            cfg.sourceRect = region.rect
            cfg.width = Int(region.rect.width * scale); cfg.height = Int(region.rect.height * scale)
            cfg.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg)
        } catch let e as CaptureFailure { throw e } catch { throw CaptureFailure.failed }
    }
}

/// A small message near the top of the screen that fades after two seconds.
@MainActor
final class Toast {
    private var window: NSWindow?
    private var hide: DispatchWorkItem?

    func show(_ text: String) {
        window?.orderOut(nil); hide?.cancel()
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .medium); label.textColor = .white
        label.sizeToFit()
        let pad: CGFloat = 16, size = NSSize(width: label.frame.width + pad * 2, height: label.frame.height + pad)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .statusBar; w.isOpaque = false; w.backgroundColor = .clear; w.ignoresMouseEvents = true; w.isReleasedWhenClosed = false
        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true; bg.layer?.cornerRadius = size.height / 2; bg.layer?.masksToBounds = true
        label.frame.origin = NSPoint(x: pad, y: pad / 2); bg.addSubview(label)
        w.contentView = bg
        if let s = NSScreen.main { w.setFrameOrigin(NSPoint(x: s.frame.midX - size.width / 2, y: s.frame.maxY - 120)) }
        w.orderFrontRegardless()
        window = w
        let work = DispatchWorkItem { [weak self] in self?.window?.orderOut(nil); self?.window = nil }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
