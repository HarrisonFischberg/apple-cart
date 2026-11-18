import Core
import SwiftUI

/// The 8-bit power flow: pixel sprites for the charger, the Mac, the battery and outside devices, joined by wires that
/// pixel packets run along (denser and faster with more watts). Drag a sprite to move it; the places are remembered.
/// Tap a sprite for its details. A lit screen in both appearances, like a handheld. Ticks only while `active`;
/// Reduce Motion draws it still.
struct PowerFlowPixel: View {
    let reading: BatteryReading?
    let active: Bool
    var pausedAt: Int?
    var selected: FlowNodeID?
    var onSelect: (FlowNodeID) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PixelPlaces.storageKey) private var saved = ""
    @State private var drag: (id: FlowNodeID, at: PixelPoint)?
    @State private var resize = LiveResize.shared

    private static let ground = Color(red: 0.114, green: 0.106, blue: 0.227)
    private static let dots = Color(red: 0.165, green: 0.157, blue: 0.314)
    private static let wireColor = Color(red: 0.267, green: 0.278, blue: 0.416)
    private static let supply = Color(red: 1, green: 0.847, blue: 0.29)
    private static let charge = Color(red: 0.365, green: 1, blue: 0.478)
    private static let drain = Color(red: 1, green: 0.42, blue: 0.353)
    private static let out = Color(red: 0.498, green: 0.839, blue: 1)
    private static let keys: [Character: Color] = ["1": Color(red: 0.545, green: 0.561, blue: 0.659), "2": Color(red: 0.227, green: 0.239, blue: 0.361),
                                                   "3": Color(red: 0.498, green: 0.839, blue: 1), "4": Color(red: 0.788, green: 0.8, blue: 0.867),
                                                   "5": Color(red: 1, green: 0.42, blue: 0.353), "6": Color(red: 1, green: 0.847, blue: 0.29)]

    private var streams: [PowerStream] { PixelFlow.shown(PowerFlows.streams(reading)) }
    private var flows: PowerFlows { PowerFlows(reading) }

    var body: some View {
        GeometryReader { geo in
            let cols = PixelFlow.columns(width: geo.size.width)
            let s = geo.size.width / Double(cols)
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active || reduceMotion || resize.active)) { tl in
                Canvas { ctx, _ in draw(&ctx, cols: cols, s: s, t: tl.date.timeIntervalSinceReferenceDate) }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { v in
                    // Moves from where the sprite sat when the drag began, in whole cells.
                    let rest = PixelPlaces(json: saved).resolved(homes: PixelFlow.homes(columns: cols, streams: streams), columns: cols)
                    if drag == nil { guard let id = hit(v.startLocation, s: s, places: rest), let p = rest[id] else { return }; drag = (id, p) }
                    guard let d = drag, let start = rest[d.id] else { return }
                    drag = (d.id, PixelPlaces.clamp(PixelPoint(start.x + Int((v.translation.width / s).rounded()),
                                                               start.y + Int((v.translation.height / s).rounded())), columns: cols))
                }
                .onEnded { _ in
                    guard let d = drag else { return }
                    var p = PixelPlaces(json: saved); p.byNode[d.id] = d.at; saved = p.json
                    drag = nil
                })
            .simultaneousGesture(SpatialTapGesture().onEnded { v in
                if let id = hit(v.location, s: s, places: places(cols)) { onSelect(id) }
            })
        }
        .frame(height: Double(PixelFlow.rows) * PixelFlow.cell)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Where each sprite sits now: saved places, the one being dragged, the rest at home.
    private func places(_ cols: Int) -> [FlowNodeID: PixelPoint] {
        var p = PixelPlaces(json: saved).resolved(homes: PixelFlow.homes(columns: cols, streams: streams), columns: cols)
        if let d = drag { p[d.id] = d.at }
        return p
    }

    private func hit(_ pt: CGPoint, s: Double, places: [FlowNodeID: PixelPoint]) -> FlowNodeID? {
        let x = Int(pt.x / s), y = Int(pt.y / s)
        return places.first { id, p in
            let (w, h) = PixelFlow.size(PixelFlow.sprite(id))
            return abs(x - p.x) <= w / 2 + 3 && y >= p.y - h / 2 - 3 && y <= p.y + h / 2 + 15 // the sprite and its label
        }?.key
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext, cols: Int, s: Double, t: Double) {
        var layers: [(Color, Path)] = []
        func put(_ c: Color, _ cells: [PixelPoint], size: Int = 1) {
            var p = Path()
            for q in cells { p.addRect(CGRect(x: Double(q.x) * s, y: Double(q.y) * s, width: s * Double(size), height: s * Double(size))) }
            layers.append((c, p))
        }
        ctx.fill(Path(CGRect(x: 0, y: 0, width: Double(cols) * s, height: Double(PixelFlow.rows) * s)), with: .color(Self.ground))
        put(Self.dots, stride(from: 0, to: cols, by: 6).flatMap { x in stride(from: 0, to: PixelFlow.rows, by: 6).map { PixelPoint(x, $0) } })

        let at = places(cols)
        let moving = active && !reduceMotion
        // Wires first, then packets on them.
        var links: [(FlowNodeID, FlowNodeID, Double, Color)] = []
        if reading?.isPluggedIn == true {
            links.append((.charger, .mac, flows.chargerToMac ?? 0, Self.supply))
            if (flows.chargerToBattery ?? 0) > 0.05 { links.append((.charger, .battery, flows.chargerToBattery ?? 0, Self.charge)) }
        }
        if (flows.batteryToMac ?? 0) > 0.05 { links.append((.battery, .mac, flows.batteryToMac ?? 0, Self.drain)) }
        for st in streams { links.append((.mac, .stream(st.title), st.watts ?? 0, Self.out)) }
        let wires = links.compactMap { l -> ([PixelPoint], Double, Color)? in
            guard let a = at[l.0], let b = at[l.1] else { return nil }
            return (PixelFlow.wire(a, b), l.2, l.3)
        }
        put(Self.wireColor, wires.flatMap(\.0))
        for (cells, watts, color) in wires {
            let idx = PixelFlow.packets(length: cells.count, watts: watts, t: moving ? t : 0)
            put(color, idx.map { PixelPoint(cells[$0].x - 1, cells[$0].y - 1) }, size: 2)
        }

        // Sprites.
        let off = reading?.isPluggedIn != true
        for (id, p) in at {
            let art = PixelFlow.sprite(id), (w, h) = PixelFlow.size(art)
            var byKey: [Character: [PixelPoint]] = [:]
            for (j, row) in art.enumerated() { for (i, c) in row.enumerated() where c != "." { byKey[c, default: []].append(PixelPoint(p.x - w / 2 + i, p.y - h / 2 + j)) } }
            for (k, cells) in byKey.sorted(by: { $0.key < $1.key }) {
                put(id == .charger && off ? Color(white: 0.3) : Self.keys[k] ?? .white, cells)
            }
            if id == .battery { let (c, cells) = batteryCells(at: p, w: w, t: moving ? t : 0); put(c, cells) }
            if id == selected { // blinking corner brackets
                if !moving || Int(t * 3) % 2 == 0 {
                    let l = p.x - w / 2 - 2, r = p.x + w / 2 + 2, tp = p.y - h / 2 - 2, b = p.y + h / 2 + 2
                    put(.white, [PixelPoint(l, tp), PixelPoint(l + 1, tp), PixelPoint(l, tp + 1), PixelPoint(r, tp), PixelPoint(r - 1, tp), PixelPoint(r, tp + 1),
                                 PixelPoint(l, b), PixelPoint(l + 1, b), PixelPoint(l, b - 1), PixelPoint(r, b), PixelPoint(r - 1, b), PixelPoint(r, b - 1)])
                }
            }
            let (caption, value) = label(id)
            let top = p.y + h / 2 + 3
            for (line, y, c) in [(caption, top, Color.white), (value, top + 7, Self.supply)] {
                let (cells, width) = PixelFlow.text(line)
                let x0 = min(max(p.x - width / 2, 1), cols - width - 1)
                put(Color.black.opacity(0.6), cells.map { PixelPoint(x0 + $0.x + 1, y + $0.y + 1) }) // drop shadow
                put(c, cells.map { PixelPoint(x0 + $0.x, y + $0.y) })
            }
        }
        for (c, p) in layers { ctx.fill(p, with: .color(c)) }
    }

    /// Five cells inside the battery shell; the top one blinks while charging.
    private func batteryCells(at p: PixelPoint, w: Int, t: Double) -> (Color, [PixelPoint]) {
        let pct = reading?.shownPercent ?? 0
        let lit = PixelFlow.cells(percent: pct), charging = (reading?.batteryWatts ?? 0) > 0.05
        let shown = charging && t != 0 && Int(t * 2.5) % 2 == 1 ? lit - 1 : lit
        let left = p.x - w / 2 + 2 // five 2x4 cells, one cell in from the shell
        let cells = (0..<max(shown, 0)).flatMap { i in (0..<2).flatMap { dx in (0..<4).map { dy in PixelPoint(left + i * 2 + dx, p.y - 2 + dy) } } }
        return (pct > 20 ? Self.charge : Self.drain, cells)
    }

    private func label(_ id: FlowNodeID) -> (String, String) {
        let r = reading
        func w(_ v: Double?) -> String { v.map { String(format: "%.1fW", abs($0)) } ?? "--" }
        switch id {
        case .charger:
            guard r?.isPluggedIn == true else { return ("CHARGER", "--") }
            return (pausedAt != nil ? "HELD" : "CHARGER", w((flows.chargerToMac ?? 0) + (flows.chargerToBattery ?? 0)))
        case .mac: return ("MAC", w(r?.systemWatts))
        case .battery:
            let b = r?.batteryWatts ?? 0
            return (r?.shownPercentText ?? "--", abs(b) < 0.05 ? "IDLE" : (b > 0 ? "+" : "-") + w(b))
        case .stream(let title):
            let short = ["Charger loss": "LOSS", "USB": "USB", "SoC": "SOC", "Other": "OTHER"][title] ?? title
            return (short, w(streams.first { $0.title == title }?.watts))
        case .more: return ("MORE", "")
        }
    }
}
