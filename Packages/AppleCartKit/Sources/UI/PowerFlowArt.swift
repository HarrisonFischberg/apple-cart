import Core
import SwiftUI

/// The animated flow: flat tiles placed from `FlowLayout`, Sankey ribbons, chevrons and travelling dots drawn in one Canvas.
/// Ticks at up to 30 fps only while `active`, something is flowing or a change is still easing in; Reduce Motion draws it still.
struct PowerFlowArt: View {
    let reading: BatteryReading?
    let active: Bool
    /// The charge limit is holding the charger off at this percent.
    var pausedAt: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var from: FlowLayout?
    @State private var changedAt: Double = 0
    @State private var settled = true
    @State private var clock = ParticleClock()

    private var state: FlowState { FlowState(reading) }
    private var streams: [PowerStream] { PowerFlows.streams(reading) }
    private var rest: Double? { PowerFlows.rest(reading, streams: streams) }
    private var leafCount: Int { streams.count }

    private func layout(_ w: CGFloat) -> FlowLayout {
        FlowLayout.make(state: state, flows: PowerFlows(reading), streams: streams, rest: rest, width: w, held: pausedAt != nil)
    }

    private var tick: Animation? { reduceMotion ? nil : .smooth(duration: FlowMotion.transition) }

    var body: some View {
        GeometryReader { geo in
            let target = layout(geo.size.width)
            let moving = target.links.contains { ($0.watts ?? 0) > 0.05 }
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || reduceMotion || (!moving && settled))) { tl in
                    Canvas { ctx, _ in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        let shown = reduceMotion || from == nil ? target
                            : FlowLayout.lerp(from!, target, FlowMotion.progress(elapsed: t - changedAt))
                        draw(&ctx, shown, t: t, particles: active && !reduceMotion)
                    }
                }
                ZStack(alignment: .topLeading) {
                    ForEach(target.nodes, id: \.id) { n in
                        tile(n).frame(width: n.rect.width, height: n.rect.height)
                            .position(x: n.rect.midX, y: n.rect.midY)
                            .transition(.opacity)
                    }
                }
                .frame(width: geo.size.width, height: target.size.height, alignment: .topLeading)
            }
            .animation(tick, value: target)
            .onChange(of: target) { old, new in
                let now = Date.now.timeIntervalSinceReferenceDate
                // Start from what is on screen, so a reading mid-transition does not snap.
                from = from.map { FlowLayout.lerp($0, old, FlowMotion.progress(elapsed: now - changedAt)) } ?? old
                changedAt = now
                settled = false
                clock.update(speeds: Dictionary(new.links.map { ($0.id, FlowMotion.speed($0.watts ?? 0)) }, uniquingKeysWith: { a, _ in a }), at: now)
            }
            .onAppear {
                clock.update(speeds: Dictionary(target.links.map { ($0.id, FlowMotion.speed($0.watts ?? 0)) }, uniquingKeysWith: { a, _ in a }),
                             at: Date.now.timeIntervalSinceReferenceDate)
            }
            .task(id: changedAt) {
                guard !settled else { return }
                try? await Task.sleep(for: .seconds(FlowMotion.transition + 0.1))
                settled = true
            }
        }
        .frame(height: FlowLayout.height(leaves: leafCount))
        .animation(tick, value: leafCount)
    }

    // MARK: Colors

    /// Power the Mac uses is blue, charge into the battery green, power taken from the battery orange.
    private func color(_ k: FlowLinkKind) -> (Color, opacity: Double) {
        switch k {
        case .supply, .stream: (Palette.accent, 0.6)
        case .charge: (Palette.green, 0.9)
        case .drain: (Palette.drain, 0.55)
        }
    }

    // MARK: Ribbons

    private func curve(_ l: FlowLayout.Link) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        let a = l.start, b = l.end
        if l.vertical {
            let dy = (b.y - a.y) * 0.5
            return (a, CGPoint(x: a.x, y: a.y + dy), CGPoint(x: b.x, y: b.y - dy), b)
        }
        let dx = (b.x - a.x) * 0.55
        return (a, CGPoint(x: a.x + dx, y: a.y), CGPoint(x: b.x - dx, y: b.y), b)
    }

    private static func point(_ c: (CGPoint, CGPoint, CGPoint, CGPoint), _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, d = 3 * u * t * t, e = t * t * t
        return CGPoint(x: a * c.0.x + b * c.1.x + d * c.2.x + e * c.3.x, y: a * c.0.y + b * c.1.y + d * c.2.y + e * c.3.y)
    }

    private static func length(_ c: (CGPoint, CGPoint, CGPoint, CGPoint)) -> Double {
        var len: CGFloat = 0, prev = c.0
        for i in 1...12 {
            let p = point(c, CGFloat(i) / 12)
            len += hypot(p.x - prev.x, p.y - prev.y); prev = p
        }
        return Double(len)
    }

    /// A Sankey band: the curve offset by half the ribbon width on each side, so its thickness reads the same along the way.
    private static func band(_ c: (CGPoint, CGPoint, CGPoint, CGPoint), width w: CGFloat, vertical: Bool) -> Path {
        func s(_ p: CGPoint, _ k: CGFloat) -> CGPoint { vertical ? CGPoint(x: p.x + w / 2 * k, y: p.y) : CGPoint(x: p.x, y: p.y + w / 2 * k) }
        var p = Path()
        p.move(to: s(c.0, -1)); p.addCurve(to: s(c.3, -1), control1: s(c.1, -1), control2: s(c.2, -1))
        p.addLine(to: s(c.3, 1)); p.addCurve(to: s(c.0, 1), control1: s(c.2, 1), control2: s(c.1, 1))
        p.closeSubpath()
        return p
    }

    /// A small chevron at the middle of the ribbon, pointing the way the power goes.
    private static func chevron(_ c: (CGPoint, CGPoint, CGPoint, CGPoint)) -> Path {
        let m = point(c, 0.5), a = point(c, 0.47), b = point(c, 0.53)
        let len = max(hypot(b.x - a.x, b.y - a.y), 0.001)
        let u = CGPoint(x: (b.x - a.x) / len, y: (b.y - a.y) / len), n = CGPoint(x: -u.y, y: u.x)
        let size: CGFloat = 4.5
        var p = Path()
        p.move(to: CGPoint(x: m.x - u.x * size / 2 + n.x * size, y: m.y - u.y * size / 2 + n.y * size))
        p.addLine(to: CGPoint(x: m.x + u.x * size / 2, y: m.y + u.y * size / 2))
        p.addLine(to: CGPoint(x: m.x - u.x * size / 2 - n.x * size, y: m.y - u.y * size / 2 - n.y * size))
        return p
    }

    private func draw(_ ctx: inout GraphicsContext, _ lay: FlowLayout, t: Double, particles: Bool) {
        for l in lay.links {
            let c = curve(l)
            var path = Path()
            path.move(to: c.0); path.addCurve(to: c.3, control1: c.1, control2: c.2)
            let width = FlowMotion.ribbonWidth(l.watts)
            guard width > 0 else {
                // Not reported, or known idle: a quiet dashed thread so the tile still reads as connected.
                ctx.stroke(path, with: .color(.primary.opacity(0.14)), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 3]))
                continue
            }
            let (tint, opacity) = color(l.kind)
            let band = Self.band(c, width: width, vertical: l.vertical)
            ctx.fill(band, with: .color(tint.opacity(opacity)))
            ctx.stroke(band, with: .color(tint.opacity(min(1, opacity + 0.3))), lineWidth: 0.75)
            ctx.stroke(Self.chevron(c), with: .color(.primary.opacity(0.85)), style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))

            guard particles, let w = l.watts else { continue }
            let len = Self.length(c)
            let r = min(max(width * 0.12, 1), 2)
            let fade = min(1, Double(width) / 4) // particles thin out with a ribbon that is fading away
            FlowMotion.particles(distance: clock.distance(l.id, at: t), length: len, watts: w) { f in
                let p = Self.point(c, CGFloat(f))
                let edge = min(f, 1 - f) * len / 10 // ease in and out at the tiles
                let a = fade * min(1, edge)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.6 * a)))
            }
        }
    }

    // MARK: Tiles

    /// `caption` names the tile (small, above the value); `note` is an optional third line under the value.
    private struct TileContent {
        var symbol: String, value: String, caption: String, note: String? = nil, tint: Color = .primary, number: Double = 0, big = false
    }

    private func content(_ id: FlowNodeID) -> TileContent {
        let r = reading
        let flows = PowerFlows(reading)
        switch id {
        case .charger:
            guard let r, r.isPluggedIn else {
                return TileContent(symbol: "powerplug", value: "—", caption: "Charger", note: r == nil ? "No data" : "Unplugged", tint: Palette.secondary)
            }
            if let n = pausedAt {
                return TileContent(symbol: "powerplug", value: PowerFlow.watts(0), caption: "Charger", note: "Held at \(n)%", tint: Palette.secondary)
            }
            guard let m = flows.chargerToMac else {
                return TileContent(symbol: "powerplug.fill", value: r.adapterWatts.map { "\($0) W" } ?? "—", caption: "Charger", note: "Rating")
            }
            let supplied = m + (flows.chargerToBattery ?? 0)
            return TileContent(symbol: "powerplug.fill", value: PowerFlow.watts(supplied), caption: "Charger",
                               note: r.adapterWatts.map { "\($0) W capacity" }, number: supplied)
        case .mac:
            return TileContent(symbol: "laptopcomputer", value: PowerFlow.watts(r?.systemWatts), caption: "Mac uses", number: r?.systemWatts ?? 0, big: true)
        case .battery:
            guard let r else { return TileContent(symbol: "battery.0percent", value: "—", caption: "No data", tint: Palette.secondary) }
            let level = [0, 25, 50, 75, 100].min { abs($0 - r.percent) < abs($1 - r.percent) } ?? 50
            switch state {
            case .charging:
                return TileContent(symbol: "battery.100percent.bolt", value: "+" + PowerFlow.watts(r.batteryWatts), caption: "Battery",
                                   tint: Palette.green, number: r.batteryWatts)
            case .onBattery, .chargerTooWeak:
                return TileContent(symbol: "battery.\(level)percent", value: "−" + PowerFlow.watts(r.batteryWatts), caption: "Battery",
                                   tint: Palette.drain, number: -r.batteryWatts)
            default:
                return TileContent(symbol: "battery.\(level)percent", value: PowerFlow.watts(0), caption: "Battery", tint: Palette.secondary)
            }
        case .more:
            return TileContent(symbol: "ellipsis", value: PowerFlow.watts(rest), caption: "Rest of Mac", tint: Palette.secondary, number: rest ?? 0)
        case .stream(let title):
            let w = streams.first { $0.title == title }?.watts
            let symbol = switch title {
            case "SoC": "cpu"
            case "USB": "cable.connector"
            case "Charger loss": "flame"
            default: "square.stack.3d.up"
            }
            return TileContent(symbol: symbol, value: w.map { PowerFlow.watts($0) } ?? "—", caption: title, number: w ?? 0)
        }
    }

    /// Flat raised tile with a hairline. Short tiles put the icon beside the text; the charger and the Mac stack it on top.
    @ViewBuilder private func tile(_ n: FlowLayout.Node) -> some View {
        let c = content(n.id)
        let compact = n.rect.height < 60
        let shape = RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
        Group {
            if compact {
                HStack(spacing: 6) {
                    Image(systemName: c.symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(c.tint).frame(width: 14)
                    VStack(alignment: .leading, spacing: 0) {
                        caption(c.caption)
                        number(c, size: 13)
                        if let note = c.note { caption(note) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
            } else {
                VStack(spacing: 2) {
                    Image(systemName: c.symbol).font(.system(size: c.big ? 17 : 15, weight: .medium)).foregroundStyle(c.tint)
                        .padding(.bottom, 2)
                    caption(c.caption)
                    number(c, size: c.big ? 19 : 15)
                    if let note = c.note { caption(note) }
                }
                .padding(.horizontal, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(n.dimmed ? Color.clear : Palette.raised, in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(n.dimmed ? 0.18 : 0.12), style: StrokeStyle(lineWidth: 1, dash: n.dimmed ? [4, 3] : [])))
        .opacity(n.dimmed ? 0.5 : 1)
        .accessibilityHidden(true)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.7)
    }

    private func number(_ c: TileContent, size: CGFloat) -> some View {
        Text(c.value).font(.system(size: size, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            .contentTransition(.numericText(value: c.number))
            .animation(tick, value: c.number)
    }
}
