import Core
import SwiftUI

/// The animated flow: flat tiles placed from `FlowLayout`, Sankey ribbons, chevrons and travelling dots drawn in one Canvas.
/// Ticks at up to 30 fps only while `active`, something is flowing or a change is still easing in; Reduce Motion draws it still.
struct PowerFlowArt: View {
    let reading: BatteryReading?
    let active: Bool
    /// The charge limit is holding the charger off at this percent.
    var pausedAt: Int?
    /// The tile the owner tapped (it is drawn with a stronger outline) and what to do when a tile is tapped.
    var selected: FlowNodeID?
    var onSelect: (FlowNodeID) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var from: FlowLayout?
    @State private var changedAt: Double = 0
    @State private var settled = true
    @State private var clock = ParticleClock()
    @State private var live = LiveResize.shared
    /// Where the owner has dragged tiles (kept across launches) and the tile being dragged right now.
    @AppStorage(FlowOffsets.storageKey) private var savedOffsets = ""
    @State private var drag: (id: FlowNodeID, by: CGSize)?

    private var state: FlowState { FlowState(reading) }
    private var streams: [PowerStream] { PowerFlows.streams(reading) }
    private var rest: Double? { PowerFlows.rest(reading, streams: streams) }
    private var leafCount: Int { streams.count }

    private func base(_ w: CGFloat) -> FlowLayout {
        FlowLayout.make(state: state, flows: PowerFlows(reading), streams: streams, rest: rest, width: w, held: pausedAt != nil)
    }

    private var offsets: FlowOffsets {
        let saved = FlowOffsets(json: savedOffsets)
        guard let drag else { return saved }
        return saved.adding(drag.by, to: drag.id)
    }

    private func layout(_ w: CGFloat) -> FlowLayout { base(w).applying(offsets) }

    /// Drag a tile to move it; the ribbons follow. A short press without movement stays a tap.
    private func dragTile(_ id: FlowNodeID, width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { v in drag = (id, v.translation) }
            .onEnded { v in
                savedOffsets = FlowOffsets(json: savedOffsets).dropping(id, by: v.translation, base: base(w)).json
                drag = nil
            }
    }

    private static let space = "powerFlowMap"

    /// What the map is made of, apart from sizes: animations follow this, not every pixel of a resize.
    private struct Topology: Hashable { var state: FlowState; var streams: [String]; var held: Bool }
    private var topology: Topology { Topology(state: state, streams: streams.compactMap { $0.watts == nil ? nil : $0.title }, held: pausedAt != nil) }

    private var tick: Animation? { reduceMotion ? nil : .smooth(duration: FlowMotion.transition) }

    var body: some View {
        GeometryReader { geo in
            let target = layout(geo.size.width)
            let moving = target.links.contains { ($0.watts ?? 0) > 0.05 }
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: drag == nil && (!active || reduceMotion || live.active || (!moving && settled)))) { tl in
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
                            .contentShape(Rectangle())
                            .scaleEffect(drag?.id == n.id ? 1.04 : 1)
                            .shadow(color: .black.opacity(drag?.id == n.id ? 0.35 : 0), radius: 10, y: 4)
                            .gesture(dragTile(n.id, width: geo.size.width))
                            .onTapGesture { onSelect(n.id) }
                            .position(x: n.rect.midX, y: n.rect.midY)
                            .transition(.opacity)
                    }
                }
                .frame(width: geo.size.width, height: target.size.height, alignment: .topLeading)
            }
            .coordinateSpace(.named(Self.space))
            // Animate only real changes (state, tiles, held), never the geometry changes of a window resize.
            .animation(tick, value: topology)
            .onChange(of: target) { old, new in
                let now = Date.now.timeIntervalSinceReferenceDate
                // The panel was resized, or a tile is being dragged: snap, no easing, so the ribbons stay on the tile.
                if abs(old.size.width - new.size.width) > 0.5 || drag != nil {
                    from = nil; settled = true
                    clock.update(speeds: Dictionary(new.links.map { ($0.id, FlowMotion.speed($0.watts ?? 0)) }, uniquingKeysWith: { a, _ in a }), at: now)
                    return
                }
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

    /// Ribbon colors, from the source end to the destination end: power the Mac uses is vivid blue brightening along the flow,
    /// charge into the battery green, power taken from the battery warm orange into amber.
    private func colors(_ k: FlowLinkKind) -> (Color, Color) {
        switch k {
        case .supply, .stream: (Palette.flow, Palette.flowLight)
        case .charge: (Palette.green, Palette.green)
        case .drain: (Palette.drain, Palette.amber)
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

    /// One edge of a Sankey band (k = -1 top, 1 bottom). It leaves the source at `w0`, pinches a little in the middle
    /// and swells to `w1` at the destination, so the ribbon reads as a soft S rather than a pipe.
    private static func edge(_ c: (CGPoint, CGPoint, CGPoint, CGPoint), _ w0: CGFloat, _ w1: CGFloat, vertical: Bool, _ k: CGFloat) -> [CGPoint] {
        let waist = (w0 + w1) / 2 * 0.8
        func s(_ p: CGPoint, _ w: CGFloat) -> CGPoint { vertical ? CGPoint(x: p.x + w / 2 * k, y: p.y) : CGPoint(x: p.x, y: p.y + w / 2 * k) }
        return [s(c.0, w0), s(c.1, waist), s(c.2, waist), s(c.3, w1)]
    }

    private static func band(_ c: (CGPoint, CGPoint, CGPoint, CGPoint), width w: CGFloat, vertical: Bool) -> (fill: Path, top: Path) {
        let t = edge(c, w, w * 1.15, vertical: vertical, -1), b = edge(c, w, w * 1.15, vertical: vertical, 1)
        var top = Path()
        top.move(to: t[0]); top.addCurve(to: t[3], control1: t[1], control2: t[2])
        var p = top
        p.addLine(to: b[3]); p.addCurve(to: b[0], control1: b[2], control2: b[1])
        p.closeSubpath()
        return (p, top)
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
        if particles { breathe(&ctx, lay, t: t) }
        for l in lay.links {
            let c = curve(l)
            var path = Path()
            path.move(to: c.0); path.addCurve(to: c.3, control1: c.1, control2: c.2)
            let width = FlowMotion.ribbonWidth(l.watts)
            guard width > 0 else {
                if pausedAt != nil, l.id == FlowLinkID(.charger, .mac) {
                    pausedLink(&ctx, path, c, l)
                } else {
                    // Not reported, or known idle: a quiet dashed thread so the tile still reads as connected.
                    ctx.stroke(path, with: .color(.primary.opacity(0.18)), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [3, 3]))
                }
                continue
            }
            let (src, dst) = colors(l.kind)
            let charge = l.kind == .charge
            let band = Self.band(c, width: width, vertical: l.vertical)
            // Soft feathered glow, the body brightening along the flow, then a light top edge.
            ctx.drawLayer { g in
                g.addFilter(.blur(radius: charge ? 3.5 : 6))
                g.fill(band.fill, with: .linearGradient(Gradient(colors: [src.opacity(charge ? 0.7 : 0.3), dst.opacity(charge ? 0.7 : 0.45)]),
                                                        startPoint: c.0, endPoint: c.3))
            }
            ctx.fill(band.fill, with: .linearGradient(Gradient(colors: [src.opacity(charge ? 0.95 : 0.6), dst.opacity(charge ? 0.95 : 0.8)]),
                                                      startPoint: c.0, endPoint: c.3))
            ctx.stroke(band.top, with: .color(.white.opacity(charge ? 0.25 : 0.4)), lineWidth: 1)
            ctx.stroke(Self.chevron(c), with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            guard particles, let w = l.watts else { continue }
            let len = Self.length(c)
            let r = min(max(width * 0.14, 1.3), 2.6)
            let fade = min(1, Double(width) / 4) // pulses thin out with a ribbon that is fading away
            // Comets: a bright head with a fading tail behind it, longer the faster the power moves.
            let tail = min(6, 2 + Int(w / 6)), step = 3.2 / len
            ctx.drawLayer { g in
                g.addFilter(.blur(radius: 1.1))
                FlowMotion.particles(distance: clock.distance(l.id, at: t), length: len, watts: w) { f in
                    for k in 0...tail {
                        let fk = f - Double(k) * step
                        guard fk > 0 else { break }
                        let p = Self.point(c, CGFloat(fk))
                        let a = fade * min(1, min(fk, 1 - fk) * len / 10) * (1 - Double(k) / Double(tail + 1)) // ease in and out at the tiles
                        let rk = r * (1.15 - 0.6 * CGFloat(k) / CGFloat(tail))
                        g.fill(Path(ellipseIn: CGRect(x: p.x - rk, y: p.y - rk, width: rk * 2, height: rk * 2)), with: .color(.white.opacity(0.95 * a)))
                    }
                }
            }
        }
    }

    /// A soft glow behind each tile that power is passing through, swelling and easing at a pace set by its watts.
    private func breathe(_ ctx: inout GraphicsContext, _ lay: FlowLayout, t: Double) {
        for n in lay.nodes where !n.dimmed {
            let links = lay.links.filter { $0.id.from == n.id || $0.id.to == n.id }
            guard let top = links.max(by: { ($0.watts ?? 0) < ($1.watts ?? 0) }), let w = top.watts, w > 0.5 else { continue }
            let tint = n.id == .charger ? Palette.amber : colors(top.kind).0
            let pulse = (sin(t * (1.6 + min(w, 40) / 10)) + 1) / 2
            let strength = min(1, w / 20)
            ctx.drawLayer { g in
                g.addFilter(.blur(radius: 9))
                g.fill(RoundedRectangle(cornerRadius: 14, style: .continuous).path(in: n.rect.insetBy(dx: -3, dy: -3)),
                       with: .color(tint.opacity((0.12 + 0.28 * pulse) * strength)))
            }
        }
    }

    /// The held charger link: a dashed amber thread with a small "Paused" pill (a pause glyph when the gap is too narrow).
    private func pausedLink(_ ctx: inout GraphicsContext, _ path: Path, _ c: (CGPoint, CGPoint, CGPoint, CGPoint), _ l: FlowLayout.Link) {
        ctx.stroke(path, with: .color(Palette.amber.opacity(0.75)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3]))
        let m = Self.point(c, 0.5)
        let label = ctx.resolve(Text("Paused").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.amberText))
        let size = label.measure(in: CGSize(width: 100, height: 20))
        let wide = size.width + 14 <= l.end.x - l.start.x - 8
        let pill = wide ? CGRect(x: m.x - size.width / 2 - 7, y: m.y - 8, width: size.width + 14, height: 16) : CGRect(x: m.x - 8, y: m.y - 8, width: 16, height: 16)
        let shape = Capsule().path(in: pill)
        ctx.fill(shape, with: .color(Palette.amberFill))
        ctx.stroke(shape, with: .color(Palette.amber.opacity(0.6)), lineWidth: 1)
        if wide {
            ctx.draw(label, at: m)
        } else {
            var glyph = ctx.resolve(Image(systemName: "pause.fill"))
            glyph.shading = .color(Palette.amberText)
            ctx.draw(glyph, in: pill.insetBy(dx: 4.5, dy: 4.5))
        }
    }

    // MARK: Tiles

    /// `caption` names the tile (small, above the value); `note` is an optional third line under the value.
    /// `lit` tiles glow in their tint; idle, held and missing ones stay neutral. `badge` is a small corner glyph, if a tile ever needs one.
    private struct TileContent {
        var symbol: String, value: String, caption: String, note: String? = nil, tint: Color, number: Double = 0, big = false
        var lit = true, badge: String? = nil
    }

    private func content(_ id: FlowNodeID) -> TileContent {
        let r = reading
        let flows = PowerFlows(reading)
        switch id {
        case .charger:
            guard let r, r.isPluggedIn else {
                return TileContent(symbol: "powerplug", value: "—", caption: "Charger", note: r == nil ? "No data" : "Unplugged",
                                   tint: Palette.secondary, lit: false)
            }
            if let n = pausedAt {
                return TileContent(symbol: "powerplug", value: PowerFlow.watts(0), caption: "Charger", note: "Held at \(n)%",
                                   tint: Palette.secondary, lit: false)
            }
            guard let m = flows.chargerToMac else {
                return TileContent(symbol: "powerplug.fill", value: r.adapterWatts.map { "\($0) W" } ?? "—", caption: "Charger", note: "Rating", tint: Palette.amber)
            }
            let supplied = m + (flows.chargerToBattery ?? 0)
            return TileContent(symbol: "powerplug.fill", value: PowerFlow.watts(supplied), caption: "Charger",
                               note: r.adapterWatts.map { "\($0) W capacity" }, tint: Palette.amber, number: supplied)
        case .mac:
            return TileContent(symbol: "laptopcomputer", value: PowerFlow.watts(r?.systemWatts), caption: "Mac uses", tint: Palette.flow,
                               number: r?.systemWatts ?? 0, big: true, lit: r?.systemWatts != nil)
        case .battery:
            guard let r else { return TileContent(symbol: "battery.0percent", value: "—", caption: "No data", tint: Palette.secondary, lit: false) }
            let level = [0, 25, 50, 75, 100].min { abs($0 - r.percent) < abs($1 - r.percent) } ?? 50
            switch state {
            case .charging:
                return TileContent(symbol: "battery.100percent.bolt", value: "+" + PowerFlow.watts(r.batteryWatts), caption: "Battery",
                                   tint: Palette.green, number: r.batteryWatts)
            case .onBattery, .chargerTooWeak:
                return TileContent(symbol: "battery.\(level)percent", value: "−" + PowerFlow.watts(r.batteryWatts), caption: "Battery",
                                   tint: Palette.drain, number: -r.batteryWatts)
            default:
                return TileContent(symbol: "battery.\(level)percent", value: PowerFlow.watts(0), caption: "Battery", tint: Palette.secondary, lit: false)
            }
        case .more:
            return TileContent(symbol: "ellipsis", value: PowerFlow.watts(rest), caption: "Rest of Mac", tint: Palette.secondary, number: rest ?? 0, lit: false)
        case .stream(let title):
            let w = streams.first { $0.title == title }?.watts
            let device = r?.usbDeviceName?.lowercased() ?? ""
            let symbol = switch title {
            case "SoC": "cpu"
            case "USB" where device.hasPrefix("iphone"): "iphone"
            case "USB" where device.hasPrefix("ipad"): "ipad"
            case "USB": "cable.connector"
            case "Charger loss": "flame"
            default: "square.stack.3d.up"
            }
            let caption = title == "USB" ? r?.usbCaption ?? title : title
            return TileContent(symbol: symbol, value: w.map { PowerFlow.watts($0) } ?? "—", caption: caption, tint: Palette.flow, number: w ?? 0)
        }
    }

    /// Lifted tile: a soft vertical gradient, a hairline in its stream's tint with a faint glow, and a light inner top edge.
    /// Short tiles put the icon beside the text; the charger and the Mac stack it on top.
    @ViewBuilder private func tile(_ n: FlowLayout.Node) -> some View {
        let c = content(n.id)
        let compact = n.rect.height < 60
        let lit = c.lit && !n.dimmed
        let shape = RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous)
        Group {
            if compact {
                HStack(spacing: 4) {
                    icon(c, size: 14).frame(width: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        caption(c.caption)
                        number(c, size: 14)
                        if let note = c.note { caption(note) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5)
            } else {
                VStack(spacing: 1) {
                    icon(c, size: c.big ? 20 : 18).padding(.bottom, 2)
                    caption(c.caption)
                    number(c, size: c.big ? 22 : 18)
                    if let note = c.note { caption(note) }
                }
                .padding(.horizontal, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if !n.dimmed {
                shape.fill(LinearGradient(colors: [Palette.raisedTop, Palette.raised], startPoint: .top, endPoint: .bottom))
                    .shadow(color: c.tint.opacity(lit ? 0.3 : 0), radius: 8)
            }
        }
        .overlay {
            shape.strokeBorder(n.id == selected ? c.tint : (lit ? c.tint.opacity(0.45) : Color.primary.opacity(n.dimmed ? 0.2 : 0.12)),
                               style: StrokeStyle(lineWidth: n.id == selected ? 2 : 1, dash: n.dimmed ? [4, 3] : []))
            if !n.dimmed {
                shape.inset(by: 1).stroke(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge = c.badge {
                Image(systemName: badge).font(.system(size: 7, weight: .bold)).foregroundStyle(Palette.amberText)
                    .frame(width: 16, height: 16)
                    .background(Palette.amberFill, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.amber.opacity(0.6)))
                    .padding(4)
            }
        }
        .opacity(n.dimmed ? 0.55 : 1)
        .accessibilityHidden(true)
    }

    private func icon(_ c: TileContent, size: CGFloat) -> some View {
        Image(systemName: c.symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(c.tint).symbolRenderingMode(.hierarchical)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.7)
    }

    private func number(_ c: TileContent, size: CGFloat) -> some View {
        Text(c.value).font(.system(size: size, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            .contentTransition(.numericText(value: c.number))
            .animation(tick, value: c.number)
    }
}
