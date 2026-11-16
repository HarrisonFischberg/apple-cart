import AppKit
import Core
import SwiftUI

/// Hand-drawn badge shapes (plug, bolt, pause bars) on a 10 x 10 grid, scaled to fit any rect.
enum BadgeShape {
    static func path(_ badge: BatteryBadge, in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        switch badge {
        case .none: break
        case .plug:
            p.addRect(CGRect(x: 3, y: 8, width: 1.3, height: 2))
            p.addRect(CGRect(x: 5.7, y: 8, width: 1.3, height: 2))
            p.addRoundedRect(in: CGRect(x: 2, y: 4, width: 6, height: 4.4), cornerWidth: 1.2, cornerHeight: 1.2)
            p.addRect(CGRect(x: 4.3, y: 0, width: 1.4, height: 4.2))
        case .bolt:
            p.addLines(between: [CGPoint(x: 6.2, y: 10), CGPoint(x: 2, y: 5.4), CGPoint(x: 4.6, y: 5.4),
                                 CGPoint(x: 3.8, y: 0), CGPoint(x: 8, y: 5), CGPoint(x: 5.4, y: 5)])
            p.closeSubpath()
        case .paused:
            p.addRect(CGRect(x: 2, y: 1, width: 2.2, height: 8))
            p.addRect(CGRect(x: 5.8, y: 1, width: 2.2, height: 8))
        }
        let s = min(rect.width, rect.height) / 10
        let t = CGAffineTransform(translationX: rect.midX - 5 * s, y: rect.midY - 5 * s).scaledBy(x: s, y: s)
        return p.copy(using: [t]) ?? p
    }
}

/// The menu bar glyph as a template image, in one of five styles.
public enum BatteryGlyphImage {
    public static func make(_ g: BatteryGlyph, style: MenuBarGlyphStyle = .classic) -> NSImage {
        let size: NSSize
        switch style {
        case .classic, .solid: size = NSSize(width: 28, height: 13)
        case .segments: size = NSSize(width: 38, height: 13)
        case .ring: size = NSSize(width: 15, height: 15)
        case .slim: size = NSSize(width: 34, height: 13)
        }
        let img = NSImage(size: size, flipped: false) { _ in
            switch style {
            case .classic: drawClassic(g)
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

    private static let dim = NSColor.black.withAlphaComponent(0.55)

    private static func nub(x: CGFloat = 25.2) {
        dim.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: 4.2, width: 2, height: 4.6), xRadius: 1, yRadius: 1).fill()
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

    /// Outline, fill to the level, badge punched into the fill.
    private static func drawClassic(_ g: BatteryGlyph) {
        let body = NSRect(x: 0.75, y: 0.75, width: 23.5, height: 11.5)
        dim.setStroke()
        let outline = NSBezierPath(roundedRect: body, xRadius: 3.2, yRadius: 3.2)
        outline.lineWidth = 1.2
        outline.stroke()
        nub()
        let inner = body.insetBy(dx: 2, dy: 2)
        if g.level > 0 {
            NSColor.black.setFill()
            let w = max(inner.height, inner.width * g.level)
            NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: w, height: inner.height), xRadius: 1.6, yRadius: 1.6).fill()
        }
        badge(g.badge, in: inner.insetBy(dx: 5, dy: -0.4))
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
