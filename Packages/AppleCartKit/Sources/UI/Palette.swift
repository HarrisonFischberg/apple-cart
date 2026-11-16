import AppKit
import SwiftUI

/// Color roles from DESIGN.md (light, dark). Only the roles used so far.
public enum Palette {
    public static let ground = adaptive(light: 0xF1F1F4, dark: 0x0B0B0D)
    public static let tile = adaptive(light: 0xFFFFFF, dark: 0x18181B)
    public static let secondary = adaptive(light: 0x5B5B66, dark: 0xA1A1AA)
    public static let accent = adaptive(light: 0x0A5ED7, dark: 0x5AB0FF)
    /// Energy colors of the power flow map: charger (amber bar), battery charging (green), battery draining (orange).
    public static let amber = adaptive(light: 0xC77700, dark: 0xF5A524)
    public static let green = adaptive(light: 0x177A3C, dark: 0x4ADE80)
    public static let drain = adaptive(light: 0xD9480F, dark: 0xFF8A4C)

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }))
    }
}
