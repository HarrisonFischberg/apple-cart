import Foundation

public enum BatteryBadge: Equatable, Sendable { case none, plug, bolt, paused }

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
        let badge: BatteryBadge = !r.isPluggedIn ? .none : chargeHeld ? .paused : r.isCharging ? .bolt : .plug
        return BatteryGlyph(level: Double(min(max(r.percent, 0), 100)) / 100, badge: badge)
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
