import Foundation
import IOKit
import IOKit.ps
import Observation
import os

/// One reading of the battery, all values straight from the system.
extension BatteryReading {
    /// While the limiter holds the charger off, the Mac runs wholly from the battery. One telemetry sample can still say
    /// the battery is charging; the map shows the held truth: the battery covers the Mac's whole load, nothing charges.
    /// The charge to show people: the battery's own figure (macOS rounds and can lag by several points while the battery
    /// drains, for example in a hold), except that a full battery on a charger reads 100.
    public var shownPercent: Double {
        guard let m = measuredPercent else { return Double(percent) }
        if percent >= 100 && batteryWatts >= -0.5 { return 100 }
        return min(max(m, 0), 100)
    }
    /// `shownPercent` as text: one decimal, no decimal at exactly 100.
    public var shownPercentText: String { shownPercent >= 100 ? "100%" : String(format: "%.1f%%", shownPercent) }

    public func whileHeld() -> BatteryReading {
        guard isPluggedIn else { return self }
        var r = self
        r.batteryWatts = -(systemWatts ?? max(-batteryWatts, 0))
        r.isCharging = false
        r.adapterLossWatts = nil // a charger held off has no conversion loss to report
        return r
    }
}

public struct BatteryReading: Sendable, Equatable {
    public var date: Date
    public var percent: Int              // as macOS shows it
    public var measuredPercent: Double?  // raw charge / raw max, no rounding by macOS
    /// The level the charge limit compares against: the same figure the app shows (`shownPercent`), so the limit holds the
    /// number on screen. macOS's own percentage can sit several points above the battery's real charge, charging or not.
    public var limitLevel: Int { Int(shownPercent.rounded()) }
    public var isPluggedIn: Bool
    public var isCharging: Bool
    public var cycleCount: Int?
    public var temperatureC: Double?     // nil when neither the battery entry nor the SMC gives it
    public var magSafeLight: MagSafeLight = .notAvailable // read only, from the SMC (readWithSensors)
    public var capacityVsDesign: Double? // measured full charge / design capacity, 0...1
    public var batteryWatts: Double      // + charging, - discharging
    public var systemWatts: Double?      // what the Mac is using
    public var adapterWatts: Int?
    public var minutesRemaining: Int?
    public var adapterVolts: Double?     // the charger's negotiated voltage
    public var adapterAmps: Double?      // the charger's current limit
    public var usbOutWatts: Double?      // power this Mac hands to devices on its USB-C ports (PowerOutDetails), nil when not reported
    public var adapterLossWatts: Double? // lost as heat in the charger path (PowerTelemetryData.AdapterEfficiencyLoss)
    /// The iPhone or iPad this Mac is powering over USB, by the name it gives ("iPhone"). Filled by `BatteryReader.read()` from
    /// the USB tree, and only when exactly one port gives power and exactly one such device is attached, so it is never a guess.
    public var usbDeviceName: String?
    /// That device's own battery level, 0...100, as it reports it over USB-C power delivery (FedDetails). nil when it does not.
    public var usbDeviceCharge: Int?
    /// How many USB-C ports are giving power right now (PowerOutDetails entries above 0 W).
    public var usbPoweredPorts = 0

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
        if let t = int(d["Temperature"]), (1...90).contains(Double(t) / 100) { temperatureC = Double(t) / 100 } // same filter as the SMC path
        if let raw = int(bd["AppleRawCurrentCapacity"]), let max = int(bd["AppleRawMaxCapacity"]), max > 0 {
            measuredPercent = Double(raw) / Double(max) * 100
            if let design = int(bd["DesignCapacity"]), design > 0 { capacityVsDesign = Double(max) / Double(design) }
        }
        // InstantAmperage is a signed 64-bit value stored unsigned when negative.
        let amps = Int64(truncatingIfNeeded: (d["InstantAmperage"] as? NSNumber)?.uint64Value ?? 0)
        let volts = Double(int(d["Voltage"]) ?? 0)
        batteryWatts = Double(amps) * volts / 1_000_000
        if let t = d["PowerTelemetryData"] as? [String: Any] {
            if let load = int(t["SystemLoad"]) { systemWatts = Double(load) / 1000 }
            if let loss = int(t["AdapterEfficiencyLoss"]) { adapterLossWatts = Double(loss) / 1000 }
        }
        if let ports = d["PowerOutDetails"] as? [[String: Any]] {
            usbOutWatts = ports.reduce(0) { $0 + Double(int($1["Watts"]) ?? 0) } / 1000 // milliwatts
            usbPoweredPorts = ports.filter { (int($0["Watts"]) ?? 0) > 0 }.count
        }
        // A device on a USB-C port that has a battery reports it here (measured on an M5 Mac with an iPhone: FedStateOfCharge
        // matched the phone and rose as it charged). Entries for empty ports and the charger are all zero. Only one powered
        // port and one battery entry name a level, so a level is never pinned on the wrong device.
        if usbPoweredPorts == 1, let fed = d["FedDetails"] as? [[String: Any]] {
            let levels = fed.compactMap { f -> Int? in
                guard (int(f["FedDesignCapacity"]) ?? 0) > 0, let soc = int(f["FedStateOfCharge"]), (0...100).contains(soc) else { return nil }
                return soc
            }
            if levels.count == 1 { usbDeviceCharge = levels[0] }
        }
        let adapter = d["AdapterDetails"] as? [String: Any]
        adapterWatts = int(adapter?["Watts"])
        adapterVolts = int(adapter?["AdapterVoltage"]).map { Double($0) / 1000 } // millivolts
        adapterAmps = int(adapter?["Current"]).map { Double($0) / 1000 }         // milliamps
        if let m = int(d["TimeRemaining"]), m != 65535 { minutesRemaining = m }
    }
}

extension BatteryReading {
    /// Plain-language state, shared by the panel and Shortcuts.
    /// What the USB tile is called: the device's name when it is known, otherwise "USB".
    public var usbLabel: String { usbDeviceName ?? "USB" }
    /// The USB tile's caption: the name plus the device's own battery level when it reports one, e.g. "iPhone 15%".
    public var usbCaption: String { usbDeviceCharge.map { "\(usbLabel) \($0)%" } ?? usbLabel }

    public var stateText: String { isCharging ? "Charging" : isPluggedIn ? "Plugged in, not charging" : "On battery" }
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
        guard var r = BatteryReading(properties: dict) else { return nil }
        if r.usbPoweredPorts == 1 { r.usbDeviceName = iOSDeviceName() } // the USB tree is walked only while a port gives power
        return r
    }

    /// The name of the one iPhone, iPad or iPod on the Mac's USB ports ("SupportsIPhoneOS" in the USB tree). nil for none or several.
    static func iOSDeviceName() -> String? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        func prop(_ s: io_object_t, _ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        var names: [String] = []
        var s = IOIteratorNext(it)
        while s != 0 {
            if (prop(s, "SupportsIPhoneOS") as? Bool) == true, let n = prop(s, "USB Product Name") as? String, !n.isEmpty { names.append(n) }
            IOObjectRelease(s)
            s = IOIteratorNext(it)
        }
        return names.count == 1 ? names[0] : nil
    }

    /// `read()` plus the SMC battery temperature (when the battery entry has none, as on Apple silicon) and the MagSafe light.
    /// The sampler uses it, and it runs only while something on the Battery tool shows or uses readings.
    public static func readWithSensors() -> BatteryReading? {
        guard var r = read() else { return nil }
        let s = BatterySensors.read()
        if r.temperatureC == nil { r.temperatureC = s.temperatureC }
        r.magSafeLight = s.light
        return r
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
    /// True when the process lives in an app bundle (a user app), false for daemons and bare tools.
    public var isApp = false
}

public enum EnergyUsers {
    /// Parses `ps -Ao pid=,pcpu=,comm=` output, busiest first. Names are the app bundle name when there is one.
    public static func parse(_ output: String, limit: Int = 5) -> [EnergyUser] {
        let users: [EnergyUser] = output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int(parts[0]), let cpu = Double(parts[1]) else { return nil }
            let path = String(parts[2])
            var name = (path as NSString).lastPathComponent
            var isApp = false
            if let app = path.components(separatedBy: "/").first(where: { $0.hasSuffix(".app") }) { name = String(app.dropLast(4)); isApp = true }
            return EnergyUser(pid: pid, name: name, cpu: cpu, isApp: isApp)
        }
        // Several processes of one app add up.
        var byName: [String: EnergyUser] = [:]
        for u in users {
            let old = byName[u.name]
            byName[u.name] = EnergyUser(pid: old?.pid ?? u.pid, name: u.name, cpu: (old?.cpu ?? 0) + u.cpu, isApp: (old?.isApp ?? false) || u.isApp)
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
        return parse(String(decoding: data, as: UTF8.self), limit: 40) // the view filters and shows the top few
    }
}

/// Samples while at least one consumer (open battery view, menu bar readout) holds it. No holders, no timer.
@MainActor @Observable
public final class BatterySampler {
    public private(set) var latest: BatteryReading?
    public private(set) var history = BatteryHistory()
    public private(set) var energyUsers: [EnergyUser] = []
    @ObservationIgnored private var holders: Set<String> = []
    /// The Battery screen's hold; the only one that shows the energy list.
    public static let viewHolder = "batteryView"
    @ObservationIgnored private var timer: Task<Void, Never>?
    public nonisolated static let log = Logger(subsystem: "app.rarecreatures.applecart", category: "power")
    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var notePort: IONotificationPortRef?
    @ObservationIgnored private var note: io_object_t = 0
    @ObservationIgnored private var adapterSeen = false
    @ObservationIgnored private var settle: Task<Void, Never>?
    /// Seconds between samples; read before each wait, so a change applies from the next tick.
    @ObservationIgnored public var interval: Duration
    @ObservationIgnored private let read: @Sendable () -> BatteryReading?

    public init(interval: Duration = .seconds(5), read: @escaping @Sendable () -> BatteryReading? = BatteryReader.readWithSensors) {
        self.interval = interval
        self.read = read
    }

    public var isSampling: Bool { timer != nil }

    public func hold(_ name: String) {
        holders.insert(name)
        guard timer == nil else {
            if name == Self.viewHolder { sample(addToHistory: false) } // fill the energy list now, not at the next tick
            return
        }
        sample()
        watchPowerSource()
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
        if holders.isEmpty {
            timer?.cancel(); timer = nil
            settle?.cancel(); settle = nil
            if let src = powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes); powerSource = nil }
            if note != 0 { IOObjectRelease(note); note = 0 }
            if let port = notePort { IONotificationPortDestroy(port); notePort = nil }
        }
    }

    /// macOS tells us the moment the charger is plugged in or removed, so the icon follows at once
    /// instead of waiting for the next timer tick.
    private func watchPowerSource() {
        guard powerSource == nil else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<BatterySampler>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.powerChanged() }
        }, ctx)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        powerSource = src
        // The battery's own registry entry speaks about a second before macOS flips "plugged in".
        // Measured on this Mac: the adapter details vanish ~1.0 s before ExternalConnected goes to 0.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        defer { IOObjectRelease(service) }
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)
        var n: io_object_t = 0
        let ok = IOServiceAddInterestNotification(port, service, kIOGeneralInterest, { ctx, _, _, _ in
            guard let ctx else { return }
            let me = Unmanaged<BatterySampler>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.sample(withEnergyUsers: false, addToHistory: false) }
        }, ctx, &n)
        if ok == KERN_SUCCESS { notePort = port; note = n } else { IONotificationPortDestroy(port) }
    }

    /// The adapter details disappear before macOS flips ExternalConnected on unplug (and appear before it on plug-in).
    /// Only trusted once this adapter has been seen with details, so an adapter that never reports them still works.
    private func adjusted(_ raw: BatteryReading) -> BatteryReading {
        var r = raw
        let present = raw.adapterWatts != nil
        if raw.isPluggedIn && !present && adapterSeen { r.isPluggedIn = false; r.isCharging = false }
        else if !raw.isPluggedIn && present { r.isPluggedIn = true }
        // Stay "seen" through the about-one-second window where the flag still lags; forget only once macOS agrees.
        if present { adapterSeen = true } else if !raw.isPluggedIn { adapterSeen = false }
        return r
    }

    /// Read now, then again as the charger's numbers settle (charging state and watts lag the plug by a second or two).
    private func powerChanged() {
        Self.log.debug("power notification")
        sample(withEnergyUsers: false, addToHistory: false)
        settle?.cancel()
        settle = Task { [weak self] in
            for ms in [400, 800, 1500] {
                try? await Task.sleep(for: .milliseconds(ms))
                guard !Task.isCancelled else { return }
                self?.sample(withEnergyUsers: false, addToHistory: false)
            }
        }
    }

    private func sample(withEnergyUsers: Bool = true, addToHistory: Bool = true) {
        guard let raw = read() else { return }
        let r = adjusted(raw)
        Self.log.debug("sample plugged=\(r.isPluggedIn) charging=\(r.isCharging) energyUsers=\(withEnergyUsers)")
        if r != latest { latest = r }
        if addToHistory { history.add(r) }
        guard withEnergyUsers, holders.contains(Self.viewHolder) else { return } // ps only while the Battery screen shows the list
        Task.detached { [weak self] in
            let users = EnergyUsers.current()
            await MainActor.run { self?.energyUsers = users }
        }
    }
}
