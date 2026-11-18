import CoreGraphics
import Foundation

extension FlowNodeID {
    /// Stable name for saving where the owner dragged a tile. Round-trips through `init?(storageKey:)`.
    public var storageKey: String {
        switch self {
        case .charger: "charger"
        case .mac: "mac"
        case .battery: "battery"
        case .more: "more"
        case .stream(let title): "stream:" + title
        }
    }

    public init?(storageKey k: String) {
        switch k {
        case "charger": self = .charger
        case "mac": self = .mac
        case "battery": self = .battery
        case "more": self = .more
        default:
            guard k.hasPrefix("stream:"), k.count > 7 else { return nil }
            self = .stream(String(k.dropFirst(7)))
        }
    }
}

/// How far the owner has dragged each tile from where the layout puts it, in points.
/// Saved as a small JSON string (one UserDefaults value); anything unreadable is treated as no offsets.
public struct FlowOffsets: Equatable, Sendable {
    /// UserDefaults key the panel keeps the dragged layout under.
    public static let storageKey = "powerFlow.offsets"
    public var byNode: [FlowNodeID: CGSize] = [:]

    public init(_ byNode: [FlowNodeID: CGSize] = [:]) { self.byNode = byNode }

    public subscript(id: FlowNodeID) -> CGSize { byNode[id] ?? .zero }
    public var isEmpty: Bool { byNode.values.allSatisfy { $0 == .zero } }

    /// This set with `id` moved by a further `delta`.
    public func adding(_ delta: CGSize, to id: FlowNodeID) -> FlowOffsets {
        var o = self
        let cur = self[id]
        o.byNode[id] = CGSize(width: cur.width + delta.width, height: cur.height + delta.height)
        return o
    }

    /// This set with `id` moved by `delta`, then trimmed to where the tile actually lands in `base` (it stops at the
    /// map's edge), so dragging back from past an edge responds at once.
    public func dropping(_ id: FlowNodeID, by delta: CGSize, base: FlowLayout) -> FlowOffsets {
        let tried = adding(delta, to: id)
        guard let from = base.node(id)?.rect, let to = base.applying(tried).node(id)?.rect else { return tried }
        var o = self
        o.byNode[id] = CGSize(width: to.minX - from.minX, height: to.minY - from.minY)
        return o
    }

    public init(json: String) {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: [Double]].self, from: data) else { return }
        for (k, v) in raw {
            guard let id = FlowNodeID(storageKey: k), v.count == 2, v.allSatisfy(\.isFinite) else { continue }
            byNode[id] = CGSize(width: v[0], height: v[1])
        }
    }

    public var json: String {
        let raw = Dictionary(uniqueKeysWithValues: byNode.filter { $0.value != .zero }
            .map { ($0.key.storageKey, [Double($0.value.width), Double($0.value.height)]) })
        guard !raw.isEmpty, let data = try? JSONEncoder().encode(raw) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension FlowLayout {
    /// The layout with each tile moved by its offset and kept inside the map. Ribbons touching a moved tile are
    /// re-anchored on the facing edges of their two tiles, so they follow it round any side; ribbons between tiles
    /// that did not move keep their exact place.
    public func applying(_ offsets: FlowOffsets) -> FlowLayout {
        guard !offsets.isEmpty else { return self }
        var out = self
        var moved: Set<FlowNodeID> = []
        out.nodes = nodes.map { n in
            let d = offsets[n.id]
            guard d != .zero else { return n }
            var m = n
            m.rect = Self.clamp(n.rect.offsetBy(dx: d.width, dy: d.height), in: size)
            if m.rect != n.rect { moved.insert(n.id) }
            return m
        }
        guard !moved.isEmpty else { return out }
        out.links = links.map { l in
            guard moved.contains(l.id.from) || moved.contains(l.id.to),
                  let a0 = node(l.id.from)?.rect, let b0 = node(l.id.to)?.rect,
                  let a = out.node(l.id.from)?.rect, let b = out.node(l.id.to)?.rect else { return l }
            // Keep each end's spot along its edge (ribbons stacked on one edge stay apart), measured from the edge's middle.
            let sAlong = l.vertical ? l.start.x - a0.midX : l.start.y - a0.midY
            let eAlong = l.vertical ? l.end.x - b0.midX : l.end.y - b0.midY
            var m = l
            (m.start, m.end, m.vertical) = Self.facing(a, b, startAlong: sAlong, endAlong: eAlong)
            return m
        }
        return out
    }

    static func clamp(_ r: CGRect, in size: CGSize) -> CGRect {
        let x = min(max(r.minX, 0), max(0, size.width - r.width))
        let y = min(max(r.minY, 0), max(0, size.height - r.height))
        return CGRect(x: x, y: y, width: r.width, height: r.height)
    }

    /// Start and end points on the edges of `a` and `b` that face each other. Side by side gives left/right edges;
    /// stacked (more apart vertically, for their sizes) gives top/bottom edges and a vertical ribbon.
    public static func facing(_ a: CGRect, _ b: CGRect, startAlong: CGFloat = 0, endAlong: CGFloat = 0) -> (CGPoint, CGPoint, Bool) {
        let dx = b.midX - a.midX, dy = b.midY - a.midY
        let horizontal = abs(dx) / max(a.width + b.width, 1) >= abs(dy) / max(a.height + b.height, 1)
        func along(_ v: CGFloat, _ half: CGFloat) -> CGFloat { min(max(v, -half + 6), half - 6) }
        if horizontal {
            let s: CGFloat = dx >= 0 ? 1 : -1
            return (CGPoint(x: a.midX + s * a.width / 2, y: a.midY + along(startAlong, a.height / 2)),
                    CGPoint(x: b.midX - s * b.width / 2, y: b.midY + along(endAlong, b.height / 2)), false)
        }
        let s: CGFloat = dy >= 0 ? 1 : -1
        return (CGPoint(x: a.midX + along(startAlong, a.width / 2), y: a.midY + s * a.height / 2),
                CGPoint(x: b.midX + along(endAlong, b.width / 2), y: b.midY - s * b.height / 2), true)
    }
}
