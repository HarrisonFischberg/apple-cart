import Charts
import Core
import SwiftUI

/// Battery details, a 24 h graph and the busiest apps. Samples only while `active` (panel open on this view).
public struct BatteryView: View {
    let sampler: BatterySampler
    let active: Bool
    @AppStorage(MenuBarReadout.hardwarePercentKey) private var showHardwarePercent = false
    @State private var widgets = BatteryWidgetSettings.shared
    @State private var didOpenEditing = false
    let limiter: ChargeLimiter?
    let chargeLimit: ChargeLimitSettings?

    public init(sampler: BatterySampler, active: Bool, limiter: ChargeLimiter? = nil, chargeLimit: ChargeLimitSettings? = nil) {
        self.sampler = sampler
        self.active = active
        self.limiter = limiter
        self.chargeLimit = chargeLimit
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let r = sampler.latest {
                    VStack(alignment: .leading, spacing: 12) {
                        if widgets.editing {
                            editList
                        } else {
                            ForEach(widgets.layout.visible) { widget($0, r) }
                            if widgets.layout.visible.isEmpty { Text("All widgets are hidden. Use Edit to show some.").hint() }
                        }
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
            if active, widgets.openInEditMode, !didOpenEditing { widgets.editing = true; didOpenEditing = true }
            if active { sampler.hold("batteryView") } else { sampler.release("batteryView") }
        }
        .onDisappear { sampler.release("batteryView") }
    }

    @ViewBuilder private func widget(_ w: BatteryWidget, _ r: BatteryReading) -> some View {
        switch w {
        case .charge: summary(r); chargeBar(r)
        case .powerFlow: PowerFlowMap(reading: r, active: active, pausedAt: limiter?.state.holdingAt)
        case .details: details(r)
        case .history: graph
        case .energyApps: apps
        }
    }

    /// Drag the handle to reorder; the arrows and the accessibility actions do the same without dragging.
    private var editList: some View {
        let order = widgets.layout.order
        return List {
            ForEach(order) { w in
                let i = order.firstIndex(of: w) ?? 0
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal").foregroundStyle(Palette.secondary).frame(width: 24, height: 44).accessibilityHidden(true)
                    Text(w.title)
                    Spacer()
                    Toggle(w.title, isOn: Binding(get: { !widgets.layout.hidden.contains(w) }, set: { on in widgets.update { $0.setVisible(w, on) } }))
                        .labelsHidden().toggleStyle(.switch)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: "Move up") { widgets.update { $0.move(w, to: i - 1) } }
                .accessibilityAction(named: "Move down") { widgets.update { $0.move(w, to: i + 1) } }
            }
            .onMove { from, to in
                guard let f = from.first else { return }
                widgets.update { $0.move(order[f], to: f < to ? to - 1 : to) }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .frame(height: CGFloat(order.count) * 52)
    }

    private func summary(_ r: BatteryReading) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                if widgets.showPercentage { Text("\(r.percent)%").font(.system(size: 34, weight: .semibold)).monospacedDigit() }
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

    /// Full-width charge bar; the badge sits at the trailing end. With charge control it is also the limit control:
    /// a handle at the limit, dragged to set it, and a dashed marker at the lower edge of the sailing range.
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
                BadgeGlyph(badge: g.badge).frame(width: g.badge.isWide ? 28 : 14, height: 14)
                    .foregroundStyle(g.level > 0.92 ? Color.white : Palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 10)
            }
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Charge \(r.percent) percent")
        .overlay { if let chargeLimit { LimitHandle(settings: chargeLimit, changed: { Task { await limiter?.reevaluate() } }) } }
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

    private var apps: some View { EnergyAppsSection(users: sampler.energyUsers) }

    private func state(_ r: BatteryReading) -> String {
        // Only the runner's confirmed hold says "Paused"; while it holds macOS reports battery power.
        if let n = limiter?.state.holdingAt { return "Paused at \(n)%" }
        return r.stateText
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

/// Drag handle and sailing marker drawn over the charge bar. Snaps to 5% steps, from 0 to 100, and shows the value while dragging.
private struct LimitHandle: View {
    let settings: ChargeLimitSettings
    let changed: () -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let x = { (p: Int) in w * CGFloat(p) / 100 }
            if settings.limit < 100 {
                Path { p in p.move(to: CGPoint(x: x(settings.sailFloor), y: 3)); p.addLine(to: CGPoint(x: x(settings.sailFloor), y: h - 3)) }
                    .stroke(Color.primary.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .accessibilityHidden(true)
            }
            Capsule().fill(Color.white).frame(width: 6, height: h + 8)
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.25)))
                .frame(width: 44, height: 44).contentShape(Rectangle()) // 44 pt target
                .position(x: min(max(x(settings.limit), 3), w - 3), y: h / 2)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("chargeBar"))
                    .onChanged { v in
                        dragging = true
                        let p = settings.clamped(Int((v.location.x / max(w, 1) * 100).rounded()))
                        if p != settings.limit { settings.setLimit(p) }
                    }
                    .onEnded { _ in dragging = false; changed() })
                .help("Drag to set the charge limit")
                .accessibilityElement()
                .accessibilityLabel("Charge limit")
                .accessibilityValue("\(settings.limit) percent")
                .accessibilityAdjustableAction { dir in
                    switch dir {
                    case .increment: settings.setLimit(settings.limit + ChargeLimitSettings.step)
                    case .decrement: settings.setLimit(settings.limit - ChargeLimitSettings.step)
                    @unknown default: return
                    }
                    changed()
                }
            if dragging {
                Text("\(settings.limit)%").font(.system(size: 15, weight: .bold)).monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Palette.accent, in: Capsule()).foregroundStyle(Color.white)
                    .position(x: min(max(x(settings.limit), 24), w - 24), y: -16)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .coordinateSpace(.named("chargeBar"))
    }
}
