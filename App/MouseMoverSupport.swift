import AppKit
import CoreGraphics
import Core

/// Moves the real pointer. Warping needs no permission and makes no input event, so it neither counts as the
/// owner's input nor resets macOS's idle timer: the display still sleeps on its usual schedule.
@MainActor
final class QuartzPointer: PointerDriver {
    var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    func warp(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        // Without this, macOS ignores the real mouse for a moment after each warp, and the owner couldn't stop it.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    func displays() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    func secondsSinceInput() -> TimeInterval {
        // HID state counts only real hardware, never the warps above.
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
    }
}

/// One black window per screen while the mover runs. A click lands here instead of in a hidden app, and stops the mover.
@MainActor
final class BlackoutOverlay {
    private var windows: [NSWindow] = []

    func show() {
        hide()
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = .screenSaver; w.backgroundColor = .black; w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func hide() { windows.forEach { $0.orderOut(nil) }; windows = [] }
}

/// On: watch for idle time. Off: stop moving and stop watching.
@MainActor
final class MouseMoverTool: Tool {
    private let mover: MouseMover
    init(_ mover: MouseMover) { self.mover = mover }
    func start() { mover.enable() }
    func stop() { mover.disable() }
}
