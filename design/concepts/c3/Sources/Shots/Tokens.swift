import SwiftUI
import ConceptShared

/// C3 Course inks. Purple is reserved for the plan (limit, controls, schedule).
enum T {
    static let ground = Color.adaptive(light: 0xFBFBF7, dark: 0x131A16)
    static let ink = Color.adaptive(light: 0x1B241E, dark: 0xE8EEE9)
    static let ink2 = Color.adaptive(light: 0x56625A, dark: 0xA7B4AB)
    static let hair = Color.adaptive(light: 0xD6D9CE, dark: 0x2B372F)
    static let contour = Color.adaptive(light: 0xC0722F, dark: 0xD08A4F)

    static let blueText = Color.adaptive(light: 0x1D63B3, dark: 0x7DB9F4)
    static let blueFill = Color.adaptive(light: 0x2D7FD6, dark: 0x4A96E0)
    static let blueSolid = Color.adaptive(light: 0x1F6BBF, dark: 0x5BA6EE)   // fill under text
    static let onBlue = Color.adaptive(light: 0xFFFFFF, dark: 0x0B1410)

    static let oliveText = Color.adaptive(light: 0x566310, dark: 0xC9D76E)
    static let oliveFill = Color.adaptive(light: 0x8A9A2B, dark: 0xA3B53A)

    static let yellow = Color.adaptive(light: 0xF2C400, dark: 0xF2CF3D)

    static let purple = Color.adaptive(light: 0xB5238C, dark: 0xE580C6)
    static let onPurple = Color.adaptive(light: 0xFFFFFF, dark: 0x131A16)

    static func num(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom("Avenir Next Condensed", size: size).weight(weight)
    }
}

enum ControlStyle { case done, active, future }

/// Numbered control circle: done = ring, active = filled, future = dashed.
struct ControlMark: View {
    let n: Int
    let style: ControlStyle
    var size: CGFloat = 18
    var body: some View {
        ZStack {
            switch style {
            case .active:
                Circle().fill(T.purple)
            case .done:
                Circle().fill(T.ground)
                Circle().strokeBorder(T.purple, lineWidth: 1.5)
            case .future:
                Circle().strokeBorder(T.purple, style: StrokeStyle(lineWidth: 1.3, dash: [2.5, 2]))
            }
            Text("\(n)").font(T.num(size * 0.66, .bold))
                .foregroundStyle(style == .active ? T.onPurple : T.purple)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Contour hairlines: the chart's ground, nothing else.
func drawContours(_ ctx: inout GraphicsContext, in r: CGRect) {
    var c = ctx
    c.clip(to: Path(r))
    for k in 0..<8 {
        var p = Path()
        let y0 = r.minY + CGFloat(k) * r.height / 7
        var x = r.minX
        while x <= r.maxX {
            let y = y0 + 8 * sin(Double(x) * 0.028 + Double(k) * 0.9) + 5 * sin(Double(x) * 0.011 + Double(k) * 2.1)
            if x == r.minX { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            x += 3
        }
        c.stroke(p, with: .color(T.contour.opacity(k % 4 == 0 ? 0.34 : 0.2)), lineWidth: k % 4 == 0 ? 0.8 : 0.5)
    }
}
