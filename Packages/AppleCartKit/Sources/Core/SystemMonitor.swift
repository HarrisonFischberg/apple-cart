import Darwin
import Foundation
import Observation

/// What the System view shows. Any field the Mac cannot report stays nil and the view says so.
public struct SystemReading: Sendable, Equatable {
    public var cpuPercent: Double?     // across all cores, 0...100
    public var gpuPercent: Double?     // "Device Utilization %" of the GPU, 0...100
    public var memory: MemoryStats?
    public var pressure: MemoryPressure?
    public var cpuTemperature: Double? // °C
    public var gpuTemperature: Double? // °C
    public var uptime: TimeInterval?

    public init(cpuPercent: Double? = nil, gpuPercent: Double? = nil, memory: MemoryStats? = nil, pressure: MemoryPressure? = nil,
                cpuTemperature: Double? = nil, gpuTemperature: Double? = nil, uptime: TimeInterval? = nil) {
        self.cpuPercent = cpuPercent; self.gpuPercent = gpuPercent; self.memory = memory; self.pressure = pressure
        self.cpuTemperature = cpuTemperature; self.gpuTemperature = gpuTemperature; self.uptime = uptime
    }
}

public struct MemoryStats: Sendable, Equatable {
    public var used: UInt64        // active + wired + compressed, Activity Monitor's Memory Used
    public var total: UInt64
    public var compressed: UInt64
    public var cached: UInt64      // file-backed pages, Activity Monitor's Cached Files
    public var swapUsed: UInt64

    public init(used: UInt64, total: UInt64, compressed: UInt64 = 0, cached: UInt64 = 0, swapUsed: UInt64 = 0) {
        self.used = used; self.total = total; self.compressed = compressed; self.cached = cached; self.swapUsed = swapUsed
    }

    public var fraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

public enum MemoryPressure: Sendable, Equatable {
    case normal, warning, critical

    /// kern.memorystatus_vm_pressure_level: 1 normal, 2 warning, 4 critical (0 is reported before the first change).
    public init?(level: Int) {
        switch level {
        case 0, 1: self = .normal
        case 2: self = .warning
        case 3...: self = .critical
        default: return nil
        }
    }

    public var title: String { switch self { case .normal: "Normal"; case .warning: "Warning"; case .critical: "Critical" } }
}

public struct CPUTicks: Sendable, Equatable {
    public var busy: UInt64
    public var total: UInt64

    public init(busy: UInt64, total: UInt64) { self.busy = busy; self.total = total }

    /// Usage between two readings; nil when no time passed.
    public static func percent(from a: CPUTicks, to b: CPUTicks) -> Double? {
        guard b.total > a.total, b.busy >= a.busy else { return nil }
        return Double(b.busy - a.busy) / Double(b.total - a.total) * 100
    }
}

/// One process's cumulative CPU time and memory footprint, named after its app bundle when it has one.
public struct ProcessSample: Sendable, Equatable {
    public var pid: Int32
    public var name: String
    public var bundlePath: String?
    public var cpuNanos: UInt64
    public var footprint: UInt64

    public init(pid: Int32, name: String, bundlePath: String? = nil, cpuNanos: UInt64, footprint: UInt64) {
        self.pid = pid; self.name = name; self.bundlePath = bundlePath; self.cpuNanos = cpuNanos; self.footprint = footprint
    }
}

/// One process's accumulated GPU time (nanoseconds), summed over its GPU connections.
public struct GPUClient: Sendable, Equatable {
    public var pid: Int32
    public var name: String
    public var bundlePath: String?
    public var gpuNanos: UInt64

    public init(pid: Int32, name: String, bundlePath: String? = nil, gpuNanos: UInt64) {
        self.pid = pid; self.name = name; self.bundlePath = bundlePath; self.gpuNanos = gpuNanos
    }
}

/// Everything read in one tick. Cumulative counters only; the sampler turns two of these into rates.
public struct SystemSnapshot: Sendable {
    public var at: UInt64 // monotonic nanoseconds
    public var ticks: CPUTicks?
    public var memory: MemoryStats?
    public var pressureLevel: Int?
    public var cpuTemperature: Double?
    public var gpuTemperature: Double?
    public var gpuUtilization: Double?
    public var gpuClients: [GPUClient]? // nil when the GPU does not report per-app time
    public var processes: [ProcessSample]
    public var uptime: TimeInterval?

    public init(at: UInt64, ticks: CPUTicks? = nil, memory: MemoryStats? = nil, pressureLevel: Int? = nil,
                cpuTemperature: Double? = nil, gpuTemperature: Double? = nil, gpuUtilization: Double? = nil,
                gpuClients: [GPUClient]? = nil, processes: [ProcessSample] = [], uptime: TimeInterval? = nil) {
        self.at = at; self.ticks = ticks; self.memory = memory; self.pressureLevel = pressureLevel
        self.cpuTemperature = cpuTemperature; self.gpuTemperature = gpuTemperature; self.gpuUtilization = gpuUtilization
        self.gpuClients = gpuClients; self.processes = processes; self.uptime = uptime
    }
}

/// Where the System view's numbers come from. The live one reads the Mac; tests pass a fake.
public protocol SystemSource: Sendable {
    func snapshot() -> SystemSnapshot
}

/// An app's share of something (percent of one core, percent of the GPU, or bytes of memory).
public struct AppUsage: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let bundlePath: String?
    public let value: Double

    public init(name: String, bundlePath: String? = nil, value: Double) { self.name = name; self.bundlePath = bundlePath; self.value = value }

    /// Processes of one app add up; biggest first, at most `limit`, dropping anything below `minimum`.
    public static func ranked(_ items: [AppUsage], minimum: Double = 0, limit: Int = SystemSampler.appRows) -> [AppUsage] {
        var byName: [String: AppUsage] = [:]
        for u in items {
            let old = byName[u.name]
            byName[u.name] = AppUsage(name: u.name, bundlePath: old?.bundlePath ?? u.bundlePath, value: (old?.value ?? 0) + u.value)
        }
        return byName.values.filter { $0.value > minimum }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.name < $1.name }
            .prefix(limit).map { $0 }
    }
}

public enum UsageDelta {
    /// Percent of `elapsed` each key used between two cumulative counters. Keys missing on either side
    /// and counters that went backwards (a reused pid) are skipped.
    public static func percents<K: Hashable>(from a: [K: UInt64], to b: [K: UInt64], elapsed: UInt64) -> [K: Double] {
        guard elapsed > 0 else { return [:] }
        var out: [K: Double] = [:]
        for (k, now) in b {
            guard let before = a[k], now >= before else { continue }
            out[k] = Double(now - before) / Double(elapsed) * 100
        }
        return out
    }
}

/// The last `capacity` samples, oldest first.
public struct SampleHistory: Sendable, Equatable {
    public let capacity: Int
    public private(set) var values: [Double] = []

    public init(capacity: Int) { self.capacity = capacity }

    public mutating func add(_ v: Double) {
        values.append(v)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    public mutating func clear() { values.removeAll() }

    /// Spoken summary for VoiceOver, values in percent.
    public var summary: String {
        guard let last = values.last, let lo = values.min(), let hi = values.max() else { return "No history yet" }
        let avg = values.reduce(0, +) / Double(values.count)
        return String(format: "Now %.0f percent, low %.0f, high %.0f, average %.0f", last, lo, hi, avg)
    }
}

/// Text for the System view's numbers.
public enum SystemText {
    /// "512 MB", "1.24 GB", "11.1 GB", "16 GB": three significant digits, whole numbers without a decimal.
    public static func bytes(_ b: UInt64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb < 1 { return String(format: "%.0f MB", Double(b) / 1_048_576) }
        if abs(gb - gb.rounded()) < 0.005 { return String(format: "%.0f GB", gb) }
        return String(format: gb < 10 ? "%.2f GB" : gb < 100 ? "%.1f GB" : "%.0f GB", gb)
    }

    /// "Up for 1d 22h", "Up for 5h 12m", "Up for 12m".
    public static func uptime(_ t: TimeInterval) -> String {
        let m = max(0, Int(t) / 60)
        if m >= 1440 { return "Up for \(m / 1440)d \(m % 1440 / 60)h" }
        if m >= 60 { return "Up for \(m / 60)h \(m % 60)m" }
        return "Up for \(m)m"
    }

    /// Stored in Celsius, shown in the unit the Mac's region uses for weather (same as the charge settings).
    public static func temperature(_ c: Double, locale: Locale = .current) -> String {
        Measurement(value: c, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    /// Header percent: whole numbers. App rows: one decimal under 10, like Activity Monitor.
    public static func percent(_ p: Double) -> String { String(format: "%.0f%%", p) }
    public static func appPercent(_ p: Double) -> String { String(format: p < 10 ? "%.1f%%" : "%.0f%%", p) }
}

/// Samples only while a view holds it, like the battery sampler. Reads run off the main thread.
@MainActor @Observable
public final class SystemSampler {
    /// Two minutes of history at the 2 s interval.
    public nonisolated static let historyLength = 60
    public nonisolated static let appRows = 8

    public private(set) var latest: SystemReading?
    public private(set) var cpuHistory = SampleHistory(capacity: historyLength)
    public private(set) var gpuHistory = SampleHistory(capacity: historyLength)
    public private(set) var memoryHistory = SampleHistory(capacity: historyLength)
    /// Busiest apps; empty until two samples have been taken.
    public private(set) var cpuApps: [AppUsage] = []
    /// nil when this Mac does not report GPU time per app.
    public private(set) var gpuApps: [AppUsage]? = []
    public private(set) var memoryApps: [AppUsage] = []
    /// True once rates (CPU %, per-app use) have two samples to compare.
    public private(set) var hasRates = false

    @ObservationIgnored private var holders: Set<String> = []
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var last: SystemSnapshot?
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let source: any SystemSource

    public init(interval: Duration = .seconds(2), source: any SystemSource = LiveSystemSource()) {
        self.interval = interval
        self.source = source
    }

    public var isSampling: Bool { timer != nil }

    public func hold(_ name: String) {
        holders.insert(name)
        guard timer == nil else { return }
        timer = Task { [weak self, source, interval] in
            while !Task.isCancelled {
                let snap = await Task.detached { source.snapshot() }.value
                guard !Task.isCancelled else { return }
                self?.ingest(snap)
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func release(_ name: String) {
        holders.remove(name)
        guard holders.isEmpty, timer != nil else { return }
        timer?.cancel(); timer = nil; last = nil; hasRates = false
        // A graph that resumes after a gap would join two unrelated stretches, so history starts over.
        cpuHistory.clear(); gpuHistory.clear(); memoryHistory.clear()
        cpuApps = []; gpuApps = []; memoryApps = []
    }

    func ingest(_ s: SystemSnapshot) {
        let prev = last
        last = s
        let elapsed = prev.map { s.at > $0.at ? s.at - $0.at : 0 } ?? 0
        let cpu = prev?.ticks.flatMap { a in s.ticks.flatMap { CPUTicks.percent(from: a, to: $0) } } ?? latest?.cpuPercent
        latest = SystemReading(cpuPercent: cpu, gpuPercent: s.gpuUtilization, memory: s.memory,
                               pressure: s.pressureLevel.flatMap(MemoryPressure.init(level:)),
                               cpuTemperature: s.cpuTemperature, gpuTemperature: s.gpuTemperature, uptime: s.uptime)
        if prev != nil, let cpu { cpuHistory.add(cpu) }
        if let g = s.gpuUtilization { gpuHistory.add(g) }
        if let m = s.memory { memoryHistory.add(m.fraction * 100) }
        memoryApps = AppUsage.ranked(s.processes.map { AppUsage(name: $0.name, bundlePath: $0.bundlePath, value: Double($0.footprint)) })

        guard let prev, elapsed > 0 else { gpuApps = s.gpuClients == nil ? nil : []; return }
        hasRates = true
        let cpuShares = UsageDelta.percents(from: Dictionary(prev.processes.map { ($0.pid, $0.cpuNanos) }, uniquingKeysWith: max),
                                            to: Dictionary(s.processes.map { ($0.pid, $0.cpuNanos) }, uniquingKeysWith: max), elapsed: elapsed)
        cpuApps = AppUsage.ranked(s.processes.compactMap { p in cpuShares[p.pid].map { AppUsage(name: p.name, bundlePath: p.bundlePath, value: $0) } },
                                  minimum: 0.05)
        if let now = s.gpuClients, let before = prev.gpuClients {
            let gpuShares = UsageDelta.percents(from: Dictionary(before.map { ($0.pid, $0.gpuNanos) }, uniquingKeysWith: +),
                                                to: Dictionary(now.map { ($0.pid, $0.gpuNanos) }, uniquingKeysWith: +), elapsed: elapsed)
            let byPid = Dictionary(now.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
            gpuApps = AppUsage.ranked(gpuShares.compactMap { pid, p in byPid[pid].map { AppUsage(name: $0.name, bundlePath: $0.bundlePath, value: min(p, 100)) } },
                                      minimum: 0.05)
        } else {
            gpuApps = s.gpuClients == nil ? nil : []
        }
    }
}
