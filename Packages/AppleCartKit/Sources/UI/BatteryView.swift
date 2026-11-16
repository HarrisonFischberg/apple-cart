import Charts
import Core
import SwiftUI

/// Battery details, a 24 h graph and the busiest apps. Samples only while `active` (panel open on this view).
public struct BatteryView: View {
    let sampler: BatterySampler
    let active: Bool

    public init(sampler: BatterySampler, active: Bool) {
        self.sampler = sampler
        self.active = active
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let r = sampler.latest {
                    VStack(alignment: .leading, spacing: 12) {
                        summary(r)
                        details(r)
                        graph
                        apps
                    }
                    .toolCard()
                } else if active {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else {
                    Text("No battery found on this Mac.").foregroundStyle(Palette.secondary).padding(40)
                }
            }
            .toolPage()
        }
        .task(id: active) {
            if active { sampler.hold("batteryView") } else { sampler.release("batteryView") }
        }
        .onDisappear { sampler.release("batteryView") }
    }

    private func summary(_ r: BatteryReading) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(r.percent)%").font(.system(size: 34, weight: .semibold)).monospacedDigit()
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                StatusText(state(r))
                Text(flow(r)).font(.callout).foregroundStyle(Palette.secondary).monospacedDigit()
            }
        }
    }

    private func details(_ r: BatteryReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Details")
            row("True charge", r.measuredPercent.map { String(format: "%.1f%%", $0) })
            row("Capacity vs new", r.capacityVsDesign.map { String(format: "%.0f%%", $0 * 100) })
            row("Cycles", r.cycleCount.map(String.init))
            row("Temperature", r.temperatureC.map { String(format: "%.1f °C", $0) } ?? "Not provided by macOS")
            row("Mac is using", r.systemWatts.map { String(format: "%.1f W", $0) })
            row("Charger", r.isPluggedIn ? r.adapterWatts.map { "\($0) W" } ?? "Connected" : "Not connected")
            row("Time left", r.minutesRemaining.map { "\($0 / 60) h \($0 % 60) min" })
        }
    }

    private var graph: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Last 24 hours")
            if sampler.history.samples.count < 2 {
                Text("History fills in while this view is open.").hint()
            } else {
                Chart(sampler.history.samples, id: \.date) {
                    LineMark(x: .value("Time", $0.date), y: .value("Percent", $0.percent))
                        .foregroundStyle(Palette.accent)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 100)
                .accessibilityLabel("Battery percent over the last 24 hours")
            }
        }
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Using the most energy")
            if sampler.energyUsers.isEmpty { Text("Measuring…").hint() }
            ForEach(sampler.energyUsers) { u in
                HStack { Text(u.name).lineLimit(1); Spacer(); Text(String(format: "%.0f%% CPU", u.cpu)).monospacedDigit().foregroundStyle(Palette.secondary) }
                    .font(.callout)
            }
        }
    }

    private func state(_ r: BatteryReading) -> String {
        if r.isCharging { "Charging" } else if r.isPluggedIn { "Plugged in, not charging" } else { "On battery" }
    }

    private func flow(_ r: BatteryReading) -> String {
        abs(r.batteryWatts) < 0.05 ? "Battery idle" : String(format: "%@%.1f W %@", r.batteryWatts > 0 ? "+" : "−", abs(r.batteryWatts), r.batteryWatts > 0 ? "into battery" : "from battery")
    }

    private func row(_ title: String, _ value: String?) -> some View {
        HStack { Text(title); Spacer(); Text(value ?? "—").foregroundStyle(Palette.secondary).monospacedDigit() }
            .font(.callout)
            .accessibilityElement(children: .combine)
    }
}
