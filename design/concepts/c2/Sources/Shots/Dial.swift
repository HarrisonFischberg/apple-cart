import SwiftUI
import AppKit

/// The charge limit as a printed round dial: scale 0-100 over 270 degrees, ink charge arc, one orange pointer.
struct Dial: View {
    @Binding var limit: Int
    let charge: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    private let size: CGFloat = 170

    private func deg(_ v: Double) -> Double { -135 + v / 100 * 270 }
    private func pt(_ degrees: Double, _ r: CGFloat) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: size / 2 + r * CGFloat(sin(a)), y: size / 2 - r * CGFloat(cos(a)))
    }

    private func set(_ v: Int) {
        let n = min(max(v, 20), 100)
        guard n != limit else { return }
        limit = n
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                for i in 0...100 {
                    let major = i % 5 == 0
                    var p = Path()
                    p.move(to: pt(deg(Double(i)), major ? 68 : 72))
                    p.addLine(to: pt(deg(Double(i)), 76))
                    ctx.stroke(p, with: .color(major ? T.ink : T.ink2), lineWidth: major ? 1 : 0.5)
                }
                for n in stride(from: 20, through: 100, by: 20) {
                    ctx.draw(Text("\(n)").font(hn(11)).foregroundColor(T.ink2), at: pt(deg(Double(n)), 50))
                }
                func arc(to v: Double) -> Path {
                    var p = Path()
                    for d in stride(from: 0.0, through: v, by: 1) {
                        let q = pt(deg(d), 62)
                        d == 0 ? p.move(to: q) : p.addLine(to: q)
                    }
                    p.addLine(to: pt(deg(v), 62))
                    return p
                }
                ctx.stroke(arc(to: 100), with: .color(T.line), lineWidth: 1)
                ctx.stroke(arc(to: charge), with: .color(T.ink), style: StrokeStyle(lineWidth: 3, lineCap: .butt))
            }
            .frame(width: size, height: size)

            // Pointer is a view so it rotates smoothly; with Reduce Motion it snaps.
            Capsule().fill(T.orange).frame(width: 3, height: 26)
                .offset(y: -69)
                .rotationEffect(.degrees(deg(Double(limit))))
                .animation(reduceMotion ? nil : .spring(duration: 0.25), value: limit)

            VStack(spacing: 0) {
                Text("\(limit)%").font(hn(26, true)).foregroundStyle(T.ink).monospacedDigit()
                Text("Charge limit").font(hn(11)).foregroundStyle(T.ink2)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            var d = atan2(g.location.x - size / 2, -(g.location.y - size / 2)) * 180 / .pi
            if d < -135 { d = d < -157.5 ? 135 : -135 }
            if d > 135 { d = d > 157.5 ? -135 : 135 }
            set(Int((((d + 135) / 270 * 100) / 5).rounded()) * 5)
        })
        .focusable()
        .focused($focused)
        .onKeyPress(.leftArrow) { set(limit - 5); return .handled }
        .onKeyPress(.downArrow) { set(limit - 5); return .handled }
        .onKeyPress(.rightArrow) { set(limit + 5); return .handled }
        .onKeyPress(.upArrow) { set(limit + 5); return .handled }
        .accessibilityElement()
        .accessibilityLabel("Charge limit")
        .accessibilityValue("\(limit) percent")
        .accessibilityAdjustableAction { dir in set(limit + (dir == .increment ? 5 : -5)) }
    }
}
