import Foundation
import Testing
@testable import Core

/// Hands the sampler prepared snapshots, one per tick.
final class FakeSystemSource: SystemSource, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [SystemSnapshot]
    init(_ snaps: [SystemSnapshot]) { queue = snaps }
    func snapshot() -> SystemSnapshot {
        lock.lock(); defer { lock.unlock() }
        return queue.count > 1 ? queue.removeFirst() : queue[0]
    }
}

@Suite struct SystemStatsTests {
    @Test func historyKeepsTheNewestSamples() {
        var h = SampleHistory(capacity: 3)
        #expect(h.summary == "No history yet")
        for v in [10.0, 20, 30, 40] { h.add(v) }
        #expect(h.values == [20, 30, 40])
        #expect(h.summary == "Now 40 percent, low 20, high 40, average 30")
        h.clear(); #expect(h.values.isEmpty)
    }

    @Test func percentFromCounterDeltas() {
        let p = UsageDelta.percents(from: [1: 100, 2: 500, 3: 0], to: [1: 600, 2: 400, 4: 50], elapsed: 1000)
        #expect(p == [1: 50]) // 2 went backwards (pid reused), 3 ended, 4 is new
        #expect(UsageDelta.percents(from: [1: 0], to: [1: 10], elapsed: 0).isEmpty)
    }

    @Test func pressureLevelsMapToStatus() {
        #expect(MemoryPressure(level: 1) == .normal)
        #expect(MemoryPressure(level: 0) == .normal)
        #expect(MemoryPressure(level: 2) == .warning)
        #expect(MemoryPressure(level: 4) == .critical)
        #expect(MemoryPressure(level: -1) == nil)
        #expect(MemoryPressure.warning.title == "Warning")
    }

    @Test func textFormats() {
        let gb: UInt64 = 1_073_741_824
        #expect(SystemText.bytes(512 * 1_048_576) == "512 MB")
        #expect(SystemText.bytes(UInt64(1.24 * Double(gb))) == "1.24 GB")
        #expect(SystemText.bytes(UInt64(11.1 * Double(gb))) == "11.1 GB")
        #expect(SystemText.bytes(16 * gb) == "16 GB")
        #expect(SystemText.uptime(86_400 + 22 * 3600 + 59) == "Up for 1d 22h")
        #expect(SystemText.uptime(5 * 3600 + 12 * 60) == "Up for 5h 12m")
        #expect(SystemText.uptime(30) == "Up for 0m")
        #expect(SystemText.percent(25.4) == "25%")
        #expect(SystemText.appPercent(3.25) == "3.2%" || SystemText.appPercent(3.25) == "3.3%")
        #expect(SystemText.appPercent(42.6) == "43%")
        let c = SystemText.temperature(48, locale: Locale(identifier: "en_GB"))
        #expect(c.contains("48") && c.contains("°C"))
        let f = SystemText.temperature(48, locale: Locale(identifier: "en_US"))
        #expect(f.contains("118") && f.contains("°F"))
    }

    @Test func appsGroupSortAndCap() {
        let items = [AppUsage(name: "Safari", bundlePath: "/Applications/Safari.app", value: 3), AppUsage(name: "Mail", value: 9),
                     AppUsage(name: "Safari", value: 7), AppUsage(name: "Idle", value: 0.01)]
        let r = AppUsage.ranked(items, minimum: 0.05)
        #expect(r.map(\.name) == ["Safari", "Mail"])
        #expect(r[0].value == 10 && r[0].bundlePath == "/Applications/Safari.app")
        let many = (0..<12).map { AppUsage(name: "A\($0)", value: Double($0 + 1)) }
        #expect(AppUsage.ranked(many).count == SystemSampler.appRows)
        #expect(AppUsage.ranked(many).first?.name == "A11")
    }

    @Test func temperatureKeysAndAverage() {
        let keys = ChipTemperatures.keys(in: [("Tp00", "flt "), ("Te04", "flt "), ("Tg0C", "flt "), ("TG0B", "ioft"), ("TPD0", "flt "), ("TB0T", "flt ")])
        #expect(keys == .init(cpu: ["Tp00", "Te04"], gpu: ["Tg0C"]))
        #expect(ChipTemperatures.keys(in: [("TB0T", "flt ")]) == nil)
        #expect(ChipTemperatures.average(["Tp00": 50, "Tp04": 60, "Tz11": 0]) == 55)
        #expect(ChipTemperatures.average(["Tz11": 0]) == nil)
    }

    @Test func processNamesUseTheirApp() {
        #expect(ProcessReader.name(path: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper")
                == ("Claude", "/Applications/Claude.app"))
        #expect(ProcessReader.name(path: "/usr/sbin/cfprefsd") == ("cfprefsd", nil))
        #expect(GPUReader.pid(fromCreator: "pid 680, Safari") == 680)
        #expect(GPUReader.pid(fromCreator: "WindowServer") == nil)
    }

    @MainActor @Test func samplerTurnsSnapshotsIntoRatesAndApps() {
        let s = SystemSampler(source: FakeSystemSource([]))
        let mem = MemoryStats(used: 8, total: 16)
        s.ingest(SystemSnapshot(at: 0, ticks: .init(busy: 0, total: 0), memory: mem, pressureLevel: 1, cpuTemperature: 48, gpuUtilization: 30,
                                gpuClients: [GPUClient(pid: 7, name: "Game", gpuNanos: 0)],
                                processes: [ProcessSample(pid: 7, name: "Game", cpuNanos: 0, footprint: 300), ProcessSample(pid: 8, name: "Mail", cpuNanos: 0, footprint: 500)],
                                uptime: 100))
        #expect(s.latest?.cpuPercent == nil && !s.hasRates)
        #expect(s.memoryApps.map(\.name) == ["Mail", "Game"])
        #expect(s.gpuHistory.values == [30] && s.memoryHistory.values == [50] && s.cpuHistory.values.isEmpty)
        s.ingest(SystemSnapshot(at: 2_000_000_000, ticks: .init(busy: 25, total: 100), memory: mem, pressureLevel: 2, gpuUtilization: 40,
                                gpuClients: [GPUClient(pid: 7, name: "Game", gpuNanos: 600_000_000)],
                                processes: [ProcessSample(pid: 7, name: "Game", cpuNanos: 1_000_000_000, footprint: 300),
                                            ProcessSample(pid: 8, name: "Mail", cpuNanos: 200_000_000, footprint: 500)]))
        #expect(s.latest?.cpuPercent == 25 && s.latest?.pressure == .warning && s.latest?.cpuTemperature == nil)
        #expect(s.cpuApps == [AppUsage(name: "Game", value: 50), AppUsage(name: "Mail", value: 10)])
        #expect(s.gpuApps == [AppUsage(name: "Game", value: 30)])
        #expect(s.cpuHistory.values == [25])
    }

    @MainActor @Test func perAppGPUUnavailableIsNil() {
        let s = SystemSampler(source: FakeSystemSource([]))
        s.ingest(SystemSnapshot(at: 0)); s.ingest(SystemSnapshot(at: 1_000))
        #expect(s.gpuApps == nil)
    }

    @MainActor @Test func releaseStopsAndForgets() async {
        let s = SystemSampler(interval: .milliseconds(5), source: FakeSystemSource([SystemSnapshot(at: 0, gpuUtilization: 10)]))
        s.hold("view")
        for _ in 0..<100 where s.latest == nil { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(s.latest?.gpuPercent == 10 && !s.gpuHistory.values.isEmpty)
        s.release("view")
        #expect(!s.isSampling && s.gpuHistory.values.isEmpty)
    }

    @Test func liveSourceReadsThisMac() {
        let snap = LiveSystemSource().snapshot()
        #expect(snap.ticks != nil && snap.memory != nil && !snap.processes.isEmpty)
        #expect(snap.memory!.used <= snap.memory!.total)
    }
}
