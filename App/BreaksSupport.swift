import AppKit
import ApplicationServices
import Core
import SwiftUI
import UI
import UserNotifications

/// Banners for break reminders, with a Snooze button.
@MainActor
final class BreakBanners: NSObject, BreakNotifier, @preconcurrency UNUserNotificationCenterDelegate {
    var onSnooze: ((BreakKind) -> Void)?
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        let snooze = UNNotificationAction(identifier: "snooze", title: "Snooze \(BreakReminders.snoozeMinutes) min", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "break", actions: [snooze], intentIdentifiers: [])])
    }

    func prepare() async { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }

    func send(_ kind: BreakKind) async {
        let c = UNMutableNotificationContent()
        c.title = kind.title; c.body = kind.message; c.categoryIdentifier = "break"; c.userInfo = ["kind": kind.rawValue]
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions { [.banner] }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        guard r.actionIdentifier == "snooze", let raw = r.notification.request.content.userInfo["kind"] as? String, let k = BreakKind(rawValue: raw) else { return }
        onSnooze?(k)
    }
}

/// Keyboard and pointer lock for cleaning mode, via an event tap (needs Accessibility). Holding Esc ends it.
@MainActor
final class EventTapBlocker: InputBlocker {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var holdTimer: DispatchWorkItem?
    private var onExit: (@MainActor () -> Void)?

    var canBlock: Bool { AXIsProcessTrusted() }

    func start(onExitHeld: @escaping @MainActor () -> Void) -> Bool {
        onExit = onExitHeld
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return nil }
            let me = Unmanaged<EventTapBlocker>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { me.handle(type, event) }
            return nil // every event is swallowed
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: ~0,
                                        callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return }
        guard event.getIntegerValueField(.keyboardEventKeycode) == 53 else { return }
        if type == .keyDown, holdTimer == nil {
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.onExit?() } }
            holdTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(CleaningMode.exitHoldSeconds), execute: work)
        } else if type == .keyUp { holdTimer?.cancel(); holdTimer = nil }
    }

    func stop() {
        holdTimer?.cancel(); holdTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; onExit = nil
    }
}

/// One black window per screen while cleaning mode is on.
@MainActor
final class CleaningOverlay {
    private var windows: [NSWindow] = []

    func show(mode: CleaningMode) {
        hide()
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = .screenSaver; w.backgroundColor = .black; w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView: CleaningOverlayView(mode: mode))
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func hide() { windows.forEach { $0.orderOut(nil) }; windows = [] }
}
