import Foundation

public enum BatteryBadge: Equatable, Sendable { case none, plug, bolt, paused, discharge, drain, plugPaused, plugBolt, plugDrain
    /// One-glyph form for the small styles and places that have room for only a single badge.
    public var single: BatteryBadge { self == .plugPaused ? .paused : self == .plugBolt ? .bolt : self == .plugDrain ? .drain : self }
    /// True when the badge is two glyphs side by side and needs a wide box.
    public var isWide: Bool { self == .plugPaused || self == .plugBolt || self == .plugDrain }
}

/// What the menu bar battery glyph shows: fill level plus one badge inside the outline.
public struct BatteryGlyph: Equatable, Sendable {
    public var level: Double   // 0...1
    public var badge: BatteryBadge

    public init(level: Double, badge: BatteryBadge) { self.level = level; self.badge = badge }
}

extension MenuBarReadout {
    /// Charging wins over plugged; `chargeHeld` (charge paused at a limit) only counts while on AC.
    /// No reading gives an empty outline: nothing is invented.
    public static func glyph(for r: BatteryReading?, chargeHeld: Bool = false) -> BatteryGlyph {
        guard let r else { return BatteryGlyph(level: 0, badge: .none) }
        // Plugged in but the Mac is running from the battery (a held or paused charge): an arrow down, not a pause.
        let draining = r.isPluggedIn && !r.isCharging && r.batteryWatts < -0.5
        let badge: BatteryBadge = !r.isPluggedIn ? .discharge : (chargeHeld || !r.isCharging) ? (draining ? .plugDrain : .plugPaused) : .plugBolt
        return BatteryGlyph(level: min(max(r.shownPercent, 0), 100) / 100, badge: badge)
    }
}

/// The adapter -> Mac -> battery tiles as display strings. Missing data is an em dash, never a guess.
public struct PowerFlow: Equatable, Sendable {
    public var adapter = "—", adapterNote = "Not connected"
    public var system = "—", systemNote = "Mac is using"
    public var battery = "—", batteryNote = "No data"

    public static func watts(_ w: Double?) -> String { w.map { String(format: "%.1f W", abs($0)) } ?? "—" }

    public init(_ r: BatteryReading?) {
        guard let r else { adapterNote = "No data"; return }
        if r.isPluggedIn {
            adapter = r.adapterWatts.map { "\($0) W" } ?? "—"
            adapterNote = "Charger rating"
        }
        system = Self.watts(r.systemWatts)
        if abs(r.batteryWatts) < 0.05 {
            battery = Self.watts(0); batteryNote = "Idle"
        } else {
            battery = Self.watts(r.batteryWatts); batteryNote = r.batteryWatts > 0 ? "Charging" : "Discharging"
        }
    }
}

/// Watts along each link of the map, from real readings only. nil = unknown, 0 = known to be idle.
public struct PowerFlows: Equatable, Sendable {
    public var chargerToMac: Double?
    public var chargerToBattery: Double?
    public var batteryToMac: Double?

    public init(_ r: BatteryReading?) {
        guard let r else { return }
        let into = r.batteryWatts > 0.05 ? r.batteryWatts : 0
        let out = r.batteryWatts < -0.05 ? -r.batteryWatts : 0
        batteryToMac = out
        if r.isPluggedIn {
            chargerToBattery = into
            chargerToMac = r.systemWatts.map { max(0, $0 - out) } // the battery covers part of the load when it helps the charger
        } else {
            chargerToBattery = 0
            chargerToMac = 0
        }
    }
}

/// A reported extra stream out of the power budget. watts nil = this Mac does not report it (shown as a dash).
public struct PowerStream: Equatable, Sendable, Identifiable {
    public var id: String { title }
    public let title: String
    public let watts: Double?
}

extension PowerFlows {
    /// Streams under this many watts are hidden.
    public static let hideBelow = 1.0

    /// Plugged in, yet the battery is giving power: the charger cannot cover the Mac's load alone.
    public static func chargerTooWeak(_ r: BatteryReading?) -> Bool {
        guard let r, r.isPluggedIn else { return false }
        return -r.batteryWatts >= hideBelow
    }

    /// The Mac side of the map: SoC, USB and Other, plus charger loss. Unreported entries keep a nil value (a dash);
    /// reported ones under 1 W drop out. This Mac's registry reports USB out and charger loss only, so SoC and Other
    /// stay dashes here. Fill `socWatts` / `otherWatts` in when a Mac exposes them (not verified on real hardware).
    public static func streams(_ r: BatteryReading?, socWatts: Double? = nil, otherWatts: Double? = nil) -> [PowerStream] {
        guard let r else { return [] }
        return [PowerStream(title: "SoC", watts: socWatts),
                PowerStream(title: "USB", watts: r.usbOutWatts),
                PowerStream(title: "Other", watts: otherWatts),
                PowerStream(title: "Charger loss", watts: r.isPluggedIn ? r.adapterLossWatts : nil)]
            // A device on a USB-C port is a real outside consumer, so it shows however little it draws; the rest hide under 1 W.
            .filter { s in s.watts.map { s.title == "USB" ? $0 > 0 : $0 >= hideBelow } ?? true }
    }
}
