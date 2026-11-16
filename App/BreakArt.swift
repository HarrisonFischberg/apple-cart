import SwiftUI
import Core

/// Original banner pictures for each break, drawn here so no stock art or icon font is needed.
struct BreakArt: View {
    let kind: BreakKind

    var body: some View {
        ZStack {
            LinearGradient(colors: kind.sky, startPoint: .top, endPoint: .bottom)
            switch kind {
            case .eyes: eyes
            case .stretch: outdoors
            case .water: droplet
            }
        }
        .frame(width: 256, height: 256)
    }

    /// Just an eyeball.
    private var eyes: some View {
        ZStack {
            Ellipse().fill(.white).frame(width: 196, height: 112)
            Circle().fill(Color(red: 0.16, green: 0.42, blue: 0.78)).frame(width: 84, height: 84)
            Circle().fill(.black).frame(width: 36, height: 36)
            Circle().fill(.white.opacity(0.9)).frame(width: 14, height: 14).offset(x: -10, y: -12)
        }
    }

    /// Mountains and a sun.
    private var outdoors: some View {
        ZStack {
            Circle().fill(.yellow).frame(width: 52, height: 52).position(x: 196, y: 58)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 200)); p.addLine(to: CGPoint(x: 80, y: 90)); p.addLine(to: CGPoint(x: 150, y: 190))
                p.addLine(to: CGPoint(x: 190, y: 130)); p.addLine(to: CGPoint(x: 256, y: 210)); p.addLine(to: CGPoint(x: 256, y: 256))
                p.addLine(to: CGPoint(x: 0, y: 256)); p.closeSubpath()
            }.fill(Color(red: 0.25, green: 0.45, blue: 0.40))
            Path { p in
                p.move(to: CGPoint(x: 80, y: 90)); p.addLine(to: CGPoint(x: 62, y: 118)); p.addLine(to: CGPoint(x: 80, y: 112)); p.addLine(to: CGPoint(x: 96, y: 120)); p.closeSubpath()
            }.fill(.white)
            Rectangle().fill(Color(red: 0.18, green: 0.34, blue: 0.30)).frame(width: 256, height: 56).position(x: 128, y: 228)
        }
    }

    /// A single water droplet.
    private var droplet: some View {
        Path { p in
            p.move(to: CGPoint(x: 128, y: 40))
            p.addCurve(to: CGPoint(x: 190, y: 150), control1: CGPoint(x: 150, y: 80), control2: CGPoint(x: 190, y: 108))
            p.addCurve(to: CGPoint(x: 128, y: 216), control1: CGPoint(x: 190, y: 190), control2: CGPoint(x: 160, y: 216))
            p.addCurve(to: CGPoint(x: 66, y: 150), control1: CGPoint(x: 96, y: 216), control2: CGPoint(x: 66, y: 190))
            p.addCurve(to: CGPoint(x: 128, y: 40), control1: CGPoint(x: 66, y: 108), control2: CGPoint(x: 106, y: 80))
            p.closeSubpath()
        }
        .fill(.white.opacity(0.95))
        .overlay(Ellipse().fill(Color(red: 0.55, green: 0.85, blue: 1.0).opacity(0.8)).frame(width: 18, height: 36).rotationEffect(.degrees(20)).position(x: 100, y: 152))
    }
}

private extension BreakKind {
    var sky: [Color] {
        switch self {
        case .eyes: [Color(red: 0.31, green: 0.52, blue: 0.86), Color(red: 0.70, green: 0.82, blue: 0.96)]
        case .stretch: [Color(red: 0.98, green: 0.62, blue: 0.40), Color(red: 1.0, green: 0.86, blue: 0.62)]
        case .water: [Color(red: 0.18, green: 0.55, blue: 0.80), Color(red: 0.42, green: 0.80, blue: 0.90)]
        }
    }
}

/// Writes each break's picture to a PNG once and hands back its URL for the banner.
@MainActor
enum BreakArtFiles {
    private static var cache: [BreakKind: URL] = [:]

    static func url(for kind: BreakKind) -> URL? {
        if let u = cache[kind], FileManager.default.fileExists(atPath: u.path) { return u }
        let r = ImageRenderer(content: BreakArt(kind: kind)); r.scale = 2
        guard let png = r.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:]) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("applecart-break-art", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("\(kind.rawValue).png")
        guard (try? png.write(to: u)) != nil else { return nil }
        cache[kind] = u
        return u
    }
}
