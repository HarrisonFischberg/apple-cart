import Core
import SwiftUI

/// Entry point for the power flow widget: the animated map (PowerFlowArt), the weak-charger warning, one spoken summary.
struct PowerFlowMap: View {
    let reading: BatteryReading?
    var active = true
    /// The charge limit is deliberately holding the charger off (the percent), so a low charger reading is not a weak charger.
    var pausedAt: Int?
    /// The charger was just given back and macOS has not started charging yet.
    var resuming = false
    @State private var selected: FlowNodeID?
    @AppStorage(FlowOffsets.storageKey) private var savedOffsets = ""
    @AppStorage(FlowStyle.storageKey) private var style = FlowStyle.space.rawValue
    @AppStorage(SpaceView.storageKey) private var savedView = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// While the charger is held off the Mac runs wholly from the battery, even when one telemetry sample says otherwise.
    private var shown: BatteryReading? { pausedAt == nil ? reading : reading?.whileHeld() }

    var body: some View {
        let streams = PowerFlows.streams(shown)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Power flow").font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
                // Live only while the panel samples this view; a closed or stale map does not claim it.
                if active, reading != nil {
                    HStack(spacing: 5) {
                        Circle().fill(Palette.green).frame(width: 6, height: 6)
                        Text("Live").font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Palette.raised, in: Capsule())
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.12)))
                    .accessibilityElement(children: .ignore).accessibilityLabel("Live")
                }
                Spacer()
                // Only once something has been moved: put the view or the tiles back where they start.
                if moved {
                    Button(space ? "Reset view" : "Reset layout", action: resetLayout)
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
                        .help(space ? "Turn the view back and put the moons in their usual places" : "Put the power flow tiles back in their usual places")
                }
            }
            Group {
                if space {
                    PowerFlowSpace(reading: shown, active: active, pausedAt: pausedAt, selected: selected, onSelect: select)
                } else {
                    PowerFlowArt(reading: shown, active: active, pausedAt: pausedAt, selected: selected, onSelect: select)
                }
            }
                // Right-click to switch between the 3D planets, the flat orbit and the original columns.
                .contextMenu {
                    Picker("Style", selection: $style) {
                        ForEach(FlowStyle.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.inline)
                    if moved { Button(space ? "Reset view" : "Reset layout", action: resetLayout) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(FlowSummary.text(shown, streams: streams, rest: PowerFlows.rest(shown, streams: streams))
                    .replacingOccurrences(of: "the charger is too weak", with: pausedAt != nil ? "charging is paused" : resuming ? "charging has not started yet" : "the charger is too weak"))
            if let selected, let reading {
                detail(FlowExplain.make(selected, reading: shown ?? reading, pausedAt: pausedAt, streams: streams))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if PowerFlows.chargerTooWeak(shown) {
                let waiting = pausedAt == nil && resuming
                Label(pausedAt.map { "Charging is paused at \($0)%. The Mac is running on the battery." }
                      ?? (waiting ? "The charger is back. Waiting for macOS to start charging."
                                  : "The charger is too weak for what this Mac is doing. The battery is covering the rest."),
                      systemImage: pausedAt == nil && !waiting ? "exclamationmark.triangle.fill" : (waiting ? "bolt.horizontal.circle.fill" : "pause.circle.fill"))
                    .font(.callout).foregroundStyle(pausedAt == nil && !waiting ? Palette.drain : Palette.secondary)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var space: Bool { style == FlowStyle.space.rawValue }
    private var moved: Bool { space ? !SpaceView(json: savedView).isDefault : !FlowOffsets(json: savedOffsets).isEmpty }

    private func resetLayout() {
        withAnimation(reduceMotion ? nil : .smooth(duration: FlowMotion.transition)) {
            if space { savedView = "" } else { savedOffsets = "" }
        }
    }

    private func select(_ id: FlowNodeID) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { selected = selected == id ? nil : id }
    }

    /// What the tapped tile is, in plain words. Tap the tile again or the close button to fold it away.
    private func detail(_ e: FlowExplanation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(e.title).font(.system(size: 14, weight: .semibold))
                Text(e.value).font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(Palette.secondary)
                Spacer()
                Button { select(selected ?? .mac) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.secondary).frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Close details")
            }
            if !e.text.isEmpty { Text(e.text).font(.callout).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true) }
            ForEach(e.facts, id: \.self) { Text($0).font(.callout).monospacedDigit() }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}
