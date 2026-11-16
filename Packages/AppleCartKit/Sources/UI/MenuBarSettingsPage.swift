import AppKit
import Core
import SwiftUI

/// Settings, Menu bar: a live preview, the glyph, the catalog of values, spacing and refresh, right-click entries, popover options.
struct MenuBarSettingsView: View {
    @Bindable var readout: ReadoutSettings
    var glyphStyle: GlyphStyleSettings?
    @State private var popover = BatteryWidgetSettings.shared
    @State private var sample = BatteryReader.read() // one read for the preview; nothing keeps sampling here

    init(readout: ReadoutSettings, glyphStyle: GlyphStyleSettings?) {
        self.readout = readout
        self.glyphStyle = glyphStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle("Menu bar")
            preview
            SettingsCard("Quick choice") { ReadoutRow(readout: readout) }
            if let glyphStyle {
                SettingsCard("Battery look") {
                    SettingsRow("Show the battery icon", detail: "With no icon and no values the icon stays, so the menu bar item can be found.") {
                        Toggle("Show the battery icon", isOn: $readout.showGlyph).toggleStyle(.switch).labelsHidden()
                    }
                    GlyphStylePicker(settings: glyphStyle)
                }
            }
            ForEach(MenuBarItemGroup.allCases, id: \.self) { group in
                SettingsCard(group.title) {
                    ForEach(MenuBarItem.allCases.filter { $0.group == group }, id: \.self) { item in
                        SettingsRow(item.title) {
                            Toggle(item.title, isOn: Binding(get: { readout.items.contains(item) },
                                                             set: { if $0 { readout.items.insert(item) } else { readout.items.remove(item) } }))
                                .toggleStyle(.switch).labelsHidden()
                        }
                    }
                }
            }
            HStack {
                Button("Reset", action: readout.reset).buttonStyle(ChipStyle()).frame(width: 120)
                Button("Clear all", action: readout.clearAll).buttonStyle(ChipStyle()).frame(width: 120)
            }
            SettingsCard("Spacing and refresh") {
                SettingsRow("Item spacing: \(readout.spacing) pt") {
                    Slider(value: Binding(get: { Double(readout.spacing) }, set: { readout.spacing = Int($0) }),
                           in: Double(MenuBarLimits.spacing.lowerBound)...Double(MenuBarLimits.spacing.upperBound), step: 1)
                        .frame(width: 180).accessibilityLabel("Item spacing").accessibilityValue("\(readout.spacing) points")
                }
                SettingsRow("Update every \(readout.updateSeconds) s", detail: "Faster updates use a little more power.") {
                    Slider(value: Binding(get: { Double(readout.updateSeconds) }, set: { readout.updateSeconds = Int($0) }),
                           in: Double(MenuBarLimits.updateSeconds.lowerBound)...Double(MenuBarLimits.updateSeconds.upperBound), step: 1)
                        .frame(width: 180).accessibilityLabel("Update interval").accessibilityValue("\(readout.updateSeconds) seconds")
                }
            }
            SettingsCard("Right-click menu") {
                SettingsRow("Settings and Quit", detail: "Always shown.") { EmptyView() }
                ForEach(RightClickAction.allCases, id: \.self) { a in
                    SettingsRow(a.title) {
                        Toggle(a.title, isOn: Binding(get: { readout.rightClick.contains(a) },
                                                      set: { if $0 { readout.rightClick.insert(a) } else { readout.rightClick.remove(a) } }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                }
            }
            SettingsCard("Battery popover") {
                SettingsRow("Show on startup", detail: "Opens the panel when Apple Cart launches.") {
                    Toggle("Show on startup", isOn: $popover.showOnStartup).toggleStyle(.switch).labelsHidden()
                }
                SettingsRow("Show percentage") { Toggle("Show percentage", isOn: $popover.showPercentage).toggleStyle(.switch).labelsHidden() }
                SettingsRow("Open in edit mode", detail: "Reorder and hide widgets as soon as the Battery screen opens.") {
                    Toggle("Open in edit mode", isOn: $popover.openInEditMode).toggleStyle(.switch).labelsHidden()
                }
            }
            Text("Click the icon to open the panel. Values this Mac does not report are left out, never guessed.").hint()
        }
    }

    /// The chosen values as they will read in the menu bar, from one reading taken when this page opened.
    private var preview: some View {
        let parts = MenuBarItem.segments(readout.items, for: sample)
        return SettingsCard("Preview") {
            HStack(spacing: CGFloat(readout.spacing)) {
                if readout.showGlyph || parts.isEmpty { Image(systemName: MenuBarReadout.symbol(for: sample)) }
                ForEach(parts, id: \.self) { Text($0).monospacedDigit() }
                if sample == nil { Text("No battery on this Mac").foregroundStyle(Palette.secondary) }
            }
            .font(.system(size: 14, weight: .medium))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Menu bar preview: " + (parts.isEmpty ? "icon only" : parts.joined(separator: ", ")))
        }
    }
}
