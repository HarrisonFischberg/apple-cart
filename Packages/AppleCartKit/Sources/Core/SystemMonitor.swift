import Darwin
import Foundation
import Observation

public struct SystemReading: Sendable, Equatable {
    public var cpuPercent: Double      // across all cores, 0...100
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    public var thermal: ProcessInfo.ThermalState
    public var uptime: TimeInterval

    public var memoryFraction: Double { memoryTotalBytes == 0 ? 0 : Double(memoryUsedBytes) / Double(memoryTotalBytes) }
}

public struct CPUTicks: Sendable, Equatable {
    public var busy: UInt64
    public var total: UInt64

    /// Usage between two readings; nil when no time passed.
    public static func percent(from a: CPUTicks, to b: CPUTicks) -> Double? {
        guard b.total > a.total, b.busy >= a.busy else { return nil }
        return Double(b.busy - a.busy) / Double(b.total - a.total) * 100
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
    public static func memory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (used, ProcessInfo.processInfo.physicalMemory)
    }
}

/// Samples only while a view holds it, like the battery sampler.
@MainActor @Observable
public final class SystemSampler {
    public private(set) var latest: SystemReading?
    @ObservationIgnored private var holders: Set<String> = []
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var lastTicks: CPUTicks?
    @ObservationIgnored private let interval: Duration

    public init(interval: Duration = .seconds(2)) { self.interval = interval }

    public var isSampling: Bool { timer != nil }

    public func hold(_ name: String) {
        holders.insert(name)
        guard timer == nil else { return }
        lastTicks = SystemReader.cpuTicks()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.interval ?? .seconds(2))
                guard !Task.isCancelled else { return }
                self?.sample()
            }
        }
    }

    public func release(_ name: String) {
        holders.remove(name)
        if holders.isEmpty { timer?.cancel(); timer = nil; lastTicks = nil }
    }

    private func sample() {
        guard let now = SystemReader.cpuTicks(), let mem = SystemReader.memory() else { return }
        let cpu = lastTicks.flatMap { CPUTicks.percent(from: $0, to: now) } ?? latest?.cpuPercent ?? 0
        lastTicks = now
        latest = SystemReading(cpuPercent: cpu, memoryUsedBytes: mem.used, memoryTotalBytes: mem.total,
                               thermal: ProcessInfo.processInfo.thermalState, uptime: ProcessInfo.processInfo.systemUptime)
    }
}
