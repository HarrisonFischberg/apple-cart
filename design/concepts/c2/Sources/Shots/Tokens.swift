import SwiftUI
import ConceptShared

/// C2 Rams tokens. Orange is spent only on the dial pointer, the active rail item and the pause state.
enum T {
    static let bg = Color.adaptive(light: 0xE4E6E5, dark: 0x161717)
    static let surface = Color.adaptive(light: 0xEEF0EF, dark: 0x202222)
    static let rail = Color.adaptive(light: 0xD9DCDB, dark: 0x0F1010)
    static let line = Color.adaptive(light: 0xB4B9B8, dark: 0x3A3D3D)
    static let ink = Color.adaptive(light: 0x181A1A, dark: 0xE8EAE9)
    static let ink2 = Color.adaptive(light: 0x4F5554, dark: 0x9BA2A0)
    static let orange = Color(hex: 0xF26A1B)
    /// Orange for text: darkened in light mode to hold 4.5:1.
    static let orangeText = Color.adaptive(light: 0xA33C06, dark: 0xF26A1B)
    static let onOrange = Color(hex: 0x181A1A)
    static let switchOn = Color.adaptive(light: 0x2A2D2D, dark: 0x8A9290)
    static let switchOff = Color.adaptive(light: 0xB4B9B8, dark: 0x3A3D3D)
    static let radius: CGFloat = 6
    static let hair: CGFloat = 0.5
}

/// Helvetica Neue, two weights only.
func hn(_ size: CGFloat, _ medium: Bool = false) -> Font {
    .custom(medium ? "HelveticaNeue-Medium" : "HelveticaNeue", size: size)
}

struct Hair: View {
    var body: some View { Rectangle().fill(T.line).frame(height: T.hair) }
}

struct VHair: View {
    var body: some View { Rectangle().fill(T.line).frame(width: T.hair) }
}

/// Grouped surface with a hairline border (native System Settings style).
struct Grouped<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(T.surface)
            .clipShape(RoundedRectangle(cornerRadius: T.radius))
            .overlay(RoundedRectangle(cornerRadius: T.radius).strokeBorder(T.line, lineWidth: T.hair))
    }
}

/// Label left, value right, on one baseline.
struct Reading: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(hn(12)).foregroundStyle(T.ink2)
            Spacer(minLength: 6)
            Text(value).font(hn(13, true)).foregroundStyle(T.ink).monospacedDigit()
        }
        .lineLimit(1)
        .frame(height: 22)
        .accessibilityElement(children: .combine)
    }
}

struct InkButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(hn(12, true))
            .foregroundStyle(filled ? T.bg : T.ink)
            .padding(.horizontal, 14).frame(height: 28)
            .background(filled ? T.ink : T.surface, in: RoundedRectangle(cornerRadius: T.radius))
            .overlay(RoundedRectangle(cornerRadius: T.radius).strokeBorder(T.line, lineWidth: filled ? 0 : T.hair))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

func switchStyle() -> PreviewSwitchStyle { PreviewSwitchStyle(tint: T.switchOn, offTrack: T.switchOff) }
