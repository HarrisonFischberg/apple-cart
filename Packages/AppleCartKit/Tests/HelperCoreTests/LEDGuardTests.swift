import Foundation
import Testing
@testable import HelperCore
import HelperProtocol

/// An SMC with the ACLC key Mac17,2 reports (ui8, 4 = orange). Records every write; refuses what the real connection refuses.
final class FakeLEDSMC: LEDSMC, @unchecked Sendable {
    private let lock = NSLock()
    var type: SMCKeyType? = .uint8
    var value: UInt8 = 4
    private(set) var writes: [UInt8] = []
    var failWrites = false
    var failReads = false
    /// The SMC takes the write and keeps the old value.
    var ignoreWrites = false

    func ledKeyType(_ key: String) throws -> SMCKeyType {
        guard LEDWhitelist.allowsRead(key: key) else { throw SMCError.refused }
        lock.lock(); defer { lock.unlock() }
        if failReads { throw SMCError.io(-536870212) }
        guard let type else { throw SMCError.keyMissing }
        return type
    }

    func ledRead(_ key: String) throws -> [UInt8] {
        guard LEDWhitelist.allowsRead(key: key) else { throw SMCError.refused }
        lock.lock(); defer { lock.unlock() }
        if failReads { throw SMCError.io(-536870212) }
        guard type != nil else { throw SMCError.keyMissing }
        return [value]
    }

    func ledWrite(_ key: String, _ bytes: [UInt8]) throws {
        guard LEDWhitelist.allowsWrite(key: key, bytes: bytes) else { throw SMCError.refused }
        lock.lock(); defer { lock.unlock() }
        guard type != nil else { throw SMCError.keyMissing }
        if failWrites { throw SMCError.smc(0x82) }
        writes.append(bytes[0])
        if !ignoreWrites { value = bytes[0] }
    }
}

private func makeLEDGuard(_ smc: FakeLEDSMC = FakeLEDSMC()) -> (LEDGuard, FakeLEDSMC, FakeTimers, Clock) {
    let timers = FakeTimers(), clock = Clock()
    return (LEDGuard(smc: smc, schedule: timers.scheduler, now: { clock.now }, monotonic: { clock.mono }, settle: {}), smc, timers, clock)
}

private extension FakeTimers {
    var tick: Timer? { live.first { $0.seconds == LEDGuard.tickSeconds } }
    var lease: Timer? { live.first { $0.seconds != LEDGuard.tickSeconds } }
}

@Suite struct LEDGuardTests {
    @Test func greenIsWrittenUnderALeaseAndReadBack() {
        let (g, smc, timers, _) = makeLEDGuard()
        #expect(g.setLED(color: 3, leaseSeconds: 90) == .ok)
        #expect(smc.writes == [3] && smc.value == 3)
        #expect(timers.lease?.seconds == 90 && timers.tick != nil)
        let s = g.status()
        #expect(s.supported && s.raw == 3 && s.wanted == 3 && s.leaseRemaining == 90 && s.code == .ok)
    }

    @Test func settlesBeforeReadingBack() {
        let smc = FakeLEDSMC(), timers = FakeTimers()
        nonisolated(unsafe) var settles = 0
        let g = LEDGuard(smc: smc, schedule: timers.scheduler, settle: { settles += 1 })
        #expect(g.setLED(color: 3, leaseSeconds: 90) == .ok && settles == 1)
        #expect(g.setLED(color: 3, leaseSeconds: 90) == .ok && settles == 1) // already green: no write, no wait
        #expect(LEDGuard.settleSeconds >= 0.5) // the probe saw the old value for about 0.5 s
    }

    @Test func aColourThatDoesNotTakeIsNotAppliedAndNothingIsLeftArmed() {
        let (g, smc, timers, _) = makeLEDGuard()
        smc.ignoreWrites = true
        #expect(g.setLED(color: 3, leaseSeconds: 90) == .notApplied)
        #expect(smc.writes == [3] && smc.value == 4) // the key never changed, so restoring writes nothing
        #expect(timers.live.isEmpty && g.status().wanted == 0)
    }

    @Test func leaseExpiryRestoresTheOriginalAndStopsTheTick() {
        let (g, smc, timers, _) = makeLEDGuard()
        _ = g.setLED(color: 3, leaseSeconds: 100_000)
        #expect(timers.lease?.seconds == AdapterLease.range.upperBound)
        _ = g.setLED(color: 3, leaseSeconds: 1)
        #expect(timers.lease?.seconds == AdapterLease.range.lowerBound)
        let tick = timers.tick
        timers.lease?.fire()
        #expect(smc.value == 4 && smc.writes == [3, 4] && timers.live.isEmpty)
        smc.value = 4
        tick?.fire() // a stale tick does nothing
        #expect(smc.writes == [3, 4])
    }

    @Test func leaseEndsOnWallClockOrUptime() {
        let (g, smc, _, clock) = makeLEDGuard()
        _ = g.setLED(color: 3, leaseSeconds: 30)
        clock.now -= 3600; clock.mono += 31
        #expect(g.status().wanted == 0 && smc.value == 4)
        _ = g.setLED(color: 3, leaseSeconds: 30)
        clock.advance(600)
        g.systemDidWake()
        #expect(smc.value == 4)
    }

    @Test func tickCorrectsAMacOSOverwriteUntilRestored() {
        let logs = LogBox()
        let smc = FakeLEDSMC(), timers = FakeTimers(), clock = Clock()
        let g = LEDGuard(smc: smc, schedule: timers.scheduler, now: { clock.now }, monotonic: { clock.mono }, log: { logs.add($0) }, settle: {})
        _ = g.setLED(color: 3, leaseSeconds: 90)
        timers.tick?.fire()
        #expect(smc.writes == [3]) // unchanged: nothing written, tick re-armed
        smc.value = 4 // adapter replug: macOS writes orange
        timers.tick?.fire()
        #expect(smc.value == 3 && smc.writes == [3, 3])
        smc.value = 4
        clock.advance(1)
        timers.tick?.fire()
        #expect(smc.writes == [3, 3, 3])
        #expect(logs.lines.filter { $0.contains("writing 3 again") }.count == 1) // at most one log per 10 s
        clock.advance(10)
        smc.value = 4
        timers.tick?.fire()
        #expect(logs.lines.filter { $0.contains("writing 3 again") }.count == 2)
        #expect(timers.live.filter { $0.seconds == LEDGuard.tickSeconds }.count == 1) // one tick, never stacked
        #expect(g.restore(reason: "test") == .ok)
        #expect(smc.value == 4 && timers.live.isEmpty) // macOS's latest value back, tick gone
        let before = smc.writes
        smc.value = 4
        for t in timers.all { t.fire() } // even stale fires write nothing after a restore
        #expect(smc.writes == before)
    }

    @Test func restoreWritesBackTheValueMacOSLastSet() {
        let (g, smc, timers, _) = makeLEDGuard()
        smc.value = 3 // green at the first arm
        _ = g.setLED(color: 4, leaseSeconds: 90)
        #expect(smc.value == 4)
        _ = g.setLED(color: 4, leaseSeconds: 90) // renewal: must not capture our own 4 as the original
        _ = g.restore(reason: "test")
        #expect(smc.value == 3)
        smc.value = 4
        _ = g.setLED(color: 3, leaseSeconds: 90)
        smc.value = 4 // macOS changes its mind while we force green
        timers.tick?.fire()
        _ = g.restore(reason: "test")
        #expect(smc.value == 4) // the newer macOS value, not a stale one
    }

    @Test func sleepRestoresAndRefusesUntilPowerOn() {
        let (g, smc, timers, clock) = makeLEDGuard()
        _ = g.setLED(color: 3, leaseSeconds: 90)
        g.systemWillSleep()
        #expect(smc.value == 4 && timers.live.isEmpty)
        #expect(g.setLED(color: 3, leaseSeconds: 90) == .sleeping)
        g.systemDidWake()
        #expect(g.setLED(color: 3, leaseSeconds: 90) == .ok)
        g.systemWillSleep()
        clock.advance(61)
        #expect(g.setLED(color: 3, leaseSeconds: 90) == .ok)
    }

    @Test func helperStartWritesNothing() {
        let (g, smc, timers, _) = makeLEDGuard()
        smc.value = 3 // whatever a crashed run left: unknown original, so nothing is written (macOS rewrites on its next event)
        g.start()
        #expect(smc.writes.isEmpty && timers.live.isEmpty)
        #expect(g.restore(reason: "reset led") == .ok && smc.writes.isEmpty) // resetLED with nothing set
    }

    @Test func signalAndConnectionEndRestore() {
        let (g, smc, timers, _) = makeLEDGuard()
        _ = g.setLED(color: 3, leaseSeconds: 90)
        #expect(g.restore(reason: "signal 15") == .ok && smc.value == 4 && timers.live.isEmpty) // what main.swift calls
        _ = g.setLED(color: 3, leaseSeconds: 90)
        let adapter = AdapterGuard(smc: FakeSMC(), schedule: FakeTimers().scheduler)
        let conn = NSXPCConnection(serviceName: "test.invalid")
        HelperListenerDelegate.attachRestore(to: conn, adapter: adapter, led: g)
        conn.interruptionHandler?()
        #expect(smc.value == 4 && timers.live.isEmpty)
    }

    @Test func failedRestoreRetriesWithBackoff() {
        let (g, smc, timers, _) = makeLEDGuard()
        _ = g.setLED(color: 3, leaseSeconds: 90)
        smc.failWrites = true
        #expect(g.restore(reason: "test") == .smcFailed)
        #expect(timers.tick == nil) // correcting stops at once, whatever the write does
        var delays: [Int] = []
        for _ in 0..<4 { let t = timers.live[0]; delays.append(t.seconds); t.fire() }
        #expect(delays == [5, 15, 60, 60])
        smc.failWrites = false
        timers.live[0].fire()
        #expect(smc.value == 4 && timers.live.isEmpty)
    }

    @Test func failedWriteRestores() {
        let (g, smc, timers, _) = makeLEDGuard()
        smc.failWrites = true
        #expect(g.setLED(color: 3, leaseSeconds: 90) == .smcFailed)
        #expect(timers.tick == nil && smc.value == 4)
        #expect(timers.live.isEmpty) // the key still shows macOS's value: nothing to retry
    }

    @Test func unsupportedKeyWritesNothing() {
        for type: SMCKeyType? in [nil, SMCKeyType("ui16", 2), .float] {
            let smc = FakeLEDSMC()
            smc.type = type
            let (g, _, timers, _) = makeLEDGuard(smc)
            #expect(g.setLED(color: 3, leaseSeconds: 90) == .unsupported)
            #expect(smc.writes.isEmpty && timers.live.isEmpty)
            #expect(!g.status().supported && g.status().code == .unsupported)
        }
    }

    @Test func otherColoursAreRefusedWithNothingWritten() {
        let (g, smc, timers, _) = makeLEDGuard()
        for c in [0, 1, 2, 5, 255, -1, 259] { #expect(g.setLED(color: c, leaseSeconds: 90) == .refused) }
        #expect(smc.writes.isEmpty && timers.live.isEmpty)
    }

    @Test func aSecondSetReplacesTheFirst() {
        let (g, smc, timers, _) = makeLEDGuard()
        _ = g.setLED(color: 3, leaseSeconds: 90)
        let firstLease = timers.lease, firstTick = timers.tick
        #expect(g.setLED(color: 4, leaseSeconds: 60) == .ok)
        #expect(firstLease?.cancelled == true && firstTick?.cancelled == true)
        #expect(timers.live.count == 2 && timers.lease?.seconds == 60)
        #expect(smc.value == 4 && g.status().wanted == 4)
        firstLease?.fire() // superseded: does not end the new lease
        #expect(g.status().wanted == 4)
    }

    @Test func whitelistAllowsOnlyACLCWithThreeOrFour() {
        #expect(LEDWhitelist.allowsWrite(key: "ACLC", bytes: [3]) && LEDWhitelist.allowsWrite(key: "ACLC", bytes: [4]))
        for b: [UInt8] in [[0], [1], [2], [5], [255], [3, 0], []] { #expect(!LEDWhitelist.allowsWrite(key: "ACLC", bytes: b)) }
        for k in ["CHIE", "F0md", "ACLc", "ACLC ", "", "ACLD"] {
            #expect(!LEDWhitelist.allowsWrite(key: k, bytes: [3]))
            #expect(!LEDWhitelist.allowsRead(key: k))
        }
        #expect(LEDWhitelist.allowsRead(key: "ACLC"))
        #expect(!FanWhitelist.allowsWrite(key: "ACLC", bytes: [3]) && !FanWhitelist.allowsRead(key: "ACLC"))
        #expect(!SMCWhitelist.allows(key: "ACLC", value: 3))
    }

    @Test func serviceCoversTheLight() {
        let (g, smc, _, _) = makeLEDGuard()
        let service = HelperService(adapter: AdapterGuard(smc: FakeSMC(), schedule: FakeTimers().scheduler), led: g)
        nonisolated(unsafe) var code = -1
        service.setLED(color: 3, leaseSeconds: 30) { code = $0 }
        #expect(code == 0 && smc.value == 3)
        nonisolated(unsafe) var reply: (Bool, Int, Int) = (false, 0, 0)
        service.ledStatus { sup, raw, wanted, _, _ in reply = (sup, raw, wanted) }
        #expect(reply == (true, 3, 3))
        service.resetLED { code = $0 }
        #expect(code == 0 && smc.value == 4)
        service.setLED(color: 7, leaseSeconds: 30) { code = $0 }
        #expect(code == HelperErrorCode.refused.rawValue && smc.value == 4)
        nonisolated(unsafe) var none = -1
        HelperService(adapter: AdapterGuard(smc: FakeSMC(), schedule: FakeTimers().scheduler)).setLED(color: 3, leaseSeconds: 30) { none = $0 }
        #expect(none == HelperErrorCode.unsupported.rawValue)
    }

    @Test func transientReadErrorIsNotUnsupported() {
        let (g, smc, _, _) = makeLEDGuard()
        smc.failReads = true
        let s = g.status()
        #expect(s.supported && s.code == .smcFailed && s.raw == -1)
        smc.failReads = false
        #expect(g.status().code == .ok)
    }
}

final class LogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    var lines: [String] { lock.withLock { _lines } }
    func add(_ s: String) { lock.withLock { _lines.append(s) } }
}
