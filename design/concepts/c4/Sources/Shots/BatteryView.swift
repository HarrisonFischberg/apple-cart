import SwiftUI
import ConceptShared

struct LimitTile: View {
    @Binding var limit: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    private func set(_ v: Int) {
        let c = min(100, max(50, v))
        if reduceMotion { limit = c } else { withAnimation(.spring(duration: 0.2)) { limit = c } }
    }
    var body: some View {
        Tile(icon: "gauge.with.dots.needle.67percent", title: "Limit") {
            Spacer(minLength: 0)
            Value(text: "\(limit)", suffix: "%")
            HStack(spacing: 2) {
                stepper("minus", "Lower limit by 5") { set(limit - 5) }
                GeometryReader { g in
                    Bar(fraction: Double(limit - 50) / 50, tint: T.blue).frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            let f = min(max(v.location.x / g.size.width, 0), 1)
                            set(Int((50 + f * 50) / 5 * 1.0 + 0.5) * 5)  // detents every 5
                        })
                }.frame(height: 28)
                stepper("plus", "Raise limit by 5") { set(limit + 5) }
            }
            .padding(.horizontal, -6)
        }
        .focusable().focused($focused)
        .onKeyPress(.leftArrow) { set(limit - 5); return .handled }
        .onKeyPress(.rightArrow) { set(limit + 5); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Charge limit, \(limit) percent, adjustable")
        .accessibilityAdjustableAction { d in set(limit + (d == .increment ? 5 : -5)) }
    }
    private func stepper(_ sym: String, _ label: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: sym).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.text)
                .frame(width: 22, height: 22).overlay(Circle().strokeBorder(T.border.opacity(2), lineWidth: 1))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct HistoryChart: View {
    var body: some View {
        let ph: CGFloat = 70, inset: CGFloat = 6.5
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 0) {
                    Text("100"); Spacer(); Text("50"); Spacer(); Text("0")
                }
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(T.secondary)
                .frame(width: 24, height: ph + inset * 2, alignment: .trailing)
                Canvas { ctx, size in
                    let w = size.width
                    func x(_ h: Double) -> CGFloat { w * (24 - h) / 24 }
                    func y(_ p: Double) -> CGFloat { inset + ph * (1 - p / 100) }
                    for g in [0.0, 50, 100] {
                        var p = Path(); p.move(to: CGPoint(x: 0, y: y(g))); p.addLine(to: CGPoint(x: w, y: y(g)))
                        ctx.stroke(p, with: .color(T.track), lineWidth: 1)
                    }
                    var start: Double? = nil
                    func band(_ a: Double, _ b: Double) {
                        ctx.fill(Path(CGRect(x: x(a), y: inset, width: x(b) - x(a), height: ph)), with: .color(T.blue.opacity(0.16)))
                    }
                    var last = 24.0
                    for pt in Mock.history {
                        if pt.pluggedIn { if start == nil { start = pt.hoursAgo } }
                        else if let s = start { band(s, last); start = nil }
                        last = pt.hoursAgo
                    }
                    if let s = start { band(s, 0) }
                    var lim = Path(); lim.move(to: CGPoint(x: 0, y: y(Double(Mock.limit)))); lim.addLine(to: CGPoint(x: w, y: y(Double(Mock.limit))))
                    ctx.stroke(lim, with: .color(T.blue), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    var line = Path()
                    for (i, pt) in Mock.history.enumerated() {
                        let p = CGPoint(x: x(pt.hoursAgo), y: y(pt.percent))
                        i == 0 ? line.move(to: p) : line.addLine(to: p)
                    }
                    ctx.stroke(line, with: .color(T.text), style: StrokeStyle(lineWidth: 1.75, lineJoin: .round))
                }
                .frame(height: ph + inset * 2)
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: 30, height: 1)
                ForEach([24.0, 18, 12, 6, 0], id: \.self) { h in
                    Text(Mock.clock(hoursAgo: h)).font(.system(size: 11)).monospacedDigit().foregroundStyle(T.secondary)
                    if h != 0 { Spacer(minLength: 0) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery level over the last 24 hours, from 62 to \(Int(Mock.percent)) percent, with plugged-in spans and the \(Mock.limit) percent limit")
    }
}

struct BatteryView: View {
    @State var limit = Mock.limit
    static let rows: [CGFloat] = [124, 152, 148, 160, 164]
    static var height: CGFloat { T.shotHeight(rows: rows) }
    var body: some View {
        ScrollView {
            VStack(spacing: T.gap) {
                TileRow(height: Self.rows[0]) {
                    Tile(icon: "battery.75percent", title: "Charge") {
                        Spacer(minLength: 0)
                        Value(text: "\(Int(Mock.percent))", suffix: "%")
                        Bar(fraction: Mock.percent / 100, marker: Double(limit) / 100)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Charge, \(Int(Mock.percent)) percent, limit marker at \(limit) percent")
                    LimitTile(limit: $limit)
                    Tile(icon: "thermometer.medium", title: "Temperature", style: .normal) {
                        Spacer(minLength: 0)
                        Value(text: String(format: "%.1f", Mock.tempC), suffix: " °C", color: T.amber)
                        Bar(fraction: Mock.tempC / 50, marker: Mock.heatLimitC / 50, tint: T.amberBar)
                        Caption("Heat limit \(Int(Mock.heatLimitC)) °C", color: T.amber)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(format: "Temperature, %.1f degrees Celsius, above the %.0f degree heat limit", Mock.tempC, Mock.heatLimitC))
                }
                TileRow(height: Self.rows[1]) {
                    Tile(icon: "pause.circle", title: "State", span: .two, style: .amber) {
                        Text(Mock.stateTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(T.amberText)
                        Text(Mock.stateReason).font(.system(size: 12)).foregroundStyle(T.amberText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Tile(icon: "bolt.fill", title: "Top up") {
                        Caption("Charge to 100% once.")
                        Spacer(minLength: 0)
                        SmallButton(title: "Top up now", filled: true)
                        SmallButton(title: "Discharge to...")
                    }
                }
                TileRow(height: Self.rows[2]) {
                    Tile(icon: "powerplug", title: "Power") {
                        Value(text: String(format: "%.1f", Mock.wattsToMac), suffix: " W")
                        Caption("to Mac")
                        Caption(String(format: "%.1f W to battery", Mock.wattsToBattery))
                        Caption("\(Mock.adapterRatedWatts) W adapter")
                    }
                    Tile(icon: "heart", title: "Health") {
                        Value(text: "\(Mock.maxCapacityPercent)", suffix: "%")
                        Caption("maximum capacity")
                        Caption("\(Mock.cycles) cycles")
                        Caption(Mock.health, color: T.green)
                    }
                    Tile(icon: "cpu", title: "Hardware %") {
                        Value(text: String(format: "%.1f", Mock.hardwarePercent), suffix: "%")
                        Caption("Chip reading")
                        Caption("Shown as \(Int(Mock.percent))%")
                    }
                }
                TileRow(height: Self.rows[3]) {
                    Tile(icon: "chart.xyaxis.line", title: "History, 24 hours", span: .three, trailing: {
                        HStack(spacing: 10) {
                            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(T.blue.opacity(0.3)).frame(width: 10, height: 10); Caption("Plugged in") }
                            HStack(spacing: 4) { Capsule().fill(T.blue).frame(width: 12, height: 2); Caption("\(Mock.limit)% limit") }
                        }
                    }) { HistoryChart() }
                }
                TileRow(height: Self.rows[4]) {
                    Tile(icon: "calendar", title: "Schedule", span: .three, trailing: {
                        Button {} label: {
                            Label("Add task", systemImage: "plus").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(T.text).padding(.horizontal, 8).frame(height: 28)
                                .overlay(Capsule().strokeBorder(T.border.opacity(2), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }) {
                        VStack(spacing: 8) {
                            ForEach(Mock.schedule) { s in
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.action).font(.system(size: 13, weight: .medium)).foregroundStyle(T.text)
                                        Caption(s.note)
                                    }
                                    Spacer(minLength: 8)
                                    Text(s.when).font(.system(size: 13)).monospacedDigit().foregroundStyle(T.text)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, T.pad).padding(.bottom, T.pad)
        }
    }
}
