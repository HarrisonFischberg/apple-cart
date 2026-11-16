import Foundation
import Observation

/// How the battery looks in the menu bar. The percent text beside it is a separate choice.
public enum MenuBarGlyphStyle: String, CaseIterable, Sendable {
    case classic, solid, segments, ring, slim

    public var title: String {
        switch self {
        case .classic: "Classic"
        case .solid: "Solid"
        case .segments: "Segments"
        case .ring: "Ring"
        case .slim: "Slim bar"
        }
    }
}

/// The chosen glyph style, kept in the app's own defaults.
@MainActor @Observable
public final class GlyphStyleSettings {
    public static let key = "menuBar.glyphStyle"
    public var style: MenuBarGlyphStyle { didSet { defaults.set(style.rawValue, forKey: Self.key) } }
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        style = defaults.string(forKey: Self.key).flatMap(MenuBarGlyphStyle.init(rawValue:)) ?? .classic
    }
}
