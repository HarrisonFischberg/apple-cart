import SwiftUI
import ConceptShared

enum T {
    static let yellow = Color(hex: 0xFFC800)
    static let onYellow = Color(hex: 0x16150F)
    static let ground = Color.adaptive(light: 0xF4F3EE, dark: 0x1E1E1C)
    static let well = Color.adaptive(light: 0xE6E4DA, dark: 0x2B2B28)
    static let ink = Color.adaptive(light: 0x16150F, dark: 0xF1F0EA)
    static let ink2 = Color.adaptive(light: 0x55534A, dark: 0xB6B4AA)
    static let rule = Color.adaptive(light: 0xCFCDC1, dark: 0x3C3C37)
    static let red = Color.adaptive(light: 0xC22314, dark: 0xFF7A66)
    static let redWash = Color.adaptive(light: 0xF8E1DC, dark: 0x3A2420)
    static let yellowWash = Color.adaptive(light: 0xFFE98A, dark: 0x4A3F10)
    static let lockFill = ink
    static let lockText = ground

    static func din(_ size: CGFloat) -> Font { .custom("DIN Condensed Bold", size: size) }
    static let label = Font.system(size: 13)
    static let small = Font.system(size: 11)
    static let pad: CGFloat = 16
}

struct Rule: View {
    var body: some View { Rectangle().fill(T.rule).frame(height: 1) }
}

/// Section title: plain heading, more space above than below.
struct Heading: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(T.ink)
            Spacer()
            if let trailing { Text(trailing).font(T.small).foregroundStyle(T.ink2) }
        }
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(T.onYellow)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(T.yellow.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(T.ink)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(T.well.opacity(configuration.isPressed ? 0.6 : 1)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.ink2.opacity(0.5), lineWidth: 1))
    }
}

/// Plot with axis labels: y labels on the left, x labels below. Content draws in unit space (0...1, y up).
struct AxisChart<Content: View>: View {
    let yLabels: [(Double, String)]      // (0...1, text)
    let xLabels: [(Double, String)]      // (0...1, text)
    var height: CGFloat = 70
    var yWidth: CGFloat = 34
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .top, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    ForEach(yLabels.indices, id: \.self) { i in
                        Text(yLabels[i].1).font(T.small).foregroundStyle(T.ink2)
                            .position(x: yWidth - 12, y: min(max(height * (1 - yLabels[i].0), 7), height - 7))
                    }
                }
                .frame(width: yWidth, height: height)
                ZStack { content() }
                    .frame(height: height)
                    .background(T.well.opacity(0.5))
            }
            HStack(spacing: 6) {
                Color.clear.frame(width: yWidth, height: 14)
                GeometryReader { g in
                    ForEach(xLabels.indices, id: \.self) { i in
                        let f = xLabels[i].0
                        Text(xLabels[i].1).font(T.small).foregroundStyle(T.ink2).fixedSize()
                            .position(x: min(max(g.size.width * f, 14), g.size.width - (f >= 1 ? 14 : 0)),
                                      y: 7)
                    }
                }
                .frame(height: 14)
            }
        }
    }
}
