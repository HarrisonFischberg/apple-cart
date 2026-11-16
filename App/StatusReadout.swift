import AppKit
import Core
import UI
import Observation
import os

/// Keeps the menu bar icon and text current. Holds the battery sampler only while the Battery tool is on
/// and a text readout is chosen; otherwise the icon is static and nothing samples.
@MainActor
final class StatusReadout {
    private let button: NSStatusBarButton?
    private let sampler: BatterySampler
    private let registry: FeatureRegistry
    private let settings: ReadoutSettings
    private let glyphStyle: GlyphStyleSettings
    private var holding = false

    init(button: NSStatusBarButton?, sampler: BatterySampler, registry: FeatureRegistry, settings: ReadoutSettings, glyphStyle: GlyphStyleSettings) {
        self.button = button
        self.sampler = sampler
        self.registry = registry
        self.settings = settings
        self.glyphStyle = glyphStyle
        track()
    }

    private func track() {
        let wanted = withObservationTracking {
            let on = registry.isEnabled(.battery) && !settings.items.isEmpty
            _ = sampler.latest
            _ = settings.spacing
            _ = settings.showGlyph
            sampler.interval = .seconds(settings.updateSeconds)
            _ = glyphStyle.style
            return on
        } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
        if wanted != holding {
            holding = wanted
            wanted ? sampler.hold("menuBar") : sampler.release("menuBar")
        }
        let reading = wanted ? sampler.latest : nil
        // Percent text first, then the battery glyph (the glyph carries the plug / bolt / pause state).
        let parts = MenuBarItem.segments(settings.items, for: reading)
        let glyph = BatteryGlyphImage.make(reading == nil ? BatteryGlyph(level: 0.75, badge: .none) : MenuBarReadout.glyph(for: reading), style: glyphStyle.style) // no reading: neutral app icon
        // Never leave the item empty: with no text the icon stays, so there is always something to click.
        button?.image = settings.showGlyph || parts.isEmpty ? glyph : nil
        BatterySampler.log.debug("status icon updated plugged=\(reading?.isPluggedIn ?? false)")
        // The item spacing is a kern on the gap between values, and between the text and the icon.
        // The text is a touch smaller than the system size so the larger battery leads.
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        let gap = NSAttributedString(string: " ", attributes: [.kern: CGFloat(settings.spacing), .font: font])
        let title = NSMutableAttributedString()
        for (i, part) in parts.enumerated() {
            if i > 0 { title.append(gap) }
            title.append(NSAttributedString(string: part, attributes: [.font: font]))
        }
        if !parts.isEmpty && button?.image != nil { title.append(gap) }
        button?.attributedTitle = title
        button?.imagePosition = parts.isEmpty ? .imageOnly : button?.image == nil ? .noImage : .imageTrailing
    }
}
