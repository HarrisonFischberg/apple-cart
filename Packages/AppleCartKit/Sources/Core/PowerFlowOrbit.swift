import CoreGraphics
import Foundation

/// The orbit map: the Mac as a ringed planet in the middle, the charger, battery and outside devices as cards around it,
/// joined by curved arcs. Same `FlowLayout` model as the column map, so lerp, offsets and tests carry over.
extension FlowLayout {
    public static let orbitHeight: CGFloat = 250
    /// The planet's radius; the Mac node is a square around the planet and its load dial.
    public static let planet: CGFloat = 30
    public static let orbitHub = CGSize(width: (planet + 12) * 2, height: (planet + 12) * 2)
    public static let card = CGSize(width: 92, height: 40)

    /// Where the cards go before anyone drags them: corners first, then the middle of each side.
    static func slots(_ w: CGFloat, _ h: CGFloat) -> [CGPoint] {
        let l = card.width / 2 + inset, r = w - card.width / 2 - inset, t = card.height / 2 + inset, b = h - card.height / 2 - inset
        return [CGPoint(x: l, y: t), CGPoint(x: r, y: t), CGPoint(x: r, y: b), CGPoint(x: l, y: b),
                CGPoint(x: r, y: h / 2), CGPoint(x: l, y: h / 2)]
    }

    public static func orbit(state: FlowState, flows: PowerFlows, streams: [PowerStream], width w: CGFloat, held: Bool = false,
                             offsets: FlowOffsets = FlowOffsets()) -> FlowLayout {
        let h = orbitHeight
        let size = CGSize(width: w, height: h)
        func place(_ id: FlowNodeID, _ c: CGPoint, _ s: CGSize, dimmed: Bool = false) -> Node {
            let d = offsets[id]
            let r = CGRect(x: c.x - s.width / 2 + d.width, y: c.y - s.height / 2 + d.height, width: s.width, height: s.height)
            return Node(id: id, rect: clamp(r, in: size), dimmed: dimmed)
        }
        let slot = slots(w, h)
        let leaves = streams.compactMap { $0.watts == nil ? nil : (FlowNodeID.stream($0.title), $0.watts) }
        // Charger top left, battery bottom right, outside devices in the free slots (top right first).
        let free = [1, 3, 4, 5]
        var nodes = [place(.mac, CGPoint(x: w / 2, y: h / 2 + 6), orbitHub),
                     place(.charger, slot[0], card, dimmed: state == .onBattery),
                     place(.battery, slot[2], card)]
        for (i, leaf) in leaves.prefix(free.count).enumerated() { nodes.append(place(leaf.0, slot[free[i]], card)) }

        var links: [Link] = []
        func link(_ from: FlowNodeID, _ to: FlowNodeID, _ kind: FlowLinkKind, _ watts: Double?) {
            guard let a = nodes.first(where: { $0.id == from })?.rect, let b = nodes.first(where: { $0.id == to })?.rect else { return }
            let (s, e) = arcEnds(a, from == .mac, b, to == .mac)
            links.append(Link(id: FlowLinkID(from, to), kind: kind, start: s, end: e, watts: watts))
        }
        switch state {
        case .onBattery:
            link(.battery, .mac, .drain, flows.batteryToMac)
        case .charging:
            link(.charger, .mac, .supply, flows.chargerToMac)
            link(.mac, .battery, .charge, flows.chargerToBattery)
        case .pluggedIdle, .noData:
            link(.charger, .mac, .supply, state == .noData ? nil : held ? 0 : flows.chargerToMac)
            link(.mac, .battery, .charge, state == .noData ? nil : 0)
        case .chargerTooWeak:
            link(.charger, .mac, .supply, held ? 0 : flows.chargerToMac)
            link(.battery, .mac, .drain, flows.batteryToMac)
        }
        for (id, watts) in leaves.prefix(free.count) { link(.mac, id, .stream, watts) }
        return FlowLayout(size: size, nodes: nodes, links: links)
    }

    /// End points of the arc between two nodes: on the planet's dial when a node is the Mac, else where the line between
    /// the centres leaves the card.
    static func arcEnds(_ a: CGRect, _ aHub: Bool, _ b: CGRect, _ bHub: Bool) -> (CGPoint, CGPoint) {
        let ca = CGPoint(x: a.midX, y: a.midY), cb = CGPoint(x: b.midX, y: b.midY)
        func exit(_ r: CGRect, hub: Bool, from c: CGPoint, toward t: CGPoint) -> CGPoint {
            let dx = t.x - c.x, dy = t.y - c.y, d = max(hypot(dx, dy), 0.001)
            if hub { return CGPoint(x: c.x + dx / d * (planet + 10), y: c.y + dy / d * (planet + 10)) }
            // Ray from the centre to the rectangle's border.
            let sx = dx == 0 ? .infinity : (r.width / 2) / abs(dx), sy = dy == 0 ? .infinity : (r.height / 2) / abs(dy)
            let s = min(sx, sy)
            return CGPoint(x: c.x + dx * s, y: c.y + dy * s)
        }
        return (exit(a, hub: aHub, from: ca, toward: cb), exit(b, hub: bHub, from: cb, toward: ca))
    }
}

/// Which map the Battery page draws. Saved under `storageKey`; the 3D planets are the default.
public enum FlowStyle: String, CaseIterable, Sendable {
    case space, orbit, column
    public static let storageKey = "powerFlow.style"
    public var title: String {
        switch self {
        case .space: "3D planets"
        case .orbit: "Flat orbit"
        case .column: "Columns"
        }
    }
}

/// The Saturn-style ring around the planet. Pure numbers so it can be tested and drawn the same way everywhere.
public enum OrbitRing {
    /// Tilt of the ring plane (radians) and how flat it looks.
    public static let tilt: Double = -0.3, flat: Double = 0.3
    /// Bands as (inner, outer, opacity), in planet radii.
    public static let bands: [(Double, Double, Double)] = [(1.32, 1.52, 0.20), (1.56, 1.92, 0.42), (1.97, 2.04, 0.08), (2.08, 2.42, 0.30), (2.48, 2.6, 0.14)]
    public static let dustInner = 1.34, dustSpan = 1.24

    /// Angular speed of the ring in radians per second: a slow drift when idle, quicker with load.
    public static func spin(_ watts: Double?) -> Double { 0.08 + min(max(watts ?? 0, 0), 90) / 90 }

    /// A dust grain on the ring plane, `u` (0...1) across the band, at angle `a` after `t` seconds turning at `omega`.
    /// Inner grains go round faster, roughly as orbits do. Returns the offset from the planet's centre and whether
    /// the grain is on the near side (drawn over the planet).
    public static func grain(u: Double, a: Double, size r: Double, t: Double, omega: Double) -> (dx: Double, dy: Double, front: Bool) {
        let rr = dustInner + u * dustSpan
        let ang = a + t * omega * 2 * pow(dustInner / rr, 1.5)
        let x = cos(ang) * rr * r, y = sin(ang) * rr * r
        return (x * cos(tilt) - y * flat * sin(tilt), x * sin(tilt) + y * flat * cos(tilt), y > 0)
    }
}
