import Core
import SwiftUI

/// The animated flow: glass tiles placed from `FlowLayout`, ribbons and travelling light drawn in one Canvas.
/// Ticks at up to 30 fps only while `active`, something is flowing or a change is still easing in; Reduce Motion draws it still.
struct PowerFlowArt: View {
    let reading: BatteryReading?
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var from: FlowLayout?
    @State private var changedAt: Double = 0
    @State private var settled = true
    @State private var clock = ParticleClock()

    private var state: FlowState { FlowState(reading) }
    private var streams: [PowerStream] { PowerFlows.streams(reading) }
    private var rest: Double? { PowerFlows.rest(reading, streams: streams) }
    private var leafCount: Int { streams.count + ((rest ?? 0) >= PowerFlows.hideBelow ? 1 : 0) }

    private func layout(_ w: CGFloat) -> FlowLayout {
        FlowLayout.make(state: state, flows: PowerFlows(reading), streams: streams, rest: rest, width: w)
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
                GlassEffectContainer(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        ForEach(target.nodes, id: \.id) { n in
                            tile(n).frame(width: n.rect.width, height: n.rect.height)
                                .position(x: n.rect.midX, y: n.rect.midY)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: geo.size.width, height: target.size.height, alignment: .topLeading)
                }
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

    private func colors(_ k: FlowLinkKind) -> (Color, Color) {
        switch k {
        case .supply: (Palette.amber, Palette.accent)
        case .charge: (Palette.amber, Palette.green)
        case .drain: (Palette.drain, Palette.accent)
        case .stream: (Palette.accent, Palette.secondary)
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
            let (src, dst) = colors(l.kind)
            let grad = Gradient(colors: [src.opacity(0.55), dst.opacity(0.8)])
            let shade = GraphicsContext.Shading.linearGradient(grad, startPoint: c.0, endPoint: c.3)
            // Soft halo, body, then a thin glassy sheen along the top of the ribbon.
            ctx.stroke(path, with: .linearGradient(Gradient(colors: [src.opacity(0.10), dst.opacity(0.14)]), startPoint: c.0, endPoint: c.3),
                       style: StrokeStyle(lineWidth: width + 7, lineCap: .round))
            ctx.stroke(path, with: shade, style: StrokeStyle(lineWidth: width, lineCap: .round))
            ctx.stroke(path.offsetBy(dx: 0, dy: l.vertical ? 0 : -width * 0.18), with: .color(.white.opacity(0.22)),
                       style: StrokeStyle(lineWidth: max(0.75, width * 0.22), lineCap: .round))

            guard particles, let w = l.watts else { continue }
            let len = Self.length(c)
            let r = min(max(width * 0.26, 1.2), 3.2)
            let fade = min(1, Double(width) / 4) // particles thin out with a ribbon that is fading away
            FlowMotion.particles(distance: clock.distance(l.id, at: t), length: len, watts: w) { f in
                let p = Self.point(c, CGFloat(f))
                let edge = min(f, 1 - f) * len / 10 // ease in and out at the tiles
                let a = fade * min(1, edge)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 2.4, y: p.y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                         with: .color(dst.opacity(0.22 * a)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.9 * a)))
            }
        }
    }

    // MARK: Tiles

    private struct TileContent {
        var symbol: String, value: String, caption: String, tint: Color, number: Double = 0, big = false
    }

    private func content(_ id: FlowNodeID) -> TileContent {
        let r = reading
        let flows = PowerFlows(reading)
        switch id {
        case .charger:
            guard let r, r.isPluggedIn else {
                return TileContent(symbol: "powerplug", value: "—", caption: r == nil ? "No data" : "Unplugged", tint: Palette.secondary)
            }
            let rating = r.adapterWatts.map { "of \($0) W" } ?? "Charger"
            guard let m = flows.chargerToMac else {
                return TileContent(symbol: "powerplug.fill", value: r.adapterWatts.map { "\($0) W" } ?? "—", caption: "Charger rating", tint: Palette.amber)
            }
            let supplied = m + (flows.chargerToBattery ?? 0)
            return TileContent(symbol: "powerplug.fill", value: PowerFlow.watts(supplied), caption: rating, tint: Palette.amber, number: supplied)
        case .mac:
            return TileContent(symbol: "laptopcomputer", value: PowerFlow.watts(r?.systemWatts), caption: "Mac uses", tint: Palette.accent,
                               number: r?.systemWatts ?? 0, big: true)
        case .battery:
            guard let r else { return TileContent(symbol: "battery.0percent", value: "—", caption: "No data", tint: Palette.secondary) }
            let level = [0, 25, 50, 75, 100].min { abs($0 - r.percent) < abs($1 - r.percent) } ?? 50
            switch state {
            case .charging:
                return TileContent(symbol: "battery.100percent.bolt", value: PowerFlow.watts(r.batteryWatts), caption: "Charging · \(r.percent)%",
                                   tint: Palette.green, number: r.batteryWatts)
            case .onBattery, .chargerTooWeak:
                return TileContent(symbol: "battery.\(level)percent", value: PowerFlow.watts(r.batteryWatts), caption: "From battery · \(r.percent)%",
                                   tint: Palette.drain, number: -r.batteryWatts)
            default:
                return TileContent(symbol: "battery.\(level)percent", value: PowerFlow.watts(0), caption: "Idle · \(r.percent)%", tint: Palette.secondary)
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
            return TileContent(symbol: symbol, value: w.map { PowerFlow.watts($0) } ?? "—", caption: title, tint: Palette.secondary, number: w ?? 0)
        }
    }

    @ViewBuilder private func tile(_ n: FlowLayout.Node) -> some View {
        let c = content(n.id)
        let shape = RoundedRectangle(cornerRadius: n.rect.height < 40 ? 11 : 15, style: .continuous)
        let leaf = n.rect.height < 40
        Group {
            if leaf {
                HStack(spacing: 5) {
                    Image(systemName: c.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(c.tint).frame(width: 12)
                    VStack(alignment: .leading, spacing: 0) {
                        number(c, size: 12)
                        Text(c.caption).font(.system(size: 9.5)).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
            } else {
                VStack(spacing: c.big ? 3 : 2) {
                    Image(systemName: c.symbol).font(.system(size: c.big ? 17 : 14, weight: .medium)).foregroundStyle(c.tint)
                        .symbolRenderingMode(.hierarchical)
                    number(c, size: c.big ? 19 : 14)
                    Text(c.caption).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular.tint(c.tint.opacity(n.dimmed ? 0 : 0.10)), in: shape)
        .overlay(shape.strokeBorder(n.dimmed ? Color.primary.opacity(0.18) : c.tint.opacity(0.22),
                                    style: StrokeStyle(lineWidth: 1, dash: n.dimmed ? [4, 3] : [])))
        .opacity(n.dimmed ? 0.5 : 1)
        .accessibilityHidden(true)
    }

    private func number(_ c: TileContent, size: CGFloat) -> some View {
        Text(c.value).font(.system(size: size, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            .contentTransition(.numericText(value: c.number))
            .animation(tick, value: c.number)
    }
}
