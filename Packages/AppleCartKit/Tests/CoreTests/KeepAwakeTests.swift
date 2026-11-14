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
            return String(decoding: data, as: UTF8.self)
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
