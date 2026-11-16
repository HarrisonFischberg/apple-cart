import Darwin
import Foundation
import IOKit

/// Reads the Mac for the System view. All read-only and unprivileged; nothing is stored.
public final class LiveSystemSource: SystemSource, @unchecked Sendable {
    private let lock = NSLock()
    private var smcKeys: ChipTemperatures.Keys? // listed once; the SMC's key list does not change while running

    public init() {}

    public func snapshot() -> SystemSnapshot {
        let temps = temperatures()
        let gpu = GPUReader.read()
        return SystemSnapshot(at: DispatchTime.now().uptimeNanoseconds, ticks: SystemReader.cpuTicks(), memory: SystemReader.memory(),
                              pressureLevel: SystemReader.pressureLevel(), cpuTemperature: temps.cpu, gpuTemperature: temps.gpu,
                              gpuUtilization: gpu.utilization, gpuClients: gpu.clients, processes: ProcessReader.all(),
                              uptime: SystemReader.uptime())
    }

    private func temperatures() -> (cpu: Double?, gpu: Double?) {
        lock.lock(); defer { lock.unlock() }
        guard let smc = SMCReader() else { return (nil, nil) }
        if smcKeys == nil { smcKeys = ChipTemperatures.keys(in: smc.allKeys()) }
        guard let keys = smcKeys else { return (nil, nil) }
        let cpu = Dictionary(keys.cpu.compactMap { k in smc.float(k).map { (k, $0) } }, uniquingKeysWith: { a, _ in a })
        let gpu = Dictionary(keys.gpu.compactMap { k in smc.float(k).map { (k, $0) } }, uniquingKeysWith: { a, _ in a })
        return (ChipTemperatures.average(cpu), ChipTemperatures.average(gpu))
    }
}

public enum SystemReader {
    public static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let t = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3].map(UInt64.init)
        return CPUTicks(busy: t[0] + t[1] + t[3], total: t.reduce(0, +)) // user + system + nice; idle is index 2
    }

    /// Used = active + wired + compressed, the figure Activity Monitor calls Memory Used.
    public static func memory() -> MemoryStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        let compressed = UInt64(stats.compressor_page_count) * page
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count)) * page + compressed
        var swap = xsw_usage(); var size = MemoryLayout<xsw_usage>.size
        let swapUsed = sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 ? swap.xsu_used : 0
        return MemoryStats(used: used, total: ProcessInfo.processInfo.physicalMemory, compressed: compressed,
                           cached: UInt64(stats.external_page_count) * page, swapUsed: swapUsed)
    }

    public static func pressureLevel() -> Int? {
        var level: Int32 = 0; var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 ? Int(level) : nil
    }

    /// Wall-clock time since boot, sleep included (what `uptime` prints).
    public static func uptime() -> TimeInterval? {
        var boot = timeval(); var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date().timeIntervalSince1970 - (Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000)
    }
}

/// CPU and GPU die temperatures from the SMC's float sensor keys. Measured on an M5 (Mac17,2, macOS 27.2):
/// Tp* (performance cores) and Te* (efficiency cores) for the CPU, Tg* for the GPU.
public enum ChipTemperatures {
    public struct Keys: Sendable, Equatable { public var cpu: [String]; public var gpu: [String] }

    static let cpuPrefixes = ["Tp", "Te"], gpuPrefixes = ["Tg"]

    /// The float keys that name CPU and GPU sensors; nil when there are none (older or different SMC).
    public static func keys(in all: [(name: String, type: String)]) -> Keys? {
        let floats = all.filter { $0.type == "flt " }.map(\.name)
        let k = Keys(cpu: floats.filter { n in cpuPrefixes.contains { n.hasPrefix($0) } }, gpu: floats.filter { n in gpuPrefixes.contains { n.hasPrefix($0) } })
        return k.cpu.isEmpty && k.gpu.isEmpty ? nil : k
    }

    /// Mean of the plausible readings; sensors that are off read 0 and are left out. nil when none are plausible.
    public static func average(_ readings: [String: Double]) -> Double? {
        let ok = readings.values.filter { (5...130).contains($0) }
        return ok.isEmpty ? nil : ok.reduce(0, +) / Double(ok.count)
    }
}

/// Read-only AppleSMC client (same struct layout as spikes/smc-probe). It never writes; reading needs no privileges.
struct SMCReader {
    private struct Vers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0; var attrs: UInt8 = 0 }
    private struct KeyData {
        var key: UInt32 = 0; var vers = Vers(); var pLimit = PLimit(); var info = KeyInfo(); var pad: UInt16 = 0
        var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0; var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }
    private static let readBytes: UInt8 = 5, readIndex: UInt8 = 8, readInfo: UInt8 = 9

    private let conn: Connection

    /// Closes the connection when the last copy goes away.
    private final class Connection {
        let id: io_connect_t
        init(_ id: io_connect_t) { self.id = id }
        deinit { IOServiceClose(id) }
    }

    init?() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var c: io_connect_t = 0
        guard IOServiceOpen(svc, mach_task_self_, 0, &c) == KERN_SUCCESS else { return nil }
        conn = Connection(c)
        _ = IOConnectCallMethod(c, 0, nil, 0, nil, 0, nil, nil, nil, nil) // user client open, as the probe does
    }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    private static func name(_ v: UInt32) -> String { String(decoding: (0..<4).map { UInt8((v >> UInt32(24 - 8 * $0)) & 0xff) }, as: UTF8.self) }

    private func call(_ input: KeyData) -> KeyData? {
        var i = input, out = KeyData(); var size = MemoryLayout<KeyData>.size
        let r = IOConnectCallStructMethod(conn.id, 2, &i, MemoryLayout<KeyData>.size, &out, &size)
        return r == KERN_SUCCESS && out.result == 0 ? out : nil
    }

    private func info(_ key: UInt32) -> KeyInfo? {
        var d = KeyData(); d.key = key; d.data8 = Self.readInfo
        return call(d)?.info
    }

    /// Every key with its type, e.g. ("Tp00", "flt ").
    func allKeys() -> [(name: String, type: String)] {
        var d = KeyData(); d.key = Self.fourCC("#KEY"); d.info.dataSize = 4; d.data8 = Self.readBytes
        guard let out = call(d) else { return [] }
        let count = withUnsafeBytes(of: out.bytes) { $0.load(as: UInt32.self).bigEndian }
        return (0..<min(count, 10_000)).compactMap { i in
            var q = KeyData(); q.data8 = Self.readIndex; q.data32 = i
            guard let k = call(q)?.key, let ki = info(k) else { return nil }
            return (Self.name(k), Self.name(ki.dataType))
        }
    }

    /// A 4-byte little-endian float key, or nil.
    func float(_ key: String) -> Double? {
        let k = Self.fourCC(key)
        var d = KeyData(); d.key = k; d.info.dataSize = 4; d.data8 = Self.readBytes
        guard let out = call(d) else { return nil }
        return Double(Float(bitPattern: UInt32(truncatingIfNeeded: out.bytes.0)))
    }
}

/// GPU load and per-app GPU time from the IORegistry (IOAccelerator and its user clients), no privileges needed.
enum GPUReader {
    static func read() -> (utilization: Double?, clients: [GPUClient]?) {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return (nil, nil) }
        defer { IOObjectRelease(it) }
        var util: Double?
        var times: [Int32: UInt64] = [:]
        var sawUsage = false
        while case let svc = IOIteratorNext(it), svc != 0 {
            defer { IOObjectRelease(svc) }
            if let stats = property(svc, "PerformanceStatistics") as? [String: Any], let u = stats["Device Utilization %"] as? NSNumber {
                util = max(util ?? 0, u.doubleValue)
            }
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(svc, kIOServicePlane, &children) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(children) }
            while case let c = IOIteratorNext(children), c != 0 {
                defer { IOObjectRelease(c) }
                guard let creator = property(c, "IOUserClientCreator") as? String, let pid = pid(fromCreator: creator),
                      let usage = property(c, "AppUsage") as? [[String: Any]] else { continue }
                sawUsage = true
                times[pid, default: 0] += usage.reduce(0) { $0 + (($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value ?? 0) }
            }
        }
        let clients = times.map { pid, ns in
            let n = ProcessReader.name(pid: pid)
            return GPUClient(pid: pid, name: n.name, bundlePath: n.bundlePath, gpuNanos: ns)
        }
        return (util, sawUsage ? clients : nil)
    }

    /// "pid 680, Safari" -> 680.
    static func pid(fromCreator s: String) -> Int32? {
        guard s.hasPrefix("pid ") else { return nil }
        return Int32(s.dropFirst(4).prefix { $0.isNumber })
    }

    private static func property(_ e: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(e, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

/// CPU time and memory footprint of every process this user may read (others are skipped). Numbers only.
enum ProcessReader {
    private static let ticksToNanos: Double = {
        var tb = mach_timebase_info(); mach_timebase_info(&tb)
        return tb.denom == 0 ? 1 : Double(tb.numer) / Double(tb.denom)
    }()

    static func all() -> [ProcessSample] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(n) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        return pids.prefix(Int(max(got, 0))).compactMap { pid in
            guard pid > 0 else { return nil }
            var ri = rusage_info_v4()
            let r = withUnsafeMutablePointer(to: &ri) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) } }
            guard r == 0 else { return nil }
            let n = name(pid: pid)
            // rusage times are mach ticks on Apple silicon.
            let cpu = UInt64(Double(ri.ri_user_time + ri.ri_system_time) * ticksToNanos)
            return ProcessSample(pid: pid, name: n.name, bundlePath: n.bundlePath, cpuNanos: cpu, footprint: ri.ri_phys_footprint)
        }
    }

    static func name(pid: Int32) -> (name: String, bundlePath: String?) {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else {
            var short = [CChar](repeating: 0, count: 64)
            return (proc_name(pid, &short, UInt32(short.count)) > 0 ? cString(short) : "pid \(pid)", nil)
        }
        return name(path: cString(buf))
    }

    private static func cString(_ b: [CChar]) -> String { String(decoding: b.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) }

    /// The app a binary belongs to: the outermost ".app" in its path, so helpers count toward their app.
    static func name(path: String) -> (name: String, bundlePath: String?) {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        if let i = parts.firstIndex(where: { $0.hasSuffix(".app") }) {
            return (String(parts[i].dropLast(4)), parts[...i].joined(separator: "/"))
        }
        return ((path as NSString).lastPathComponent, nil)
    }
}
