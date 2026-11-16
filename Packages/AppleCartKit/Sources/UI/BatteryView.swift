import Charts
import Core
import SwiftUI

/// Battery details, a 24 h graph and the busiest apps. Samples only while `active` (panel open on this view).
public struct BatteryView: View {
    let sampler: BatterySampler
    let active: Bool
    @AppStorage(MenuBarReadout.hardwarePercentKey) private var showHardwarePercent = false

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
                        chargeBar(r)
                        PowerFlowMap(reading: r)
                        details(r)
                        graph
                        EnergyAppsSection(users: sampler.energyUsers)
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
            VStack(alignment: .leading, spacing: 0) {
                Text("\(r.percent)%").font(.system(size: 34, weight: .semibold)).monospacedDigit()
                if showHardwarePercent {
                    Text("Battery reports \(MenuBarReadout.hardwarePercentText(r))").font(.caption).foregroundStyle(Palette.secondary).monospacedDigit()
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                StatusText(state(r))
                Text(flow(r)).font(.callout).foregroundStyle(Palette.secondary).monospacedDigit()
            }
        }
    }

    /// Full-width charge bar; the badge sits at the trailing end (limit marker is reserved for the charge limit feature).
    private func chargeBar(_ r: BatteryReading) -> some View {
        let g = MenuBarReadout.glyph(for: r)
        let low = !r.isPluggedIn && r.percent <= 20
        return ZStack(alignment: .leading) {
            Capsule().fill(Palette.ground)
            GeometryReader { geo in
                Capsule().fill(low ? Color.red : Palette.accent)
                    .frame(width: max(geo.size.height, geo.size.width * g.level))
                    .opacity(g.level > 0 ? 1 : 0)
            }
            if g.badge != .none {
                BadgeGlyph(badge: g.badge).frame(width: 14, height: 14)
                    .foregroundStyle(g.level > 0.92 ? Color.white : Palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 10)
            }
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Charge \(r.percent) percent")
    }

    private func details(_ r: BatteryReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Details")
            row("True charge", r.measuredPercent.map { String(format: "%.1f%%", $0) })
            row("Capacity vs new", r.capacityVsDesign.map { String(format: "%.0f%%", $0 * 100) })
            row("Cycles", r.cycleCount.map(String.init))
            row("Temperature", r.temperatureC.map { String(format: "%.1f °C", $0) } ?? "Not provided by macOS")
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
                .chartXAxis {
                    AxisMarks(values: .stride(by: axis.component, count: axis.count)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .frame(height: 100)
                .accessibilityLabel("Battery percent over the last 24 hours")
            }
        }
    }

    /// Tick spacing that fits the data so far: minutes while there is under an hour, then whole hours.
    private var axis: (component: Calendar.Component, count: Int) {
        let s = sampler.history.samples
        let span = (s.last?.date.timeIntervalSince(s.first?.date ?? .now) ?? 0)
        switch span {
        case ..<(15 * 60): return (.minute, 5)
        case ..<3600: return (.minute, 15)
        case ..<(6 * 3600): return (.hour, 1)
        case ..<(12 * 3600): return (.hour, 3)
        default: return (.hour, 6)
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
