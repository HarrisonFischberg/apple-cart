import CoreGraphics
import Foundation

/// Which story the power flow map tells. Picked from the reading only; nothing is guessed.
public enum FlowState: Equatable, Sendable {
    case charging, pluggedIdle, onBattery, chargerTooWeak, noData

    public init(_ r: BatteryReading?) {
        guard let r else { self = .noData; return }
        if !r.isPluggedIn { self = .onBattery }
        else if PowerFlows.chargerTooWeak(r) { self = .chargerTooWeak }
        else if r.batteryWatts > 0.05 { self = .charging }
        else { self = .pluggedIdle }
    }
}

public enum FlowNodeID: Hashable, Sendable {
    case charger, mac, battery, more
    case stream(String)
}

public enum FlowLinkKind: Equatable, Sendable { case supply, charge, drain, stream }

public struct FlowLinkID: Hashable, Sendable {
    public let from: FlowNodeID, to: FlowNodeID
    public init(_ from: FlowNodeID, _ to: FlowNodeID) { self.from = from; self.to = to }
}

/// Tiles and ribbons of the map in points. Pure geometry so it can be tested without drawing.
public struct FlowLayout: Equatable, Sendable {
    public struct Node: Equatable, Sendable {
        public var id: FlowNodeID
        public var rect: CGRect
        public var dimmed = false
    }

    public struct Link: Equatable, Sendable {
        public var id: FlowLinkID
        public var kind: FlowLinkKind
        public var start: CGPoint, end: CGPoint
        public var watts: Double?   // nil = not reported (dashed hairline), 0 = known idle
        public var vertical = false // leaves a tile's top edge instead of its side
    }

    public var size: CGSize
    public var nodes: [Node]
    public var links: [Link]

    public func node(_ id: FlowNodeID) -> Node? { nodes.first { $0.id == id } }
    public func link(_ id: FlowLinkID) -> Link? { links.first { $0.id == id } }

    // Tile sizes. The panel card gives the map about 320 pt (380 panel - page and card padding).
    public static let source = CGSize(width: 68, height: 72)
    public static let hub = CGSize(width: 96, height: 80)
    public static let below = CGSize(width: 96, height: 54)
    public static let parked = CGSize(width: 68, height: 54)
    public static let leaf = CGSize(width: 68, height: 36)
    public static let leafGap: CGFloat = 6
    static let inset: CGFloat = 4

    /// Map height: room for the hub over the battery, or for the leaf column, whichever is taller.
    public static func height(leaves n: Int, battery: Bool = true) -> CGFloat {
        max(inset * 2 + hub.height + (battery ? 28 + below.height : 0), CGFloat(n) * leaf.height + CGFloat(max(0, n - 1)) * leafGap)
    }

    /// Vertical centres of `widths.count` ribbons stacked on one tile edge, centred on `mid`, never wider than `span`.
    /// Order is kept, so ribbons fanning out from here to a sorted column never cross.
    public static func stack(_ widths: [CGFloat], mid: CGFloat, span: CGFloat, gap: CGFloat = 3) -> [CGFloat] {
        guard !widths.isEmpty else { return [] }
        let total = widths.reduce(0, +) + gap * CGFloat(widths.count - 1)
        let scale = total > span ? span / total : 1
        var y = mid - total * scale / 2
        return widths.map { w in
            defer { y += (w + gap) * scale }
            return y + w * scale / 2
        }
    }

    /// Leaves: each reported or dashed Mac-side stream, then the remainder ("more") when it is at least 1 W.
    public static func make(state: FlowState, flows: PowerFlows, streams: [PowerStream], rest: Double?, width w: CGFloat) -> FlowLayout {
        // Only streams macOS actually reports get a tile: no dash tiles. The Mac's own use is the middle tile and is
        // never split out into a "Rest of Mac" tile; only outside consumers (USB) are drawn beside it.
        let leaves: [(FlowNodeID, Double?)] = streams.compactMap { $0.watts == nil ? nil : (.stream($0.title), $0.watts) }
        // A battery that is full and idle has nothing to say, so it gets no tile.
        let showBattery = state != .pluggedIdle
        let h = height(leaves: leaves.count, battery: showBattery)

        let hub = CGRect(x: (w - Self.hub.width) / 2, y: inset, width: Self.hub.width, height: Self.hub.height)
        let below = CGRect(x: hub.minX, y: h - inset - Self.below.height, width: Self.below.width, height: Self.below.height)
        let hubRect = hub
        let sourceSlot = CGRect(x: 0, y: hub.midY - source.height / 2, width: source.width, height: source.height)
        let parkedSlot = CGRect(x: 0, y: h - inset - parked.height, width: parked.width, height: parked.height)

        var nodes = [Node(id: .mac, rect: hub)]
        var links: [Link] = []
        let onBattery = state == .onBattery
        // On battery the battery takes the source slot and the charger is parked, dimmed and unlinked.
        nodes.append(Node(id: .charger, rect: onBattery ? parkedSlot : sourceSlot, dimmed: onBattery))
        if showBattery { nodes.append(Node(id: .battery, rect: onBattery ? sourceSlot : below)) }

        func right(_ r: CGRect, _ y: CGFloat) -> CGPoint { CGPoint(x: r.maxX, y: y) }
        func left(_ r: CGRect, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX, y: y) }

        switch state {
        case .onBattery:
            links.append(Link(id: FlowLinkID(.battery, .mac), kind: .drain, start: right(sourceSlot, sourceSlot.midY),
                              end: left(hub, hub.midY), watts: flows.batteryToMac))
        case .charging:
            let ws = [FlowMotion.ribbonWidth(flows.chargerToMac), FlowMotion.ribbonWidth(flows.chargerToBattery)]
            let ys = stack(ws, mid: sourceSlot.midY, span: sourceSlot.height - 20)
            links.append(Link(id: FlowLinkID(.charger, .mac), kind: .supply, start: right(sourceSlot, ys[0]),
                              end: left(hub, hub.midY), watts: flows.chargerToMac))
            links.append(Link(id: FlowLinkID(.charger, .battery), kind: .charge, start: right(sourceSlot, ys[1]),
                              end: left(below, below.midY), watts: flows.chargerToBattery))
        case .pluggedIdle, .noData:
            links.append(Link(id: FlowLinkID(.charger, .mac), kind: .supply, start: right(sourceSlot, sourceSlot.midY),
                              end: left(hub, hub.midY), watts: state == .noData ? nil : flows.chargerToMac))
        case .chargerTooWeak:
            links.append(Link(id: FlowLinkID(.charger, .mac), kind: .supply, start: right(sourceSlot, sourceSlot.midY),
                              end: left(hub, hub.midY), watts: flows.chargerToMac))
            links.append(Link(id: FlowLinkID(.battery, .mac), kind: .drain, start: CGPoint(x: below.midX, y: below.minY),
                              end: CGPoint(x: hub.midX, y: hub.maxY), watts: flows.batteryToMac, vertical: true))
        }

        // The fork: the hub's right edge fans out to a column of leaves.
        let total = CGFloat(leaves.count) * leaf.height + CGFloat(max(0, leaves.count - 1)) * leafGap
        let top = (h - total) / 2
        let ys = stack(leaves.map { max(1.5, FlowMotion.ribbonWidth($0.1)) }, mid: hub.midY, span: hub.height - 16)
        for (i, (id, watts)) in leaves.enumerated() {
            let r = CGRect(x: w - leaf.width, y: top + CGFloat(i) * (leaf.height + leafGap), width: leaf.width, height: leaf.height)
            nodes.append(Node(id: id, rect: r))
            links.append(Link(id: FlowLinkID(.mac, id), kind: .stream, start: right(hub, ys[i]), end: left(r, r.midY), watts: watts))
        }
        return FlowLayout(size: CGSize(width: w, height: h), nodes: nodes, links: links)
    }

    /// Blend two layouts for a state change or a new reading. Ribbons only in `a` thin out to nothing; ribbons only in `b` grow from nothing.
    public static func lerp(_ a: FlowLayout, _ b: FlowLayout, _ t: Double) -> FlowLayout {
        let t = CGFloat(min(max(t, 0), 1))
        if t >= 1 { return b }
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        func mix(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: mix(p.x, q.x), y: mix(p.y, q.y)) }
        func mix(_ r: CGRect, _ s: CGRect) -> CGRect { CGRect(x: mix(r.minX, s.minX), y: mix(r.minY, s.minY), width: mix(r.width, s.width), height: mix(r.height, s.height)) }
        func mixW(_ x: Double?, _ y: Double?) -> Double? {
            if x == nil, y == nil { return nil }
            return (x ?? 0) + ((y ?? 0) - (x ?? 0)) * Double(t)
        }
        var out = b
        out.size = CGSize(width: mix(a.size.width, b.size.width), height: mix(a.size.height, b.size.height))
        out.nodes = b.nodes.map { n in
            guard let o = a.node(n.id) else { return n }
            var m = n; m.rect = mix(o.rect, n.rect); return m
        }
        out.links = b.links.map { l in
            var m = l
            if let o = a.link(l.id) {
                m.start = mix(o.start, l.start); m.end = mix(o.end, l.end); m.watts = mixW(o.watts, l.watts)
            } else {
                m.watts = l.watts.map { $0 * Double(t) }
            }
            return m
        }
        for o in a.links where b.link(o.id) == nil {
            var m = o; m.watts = o.watts.map { $0 * Double(1 - t) }; out.links.append(m)
        }
        return out
    }
}

extension PowerFlows {
    /// What the Mac uses beyond the reported SoC, USB and Other streams. Charger loss is left out: it is lost in the charger path,
    /// not part of the Mac's load. Assumes USB out is counted inside SystemLoad (not verified on hardware). nil when the load is unknown.
    public static func rest(_ r: BatteryReading?, streams: [PowerStream]) -> Double? {
        guard let system = r?.systemWatts else { return nil }
        let shown = streams.filter { $0.title != "Charger loss" }.compactMap(\.watts).reduce(0, +)
        return max(0, system - shown)
    }
}

/// Timing and sizing for the animated map. Pure so it can be tested.
public enum FlowMotion {
    public static let transition: Double = 0.55
    public static let minWidth: CGFloat = 2.5, maxWidth: CGFloat = 20

    /// Ribbon thickness from watts: 0 for unknown or idle, otherwise clamped so 1 W stays visible and 45 W+ stays inside its tile.
    public static func ribbonWidth(_ w: Double?) -> CGFloat {
        guard let w, w > 0.05 else { return 0 }
        return min(max(2 + CGFloat(w) * 0.4, minWidth), maxWidth)
    }

    /// Smoothstep from 0 to 1 over `duration` seconds after a change.
    public static func progress(elapsed: Double, duration: Double = transition) -> Double {
        let p = min(max(elapsed / duration, 0), 1)
        return p * p * (3 - 2 * p)
    }

    /// Particle speed in points per second: a slow trickle at 1 W, brisk at 30 W and above.
    public static func speed(_ w: Double) -> Double { w > 0.05 ? 12 + min(w, 40) * 2 : 0 }
    /// Share of particle slots that are lit: sparse at low watts, full at 26 W and above.
    public static func density(_ w: Double) -> Double { min(1, 0.35 + max(w, 0) / 40) }
    public static let spacing: Double = 22

    /// Calls `body` with each lit particle's position as a fraction (0...1) of a ribbon `length` points long, after the flow has
    /// travelled `distance` points. Slots keep their identity as they move, so a density change lights or dims particles in place.
    public static func particles(distance: Double, length: Double, watts: Double, _ body: (Double) -> Void) {
        guard length > 1, watts > 0.05 else { return }
        let d = distance.truncatingRemainder(dividingBy: spacing)
        let base = Int((distance / spacing).rounded(.down))
        let lit = density(watts)
        var k = 0
        while true {
            let x = d + Double(k) * spacing
            if x > length { break }
            let id = Double(k - base) * 0.6180339887
            if id - id.rounded(.down) < lit { body(x / length) }
            k += 1
        }
    }
}

/// How far each ribbon's particles have travelled. Re-anchored only when speeds change, so particles never jump.
public struct ParticleClock: Equatable, Sendable {
    struct Anchor: Equatable, Sendable { var offset: Double, time: Double, speed: Double }
    var anchors: [FlowLinkID: Anchor] = [:]

    public init() {}

    public func distance(_ id: FlowLinkID, at t: Double) -> Double {
        guard let a = anchors[id] else { return 0 }
        return a.offset + (t - a.time) * a.speed
    }

    public mutating func update(speeds: [FlowLinkID: Double], at t: Double) {
        var next: [FlowLinkID: Anchor] = [:]
        for (id, s) in speeds {
            // Keep the offset small so float precision holds over long sessions.
            next[id] = Anchor(offset: distance(id, at: t).truncatingRemainder(dividingBy: FlowMotion.spacing * 1000), time: t, speed: s)
        }
        anchors = next
    }
}

/// One spoken sentence set for the whole map. Unreported streams say so; nothing is invented.
public enum FlowSummary {
    public static func text(_ r: BatteryReading?, streams: [PowerStream], rest: Double?) -> String {
        guard let r else { return "Power flow. No data." }
        let flows = PowerFlows(r)
        func w(_ x: Double) -> String { String(format: "%.1f watts", x) }
        var parts: [String] = []
        switch FlowState(r) {
        case .onBattery:
            parts.append("On battery. Charger not connected.")
            parts.append("The battery supplies \(w(flows.batteryToMac ?? 0)).")
        default:
            if let m = flows.chargerToMac {
                parts.append("Charger supplies \(w(m + (flows.chargerToBattery ?? 0))).")
            } else {
                parts.append("Charger connected\(r.adapterWatts.map { ", rated \($0) watts" } ?? "").")
            }
        }
        parts.append(r.systemWatts.map { "The Mac uses \(w($0))." } ?? "The Mac's use is not reported.")
        for s in streams { parts.append(s.watts.map { "\(s.title) \(w($0))." } ?? "\(s.title) not reported by macOS.") }
        if let rest, rest >= PowerFlows.hideBelow { parts.append("Rest of the Mac \(w(rest)).") }
        switch FlowState(r) {
        case .charging: parts.append("Battery charging at \(w(r.batteryWatts)), \(r.percent) percent.")
        case .chargerTooWeak: parts.append("Battery helping with \(w(-r.batteryWatts)), the charger is too weak. \(r.percent) percent.")
        case .onBattery: parts.append("Battery at \(r.percent) percent.")
        default: parts.append("Battery idle, \(r.percent) percent.")
        }
        return parts.joined(separator: " ")
    }
}
