import Core
import SwiftUI

/// Charger on the left, Mac and battery stacked on the right, joined by ribbons whose thickness follows watts.
/// Labels are raw readings; a missing value is an em dash and draws no ribbon.
struct PowerFlowMap: View {
    let reading: BatteryReading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 188
    private static let node: CGFloat = 46

    private struct Spots {
        let charger: CGPoint, mac: CGPoint, battery: CGPoint
        init(width w: CGFloat) {
            charger = CGPoint(x: 28, y: 86)
            mac = CGPoint(x: w * 0.5, y: 30)
            battery = CGPoint(x: w * 0.5, y: 158)
        }
    }

    private struct Ribbon {
        let from: CGPoint, to: CGPoint
        let watts: Double?
        let color: Color
        /// Gentle S-curve; same-x links bow sideways so they still read as a ribbon.
        var path: Path {
            var p = Path()
            p.move(to: from)
            if abs(from.x - to.x) < 1 {
                p.addCurve(to: to, control1: CGPoint(x: from.x + 22, y: from.y + (to.y - from.y) * 0.3),
                           control2: CGPoint(x: to.x + 22, y: to.y - (to.y - from.y) * 0.3))
            } else {
                let dx = (to.x - from.x) * 0.55
                p.addCurve(to: to, control1: CGPoint(x: from.x + dx, y: from.y), control2: CGPoint(x: to.x - dx, y: to.y))
            }
            return p
        }
    }

    private var flows: PowerFlows { PowerFlows(reading) }
    private var moving: Bool { [flows.chargerToMac, flows.chargerToBattery, flows.batteryToMac].contains { ($0 ?? 0) > 0.05 } }

    private func ribbons(_ s: Spots) -> [Ribbon] {
        let r = Self.node / 2
        let into = Color.green, supply = Palette.accent, out = Color.orange
        return [
            Ribbon(from: CGPoint(x: s.charger.x + r, y: s.charger.y), to: CGPoint(x: s.mac.x - r, y: s.mac.y), watts: flows.chargerToMac, color: supply),
            Ribbon(from: CGPoint(x: s.charger.x + r, y: s.charger.y), to: CGPoint(x: s.battery.x - r, y: s.battery.y), watts: flows.chargerToBattery, color: into),
            Ribbon(from: CGPoint(x: s.battery.x, y: s.battery.y - r), to: CGPoint(x: s.mac.x, y: s.mac.y + r), watts: flows.batteryToMac, color: out),
        ]
    }

    /// 100 W is the thickest ribbon; anything real and non-zero stays visible.
    private func thickness(_ w: Double) -> CGFloat { max(3, min(24, CGFloat(w) * 0.24)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            map
            if PowerFlows.chargerTooWeak(reading) {
                Label("The charger is too weak for what this Mac is doing. The battery is covering the rest.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(Color.orange)
                    .accessibilityElement(children: .combine)
            }
            streams
        }
    }

    /// Where the Mac's power goes, as far as macOS reports it: a bar per stream sized against the Mac's load; a dash when not reported.
    private var streams: some View {
        let list = PowerFlows.streams(reading)
        let total = max(reading.systemWatts ?? 0, 1)
        return VStack(spacing: 6) {
            ForEach(list) { st in
                HStack(spacing: 10) {
                    Text(st.title).font(.callout).frame(width: 84, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(.primary.opacity(0.08))
                        if let w = st.watts {
                            Capsule().fill(Palette.accent.opacity(0.85)).frame(width: max(6, geo.size.width * min(1, w / total)))
                        }
                    }
                    .frame(height: 8)
                    Text(st.watts.map { PowerFlow.watts($0) } ?? "—").font(.callout).monospacedDigit().foregroundStyle(Palette.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
                .frame(minHeight: 22)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(st.title) \(st.watts.map { PowerFlow.watts($0) } ?? "not reported by macOS")")
            }
        }
    }

    private var map: some View {
        GeometryReader { geo in
            let s = Spots(width: geo.size.width)
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(paused: reduceMotion || !moving)) { tl in
                    Canvas { ctx, _ in draw(&ctx, s, t: tl.date.timeIntervalSinceReferenceDate) }
                }
                let f = PowerFlow(reading)
                node(at: s.charger, symbol: "powerplug.fill", active: reading.isPluggedIn)
                caption(f.adapter, f.adapterNote).frame(width: 110).position(x: s.charger.x + 28, y: s.charger.y + 58)
                node(at: s.mac, symbol: "laptopcomputer", active: true)
                caption(f.system, f.systemNote, leading: true).position(x: s.mac.x + 38 + 52, y: s.mac.y)
                node(at: s.battery, symbol: reading.isCharging ? "battery.100percent.bolt" : "battery.50percent", active: abs(reading.batteryWatts) > 0.05)
                caption(f.battery, f.batteryNote, leading: true).position(x: s.battery.x + 38 + 52, y: s.battery.y)
            }
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func draw(_ ctx: inout GraphicsContext, _ s: Spots, t: TimeInterval) {
        for rb in ribbons(s) {
            ctx.stroke(rb.path, with: .color(.primary.opacity(0.08)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round)) // the link itself
            guard let w = rb.watts, w > 0.05 else { continue }
            let th = thickness(w)
            ctx.stroke(rb.path, with: .linearGradient(Gradient(colors: [rb.color.opacity(0.25), rb.color.opacity(0.85)]),
                                                      startPoint: rb.from, endPoint: rb.to),
                       style: StrokeStyle(lineWidth: th, lineCap: .round))
            if !reduceMotion { // light beads travelling from source to sink
                ctx.stroke(rb.path, with: .color(.white.opacity(0.45)),
                           style: StrokeStyle(lineWidth: max(1.5, th * 0.35), lineCap: .round, dash: [0.1, 16], dashPhase: -CGFloat(t * 24)))
            }
        }
    }

    private func node(at p: CGPoint, symbol: String, active: Bool) -> some View {
        Image(systemName: symbol).font(.system(size: 19))
            .foregroundStyle(active ? Palette.accent : Palette.secondary)
            .frame(width: Self.node, height: Self.node)
            .background(Palette.ground, in: Circle())
            .overlay(Circle().strokeBorder(active ? Palette.accent.opacity(0.5) : .primary.opacity(0.08), lineWidth: 1.5))
            .position(p)
            .accessibilityHidden(true)
    }

    private func caption(_ value: String, _ note: String, leading: Bool = false) -> some View {
        VStack(alignment: leading ? .leading : .center, spacing: 1) {
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(note).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(width: leading ? 104 : nil, alignment: leading ? .leading : .center)
        .accessibilityHidden(true)
    }

    private var summary: String {
        let f = PowerFlow(reading)
        return "Power flow. Charger \(f.adapter), \(f.adapterNote). Mac \(f.system), \(f.systemNote). Battery \(f.battery), \(f.batteryNote)."
    }
}
