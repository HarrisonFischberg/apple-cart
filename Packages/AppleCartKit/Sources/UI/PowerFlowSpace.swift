import Core
import SwiftUI

/// The 3D power flow: the Mac is a ringed planet, the charger its sun (the planet is lit from wherever the sun is),
/// the battery and outside devices moons. Drag empty space to turn the view (a flick coasts, then settles); drag a moon
/// to slide it along its orbit. The view and the moons are remembered. Ticks only while `active`; Reduce Motion draws it still.
struct PowerFlowSpace: View {
    let reading: BatteryReading?
    let active: Bool
    var pausedAt: Int?
    var selected: FlowNodeID?
    var onSelect: (FlowNodeID) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(SpaceView.storageKey) private var saved = ""
    /// The view while a drag is under way; nil when at rest (then `saved` is what shows).
    @State private var live: SpaceView?
    @State private var grab: Grab?
    @State private var coast: Coast?
    @State private var clock = ParticleClock()
    @State private var resize = LiveResize.shared

    private enum Grab: Equatable { case rotate(SpaceCamera), moon(FlowNodeID) }
    /// A flick: the camera keeps turning from `from` at `velocity` (points per second), easing out.
    private struct Coast: Equatable { var from: SpaceView; var velocity: CGSize; var start: Double }
    private static let coastDecay = 3.0

    private var stored: SpaceView { SpaceView(json: saved) }
    private var streams: [PowerStream] { PowerFlows.streams(reading) }
    private var state: FlowState { FlowState(reading) }
    private var flows: PowerFlows { PowerFlows(reading) }

    private func current(at t: Double) -> SpaceView {
        if let live { return live }
        guard let coast else { return stored }
        let k = Self.coastDecay, e = (1 - exp(-k * max(0, t - coast.start))) / k
        var v = coast.from
        v.camera = v.camera.dragged(coast.velocity.width * e, coast.velocity.height * e)
        return v
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || reduceMotion || resize.active)) { tl in
                Canvas { ctx, _ in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    draw(&ctx, size: size, view: current(at: t), t: t, moving: active && !reduceMotion)
                }
            }
            .contentShape(Rectangle())
            .gesture(drag(size))
            .simultaneousGesture(SpatialTapGesture().onEnded { v in
                if let id = hit(v.location, size: size, view: current(at: Date.now.timeIntervalSinceReferenceDate)) { onSelect(id) }
            })
            .onAppear { retime() }
            .onChange(of: speeds) { retime() }
            .task(id: coast?.start) {
                // Settle a flick and remember where it stopped.
                guard let c = coast else { return }
                try? await Task.sleep(for: .seconds(1.6))
                guard coast?.start == c.start else { return }
                saved = current(at: c.start + 10).json
                coast = nil
            }
        }
        .frame(height: PowerSpace.height)
    }

    // MARK: Gestures

    private func layout(_ size: CGSize) -> (center: CGPoint, scale: Double) {
        (CGPoint(x: size.width / 2, y: size.height / 2 + 8), Double(min(size.width, size.height * 1.25)) / PowerSpace.span)
    }

    private func orbits(_ v: SpaceView) -> [(FlowNodeID, SpaceOrbit)] { PowerSpace.orbits(streams: streams, angles: v.angles) }

    /// The body under `p`, nearest the viewer first; the planet counts as the Mac.
    private func hit(_ p: CGPoint, size: CGSize, view v: SpaceView) -> FlowNodeID? {
        let (center, scale) = layout(size)
        let bodies = orbits(v).map { id, o in
            let c = v.camera.view(o.position())
            let q = v.camera.project(c, center: center, scale: scale)
            return (id, q.point, radius(id) * q.s * scale / 26 + 8, c.z)
        }
        if let b = bodies.filter({ hypot($0.1.x - p.x, $0.1.y - p.y) < $0.2 }).max(by: { $0.3 < $1.3 }) { return b.0 }
        return hypot(p.x - center.x, p.y - center.y) < scale + 6 ? .mac : nil // the planet is one unit across, at depth 0
    }

    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                let now = Date.now.timeIntervalSinceReferenceDate
                if grab == nil {
                    let start = current(at: now)
                    coast = nil
                    live = start
                    if let id = hit(v.startLocation, size: size, view: start), id != .mac { grab = .moon(id) } else { grab = .rotate(start.camera) }
                }
                guard var view = live else { return }
                switch grab {
                case .rotate(let from):
                    view.camera = from.dragged(v.translation.width, v.translation.height)
                case .moon(let id):
                    guard let o = orbits(view).first(where: { $0.0 == id })?.1 else { return }
                    let (center, scale) = layout(size)
                    view.angles[id] = o.angle(nearest: v.location, camera: view.camera, center: center, scale: scale)
                case nil: break
                }
                live = view
            }
            .onEnded { v in
                guard let view = live else { return }
                if case .rotate = grab, !reduceMotion, hypot(v.velocity.width, v.velocity.height) > 80 {
                    coast = Coast(from: view, velocity: v.velocity, start: Date.now.timeIntervalSinceReferenceDate)
                } else {
                    saved = view.json
                }
                live = nil; grab = nil
            }
    }

    // MARK: Model

    private struct Body { var id: FlowNodeID; var caption: String; var value: String; var tint: Color; var watts: Double?; var lit: Bool; var sun = false }
    private struct Flow { var id: FlowLinkID; var watts: Double?; var kind: FlowLinkKind }

    private func radius(_ id: FlowNodeID) -> Double {
        switch id {
        case .charger: reading?.isPluggedIn == true ? 9 + max(supplied ?? 0, 0).squareRoot() * 0.9 : 7
        case .battery: PowerSpace.moonSize(abs(reading?.batteryWatts ?? 0)) + 0.5
        default: PowerSpace.moonSize(streams.first { FlowNodeID.stream($0.title) == id }?.watts)
        }
    }

    private var supplied: Double? { flows.chargerToMac.map { $0 + (flows.chargerToBattery ?? 0) } }

    private func info(_ id: FlowNodeID) -> Body {
        let r = reading
        switch id {
        case .charger:
            guard let r, r.isPluggedIn else { return Body(id: id, caption: "Charger", value: r == nil ? "—" : "Unplugged", tint: .gray, watts: nil, lit: false, sun: true) }
            let caption = r.adapterWatts.map { "Charger · \($0) W" } ?? "Charger"
            if let n = pausedAt { return Body(id: id, caption: caption, value: "Held at \(n)%", tint: Palette.amber, watts: 0, lit: false, sun: true) }
            return Body(id: id, caption: caption, value: PowerFlow.watts(supplied), tint: Palette.amber, watts: supplied, lit: true, sun: true)
        case .battery:
            let caption = "Battery" // its level sits under the planet
            switch state {
            case .charging: return Body(id: id, caption: caption, value: "+" + PowerFlow.watts(r?.batteryWatts), tint: Palette.green, watts: r?.batteryWatts, lit: true)
            case .onBattery, .chargerTooWeak: return Body(id: id, caption: caption, value: "−" + PowerFlow.watts(r?.batteryWatts), tint: Palette.drain, watts: r.map { -$0.batteryWatts }, lit: true)
            default: return Body(id: id, caption: caption, value: r == nil ? "—" : "Idle", tint: Color(white: 0.55), watts: 0, lit: false)
            }
        default:
            guard case .stream(let title) = id else { return Body(id: id, caption: "", value: "", tint: .gray, watts: nil, lit: false) }
            let w = streams.first { $0.title == title }?.watts
            let caption = title == "USB" ? r?.usbCaption ?? title : title
            return Body(id: id, caption: caption, value: PowerFlow.watts(w), tint: Color(red: 0.61, green: 0.79, blue: 1), watts: w, lit: (w ?? 0) > 0.05)
        }
    }

    /// The arcs power travels on, which way, and how much.
    private var links: [Flow] {
        var out: [Flow] = []
        switch state {
        case .noData:
            out.append(Flow(id: FlowLinkID(.charger, .mac), watts: nil, kind: .supply))
        case .onBattery:
            out.append(Flow(id: FlowLinkID(.battery, .mac), watts: flows.batteryToMac, kind: .drain))
        case .charging:
            out.append(Flow(id: FlowLinkID(.charger, .mac), watts: flows.chargerToMac, kind: .supply))
            out.append(Flow(id: FlowLinkID(.mac, .battery), watts: flows.chargerToBattery, kind: .charge))
        case .pluggedIdle:
            out.append(Flow(id: FlowLinkID(.charger, .mac), watts: pausedAt != nil ? 0 : flows.chargerToMac, kind: .supply))
            out.append(Flow(id: FlowLinkID(.mac, .battery), watts: 0, kind: .charge))
        case .chargerTooWeak:
            out.append(Flow(id: FlowLinkID(.charger, .mac), watts: pausedAt != nil ? 0 : flows.chargerToMac, kind: .supply))
            out.append(Flow(id: FlowLinkID(.battery, .mac), watts: flows.batteryToMac, kind: .drain))
        }
        for s in streams where s.watts != nil { out.append(Flow(id: FlowLinkID(.mac, .stream(s.title)), watts: s.watts, kind: .stream)) }
        return out
    }

    /// Comet speed along each arc in world units per second, and the ring's spin under a link id of its own.
    private static let ringID = FlowLinkID(.mac, .mac)
    private var speeds: [FlowLinkID: Double] {
        var d = Dictionary(links.map { ($0.id, ($0.watts ?? 0) > 0.05 ? 0.8 + min($0.watts!, 60) * 0.11 : 0) }, uniquingKeysWith: { a, _ in a })
        d[Self.ringID] = OrbitRing.spin(reading?.systemWatts)
        return d
    }

    private func retime() { clock.update(speeds: speeds, at: Date.now.timeIntervalSinceReferenceDate) }

    private func tint(_ f: Flow) -> Color {
        switch f.kind {
        case .supply: Palette.amber
        case .charge: Palette.green
        case .drain: Palette.drain
        case .stream: Palette.flowLight
        }
    }

    private var ringColor: Color {
        switch state {
        case .charging: Palette.green
        case .onBattery, .chargerTooWeak: Palette.drain
        default: Color(red: 0.91, green: 0.83, blue: 0.65)
        }
    }

    // MARK: Drawing

    private static let stars: [(v: Vec3, b: Double, p: Double)] = (0..<200).map { i in
        let d = Double(i)
        let u = abs((sin(d * 12.99) * 43758.5).truncatingRemainder(dividingBy: 1)), w = abs((sin(d * 78.23) * 12543.3).truncatingRemainder(dividingBy: 1))
        let th = u * 2 * .pi, ph = acos(2 * w - 1)
        return (Vec3(sin(ph) * cos(th), cos(ph), sin(ph) * sin(th)), 0.25 + abs((sin(d * 3.7) * 999).truncatingRemainder(dividingBy: 1)) * 0.6, d)
    }
    private static let dust: [(u: Double, a: Double, s: Double)] = (0..<240).map { i in
        let d = Double(i)
        return (abs((sin(d * 91.7) * 24634.6).truncatingRemainder(dividingBy: 1)), abs((sin(d * 33.1) * 9137.3).truncatingRemainder(dividingBy: 1)) * 2 * .pi,
                0.6 + abs((sin(d * 5.3) * 733.1).truncatingRemainder(dividingBy: 1)))
    }

    /// One thing to paint, with its depth: everything behind the planet's centre is painted before the planet, the rest after.
    private enum Mark {
        case line(CGPoint, CGPoint, Color, CGFloat, Bool) // the last is dashed
        case quad([CGPoint], Color)
        case dot(CGRect, Color)
        case comet(CGPoint, CGFloat, Double)
        case body(Body, CGPoint, CGFloat)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, view v: SpaceView, t: Double, moving: Bool) {
        let (center, scale) = layout(size), cam = v.camera
        func project(_ w: Vec3) -> (CGPoint, Double, Double) { let c = cam.view(w); let q = cam.project(c, center: center, scale: scale); return (q.point, q.s, c.z) }

        let frame = RoundedRectangle(cornerRadius: 14, style: .continuous).path(in: CGRect(origin: .zero, size: size))
        ctx.fill(frame, with: .radialGradient(Gradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.16), Color(red: 0.04, green: 0.05, blue: 0.08), Color(red: 0.02, green: 0.02, blue: 0.03)]),
                                              center: center, startRadius: 10, endRadius: max(size.width, size.height) * 0.8))
        ctx.clip(to: frame)
        for s in Self.stars {
            let c = cam.view(s.v)
            guard c.z <= 0.15 else { continue }
            let p = CGPoint(x: center.x + c.x * size.width * 0.9, y: center.y - c.y * size.width * 0.9)
            let a = s.b * (moving ? 0.55 + 0.45 * sin(t * 1.2 + s.p) : 0.7)
            ctx.fill(Path(CGRect(x: p.x, y: p.y, width: 1.2, height: 1.2)), with: .color(.white.opacity(a)))
        }

        var marks: [(Double, Mark)] = []
        let os = orbits(v)
        // Orbits, faint.
        for (_, o) in os {
            var prev = project(o.position(at: 0))
            for i in 1...72 {
                let q = project(o.position(at: Double(i) / 72 * 2 * .pi))
                let z = (q.2 + prev.2) / 2
                marks.append((z, .line(prev.0, q.0, .white.opacity(0.05 + (z + 6) / 12 * 0.07), 1, false)))
                prev = q
            }
        }
        // The ring, as short pieces so each sorts by its own depth; then its dust.
        let ring = ringColor
        for (inner, outer, opacity) in OrbitRing.bands {
            for i in 0..<64 {
                let a0 = Double(i) / 64 * 2 * .pi, a1 = Double(i + 1) / 64 * 2 * .pi
                let pts = [PowerSpace.ringPoint(inner, a0), PowerSpace.ringPoint(outer, a0), PowerSpace.ringPoint(outer, a1), PowerSpace.ringPoint(inner, a1)].map { project($0).0 }
                let z = cam.view(PowerSpace.ringPoint((inner + outer) / 2, (a0 + a1) / 2)).z
                marks.append((z, .quad(pts, ring.opacity(opacity * (z < 0 ? 0.7 : 1)))))
            }
        }
        let phase = clock.distance(Self.ringID, at: t)
        for d in Self.dust {
            let rr = OrbitRing.dustInner + d.u * OrbitRing.dustSpan
            let q = project(PowerSpace.ringPoint(rr, d.a + phase * 2 * pow(OrbitRing.dustInner / rr, 1.5)))
            let s = d.s * q.1
            marks.append((q.2, .dot(CGRect(x: q.0.x, y: q.0.y, width: s, height: s), Color(red: 1, green: 0.98, blue: 0.92).opacity(q.2 < 0 ? 0.35 : 0.7))))
        }
        // Arcs and comets.
        let pos = Dictionary(os.map { ($0.0, $0.1.position()) }, uniquingKeysWith: { a, _ in a })
        for f in links {
            let fromMac = f.id.from == .mac, other = fromMac ? f.id.to : f.id.from
            guard let body = pos[other] else { continue }
            let a = fromMac ? PowerSpace.landing(toward: body) : body, b = fromMac ? body : PowerSpace.landing(toward: body)
            let on = (f.watts ?? 0) > 0.05, col = tint(f)
            let held = pausedAt != nil && f.id == FlowLinkID(.charger, .mac)
            var prev = project(a), length = 0.0, prevW = a
            for i in 1...24 {
                let w = PowerSpace.arc(a, b, Double(i) / 24), q = project(w)
                length += (w + prevW * -1).length
                let width: CGFloat = on ? CGFloat(min(max((f.watts ?? 0) * 0.25, 1.2), 7) * prev.1) : 1
                marks.append(((q.2 + prev.2) / 2, .line(prev.0, q.0, on ? col.opacity(0.45) : held ? Palette.amber.opacity(0.75) : .white.opacity(0.15), width, !on)))
                prev = q; prevW = w
            }
            guard on, moving, let watts = f.watts else { continue }
            let gap = max(0.35, 1.1 - watts * 0.02), travelled = clock.distance(f.id, at: t)
            var x = travelled.truncatingRemainder(dividingBy: gap)
            while x < length {
                for j in 0..<5 {
                    let q = project(PowerSpace.arc(a, b, max(0, (x - Double(j) * 0.07) / length)))
                    let fade = min(1, min(x, length - x) / 0.4) * (1 - Double(j) / 5.5)
                    marks.append((q.2, .comet(q.0, CGFloat((1.4 + watts / 30) * q.1 * (1 - Double(j) / 6)), fade)))
                }
                x += gap
            }
        }
        // Moons and the sun.
        for (id, o) in os {
            let q = project(o.position())
            marks.append((q.2, .body(info(id), q.0, CGFloat(radius(id) * q.1 * scale / 26))))
        }

        let light = cam.view(pos[.charger] ?? Vec3(1, 1, 1)).unit
        let sorted = marks.sorted { $0.0 < $1.0 }
        for (z, m) in sorted where z < 0 { paint(&ctx, m, light: light, t: t, moving: moving) }
        planet(&ctx, center: center, radius: CGFloat(scale), camera: cam, light: light, t: t, moving: moving)
        for (z, m) in sorted where z >= 0 { paint(&ctx, m, light: light, t: t, moving: moving) }

        // Labels and the Mac's readout on top of everything.
        for case (_, .body(let b, let p, let r)) in sorted {
            ctx.draw(Text(b.caption).font(.system(size: 9)).foregroundStyle(.white.opacity(0.62)), at: CGPoint(x: p.x, y: p.y - r - 20))
            ctx.draw(Text(b.value).font(.system(size: 11, weight: .bold)).monospacedDigit().foregroundStyle(.white), at: CGPoint(x: p.x, y: p.y - r - 8))
        }
        let dial = CGFloat(scale) + 7
        var share = "Mac uses"
        if let w = reading?.systemWatts, let rating = reading?.adapterWatts, rating > 0, reading?.isPluggedIn == true, pausedAt == nil {
            share += " · \(Int((w / Double(rating) * 100).rounded()))% of charger"
        } else if reading?.isPluggedIn == false || pausedAt != nil { share += " · on battery" }
        ctx.draw(Text(share).font(.system(size: 9)).foregroundStyle(.white.opacity(0.65)), at: CGPoint(x: center.x, y: center.y - dial - 26))
        ctx.draw(Text(PowerFlow.watts(reading?.systemWatts)).font(.system(size: 16, weight: .bold)).monospacedDigit().foregroundStyle(.white),
                 at: CGPoint(x: center.x, y: center.y - dial - 11))
        // The Mac's battery level, under the planet.
        if let r = reading {
            ctx.addFilter(.shadow(color: .black.opacity(0.9), radius: 3)) // last thing drawn: keeps the text clear of the ring
            ctx.draw(Text("\(r.percent)%").font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(.white),
                     at: CGPoint(x: center.x, y: center.y + dial + 12))
            ctx.draw(Text(pausedAt.map { "Battery · held at \($0)%" } ?? "Battery").font(.system(size: 9)).foregroundStyle(.white.opacity(0.65)),
                     at: CGPoint(x: center.x, y: center.y + dial + 26))
        }
    }

    private func paint(_ ctx: inout GraphicsContext, _ m: Mark, light: Vec3, t: Double, moving: Bool) {
        switch m {
        case let .line(a, b, c, w, dashed):
            var p = Path(); p.move(to: a); p.addLine(to: b)
            ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: dashed ? .butt : .round, dash: dashed ? [2, 3] : []))
        case let .quad(pts, c):
            var p = Path(); p.addLines(pts); p.closeSubpath()
            ctx.fill(p, with: .color(c))
        case let .dot(r, c):
            ctx.fill(Path(r), with: .color(c))
        case let .comet(p, r, a):
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(a)))
        case let .body(b, p, r):
            let disc = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            if b.lit {
                let glow = b.sun ? 13 + (moving ? sin(t * 3) * 2 : 0) : 6
                ctx.drawLayer { g in g.addFilter(.blur(radius: glow)); g.fill(disc, with: .color(b.tint.opacity(0.9))) }
            }
            sphere(&ctx, disc, center: p, radius: r, color: b.lit || b.sun ? b.tint : b.tint.opacity(0.6), light: b.sun ? nil : light)
            if selected == b.id || grab == .moon(b.id) {
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r - 3, y: p.y - r - 3, width: r * 2 + 6, height: r * 2 + 6)), with: .color(.white.opacity(0.7)), lineWidth: 1.5)
            }
        }
    }

    /// A lit ball: a highlight toward the light, fading to a dark limb on the far side.
    private func sphere(_ ctx: inout GraphicsContext, _ disc: Path, center p: CGPoint, radius r: CGFloat, color: Color, light: Vec3?) {
        let lx = light?.x ?? -0.5, ly = -(light?.y ?? 0.6), lit = light.map { 0.35 + 0.65 * max(0, $0.z * 0.5 + 0.5) } ?? 1
        ctx.fill(disc, with: .radialGradient(Gradient(stops: [.init(color: .white.opacity((light == nil ? 0.9 : 0.5) * lit), location: 0),
                                                              .init(color: color, location: 0.25), .init(color: .black.opacity(0.92), location: 1)]),
                                             center: CGPoint(x: p.x + lx * r * 0.5, y: p.y + ly * r * 0.5), startRadius: r * 0.08, endRadius: r * 1.15))
    }

    /// The Mac: a blue planet lit by the sun, bands that follow its tilt, an atmosphere that breathes with the load, and the dial.
    private func planet(_ ctx: inout GraphicsContext, center c: CGPoint, radius r: CGFloat, camera cam: SpaceCamera, light: Vec3, t: Double, moving: Bool) {
        let w = reading?.systemWatts ?? 0
        let breath = moving ? sin(t * (1.4 + min(w, 40) / 15)) * 0.07 : 0
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.8, y: c.y - r * 1.8, width: r * 3.6, height: r * 3.6)),
                 with: .radialGradient(Gradient(colors: [Palette.flow.opacity(0.35 + breath), Palette.flow.opacity(0)]), center: c, startRadius: r * 0.8, endRadius: r * 1.8))
        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        sphere(&ctx, disc, center: c, radius: r, color: Color(red: 0.17, green: 0.35, blue: 0.6), light: light)
        var bands = ctx
        bands.clip(to: disc)
        for i in -3...3 {
            var p = Path(), on = false
            for j in 0...48 {
                let v = cam.view(PowerSpace.surface(lat: Double(i) * 0.26, lon: Double(j) / 48 * 2 * .pi))
                guard v.z >= 0 else { on = false; continue }
                let q = CGPoint(x: c.x + v.x * r, y: c.y - v.y * r)
                if on { p.addLine(to: q) } else { p.move(to: q) }
                on = true
            }
            bands.stroke(p, with: .color(.white.opacity(i % 2 == 0 ? 0.08 : 0.05)), lineWidth: r * 0.09)
        }
        if selected == .mac { ctx.stroke(disc, with: .color(Palette.flowLight), lineWidth: 2) }

        let dial = r + 7
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - dial, y: c.y - dial, width: dial * 2, height: dial * 2)), with: .color(.white.opacity(0.08)), lineWidth: 3.5)
        guard pausedAt == nil, let rating = reading?.adapterWatts, rating > 0, reading?.isPluggedIn == true, let load = reading?.systemWatts else { return }
        var arc = Path()
        arc.addArc(center: c, radius: dial, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * min(1, load / Double(rating))), clockwise: false)
        ctx.drawLayer { g in
            g.addFilter(.shadow(color: Palette.flow, radius: 5))
            g.stroke(arc, with: .color(Palette.flow), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
    }
}
