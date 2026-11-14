import SwiftUI

public extension Color {
    /// 0xRRGGBB
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A color that switches with the window appearance: `Color.adaptive(light: 0xF2F2EF, dark: 0x1B1B19)`.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }))
    }
}

/// Stand-in for the native macOS switch, drawn in SwiftUI so the preview harness shows the concept's tint.
/// (Offscreen windows are never "active", so a real `Toggle` renders gray in screenshots.)
/// Production uses the native `Toggle` with `.tint(...)`; keep this the same size: 38 x 22.
public struct PreviewSwitchStyle: ToggleStyle {
    let tint: Color
    let offTrack: Color
    public init(tint: Color, offTrack: Color = Color.primary.opacity(0.18)) {
        self.tint = tint; self.offTrack = offTrack
    }
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 8)
            Button { configuration.isOn.toggle() } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? tint : offTrack)
                    Circle().fill(.white).padding(2)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                }
                .frame(width: 38, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityValue(configuration.isOn ? "on" : "off")
            .accessibilityAddTraits(.isToggle)
        }
    }
}

public extension View {
    /// Matches an NSVisualEffect-free panel to the window background in both appearances.
    func fillPanel(_ color: Color) -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(color)
    }
}
