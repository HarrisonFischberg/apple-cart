import AppKit
import Carbon.HIToolbox
import Core

/// Turning the tool off ends any session and releases the assertion.
@MainActor
final class KeepAwakeTool: Tool {
    private let keepAwake: KeepAwake
    init(_ keepAwake: KeepAwake) { self.keepAwake = keepAwake }
    func start() {}
    func stop() { keepAwake.stop(reason: "Tool turned off") }
}

/// The system monitor needs no setup: views hold and release its sampler.
@MainActor
final class SystemTool: Tool {
    func start() {}
    func stop() {}
}

/// Quick toggles read the system when shown; nothing runs in the background.
@MainActor
final class QuickTogglesTool: Tool {
    func start() {}
    func stop() {}
}

/// Update checks and DNS flush run only when the user presses a button.
@MainActor
final class OnDemandTool: Tool {
    func start() {}
    func stop() {}
}

@MainActor
final class WorkspaceRunningApps: RunningApps {
    func isRunning(_ bundleID: String) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    func quit(_ bundleID: String) { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() } }
}

/// Starts the clipboard poll and the plain-paste shortcut together; stopping removes both.
@MainActor
final class ClipboardTool: Tool {
    private let history: ClipboardHistory, keys: HotKeyCenter
    init(_ history: ClipboardHistory, keys: HotKeyCenter) { self.history = history; self.keys = keys }
    func start() { history.start(); keys.add(id: 1, key: kVK_ANSI_V) { [history] in if !history.pastePlainCurrent() { NSSound.beep() } } }
    func stop() { history.stop(); keys.remove(id: 1) }
}

/// Screen text (⌃⌥⌘T) and QR (⌃⌥⌘Q) readers: the shortcut exists only while the tool is on.
@MainActor
final class ScreenReadTool: Tool {
    private let reader: ScreenReader, keys: HotKeyCenter, id: UInt32, key: Int, mode: ScreenReader.Mode
    init(_ reader: ScreenReader, keys: HotKeyCenter, id: UInt32, key: Int, mode: ScreenReader.Mode) {
        self.reader = reader; self.keys = keys; self.id = id; self.key = key; self.mode = mode
    }
    func start() { keys.add(id: id, key: key) { [reader, mode] in Task { await reader.run(mode) } } }
    func stop() { keys.remove(id: id) }
}
