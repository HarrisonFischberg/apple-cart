import Foundation
import Testing
@testable import Core

@MainActor
private final class FakeAssertions: PowerAssertions {
    var live: Set<UInt32> = []
    var lastDisplayOn: Bool?
    var refuse = false
    private var next: UInt32 = 1
    func create(keepDisplayOn: Bool, reason: String) -> UInt32? {
        guard !refuse else { return nil }
        lastDisplayOn = keepDisplayOn
        defer { next += 1 }
        live.insert(next)
        return next
    }
    func release(_ token: UInt32) { live.remove(token) }
}

private func battery(percent: Int, plugged: Bool) -> BatteryReading {
    BatteryReading(properties: ["CurrentCapacity": percent, "ExternalConnected": plugged ? 1 : 0])!
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n - 1 }
}

@MainActor
@Suite struct KeepAwakeTests {
    @Test func assertionExistsOnlyWhileActive() {
        let fake = FakeAssertions()
        let k = KeepAwake(assertions: fake)
        #expect(fake.live.isEmpty)
        k.start(.init(keepDisplayOn: true))
        #expect(fake.live.count == 1 && fake.lastDisplayOn == true && k.isActive)
        k.stop()
        #expect(fake.live.isEmpty && !k.isActive)
    }

    @Test func displayOptionCanChangeMidSession() {
        let fake = FakeAssertions()
        let k = KeepAwake(assertions: fake)
        k.setKeepDisplayOn(true) // no session: nothing happens
        #expect(fake.live.isEmpty)
        k.start(.init(duration: 3600))
        k.setKeepDisplayOn(true)
        #expect(fake.live.count == 1 && fake.lastDisplayOn == true && k.options?.keepDisplayOn == true && k.options?.duration == 3600)
        k.stop()
        #expect(fake.live.isEmpty)
    }

    @Test func startingAgainReplacesNotStacks() {
        let fake = FakeAssertions()
        let k = KeepAwake(assertions: fake)
        k.start(.init()); k.start(.init(duration: 3600))
        #expect(fake.live.count == 1)
    }

    @Test func timerEndsTheSessionAndReleases() async {
        let fake = FakeAssertions()
        let k = KeepAwake(assertions: fake)
        k.start(.init(duration: 0.05))
        try? await Task.sleep(for: .milliseconds(300))
        #expect(!k.isActive && fake.live.isEmpty && k.lastStopReason == "Timer finished")
    }

    @Test func lowBatteryEndsItOnlyWhenUnplugged() async {
        let fake = FakeAssertions()
        let k = KeepAwake(assertions: fake, readBattery: { battery(percent: 15, plugged: true) }, checkEvery: .milliseconds(10))
        k.start(.init(stopBelowPercent: 20))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(k.isActive)
        k.stop()

        let k2 = KeepAwake(assertions: fake, readBattery: { battery(percent: 15, plugged: false) }, checkEvery: .milliseconds(10))
        k2.start(.init(stopBelowPercent: 20))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!k2.isActive && fake.live.isEmpty && k2.lastStopReason == "Battery reached 20%")
    }

    private func run(_ o: KeepAwakeOptions, limit: Int = 100, _ readings: [BatteryReading]) async -> (KeepAwake, FakeAssertions) {
        let fake = FakeAssertions()
        let box = Counter()
        let k = KeepAwake(assertions: fake, readBattery: { readings[min(box.next(), readings.count - 1)] },
                          checkEvery: .milliseconds(5), chargeLimit: { limit })
        k.start(o)
        // Busy main actor in parallel suites can delay checks: wait until it ends or give up after 2 s.
        for _ in 0..<80 where k.isActive { try? await Task.sleep(for: .milliseconds(25)) }
        return (k, fake)
    }

    @Test func endsWhenTheChargerIsUnplugged() async {
        let (k, fake) = await run(.init(stopOnUnplug: true), [battery(percent: 50, plugged: true), battery(percent: 50, plugged: false)])
        #expect(!k.isActive && fake.live.isEmpty && k.lastStopReason == "Charger unplugged")
        // Started on battery: never saw a charger, so the option waits instead of ending at once.
        let (k2, _) = await run(.init(stopOnUnplug: true), [battery(percent: 50, plugged: false)])
        #expect(k2.isActive); k2.stop()
    }

    @Test func heldChargeLimitStillCountsAsPlugged() async {
        // With the charger cut macOS reports battery power, but adapter details stay.
        let held = BatteryReading(properties: ["CurrentCapacity": 80, "ExternalConnected": 0, "AdapterDetails": ["Watts": 96]])!
        let (k, _) = await run(.init(stopOnUnplug: true), [battery(percent: 80, plugged: true), held])
        #expect(k.isActive); k.stop()
        let (k2, _) = await run(.init(stopAtChargeLimit: true), limit: 80, [held])
        #expect(!k2.isActive && k2.lastStopReason == "Charge limit reached")
        let (k3, _) = await run(.init(stopBelowPercent: 90), [held])
        #expect(k3.isActive); k3.stop()
    }

    @Test func levelRangeUpTo95OnlyOnBattery() async {
        let (k, _) = await run(.init(stopBelowPercent: 95), [battery(percent: 90, plugged: false)])
        #expect(!k.isActive && k.lastStopReason == "Battery reached 95%")
        let (k2, _) = await run(.init(stopBelowPercent: 95), [battery(percent: 90, plugged: true)])
        #expect(k2.isActive); k2.stop()
    }

    @Test func endsAtTheChargeLimitWhilePlugged() async {
        let (k, _) = await run(.init(stopAtChargeLimit: true), limit: 80, [battery(percent: 79, plugged: true), battery(percent: 80, plugged: true)])
        #expect(!k.isActive && k.lastStopReason == "Charge limit reached")
        let (k2, _) = await run(.init(stopAtChargeLimit: true), limit: 80, [battery(percent: 90, plugged: false)])
        #expect(k2.isActive); k2.stop()
        let (k3, _) = await run(.init(stopAtChargeLimit: true), limit: 100, [battery(percent: 99, plugged: true)])
        #expect(k3.isActive); k3.stop()
        let (k4, _) = await run(.init(stopAtChargeLimit: true), limit: 100, [battery(percent: 100, plugged: true)])
        #expect(!k4.isActive)
    }

    @Test func customDurationMathAndStoredOptions() throws {
        #expect(KeepAwakeOptions.customSeconds(45, hours: false) == 2700)
        #expect(KeepAwakeOptions.customSeconds(3, hours: true) == 10800)
        #expect(KeepAwakeOptions.customSeconds(0, hours: false) == nil && KeepAwakeOptions.customSeconds(-5, hours: true) == nil)
        #expect(KeepAwakeOptions.customSeconds(9999, hours: true) == KeepAwakeOptions.maxCustomSeconds)
        let d = try #require(UserDefaults(suiteName: "keepawake-test-" + UUID().uuidString))
        #expect(KeepAwakeOptions.stored(duration: 60, defaults: d) == .init(duration: 60))
        d.set(true, forKey: "keepAwake.useLevel"); d.set(99, forKey: "keepAwake.level")
        d.set(true, forKey: "keepAwake.endOnUnplug"); d.set(true, forKey: "keepAwake.untilLimit")
        #expect(KeepAwakeOptions.stored(duration: nil, defaults: d) == .init(stopBelowPercent: 95, stopOnUnplug: true, stopAtChargeLimit: true))
    }

    @Test func replacingASessionDropsTheOldConditions() async {
        let fake = FakeAssertions()
        let k = KeepAwake(assertions: fake, readBattery: { battery(percent: 50, plugged: true) }, checkEvery: .milliseconds(5), chargeLimit: { 40 })
        k.start(.init(stopAtChargeLimit: true)); k.start(.init(keepDisplayOn: true))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(k.isActive && fake.live.count == 1 && k.options == .init(keepDisplayOn: true))
        k.stop()
    }

    @Test func refusedAssertionIsReportedNotHidden() {
        let fake = FakeAssertions(); fake.refuse = true
        let k = KeepAwake(assertions: fake)
        k.start(.init())
        #expect(k.failed && !k.isActive)
    }

    @Test func realAssertionShowsInPmsetOnlyWhileActive() throws {
        func pmset() throws -> String {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["-g", "assertions"]
            let pipe = Pipe(); p.standardOutput = pipe
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            // Only this process's lines: a running Apple Cart app holds the same assertion name.
            let mine = "pid \(ProcessInfo.processInfo.processIdentifier)("
            return String(decoding: data, as: UTF8.self).split(separator: "\n").filter { $0.contains(mine) }.joined(separator: "\n")
        }
        let k = KeepAwake()
        #expect(!(try pmset()).contains(KeepAwake.assertionName))
        k.start(.init())
        #expect((try pmset()).contains(KeepAwake.assertionName))
        k.stop()
        #expect(!(try pmset()).contains(KeepAwake.assertionName))
    }
}

@MainActor
@Suite struct SystemMonitorTests {
    @Test func cpuPercentFromTickDeltas() {
        #expect(CPUTicks.percent(from: .init(busy: 100, total: 400), to: .init(busy: 160, total: 500)) == 60)
        #expect(CPUTicks.percent(from: .init(busy: 1, total: 5), to: .init(busy: 1, total: 5)) == nil)
    }

    @Test func realReadingsAreSane() {
        #expect(SystemReader.cpuTicks() != nil)
        let m = SystemReader.memory()
        #expect(m != nil && m!.used > 0 && m!.used <= m!.total)
    }

    @Test func samplerRunsOnlyWhileHeld() {
        let s = SystemSampler(interval: .milliseconds(5))
        #expect(!s.isSampling)
        s.hold("view"); #expect(s.isSampling)
        s.release("view"); #expect(!s.isSampling)
    }
}
