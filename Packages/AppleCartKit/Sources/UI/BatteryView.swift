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
            VStack(spacing: 12) {
                if let r = sampler.latest {
                    summary(r)
                    details(r)
                    graph
                    apps
                } else if active {
                    ProgressView().padding(40)
                } else {
                    Text("No battery found on this Mac.").foregroundStyle(Palette.secondary).padding(40)
                }
            }
            .padding(16)
        }
        .task(id: active) {
            if active { sampler.hold("batteryView") } else { sampler.release("batteryView") }
        }
        .onDisappear { sampler.release("batteryView") }
    }

    private func summary(_ r: BatteryReading) -> some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                Text("\(r.percent)%").font(.system(size: 40, weight: .semibold)).monospacedDigit()
                Spacer()
                VStack(alignment: .trailing) {
                    Text(state(r)).font(.headline)
                    Text(flow(r)).font(.callout).foregroundStyle(Palette.secondary).monospacedDigit()
                }
            }
        }
    }

    private func details(_ r: BatteryReading) -> some View {
        card {
            VStack(spacing: 8) {
                row("True charge", r.measuredPercent.map { String(format: "%.1f%%", $0) })
                row("Capacity vs new", r.capacityVsDesign.map { String(format: "%.0f%%", $0 * 100) })
                row("Cycles", r.cycleCount.map(String.init))
                row("Temperature", r.temperatureC.map { String(format: "%.1f °C", $0) } ?? "Not provided by macOS")
                row("Mac is using", r.systemWatts.map { String(format: "%.1f W", $0) })
                row("Charger", r.isPluggedIn ? r.adapterWatts.map { "\($0) W" } ?? "Connected" : "Not connected")
                row("Time left", r.minutesRemaining.map { "\($0 / 60) h \($0 % 60) min" })
            }
        }
    }

    private var graph: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Last 24 hours").font(.headline)
                if sampler.history.samples.count < 2 {
                    Text("History fills in while this view is open.").font(.callout).foregroundStyle(Palette.secondary)
                } else {
                    Chart(sampler.history.samples, id: \.date) {
                        LineMark(x: .value("Time", $0.date), y: .value("Percent", $0.percent))
                            .foregroundStyle(Palette.accent)
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 120)
                    .accessibilityLabel("Battery percent over the last 24 hours")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var apps: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Using the most energy").font(.headline)
                if sampler.energyUsers.isEmpty {
                    Text("Measuring…").font(.callout).foregroundStyle(Palette.secondary)
                }
                ForEach(sampler.energyUsers) { u in
                    HStack { Text(u.name).lineLimit(1); Spacer(); Text(String(format: "%.0f%% CPU", u.cpu)).monospacedDigit().foregroundStyle(Palette.secondary) }
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content().padding(14).frame(maxWidth: .infinity)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
