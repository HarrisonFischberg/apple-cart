import AppKit
import CoreImage.CIFilterBuiltins
import Foundation
import Testing
@testable import Core

private func textImage(_ s: String) -> CGImage {
    let size = NSSize(width: 600, height: 120)
    let img = NSImage(size: size)
    img.lockFocus()
    NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
    (s as NSString).draw(at: NSPoint(x: 20, y: 30), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
    img.unlockFocus()
    return img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

private func qrImage(_ s: String) -> CGImage {
    let f = CIFilter.qrCodeGenerator(); f.message = Data(s.utf8)
    let scaled = f.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    let padded = scaled.composited(over: CIImage(color: .white).cropped(to: scaled.extent.insetBy(dx: -40, dy: -40)))
    return CIContext().createCGImage(padded, from: padded.extent)!
}

@MainActor private final class FakePicker: RegionSelecting {
    var region: ScreenRegion? = ScreenRegion(displayID: 1, rect: CGRect(x: 0, y: 0, width: 50, height: 50))
    func pickRegion() async -> ScreenRegion? { region }
}
@MainActor private final class FakeCapture: ScreenCapturing {
    var image: CGImage = textImage("x"); var error: CaptureFailure?
    func capture(_ r: ScreenRegion) async throws -> CGImage { if let error { throw error }; return image }
}
private struct FakeRecognizer: ImageRecognizing {
    var t = "", c: [String] = []
    func text(in image: CGImage) async -> String { t }
    func codes(in image: CGImage) async -> [String] { c }
}
@MainActor private final class Board: PasteboardAccess {
    var changeCount = 0, text: String?
    func snapshot() -> PasteboardSnapshot { .init(changeCount: changeCount, text: text) }
    func write(text: String) { self.text = text; changeCount += 1 }
    func write(imageData: Data) {}; func clear() { text = nil }; func paste() -> Bool { true }
}

@MainActor
@Suite struct ScreenReadingTests {
    @Test func visionReadsTextOffline() async {
        let t = await VisionRecognizer().text(in: textImage("Hello Apple Cart"))
        #expect(t.contains("Hello") && t.contains("Cart"), "got: \(t)")
    }

    @Test func visionReadsAQRCode() async {
        let c = await VisionRecognizer().codes(in: qrImage("https://example.com/hi"))
        #expect(c == ["https://example.com/hi"])
    }

    @Test func textIsCopiedAndToasted() async {
        let b = Board(); var toasts: [String] = []
        let r = ScreenReader(picker: FakePicker(), capturer: FakeCapture(), recognizer: FakeRecognizer(t: " hi there \n"), pasteboard: b, toast: { toasts.append($0) })
        await r.run(.text)
        #expect(b.text == "hi there" && r.last == .text("hi there") && toasts == ["Copied text."] && r.phase == .idle)
    }

    @Test func codesAreCopiedOnePerLine() async {
        let b = Board()
        let r = ScreenReader(picker: FakePicker(), capturer: FakeCapture(), recognizer: FakeRecognizer(c: ["a", "b"]), pasteboard: b, toast: { _ in })
        await r.run(.qr)
        #expect(b.text == "a\nb" && r.last == .codes(["a", "b"]))
    }

    @Test func nothingFoundLeavesTheClipboardAlone() async {
        let b = Board(); b.text = "keep"; var toasts: [String] = []
        let r = ScreenReader(picker: FakePicker(), capturer: FakeCapture(), recognizer: FakeRecognizer(), pasteboard: b, toast: { toasts.append($0) })
        await r.run(.text); await r.run(.qr)
        #expect(b.text == "keep" && toasts == ["No text found.", "No QR code found."])
    }

    @Test func cancelledPickDoesNothingAndDeniedPermissionShowsTheFix() async {
        let b = Board(); let p = FakePicker(); let c = FakeCapture(); var toasts: [String] = []
        let r = ScreenReader(picker: p, capturer: c, recognizer: FakeRecognizer(t: "x"), pasteboard: b, toast: { toasts.append($0) })
        p.region = nil; await r.run(.text)
        #expect(r.phase == .idle && toasts.isEmpty && b.text == nil)
        p.region = ScreenRegion(displayID: 1, rect: .init(x: 0, y: 0, width: 9, height: 9)); c.error = .notAllowed
        await r.run(.text)
        #expect(r.phase == .needsPermission && toasts == ["Screen Recording is off for Apple Cart."] && b.text == nil)
    }
}
