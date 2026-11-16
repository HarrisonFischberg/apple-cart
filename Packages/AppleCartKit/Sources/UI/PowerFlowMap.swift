import Core
import SwiftUI

/// Entry point for the power flow widget: the animated map (PowerFlowArt), the weak-charger warning, one spoken summary.
struct PowerFlowMap: View {
    let reading: BatteryReading?
    var active = true
    /// The charge limit is deliberately holding the charger off (the percent), so a low charger reading is not a weak charger.
    var pausedAt: Int?

    var body: some View {
        let streams = PowerFlows.streams(reading)
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
            }
            PowerFlowArt(reading: reading, active: active, pausedAt: pausedAt)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(FlowSummary.text(reading, streams: streams, rest: PowerFlows.rest(reading, streams: streams))
                    .replacingOccurrences(of: "the charger is too weak", with: pausedAt == nil ? "the charger is too weak" : "charging is paused"))
            if PowerFlows.chargerTooWeak(reading) {
                Label(pausedAt.map { "Charging is paused at \($0)%. The Mac is running on the battery." }
                      ?? "The charger is too weak for what this Mac is doing. The battery is covering the rest.",
                      systemImage: pausedAt == nil ? "exclamationmark.triangle.fill" : "pause.circle.fill")
                    .font(.callout).foregroundStyle(pausedAt == nil ? Palette.drain : Palette.secondary)
                    .accessibilityElement(children: .combine)
            }
        }
    }
}
