import SwiftUI
import ConceptShared

struct BatteryTab: View {
    @State private var limit = Mock.limit
    @State private var dragSeen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            readout
                .padding(.horizontal, T.pad).padding(.top, 12)
            TapeScale(limit: $limit, charge: Mock.percent, heatPaused: true)
                .padding(.top, 2)
            stateBlock
                .padding(.horizontal, T.pad).padding(.top, 8)
            HStack(spacing: 8) {
                Button("Top up") {}.buttonStyle(PrimaryButton())
                    .accessibilityHint("Charge to 100 percent once, ignoring the limit")
                Button("Discharge to…") {}.buttonStyle(SecondaryButton())
            }
            .padding(.horizontal, T.pad).padding(.top, 12)
            flow.padding(.horizontal, T.pad).padding(.top, 16)
            details.padding(.horizontal, T.pad).padding(.top, 16)
            history.padding(.horizontal, T.pad).padding(.top, 16)
            schedule.padding(.horizontal, T.pad).padding(.top, 16)
            Spacer(minLength: 0)
        }
    }

    private var readout: some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(Int(Mock.percent))").font(T.din(40)).foregroundStyle(T.ink)
                Text("% charge").font(T.label).foregroundStyle(T.ink2)
            }
            Spacer()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("limit").font(T.label).foregroundStyle(T.ink2)
                Text("\(limit)").font(T.din(40)).foregroundStyle(T.ink)
                    .contentTransition(.numericText())
                Text("%").font(T.label).foregroundStyle(T.ink2)
            }
        }
    }

    private var stateBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "thermometer.high").font(.system(size: 14, weight: .semibold))
                Text(Mock.stateTitle).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(T.red)
            Text(Mock.stateReason)
                .font(.system(size: 14, weight: .medium)).foregroundStyle(T.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(T.redWash))
    }

    private var flow: some View {
        HStack(alignment: .top, spacing: 0) {
            flowCell("\(Mock.adapterRatedWatts)", "W", "Adapter rating")
            arrow
            flowCell(String(format: "%.1f", Mock.wattsToMac), "W", "To Mac")
            arrow
            flowCell(String(format: "%.1f", Mock.wattsToBattery), "W", "To battery")
        }
    }
    private var arrow: some View {
        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.ink2)
            .frame(width: 24, height: 26)
    }
    private func flowCell(_ v: String, _ u: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(v).font(T.din(26)).foregroundStyle(T.ink)
                Text(u).font(T.small).foregroundStyle(T.ink2)
            }
            Text(l).font(T.small).foregroundStyle(T.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(spacing: 0) {
            Heading(text: "Details").padding(.bottom, 4)
            row("Temperature", value: String(format: "%.1f °C", Mock.tempC), note: "Heat limit \(Int(Mock.heatLimitC)) °C, too warm", hot: true)
            Rule()
            row("Cycles", value: "\(Mock.cycles)")
            Rule()
            row("Maximum capacity", value: "\(Mock.maxCapacityPercent)%")
            Rule()
            row("Health", value: Mock.health)
            Rule()
            row("Hardware percentage", value: String(format: "%.1f%%", Mock.hardwarePercent), note: "Shows \(Int(Mock.percent))%")
        }
    }
    private func row(_ k: String, value: String, note: String? = nil, hot: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(k).font(T.label).foregroundStyle(T.ink)
            if let note { Text(note).font(T.small).foregroundStyle(hot ? T.red : T.ink2) }
            Spacer()
            Text(value).font(T.din(17)).foregroundStyle(hot ? T.red : T.ink)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            Heading(text: "Last 24 hours", trailing: "Yellow bands: plugged in")
            AxisChart(
                yLabels: [(0, "0%"), (0.5, "50%"), (1, "100%")],
                xLabels: [0, 6, 12, 18, 24].map { (Double($0) / 24, Mock.clock(hoursAgo: 24 - Double($0))) },
                height: 76
            ) { HistoryPlot(limit: limit) }
        }
    }

    private var schedule: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Schedule").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.ink)
                Spacer()
                Button { } label: {
                    Label("Add task", systemImage: "plus").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(T.ink)
                .padding(.horizontal, 8).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(T.well))
            }
            .padding(.bottom, 2)
            ForEach(Mock.schedule) { s in
                HStack(alignment: .firstTextBaseline) {
                    Text(s.action).font(T.label).foregroundStyle(T.ink)
                    Spacer()
                    Text(s.when).font(T.din(16)).foregroundStyle(T.ink)
                }
                .padding(.top, 5)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct HistoryPlot: View {
    let limit: Int
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let pts = Mock.history
            let px = { (hrs: Double) in w * (1 - hrs / 24) }
            let py = { (p: Double) in h * (1 - p / 100) }
            // plugged-in spans
            Canvas { ctx, _ in
                var start: Double? = nil
                for (i, p) in pts.enumerated() {
                    if p.pluggedIn, start == nil { start = p.hoursAgo }
                    let ends = !p.pluggedIn || i == pts.count - 1
                    if let s = start, ends {
                        let e = p.pluggedIn ? p.hoursAgo : pts[i - 1].hoursAgo
                        ctx.fill(Path(CGRect(x: px(s), y: 0, width: max(px(e) - px(s), 1), height: h)), with: .color(T.yellowWash))
                        start = nil
                    }
                }
                var line = Path()
                for (i, p) in pts.enumerated() {
                    let pt = CGPoint(x: px(p.hoursAgo), y: py(p.percent))
                    i == 0 ? line.move(to: pt) : line.addLine(to: pt)
                }
                ctx.stroke(line, with: .color(T.ink), lineWidth: 1.5)
                var lim = Path()
                lim.move(to: CGPoint(x: 0, y: py(Double(limit))))
                lim.addLine(to: CGPoint(x: w, y: py(Double(limit))))
                ctx.stroke(lim, with: .color(T.ink2), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            Text("Limit \(limit)%").font(T.small).foregroundStyle(T.ink)
                .padding(.horizontal, 3).background(T.ground.opacity(0.85))
                .position(x: w - 36, y: min(max(py(Double(limit)) - 8, 8), h - 8))
        }
    }
}
