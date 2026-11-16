import AppKit
import Core
import UI
import Observation

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
            let on = registry.isEnabled(.battery) && settings.readout != .off
            _ = sampler.latest
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
        button?.image = BatteryGlyphImage.make(reading == nil ? BatteryGlyph(level: 0.75, badge: .none) : MenuBarReadout.glyph(for: reading), style: glyphStyle.style) // no reading: neutral app icon
        let text = settings.readout.text(for: reading)
        button?.title = text.isEmpty ? "" : text + " "
        button?.imagePosition = text.isEmpty ? .imageOnly : .imageTrailing
    }
}
