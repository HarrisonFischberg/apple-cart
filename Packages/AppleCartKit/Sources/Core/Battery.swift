import Foundation
import IOKit
import Observation

/// One reading of the battery, all values straight from the system.
public struct BatteryReading: Sendable, Equatable {
    public var date: Date
    public var percent: Int              // as macOS shows it
    public var measuredPercent: Double?  // raw charge / raw max, no rounding by macOS
    public var isPluggedIn: Bool
    public var isCharging: Bool
    public var cycleCount: Int?
    public var temperatureC: Double?     // nil when the OS does not expose it
    public var capacityVsDesign: Double? // measured full charge / design capacity, 0...1
    public var batteryWatts: Double      // + charging, - discharging
    public var systemWatts: Double?      // what the Mac is using
    public var adapterWatts: Int?
    public var minutesRemaining: Int?

    /// Builds a reading from the AppleSmartBattery property dictionary (top level plus nested BatteryData).
    public init?(properties d: [String: Any], date: Date = Date()) {
        func int(_ x: Any?) -> Int? { (x as? NSNumber)?.intValue }
        guard let percent = int(d["CurrentCapacity"]) else { return nil }
        let bd = d["BatteryData"] as? [String: Any] ?? [:]
        self.date = date
        self.percent = percent
        isPluggedIn = int(d["ExternalConnected"]) == 1
        isCharging = int(d["IsCharging"]) == 1
        cycleCount = int(d["CycleCount"]) ?? int(bd["CycleCount"])
        if let t = int(d["Temperature"]) { temperatureC = Double(t) / 100 }
        if let raw = int(bd["AppleRawCurrentCapacity"]), let max = int(bd["AppleRawMaxCapacity"]), max > 0 {
            measuredPercent = Double(raw) / Double(max) * 100
            if let design = int(bd["DesignCapacity"]), design > 0 { capacityVsDesign = Double(max) / Double(design) }
        }
        // InstantAmperage is a signed 64-bit value stored unsigned when negative.
        let amps = Int64(truncatingIfNeeded: (d["InstantAmperage"] as? NSNumber)?.uint64Value ?? 0)
        let volts = Double(int(d["Voltage"]) ?? 0)
        batteryWatts = Double(amps) * volts / 1_000_000
        if let t = d["PowerTelemetryData"] as? [String: Any], let load = int(t["SystemLoad"]) {
            systemWatts = Double(load) / 1000
        }
        adapterWatts = int((d["AdapterDetails"] as? [String: Any])?["Watts"])
        if let m = int(d["TimeRemaining"]), m != 65535 { minutesRemaining = m }
    }
}

public enum BatteryReader {
    /// nil on a Mac without a battery.
    public static func read() -> BatteryReading? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return BatteryReading(properties: dict)
    }
}

/// Rolling 24 hour history. Gaps stay gaps: it only holds what was actually sampled.
public struct BatteryHistory: Sendable, Equatable {
    public static let window: TimeInterval = 24 * 3600
    public private(set) var samples: [BatteryReading] = []

    public init() {}

    public mutating func add(_ r: BatteryReading) {
        samples.append(r)
        samples.removeAll { r.date.timeIntervalSince($0.date) > Self.window }
    }
}

public struct EnergyUser: Sendable, Equatable, Identifiable {
    public var id: Int { pid }
    public let pid: Int
    public let name: String
    public let cpu: Double
}

public enum EnergyUsers {
    /// Parses `ps -Ao pid=,pcpu=,comm=` output, busiest first. Names are the app bundle name when there is one.
    public static func parse(_ output: String, limit: Int = 5) -> [EnergyUser] {
        let users: [EnergyUser] = output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int(parts[0]), let cpu = Double(parts[1]) else { return nil }
            let path = String(parts[2])
            var name = (path as NSString).lastPathComponent
            if let app = path.components(separatedBy: "/").first(where: { $0.hasSuffix(".app") }) { name = String(app.dropLast(4)) }
            return EnergyUser(pid: pid, name: name, cpu: cpu)
        }
        // Several processes of one app add up.
        var byName: [String: EnergyUser] = [:]
        for u in users {
            let old = byName[u.name]
            byName[u.name] = EnergyUser(pid: old?.pid ?? u.pid, name: u.name, cpu: (old?.cpu ?? 0) + u.cpu)
        }
        return byName.values.sorted { $0.cpu > $1.cpu }.prefix(limit).map { $0 }
    }

    public static func current() -> [EnergyUser] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Ao", "pid=,pcpu=,comm=", "-r"]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }
}

/// Samples while at least one consumer (open battery view, menu bar readout) holds it. No holders, no timer.
@MainActor @Observable
public final class BatterySampler {
    public private(set) var latest: BatteryReading?
    public private(set) var history = BatteryHistory()
    public private(set) var energyUsers: [EnergyUser] = []
    @ObservationIgnored private var holders: Set<String> = []
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let read: @Sendable () -> BatteryReading?

    public init(interval: Duration = .seconds(5), read: @escaping @Sendable () -> BatteryReading? = BatteryReader.read) {
        self.interval = interval
        self.read = read
    }

    public var isSampling: Bool { timer != nil }

    public func hold(_ name: String) {
        holders.insert(name)
        guard timer == nil else { return }
        sample()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.interval ?? .seconds(5))
                guard !Task.isCancelled else { return }
                self?.sample()
            }
        }
    }

    public func release(_ name: String) {
        holders.remove(name)
        if holders.isEmpty { timer?.cancel(); timer = nil }
    }

    private func sample() {
        guard let r = read() else { return }
        latest = r
        history.add(r)
        Task.detached { [weak self] in
            let users = EnergyUsers.current()
            await MainActor.run { self?.energyUsers = users }
        }
    }
}
