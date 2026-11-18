import Foundation

/// The 8-bit power flow: chunky sprites on a pixel grid, joined by wires that pixel packets run along.
/// Pure maths (grid, sprites, wires, packets, the 3x5 font, saved places) so it can be tested without drawing.
public struct PixelPoint: Hashable, Sendable {
    public var x, y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

public enum PixelFlow {
    /// One grid cell in points, and the grid's height in cells. The width follows the panel.
    public static let cell = 3.0
    public static let rows = 90
    public static func columns(width: Double) -> Int { max(Int(width / cell), 80) }

    /// Default places, as fractions of the grid's width so they fit any panel. Up to three outside streams stack on the right.
    public static func homes(columns c: Int, streams: [PowerStream]) -> [FlowNodeID: PixelPoint] {
        // The battery sits below and between the charger and the Mac, so its wires drop into it from above and never
        // cross a label; outside devices use the right-hand side.
        var out: [FlowNodeID: PixelPoint] = [.charger: PixelPoint(c * 14 / 100, 20), .mac: PixelPoint(c * 52 / 100, 20),
                                             .battery: PixelPoint(c * 33 / 100, 60)]
        for (i, s) in shown(streams).enumerated() { out[.stream(s.title)] = PixelPoint(c * 85 / 100, 16 + i * 26) }
        return out
    }

    /// The outside streams that get a sprite: reported ones only, at most three.
    public static func shown(_ streams: [PowerStream]) -> [PowerStream] { Array(streams.filter { $0.watts != nil }.prefix(3)) }

    /// An L-shaped wire, across first and then down or up, every cell from `a` to `b` inclusive.
    public static func wire(_ a: PixelPoint, _ b: PixelPoint) -> [PixelPoint] {
        var out: [PixelPoint] = [], p = a
        while p.x != b.x { out.append(p); p.x += b.x > p.x ? 1 : -1 }
        while p.y != b.y { out.append(p); p.y += b.y > p.y ? 1 : -1 }
        out.append(b)
        return out
    }

    /// The wire power travels on from `a` to `b`: across at the higher body's level, then straight down into the lower
    /// one from above. Labels sit under their sprites, so a wire never runs up through one.
    public static func route(from a: PixelPoint, to b: PixelPoint) -> [PixelPoint] {
        a.y <= b.y ? wire(a, b) : Array(wire(b, a).reversed())
    }

    /// Cells between packets: more watts, denser traffic.
    public static func gap(_ watts: Double) -> Int { max(4, 12 - Int((max(watts, 0) / 4).rounded())) }
    /// Cells a packet moves per second: more watts, faster.
    public static func speed(_ watts: Double) -> Double { 10 + min(max(watts, 0), 60) * 0.5 }

    /// The indexes along a wire of `length` cells that hold a packet at time `t`.
    public static func packets(length: Int, watts: Double, t: Double) -> [Int] {
        guard length > 0, watts > 0.05 else { return [] }
        let g = gap(watts), off = Int((t * speed(watts)).rounded(.down)) % g
        return Array(stride(from: off, to: length, by: g))
    }

    /// Battery cells lit out of five.
    public static func cells(percent: Double) -> Int { min(5, max(0, Int((percent / 20).rounded()))) }

    // MARK: Sprites — one character per cell; "." is empty. Keys map to colours in the view.

    public static let charger = ["..1..1..", "..1..1..", "22222222", "23333332", "23333332", ".233332.", "..2442..", "...44...", "...44..."]
    public static let mac = ["1111111111111", "1222222222221", "1233333333321", "1233333333321", "1233333333321",
                             "1233333333321", "1222222222221", "1111111111111", "..444444444..", "4444444444444"]
    /// 18 x 8 shell with a nub; five 2 x 4 cells, a cell apart, are drawn inside it (see `cellRects`).
    public static let battery = ["444444444444444444.", "4................4.", "4................44", "4................44",
                                 "4................44", "4................44", "4................4.", "444444444444444444."]

    /// The lit battery cells for `lit` of five, around the battery's centre `p`.
    public static func batteryCells(_ lit: Int, at p: PixelPoint) -> [PixelPoint] {
        let left = p.x - size(battery).w / 2 + 2
        return (0..<min(max(lit, 0), 5)).flatMap { i in (0..<2).flatMap { dx in (0..<4).map { dy in PixelPoint(left + i * 3 + dx, p.y - 2 + dy) } } }
    }
    public static let phone = ["11111", "13331", "13331", "13331", "13331", "13331", "11111", "11411"]
    public static let chip = [".4.4.4.", "4111114", ".13331.", "4133314", ".13331.", "4111114", ".4.4.4."]
    public static let heat = ["...5...", "..55...", "..555..", ".55655.", ".56665.", "5566655", ".55555."]

    public static func sprite(_ id: FlowNodeID) -> [String] {
        switch id {
        case .charger: charger
        case .mac: mac
        case .battery: battery
        case .stream("USB"): phone
        case .stream("Charger loss"): heat
        default: chip
        }
    }

    public static func size(_ sprite: [String]) -> (w: Int, h: Int) { (sprite.map(\.count).max() ?? 0, sprite.count) }

    // MARK: 3x5 font

    public static let glyphs: [Character: [String]] = [
        "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"], "2": ["111", "001", "111", "100", "111"],
        "3": ["111", "001", "011", "001", "111"], "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
        "6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"], "8": ["111", "101", "111", "101", "111"],
        "9": ["111", "101", "111", "001", "111"], ".": ["0", "0", "0", "0", "1"], "%": ["101", "001", "010", "100", "101"],
        "+": ["000", "010", "111", "010", "000"], "-": ["000", "000", "111", "000", "000"], " ": ["0", "0", "0", "0", "0"],
        "A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"], "C": ["011", "100", "100", "100", "011"],
        "D": ["110", "101", "101", "101", "110"], "E": ["111", "100", "110", "100", "111"], "F": ["111", "100", "110", "100", "100"],
        "G": ["011", "100", "101", "101", "011"], "H": ["101", "101", "111", "101", "101"], "I": ["111", "010", "010", "010", "111"],
        "K": ["101", "101", "110", "101", "101"], "L": ["100", "100", "100", "100", "111"], "M": ["101", "111", "111", "101", "101"],
        "N": ["110", "101", "101", "101", "101"], "O": ["010", "101", "101", "101", "010"], "P": ["110", "101", "110", "100", "100"],
        "R": ["110", "101", "110", "101", "101"], "S": ["011", "100", "010", "001", "110"], "T": ["111", "010", "010", "010", "010"],
        "U": ["101", "101", "101", "101", "111"], "V": ["101", "101", "101", "101", "010"], "W": ["101", "101", "111", "111", "101"],
        "Y": ["101", "101", "010", "010", "010"], "J": ["001", "001", "001", "101", "010"], "Q": ["010", "101", "101", "110", "011"],
        "X": ["101", "101", "010", "101", "101"], "Z": ["111", "001", "010", "100", "111"],
    ]

    /// The lit cells of `text` (upper-cased; unknown characters become spaces), one cell between letters, and its width.
    public static func text(_ text: String) -> (cells: [PixelPoint], width: Int) {
        var out: [PixelPoint] = [], x = 0
        for ch in text.uppercased() {
            let g = glyphs[ch] ?? glyphs[" "]!
            for (y, row) in g.enumerated() { for (i, c) in row.enumerated() where c == "1" { out.append(PixelPoint(x + i, y)) } }
            x += (g.first?.count ?? 1) + 1
        }
        return (out, max(x - 1, 0))
    }
}

/// Where the owner has dragged each sprite on the pixel grid, saved between launches. Empty means the default places.
public struct PixelPlaces: Equatable, Sendable {
    public static let storageKey = "powerFlow.pixel"
    public var byNode: [FlowNodeID: PixelPoint] = [:]
    public init(_ byNode: [FlowNodeID: PixelPoint] = [:]) { self.byNode = byNode }
    public var isEmpty: Bool { byNode.isEmpty }

    /// The places to draw: saved ones kept inside the grid, the rest at home.
    public func resolved(homes: [FlowNodeID: PixelPoint], columns: Int) -> [FlowNodeID: PixelPoint] {
        homes.reduce(into: [:]) { out, e in out[e.key] = byNode[e.key].map { Self.clamp($0, columns: columns) } ?? e.value }
    }

    public static func clamp(_ p: PixelPoint, columns: Int) -> PixelPoint {
        PixelPoint(min(max(p.x, 8), columns - 9), min(max(p.y, 7), PixelFlow.rows - 20))
    }

    public init(json: String) {
        guard let data = json.data(using: .utf8), let raw = try? JSONDecoder().decode([String: [Int]].self, from: data) else { return }
        for (k, v) in raw { if let id = FlowNodeID(storageKey: k), v.count == 2 { byNode[id] = PixelPoint(v[0], v[1]) } }
    }

    public var json: String {
        guard !isEmpty, let data = try? JSONEncoder().encode(byNode.reduce(into: [String: [Int]]()) { $0[$1.key.storageKey] = [$1.value.x, $1.value.y] })
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
