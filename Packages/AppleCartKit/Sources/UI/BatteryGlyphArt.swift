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

/// The menu bar glyph as a template image: outline, fill to the charge level, badge punched into the fill.
public enum BatteryGlyphImage {
    public static func make(_ g: BatteryGlyph) -> NSImage {
        let img = NSImage(size: NSSize(width: 28, height: 13), flipped: false) { _ in
            let body = NSRect(x: 0.75, y: 0.75, width: 23.5, height: 11.5)
            NSColor.black.withAlphaComponent(0.55).setStroke()
            let outline = NSBezierPath(roundedRect: body, xRadius: 3.2, yRadius: 3.2)
            outline.lineWidth = 1.2
            outline.stroke()
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: NSRect(x: 25.2, y: 4.2, width: 2, height: 4.6), xRadius: 1, yRadius: 1).fill()
            let inner = body.insetBy(dx: 2, dy: 2)
            if g.level > 0 {
                NSColor.black.setFill()
                let w = max(inner.height, inner.width * g.level)
                NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: w, height: inner.height),
                             xRadius: 1.6, yRadius: 1.6).fill()
            }
            if g.badge != .none {
                let badge = NSBezierPath(cgPath: BadgeShape.path(g.badge, in: inner.insetBy(dx: 5, dy: -0.4)))
                // A clear halo keeps the badge readable where it sits on the fill.
                NSGraphicsContext.current?.compositingOperation = .clear
                badge.lineWidth = 2.4
                badge.lineJoinStyle = .round
                NSColor.black.setStroke()
                badge.stroke()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                badge.fill()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Battery"
        return img
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
