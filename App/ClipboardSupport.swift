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

/// Global shortcuts (⌃⌥⌘ + a letter). Each tool adds its own and removes it when it is turned off.
@MainActor
final class HotKeyCenter {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var handler: EventHandlerRef?

    func add(id: UInt32, key: Int, _ action: @escaping @MainActor () -> Void) {
        install()
        remove(id: id)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: OSType(0x41434152), id: id),
                            GetApplicationEventTarget(), 0, &ref)
        if let ref { refs[id] = ref; actions[id] = action }
    }

    func remove(id: UInt32) {
        if let r = refs.removeValue(forKey: id) { UnregisterEventHotKey(r) }
        actions[id] = nil
    }

    private func install() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard let userData else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { center.actions[hk.id]?() } }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}
