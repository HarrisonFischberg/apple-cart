import Core
import SwiftUI

/// Entry point for the power flow widget: the animated map (PowerFlowArt), the weak-charger warning, one spoken summary.
struct PowerFlowMap: View {
    let reading: BatteryReading?
    var active = true

    var body: some View {
        let streams = PowerFlows.streams(reading)
        VStack(alignment: .leading, spacing: 8) {
            PowerFlowArt(reading: reading, active: active)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(FlowSummary.text(reading, streams: streams, rest: PowerFlows.rest(reading, streams: streams)))
            if PowerFlows.chargerTooWeak(reading) {
                Label("The charger is too weak for what this Mac is doing. The battery is covering the rest.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(Palette.drain)
                    .accessibilityElement(children: .combine)
            }
        }
    }
}
