import Foundation

// All numbers here are synthetic demo data for design previews. None are measurements.

public enum ChargeState: Equatable {
    case charging
    case holding(limit: Int)
    case pausedHeat(tempC: Double, limitC: Double)
    case onBattery
}

public struct HistoryPoint: Identifiable {
    public let id: Int
    public let hoursAgo: Double   // 24 ... 0
    public let percent: Double
    public let pluggedIn: Bool
}

public struct HistoryEvent: Identifiable {
    public let id: Int            // control number, 1-based, in time order
    public let hoursAgo: Double
    public let percent: Double
    public let title: String
}

public struct ScheduleItem: Identifiable {
    public let id: Int
    public let when: String
    public let action: String
    public let note: String
}

public struct StatSeries {
    public let name: String
    public let value: String
    public let unit: String
    public let history: [Double]  // 0...1, 60 samples, oldest first
}

public struct ToggleRow: Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let isOn: Bool
}

public enum Mock {
    // Demo "now": Friday 10:42.
    public static let nowHour = 10
    public static let nowMinute = 42
    public static let menuBarClock = "Fri 10:42"

    // MARK: Battery
    public static let percent: Double = 74
    public static let hardwarePercent: Double = 71.6
    public static let limit: Int = 80
    public static let heatLimitC: Double = 40
    public static let tempC: Double = 41.2
    public static let cycles: Int = 187
    public static let maxCapacityPercent: Int = 94
    public static let health = "Normal"
    public static let state: ChargeState = .pausedHeat(tempC: 41.2, limitC: 40)

    public static let adapterRatedWatts = 70
    public static let wattsToMac: Double = 11.4
    public static let wattsToBattery: Double = 0.0

    public static var stateTitle: String {
        switch state {
        case .charging: return "Charging"
        case .holding(let l): return "Holding at \(l)%"
        case .pausedHeat: return "Paused: battery is warm"
        case .onBattery: return "On battery"
        }
    }

    public static var stateReason: String {
        switch state {
        case .charging: return "Charging toward your \(limit)% limit."
        case .holding(let l): return "At your \(l)% limit. Charging resumes below \(l - 5)%."
        case .pausedHeat(let t, let c):
            return String(format: "Battery is %.1f °C, above your %.0f °C heat limit. Charging resumes when it cools below %.0f °C.", t, c, c - 2)
        case .onBattery: return "Not plugged in."
        }
    }

    public static var shortReason: String {
        switch state {
        case .charging: return "Charging"
        case .holding: return "At limit"
        case .pausedHeat: return "Heat pause"
        case .onBattery: return "On battery"
        }
    }

    /// 24 hours of 15-minute samples, ending at `percent`.
    public static let history: [HistoryPoint] = {
        // (hoursAgo, percent, plugged) keypoints, linear between them.
        let keys: [(Double, Double, Bool)] = [
            (24.0, 62, false), (21.0, 49, false), (18.2, 33, false),
            (18.1, 33, true), (15.3, 80, true), (8.1, 80, true),
            (8.0, 80, false), (5.0, 66, false), (3.7, 58, false),
            (3.6, 58, true), (0.7, 74, true), (0.0, 74, true)
        ]
        var out: [HistoryPoint] = []
        var idx = 0
        var h = 24.0
        while h >= -0.001 {
            var i = 0
            while i < keys.count - 2 && keys[i + 1].0 > h { i += 1 }
            let a = keys[i], b = keys[i + 1]
            let t = a.0 == b.0 ? 1 : (a.0 - h) / (a.0 - b.0)
            let p = a.1 + (b.1 - a.1) * min(max(t, 0), 1)
            out.append(HistoryPoint(id: idx, hoursAgo: max(h, 0), percent: p, pluggedIn: b.2))
            idx += 1
            h -= 0.25
        }
        return out
    }()

    public static let events: [HistoryEvent] = [
        HistoryEvent(id: 1, hoursAgo: 18.1, percent: 33, title: "Plugged in at 33%"),
        HistoryEvent(id: 2, hoursAgo: 15.3, percent: 80, title: "Reached the 80% limit"),
        HistoryEvent(id: 3, hoursAgo: 8.0, percent: 80, title: "Unplugged at 80%"),
        HistoryEvent(id: 4, hoursAgo: 3.6, percent: 58, title: "Plugged in at 58%"),
        HistoryEvent(id: 5, hoursAgo: 0.7, percent: 74, title: "Paused by heat at 74%")
    ]

    public static func clock(hoursAgo: Double) -> String {
        let total = (nowHour * 60 + nowMinute) - Int((hoursAgo * 60).rounded())
        let m = ((total % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    public static let schedule: [ScheduleItem] = [
        ScheduleItem(id: 1, when: "Fri 17:00", action: "Raise limit to 100%", note: "Once, before the trip"),
        ScheduleItem(id: 2, when: "Sun 02:00", action: "Calibrate battery", note: "First Sunday of the month"),
        ScheduleItem(id: 3, when: "Mon–Fri 08:30", action: "Set limit to 80%", note: "Weekdays")
    ]

    // MARK: System
    private static func series(seed: UInt64, base: Double, swing: Double, spikes: [Int]) -> [Double] {
        var s = seed
        func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 33) / Double(1 << 31) }
        return (0..<60).map { i in
            var v = base + swing * (rnd() - 0.5)
            for sp in spikes where abs(i - sp) < 3 { v += 0.35 * (1 - Double(abs(i - sp)) / 3) }
            return min(max(v, 0.02), 1)
        }
    }

    public static let cpu = StatSeries(name: "CPU", value: "23", unit: "%", history: series(seed: 7, base: 0.2, swing: 0.16, spikes: [18, 44]))
    public static let gpu = StatSeries(name: "GPU", value: "8", unit: "%", history: series(seed: 11, base: 0.07, swing: 0.06, spikes: [44]))
    public static let memory = StatSeries(name: "Memory", value: "11.2", unit: "of 24 GB", history: series(seed: 5, base: 0.46, swing: 0.04, spikes: []))
    public static let network = StatSeries(name: "Network", value: "1.2", unit: "MB/s down · 0.2 up", history: series(seed: 23, base: 0.14, swing: 0.14, spikes: [30, 52]))
    public static let diskUsedGB = 412
    public static let diskTotalGB = 994
    public static let socTempC = 48
    public static let fanRPM = 0
    public static let fanMaxRPM = 6000

    public static let keepAwakeOptions = ["30 min", "1 hour", "3 hours", "Until 80%", "Until I stop it"]
    public static let keepAwakeSelected = 3

    public static let quickToggles: [ToggleRow] = [
        ToggleRow(id: "dark", title: "Dark mode", detail: "Follows your choice here", isOn: false),
        ToggleRow(id: "night", title: "Night Shift", detail: "Warmer screen after sunset", isOn: true),
        ToggleRow(id: "lowpower", title: "Low Power Mode", detail: "Battery only", isOn: false),
        ToggleRow(id: "hidden", title: "Show hidden files", detail: "In Finder", isOn: false),
        ToggleRow(id: "desktop", title: "Desktop icons", detail: "Show on the desktop", isOn: true)
    ]

    public static let volumeGuardCap = 60
    public static let volumeGuardOn = true
    public static let bluetoothInSleepOn = false

    /// Fan safe mode is a tool that is switched off in the demo, to show the empty state.
    public static let fanToolOn = false
}
