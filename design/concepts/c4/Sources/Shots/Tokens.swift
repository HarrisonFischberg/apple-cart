import SwiftUI
import ConceptShared

// Contrast (checked by hand): secondary on tile >= 6:1, amber/blue/green text on tile >= 5.4:1 in both appearances.
enum T {
    static let ground = Color.adaptive(light: 0xF1F1F4, dark: 0x0B0B0D)
    static let tile = Color.adaptive(light: 0xFFFFFF, dark: 0x18181B)
    static let border = Color.primary.opacity(0.08)
    static let text = Color.adaptive(light: 0x111114, dark: 0xFFFFFF)
    static let secondary = Color.adaptive(light: 0x5B5B66, dark: 0xA1A1AA)
    static let track = Color.primary.opacity(0.12)
    static let amber = Color.adaptive(light: 0x8A5300, dark: 0xF5A524)
    static let amberFill = Color.adaptive(light: 0xFFF1D6, dark: 0x2B2008)
    static let amberText = Color.adaptive(light: 0x5C3600, dark: 0xFFD58A)
    static let amberBar = Color.adaptive(light: 0xC77700, dark: 0xF5A524)
    static let blue = Color.adaptive(light: 0x0A5ED7, dark: 0x5AB0FF)
    static let onBlue = Color.adaptive(light: 0xFFFFFF, dark: 0x0B0B0D)
    static let green = Color.adaptive(light: 0x177A3C, dark: 0x4ADE80)

    static let panelW: CGFloat = 420
    static let pad: CGFloat = 14
    static let gap: CGFloat = 12
    static let inner: CGFloat = panelW - pad * 2          // 392
    static let col: CGFloat = (inner - gap * 2) / 3        // 122.67
    static let headerH: CGFloat = 52

    static func switchStyle() -> PreviewSwitchStyle { PreviewSwitchStyle(tint: blue) }

    /// Panel height for a tile view: header + rows + gaps + bottom padding, capped by the shot rule.
    static func shotHeight(rows: [CGFloat]) -> CGFloat {
        let full = headerH + rows.reduce(0, +) + gap * CGFloat(rows.count - 1) + pad
        return full < 900 ? full : 680
    }
}

enum Span { case one, two, three
    var width: CGFloat { switch self { case .one: T.col; case .two: T.col * 2 + T.gap; case .three: T.inner } }
}

enum TileStyle { case normal, amber, off }

/// The one component every view is built from.
struct Tile<Content: View, Trailing: View>: View {
    let icon: String
    let title: String
    var span: Span = .one
    var style: TileStyle = .normal
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(style == .amber ? T.amber : T.secondary)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.92)
                    .foregroundStyle(style == .amber ? T.amberText : T.secondary)
                Spacer(minLength: 0)
                trailing
            }
            content
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .frame(width: span.width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(style == .amber ? T.amberFill : style == .off ? Color.clear : T.tile))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(style == .amber ? T.amber.opacity(0.7) : T.border,
                          style: StrokeStyle(lineWidth: 1, dash: style == .off ? [4, 3] : [])))
    }
}

extension Tile where Trailing == EmptyView {
    init(icon: String, title: String, span: Span = .one, style: TileStyle = .normal, @ViewBuilder content: () -> Content) {
        self.init(icon: icon, title: title, span: span, style: style, trailing: { EmptyView() }, content: content)
    }
}

struct Value: View {
    let text: String
    var suffix: String = ""
    var color: Color = T.text
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(text).font(.system(size: 24, weight: .semibold)).monospacedDigit()
            if !suffix.isEmpty { Text(suffix).font(.system(size: 12, weight: .medium)).monospacedDigit() }
        }
        .foregroundStyle(color).lineLimit(1)
    }
}

struct Caption: View {
    let text: String
    var color: Color = T.secondary
    init(_ t: String, color: Color = T.secondary) { text = t; self.color = color }
    var body: some View { Text(text).font(.system(size: 11)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true) }
}

/// 4 pt progress bar with an optional notch (limit marker).
struct Bar: View {
    let fraction: Double
    var marker: Double? = nil
    var tint: Color = T.blue
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(T.track).frame(height: 4)
                Capsule().fill(tint).frame(width: max(4, g.size.width * min(max(fraction, 0), 1)), height: 4)
                if let m = marker {
                    Capsule().fill(T.text).frame(width: 2, height: 10).offset(x: g.size.width * m - 1)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

struct TileRow<Content: View>: View {
    let height: CGFloat
    @ViewBuilder var content: Content
    var body: some View { HStack(spacing: T.gap) { content }.frame(height: height) }
}

struct Chip: View {
    let text: String
    var selected = false
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1).fixedSize()
            .padding(.horizontal, 9).frame(height: 28)
            .foregroundStyle(selected ? T.onBlue : T.text)
            .background(Capsule().fill(selected ? T.blue : Color.clear))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : T.border.opacity(2), lineWidth: 1))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SmallButton: View {
    let title: String
    var filled = false
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                .frame(maxWidth: .infinity).frame(height: 28)
                .foregroundStyle(filled ? T.onBlue : T.text)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(filled ? T.blue : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(filled ? Color.clear : T.border.opacity(2), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
