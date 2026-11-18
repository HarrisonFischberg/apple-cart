import AppKit
import Core
import UI
import Observation
import os

/// Keeps the menu bar icon and text current. Holds the battery sampler only while the Battery tool is on
/// and a text readout is chosen; otherwise the icon is static and nothing samples.
@MainActor
final class StatusReadout {
    private let item: NSStatusItem?
    private let button: NSStatusBarButton?
    private let sampler: BatterySampler
    private let registry: FeatureRegistry
    private let settings: ReadoutSettings
    private let glyphStyle: GlyphStyleSettings
    private var holding = false
    /// Space left on each side of the item's content.
    /// Off the button's fitting width: its own padding is about 3 pt a side.
    private static let trim: CGFloat = 4

    init(item: NSStatusItem? = nil, button: NSStatusBarButton?, sampler: BatterySampler, registry: FeatureRegistry, settings: ReadoutSettings, glyphStyle: GlyphStyleSettings) {
        self.item = item
        self.button = button
        self.sampler = sampler
        self.registry = registry
        self.settings = settings
        self.glyphStyle = glyphStyle
        track()
    }

    private func track() {
        let wanted = withObservationTracking {
            // The Apple style shows the percentage inside the icon, so it needs readings even with no text chosen.
            let inIcon = glyphStyle.style.showsPercentInside && settings.showGlyph
            let on = registry.isEnabled(.battery) && (!settings.items.isEmpty || inIcon)
            _ = sampler.latest
            _ = settings.spacing
            sampler.interval = .seconds(settings.updateSeconds)
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
        // The Apple style already has the percentage inside, so the separate percent text would say it twice.
        let inIcon = glyphStyle.style.showsPercentInside && settings.showGlyph
        let parts = MenuBarItem.segments(inIcon ? settings.items.subtracting([.percent]) : settings.items, for: reading)
        let glyph = BatteryGlyphImage.make(reading == nil ? BatteryGlyph(level: 0.75, badge: .none) : MenuBarReadout.glyph(for: reading),
                                           style: glyphStyle.style, number: reading != nil) // no reading: neutral app icon, no number
        // Never leave the item empty: with no text the icon stays, so there is always something to click.
        button?.image = settings.showGlyph || parts.isEmpty ? glyph : nil
        BatterySampler.log.debug("status icon updated plugged=\(reading?.isPluggedIn ?? false)")
        // The item spacing is a kern on the gap between values, and between the text and the icon.
        // The text is a touch smaller than the system size so the larger battery leads.
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        // A zero-width space carries the kern, so spacing 0 is really 0 (a normal space adds about 3 pt of its own).
        let gap = NSAttributedString(string: "\u{200B}", attributes: [.kern: CGFloat(settings.spacing), .font: font])
        let title = NSMutableAttributedString()
        for (i, part) in parts.enumerated() {
            if i > 0 { title.append(gap) }
            title.append(NSAttributedString(string: part, attributes: [.font: font]))
        }
        if !parts.isEmpty && button?.image != nil { title.append(gap) }
        button?.attributedTitle = title
        button?.imagePosition = parts.isEmpty ? .imageOnly : button?.image == nil ? .noImage : .imageTrailing
        // The system draws each item in a window 16 pt wider than its length, outside the button, so that air cannot be
        // removed from here (a smaller length clips the text and the battery; measured: 62 pt fitting, 78 pt window).
        // What can go is the button's own padding: trim a little off the fitting width, never below the content itself.
        if let button, let item {
            let content = ceil(title.size().width + (button.image?.size.width ?? 0))
            item.length = max(ceil(button.fittingSize.width) - Self.trim, content + 2)
        }
    }
}
