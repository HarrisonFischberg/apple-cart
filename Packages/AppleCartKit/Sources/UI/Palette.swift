import AppKit
import SwiftUI

/// Color roles from DESIGN.md (light, dark). Only the roles used so far.
public enum Palette {
    public static let ground = adaptive(light: 0xF1F1F4, dark: 0x0B0B0D)
    public static let tile = adaptive(light: 0xFFFFFF, dark: 0x18181B)
    public static let secondary = adaptive(light: 0x5B5B66, dark: 0xA1A1AA)
    public static let accent = adaptive(light: 0x0A5ED7, dark: 0x5AB0FF)
    /// A surface one step up from the tile, for tiles and cards nested inside a tool card (power flow tiles, the energy list).
    public static let raised = adaptive(light: 0xF6F6F8, dark: 0x232327)
    /// Top of a lifted tile's vertical gradient (the bottom is `raised`).
    public static let raisedTop = adaptive(light: 0xFFFFFF, dark: 0x2E2E34)
    /// Vivid blue of the power flow ribbons and the charge bar fill, and its lighter end.
    public static let flow = adaptive(light: 0x0A6CFF, dark: 0x0A84FF)
    public static let flowLight = adaptive(light: 0x4C9BFF, dark: 0x64B5FF)
    /// Darker rounded track under the charge bar.
    public static let track = adaptive(light: 0xE3E3E8, dark: 0x0B0B0D)
    /// Amber chip for a held charge (DESIGN.md amber fill / amber text, checked at 5.4:1 or better).
    public static let amberFill = adaptive(light: 0xFFF1D6, dark: 0x2B2008)
    public static let amberText = adaptive(light: 0x5C3600, dark: 0xFFD58A)
    /// Energy colors of the power flow map: charger (amber bar), battery charging (green), battery draining (orange).
    public static let amber = adaptive(light: 0xC77700, dark: 0xF5A524)
    public static let green = adaptive(light: 0x177A3C, dark: 0x4ADE80)
    public static let drain = adaptive(light: 0xD9480F, dark: 0xFF8A4C)
    /// Line of the memory graph on the System view, kept apart from the CPU and GPU blues.
    public static let teal = adaptive(light: 0x0B7A80, dark: 0x5EE6D8)
    /// Critical memory pressure.
    public static let critical = adaptive(light: 0xC0262D, dark: 0xFF6B6B)

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }))
    }
}
