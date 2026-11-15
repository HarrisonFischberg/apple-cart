import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Core

@MainActor
final class SystemPasteboard: PasteboardAccess {
    private let board = NSPasteboard.general
    var changeCount: Int { board.changeCount }

    func snapshot() -> PasteboardSnapshot {
        let png = board.data(forType: .png) ?? board.data(forType: .tiff).flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        return PasteboardSnapshot(changeCount: board.changeCount, types: board.types?.map(\.rawValue) ?? [], text: board.string(forType: .string),
                                  imageData: png, sourceBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    func write(text: String) { board.clearContents(); board.setString(text, forType: .string) }
    func write(imageData: Data) { board.clearContents(); board.setData(imageData, forType: .png) }
    func clear() { board.clearContents() }

    func paste() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { // let the panel finish closing
            let src = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
                e?.flags = .maskCommand
                e?.post(tap: .cghidEventTap)
            }
        }
        return true
    }
}

/// One global shortcut, ⌃⌥⌘V: paste what is on the clipboard as plain text.
@MainActor
final class PlainPasteHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var action: (@MainActor () -> Void)?

    func register(_ action: @escaping @MainActor () -> Void) {
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { PlainPasteHotKey.action?() } }
            return noErr
        }, 1, &spec, nil, &handler)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: OSType(0x41434152), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil; handler = nil; Self.action = nil
    }
}
