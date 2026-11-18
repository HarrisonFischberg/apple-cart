import AppKit
import Core
import SwiftUI

/// Hand-drawn badge shapes (plug, bolt, pause bars) on a 10 x 10 grid, scaled to fit any rect.
enum BadgeShape {
    static func path(_ badge: BatteryBadge, in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        switch badge {
        case .none: break
        case .plugPaused, .plugBolt, .plugDrain: break
        case .plug: // big rounded head, small prongs, stubby tail
            p.addRect(CGRect(x: 2.8, y: 7.7, width: 1.3, height: 2.3))
            p.addRect(CGRect(x: 5.9, y: 7.7, width: 1.3, height: 2.3))
            p.addRoundedRect(in: CGRect(x: 1.4, y: 2.6, width: 7.2, height: 5.6), cornerWidth: 2, cornerHeight: 2)
            p.addRect(CGRect(x: 4.2, y: 0.4, width: 1.6, height: 2.4))
        case .bolt:
            p.addLines(between: [CGPoint(x: 6.0, y: 10), CGPoint(x: 2.4, y: 5.4), CGPoint(x: 4.6, y: 5.4),
                                 CGPoint(x: 4.0, y: 0), CGPoint(x: 7.6, y: 5), CGPoint(x: 5.4, y: 5)])
            p.closeSubpath()
        case .discharge: // a plain dash: running on the battery
            p.addRoundedRect(in: CGRect(x: 1.6, y: 4, width: 6.8, height: 2), cornerWidth: 1, cornerHeight: 1)
        case .drain: // an arrow pointing down: the battery is being drawn on
            p.addRect(CGRect(x: 4.1, y: 5.2, width: 1.8, height: 4.8))
            p.addLines(between: [CGPoint(x: 1.2, y: 5.6), CGPoint(x: 8.8, y: 5.6), CGPoint(x: 5, y: 0.2)])
            p.closeSubpath()
        case .paused:
            p.addRect(CGRect(x: 2, y: 1, width: 2.2, height: 8))
            p.addRect(CGRect(x: 5.8, y: 1, width: 2.2, height: 8))
        }
        if badge == .plugPaused || badge == .plugBolt || badge == .plugDrain {
            // two glyphs side by side on a 20 x 10 grid: a plug, then pause bars or a bolt
            let s = min(rect.width / 2, rect.height) / 10
            let t = CGAffineTransform(translationX: rect.midX - 10 * s, y: rect.midY - 5 * s)
            let rightKind: BatteryBadge = badge == .plugPaused ? .paused : badge == .plugDrain ? .drain : .bolt
            let left = path(.plug, in: CGRect(x: 0, y: 0, width: 10 * s, height: 10 * s)).copy(using: [t]) ?? CGMutablePath()
            let right = path(rightKind, in: CGRect(x: 10.4 * s, y: 0, width: 10 * s, height: 10 * s)).copy(using: [t]) ?? CGMutablePath()
            let all = CGMutablePath(); all.addPath(left); all.addPath(right)
            return all
        }
        let s = min(rect.width, rect.height) / 10
        let t = CGAffineTransform(translationX: rect.midX - 5 * s, y: rect.midY - 5 * s).scaledBy(x: s, y: s)
        return p.copy(using: [t]) ?? p
    }
}

/// An original apple (round body, stem, leaf, no bite) on a 100 x 100 grid, y pointing down.
enum AppleShape {
    /// Top and bottom of the body, for the fill line.
    static let bodyTop: CGFloat = 22, bodyBottom: CGFloat = 97.5
    /// Centre of the number inside the body.
    static let numberCenter = CGPoint(x: 50, y: 64)

    nonisolated(unsafe) static let body: CGPath = { // immutable once built
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 50, y: 30))
        p.addCurve(to: CGPoint(x: 86, y: 30), control1: CGPoint(x: 58, y: 22), control2: CGPoint(x: 74, y: 20))
        p.addCurve(to: CGPoint(x: 90, y: 78), control1: CGPoint(x: 98, y: 40), control2: CGPoint(x: 99, y: 62))
        p.addCurve(to: CGPoint(x: 66, y: 97), control1: CGPoint(x: 84, y: 90), control2: CGPoint(x: 75, y: 98))
        p.addCurve(to: CGPoint(x: 50, y: 94.5), control1: CGPoint(x: 60, y: 96.5), control2: CGPoint(x: 56, y: 94.5))
        p.addCurve(to: CGPoint(x: 34, y: 97), control1: CGPoint(x: 44, y: 94.5), control2: CGPoint(x: 40, y: 96.5))
        p.addCurve(to: CGPoint(x: 10, y: 78), control1: CGPoint(x: 25, y: 98), control2: CGPoint(x: 16, y: 90))
        p.addCurve(to: CGPoint(x: 14, y: 30), control1: CGPoint(x: 1, y: 62), control2: CGPoint(x: 2, y: 40))
        p.addCurve(to: CGPoint(x: 50, y: 30), control1: CGPoint(x: 26, y: 20), control2: CGPoint(x: 42, y: 22))
        p.closeSubpath()
        return p
    }()

    /// Stem and leaf as one filled shape.
    nonisolated(unsafe) static let leaf: CGPath = { // immutable once built
        let stem = CGMutablePath()
        stem.move(to: CGPoint(x: 49.5, y: 31))
        stem.addCurve(to: CGPoint(x: 53.5, y: 11), control1: CGPoint(x: 49.5, y: 23), control2: CGPoint(x: 50.5, y: 17))
        let p = CGMutablePath()
        p.addPath(stem.copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 4))
        p.move(to: CGPoint(x: 53, y: 19))
        p.addCurve(to: CGPoint(x: 79, y: 4), control1: CGPoint(x: 56, y: 8), control2: CGPoint(x: 66, y: 3))
        p.addCurve(to: CGPoint(x: 53, y: 19), control1: CGPoint(x: 77, y: 15), control2: CGPoint(x: 66, y: 21))
        p.closeSubpath()
        return p
    }()

    /// A small bolt where the leaf goes, while charging.
    nonisolated(unsafe) static let bolt: CGPath = { // immutable once built
        let p = CGMutablePath()
        p.addLines(between: [CGPoint(x: 70, y: 0), CGPoint(x: 56, y: 14), CGPoint(x: 64, y: 14),
                             CGPoint(x: 59.5, y: 25), CGPoint(x: 75.5, y: 10), CGPoint(x: 67.5, y: 10)])
        p.closeSubpath()
        return p
    }()

    /// Text as glyph outlines, centred on `center` in this y-down grid, so it can be cut out of the fill.
    static func textPath(_ text: String, size: CGFloat, center: CGPoint) -> CGPath {
        let base = NSFont.systemFont(ofSize: size, weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .kern: -size * 0.04]))
        let glyphs = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont // swiftlint:disable:this force_cast
            let n = CTRunGetGlyphCount(run)
            var ids = [CGGlyph](repeating: 0, count: n)
            var at = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(), &ids)
            CTRunGetPositions(run, CFRange(), &at)
            for i in 0..<n {
                if let g = CTFontCreatePathForGlyph(runFont, ids[i], nil) {
                    glyphs.addPath(g, transform: CGAffineTransform(translationX: at[i].x, y: at[i].y))
                }
            }
        }
        // Glyphs are y-up: flip, then centre the ink box on the point.
        let flipped = glyphs.copy(using: [CGAffineTransform(scaleX: 1, y: -1)]) ?? glyphs
        let box = flipped.boundingBoxOfPath
        let move = CGAffineTransform(translationX: center.x - box.midX, y: center.y - box.midY)
        return flipped.copy(using: [move]) ?? flipped
    }
}

/// The menu bar glyph as a template image, in one of six styles.
public enum BatteryGlyphImage {
    /// `number` puts the percentage inside the Apple style; it is off when there is no reading.
    public static func make(_ g: BatteryGlyph, style: MenuBarGlyphStyle = .classic, number: Bool = true) -> NSImage {
        if style == .apple { return makeApple(g, number: number) }
        // Only Classic has room for the two-glyph badges (plug with pause bars, plug with bolt).
        var g = g
        if style != .classic { g.badge = g.badge.single }
        let size: NSSize
        switch style {
        case .apple: size = .zero // drawn by makeApple
        case .classic: size = NSSize(width: 36 * classicScale, height: 17 * classicScale)
        case .solid: size = NSSize(width: 28, height: 13)
        case .segments: size = NSSize(width: 38, height: 13)
        case .ring: size = NSSize(width: 15, height: 15)
        case .slim: size = NSSize(width: 34, height: 13)
        }
        let img = NSImage(size: size, flipped: false) { _ in
            switch style {
            case .apple: break
            case .classic:
                NSGraphicsContext.current?.cgContext.scaleBy(x: classicScale, y: classicScale)
                drawClassic(g)
            case .solid: drawSolid(g)
            case .segments: drawSegments(g)
            case .ring: drawRing(g)
            case .slim: drawSlim(g)
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Battery"
        return img
    }

    /// An apple that fills from the bottom up, with the percentage cut out of the fill (solid where the fill has
    /// not reached). The leaf turns into a bolt while charging. Drawn on AppleShape's 100 x 100 grid.
    private static func makeApple(_ g: BatteryGlyph, number: Bool) -> NSImage {
        let side: CGFloat = 21
        let img = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            cg.scaleBy(x: side / 100, y: side / 100)
            drawApple(g, number: number, in: cg)
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = number ? "Battery \(Int((g.level * 100).rounded())) percent" : "Battery"
        return img
    }

    static func drawApple(_ g: BatteryGlyph, number: Bool, in cg: CGContext) {
        let level = CGFloat(min(max(g.level, 0), 1))
        let line = AppleShape.bodyBottom - (AppleShape.bodyBottom - AppleShape.bodyTop) * level
        let filled = CGRect(x: -10, y: line, width: 120, height: 120)
        let empty = CGRect(x: -10, y: -10, width: 120, height: line + 10)
        let ink = NSColor.black.cgColor
        // Empty part: a dim inside, so the outline reads as a full apple at any level.
        cg.saveGState()
        cg.addPath(AppleShape.body); cg.clip(); cg.clip(to: empty)
        cg.setFillColor(NSColor.black.withAlphaComponent(0.28).cgColor); cg.fill(empty)
        cg.restoreGState()
        cg.addPath(AppleShape.body)
        cg.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor); cg.setLineWidth(4); cg.strokePath()
        // Charged part: solid up to the fill line.
        cg.saveGState()
        cg.addPath(AppleShape.body); cg.clip()
        cg.setFillColor(ink); cg.fill(filled)
        cg.restoreGState()
        if number {
            let pct = Int((level * 100).rounded())
            let text = AppleShape.textPath("\(pct)%", size: pct >= 100 ? 27 : 32, center: AppleShape.numberCenter)
            // Cut out of the fill, solid over the empty part, so it reads wherever the fill line crosses it.
            cg.saveGState()
            cg.clip(to: filled); cg.addPath(text); cg.setBlendMode(.clear); cg.fillPath()
            cg.restoreGState()
            cg.saveGState()
            cg.clip(to: empty); cg.addPath(text); cg.setFillColor(ink); cg.fillPath()
            cg.restoreGState()
        }
        cg.addPath(g.badge.single == .bolt ? AppleShape.bolt : AppleShape.leaf)
        cg.setFillColor(ink); cg.fillPath()
    }

    /// Classic is drawn on a 36 x 17 grid and scaled down to its menu bar size.
    private static let classicScale: CGFloat = 0.88

    private static let dim = NSColor.black.withAlphaComponent(0.55)

    private static func nub(x: CGFloat = 25.2, midY: CGFloat = 6.5, height: CGFloat = 4.6) {
        dim.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: midY - height / 2, width: 2, height: height), xRadius: 1, yRadius: 1).fill()
    }

    /// A badge with a clear halo so it stays readable on top of a fill.
    private static func badge(_ b: BatteryBadge, in rect: NSRect, halo: Bool = true) {
        guard b != .none else { return }
        let path = NSBezierPath(cgPath: BadgeShape.path(b, in: rect))
        if halo {
            NSGraphicsContext.current?.compositingOperation = .clear
            path.lineWidth = 2.4
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }
        NSColor.black.setFill()
        path.fill()
    }

    /// Thin outline, fill close to it, and the badge cut out of the fill. Where the charge is too low for
    /// the fill to reach the badge, it sits solid in the empty part instead.
    private static func drawClassic(_ g: BatteryGlyph) {
        // A larger battery than before, with the badge filling most of the body.
        let body = NSRect(x: 0.6, y: 0.5, width: 31.5, height: 16)
        NSColor.black.withAlphaComponent(0.7).setStroke()
        let outline = NSBezierPath(roundedRect: body.insetBy(dx: 0.7, dy: 0.7), xRadius: 4.6, yRadius: 4.6)
        outline.lineWidth = 1.4
        outline.stroke()
        nub(x: body.maxX + 1, midY: body.midY, height: 6)
        let inner = body.insetBy(dx: 2.6, dy: 2.4)
        var edge = inner.minX
        // Plugged in (plug with pause bars or a bolt) and on battery (a dash) both draw a clear, hollow body with the
        // badge as solid ink; the percentage text carries the level.
        let hollow = g.badge == .discharge || g.badge.isWide
        if g.level > 0 && !hollow {
            NSColor.black.setFill()
            let w = max(inner.height, inner.width * g.level)
            edge = inner.minX + w
            NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: w, height: inner.height), xRadius: 2.2, yRadius: 2.2).fill()
        }
        guard g.badge != .none else { return }
        // The two-glyph badge only fits inside a nearly full fill; on a lower charge it shrinks to one glyph.
        let wideFits = g.badge.isWide && (hollow || edge >= body.midX + inner.height * 0.95 + 1)
        let kind = g.badge.isWide && !wideFits ? g.badge.single : g.badge
        let box = NSRect(x: 0, y: 0, width: kind.isWide ? inner.height * 1.9 : inner.height, height: inner.height)
        // On a low charge the badge goes in the middle of the empty part so it is never half cut.
        let cx = hollow || edge >= body.midX + box.width / 2 + 1 ? body.midX : (edge + inner.maxX) / 2
        let path = NSBezierPath(cgPath: BadgeShape.path(kind, in: box.offsetBy(dx: cx - box.midX, dy: inner.midY - box.midY)))
        if hollow {
            NSColor.black.setFill()
            path.fill()
        } else if cx == body.midX && g.level > 0 {
            NSGraphicsContext.current?.compositingOperation = .clear
            path.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        } else {
            NSColor.black.withAlphaComponent(0.85).setFill()
            path.fill()
        }
    }

    /// A solid body: the charged part is full black, the rest is dim, and the badge is cut out of it.
    private static func drawSolid(_ g: BatteryGlyph) {
        let body = NSRect(x: 0.5, y: 0.5, width: 24, height: 12)
        let shape = NSBezierPath(roundedRect: body, xRadius: 3.4, yRadius: 3.4)
        dim.withAlphaComponent(0.35).setFill()
        shape.fill()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSColor.black.setFill()
        NSRect(x: body.minX, y: body.minY, width: body.width * g.level, height: body.height).fill()
        NSGraphicsContext.restoreGraphicsState()
        nub()
        if g.badge != .none {
            let path = NSBezierPath(cgPath: BadgeShape.path(g.badge, in: body.insetBy(dx: 7.5, dy: 1.6)))
            NSGraphicsContext.current?.compositingOperation = .clear
            path.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }
    }

    /// The badge sits outside on the left; the battery is five bars that fill with the charge.
    private static func drawSegments(_ g: BatteryGlyph) {
        badge(g.badge, in: NSRect(x: 0, y: 1.5, width: 10, height: 10), halo: false)
        let x0: CGFloat = 12
        let body = NSRect(x: x0 + 0.5, y: 0.75, width: 23.5, height: 11.5)
        dim.setStroke()
        let outline = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
        outline.lineWidth = 1.1
        outline.stroke()
        nub(x: x0 + 25)
        let lit = Int((g.level * 5).rounded(.up))
        for i in 0..<5 {
            let r = NSRect(x: x0 + 2.6 + CGFloat(i) * 4.1, y: 3, width: 3.1, height: 7)
            (i < lit ? NSColor.black : dim.withAlphaComponent(0.25)).setFill()
            NSBezierPath(roundedRect: r, xRadius: 0.9, yRadius: 0.9).fill()
        }
    }

    /// A round gauge with the badge in the middle.
    private static func drawRing(_ g: BatteryGlyph) {
        let c = CGPoint(x: 7.5, y: 7.5)
        let ring = NSBezierPath(ovalIn: NSRect(x: 1.25, y: 1.25, width: 12.5, height: 12.5))
        ring.lineWidth = 1.6
        dim.withAlphaComponent(0.4).setStroke()
        ring.stroke()
        if g.level > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: 6.25, startAngle: 90, endAngle: 90 - 360 * g.level, clockwise: true)
            arc.lineWidth = 1.6
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
        }
        badge(g.badge, in: NSRect(x: 3.7, y: 3.7, width: 7.6, height: 7.6), halo: false)
    }

    /// A thin capsule bar with the badge in front.
    private static func drawSlim(_ g: BatteryGlyph) {
        badge(g.badge, in: NSRect(x: 0, y: 1.5, width: 10, height: 10), halo: false)
        let track = NSRect(x: 12, y: 4.5, width: 21.5, height: 4)
        dim.withAlphaComponent(0.4).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        if g.level > 0 {
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: max(4, track.width * g.level), height: track.height), xRadius: 2, yRadius: 2).fill()
        }
    }
}

/// SwiftUI badge for the panel (shapes are y-up, so flip).
struct BadgeGlyph: View {
    let badge: BatteryBadge
    var body: some View {
        GeometryReader { geo in Path(BadgeShape.path(badge, in: CGRect(origin: .zero, size: geo.size))) }
            .scaleEffect(x: 1, y: -1)
    }
}
