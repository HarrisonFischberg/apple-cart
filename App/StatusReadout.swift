import AppKit
import Core
import Observation

/// Keeps the menu bar icon and text current. Holds the battery sampler only while the Battery tool is on
/// and a text readout is chosen; otherwise the icon is static and nothing samples.
@MainActor
final class StatusReadout {
    private let button: NSStatusBarButton?
    private let sampler: BatterySampler
    private let registry: FeatureRegistry
    private let settings: ReadoutSettings
    private var holding = false

    init(button: NSStatusBarButton?, sampler: BatterySampler, registry: FeatureRegistry, settings: ReadoutSettings) {
        self.button = button
        self.sampler = sampler
        self.registry = registry
        self.settings = settings
        track()
    }

    private func track() {
        let wanted = withObservationTracking {
            let on = registry.isEnabled(.battery) && settings.readout != .off
            _ = sampler.latest
            return on
        } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
        if wanted != holding {
            holding = wanted
            wanted ? sampler.hold("menuBar") : sampler.release("menuBar")
        }
        let reading = wanted ? sampler.latest : nil
        button?.image = NSImage(systemSymbolName: MenuBarReadout.symbol(for: reading), accessibilityDescription: "Apple Cart")
        let text = settings.readout.text(for: reading)
        button?.title = text.isEmpty ? "" : " " + text
        button?.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
    }
}
