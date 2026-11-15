import CoreGraphics
import Foundation
import Observation
import Vision

/// A rectangle the user dragged, in points on one display, origin top-left.
public struct ScreenRegion: Sendable, Equatable {
    public let displayID: UInt32, rect: CGRect
    public init(displayID: UInt32, rect: CGRect) { self.displayID = displayID; self.rect = rect }
}

public enum CaptureFailure: Error, Sendable { case notAllowed, failed }

@MainActor
public protocol RegionSelecting: AnyObject {
    /// nil when the user cancels (Esc or a click without a drag).
    func pickRegion() async -> ScreenRegion?
}

@MainActor
public protocol ScreenCapturing: AnyObject {
    func capture(_ region: ScreenRegion) async throws -> CGImage
}

public protocol ImageRecognizing: Sendable {
    func text(in image: CGImage) async -> String
    func codes(in image: CGImage) async -> [String]
}

/// Apple's Vision framework: runs on the Mac, nothing is sent anywhere.
public struct VisionRecognizer: ImageRecognizing {
    public init() {}

    public func text(in image: CGImage) async -> String {
        await Task.detached {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(cgImage: image).perform([req])
            let lines = (req.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY } // top to bottom
            return lines.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }

    public func codes(in image: CGImage) async -> [String] {
        await Task.detached {
            let req = VNDetectBarcodesRequest()
            try? VNImageRequestHandler(cgImage: image).perform([req])
            return (req.results ?? []).compactMap(\.payloadStringValue)
        }.value
    }
}

@MainActor @Observable
public final class ScreenReader {
    public enum Mode: Sendable { case text, qr }
    public enum Outcome: Equatable, Sendable { case text(String), codes([String]), nothing(Mode) }
    public enum Phase: Equatable { case idle, working, needsPermission, failed }
    public private(set) var phase: Phase = .idle
    public private(set) var last: Outcome?
    @ObservationIgnored private let picker: RegionSelecting
    @ObservationIgnored private let capturer: ScreenCapturing
    @ObservationIgnored private let recognizer: ImageRecognizing
    @ObservationIgnored private let pasteboard: PasteboardAccess
    @ObservationIgnored private let toast: @MainActor (String) -> Void

    public init(picker: RegionSelecting, capturer: ScreenCapturing, recognizer: ImageRecognizing = VisionRecognizer(),
                pasteboard: PasteboardAccess, toast: @escaping @MainActor (String) -> Void) {
        self.picker = picker; self.capturer = capturer; self.recognizer = recognizer; self.pasteboard = pasteboard; self.toast = toast
    }

    /// Pick an area, read it, copy the result. The image is never saved.
    public func run(_ mode: Mode) async {
        guard phase != .working else { return }
        phase = .working
        defer { if phase == .working { phase = .idle } }
        guard let region = await picker.pickRegion() else { return }
        let image: CGImage
        do { image = try await capturer.capture(region) }
        catch CaptureFailure.notAllowed { phase = .needsPermission; toast("Screen Recording is off for Apple Cart."); return }
        catch { phase = .failed; toast("Could not read the screen."); return }
        switch mode {
        case .text:
            let t = await recognizer.text(in: image).trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { last = .nothing(.text); toast("No text found."); return }
            pasteboard.write(text: t); last = .text(t); toast("Copied text.")
        case .qr:
            let c = await recognizer.codes(in: image)
            if c.isEmpty { last = .nothing(.qr); toast("No QR code found."); return }
            pasteboard.write(text: c.joined(separator: "\n")); last = .codes(c); toast(c.count == 1 ? "Copied code." : "Copied \(c.count) codes.")
        }
    }
}
