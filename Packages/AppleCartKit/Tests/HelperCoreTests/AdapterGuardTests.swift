import Foundation
import Testing
@testable import HelperCore
import HelperProtocol

/// Records every SMC write; the fake refuses exactly what the real connection refuses.
final class FakeSMC: SMCWriting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var writes: [UInt8] = []
    private(set) var attempts: [UInt8] = []
    var value: UInt8 = 0
    var failWrites = false
    /// A Mac without the CHIE key.
    var missingKey = false

    func read(key: String) throws -> UInt8 {
        guard key == SMCWhitelist.adapterKey else { throw SMCError.refused }
        lock.lock(); defer { lock.unlock() }
        if missingKey { throw SMCError.keyMissing }
        return value
    }

    func write(key: String, value v: UInt8) throws {
        guard SMCWhitelist.allows(key: key, value: v) else { throw SMCError.refused }
        lock.lock(); defer { lock.unlock() }
        attempts.append(v)
        if missingKey { throw SMCError.keyMissing }
        if failWrites { throw SMCError.smc(0x84) }
        writes.append(v); value = v
    }
}

final class FakeTimers: @unchecked Sendable {
    final class Timer: LeaseTimer, @unchecked Sendable {
        let seconds: Int
        let fire: @Sendable () -> Void
        var cancelled = false
        init(seconds: Int, fire: @escaping @Sendable () -> Void) { self.seconds = seconds; self.fire = fire }
        func cancel() { cancelled = true }
    }
    var all: [Timer] = []
    var live: [Timer] { all.filter { !$0.cancelled } }
    var scheduler: LeaseScheduler {
        { [self] seconds, fire in let t = Timer(seconds: seconds, fire: fire); all.append(t); return t }
    }
}

final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
}

private func makeGuard() -> (AdapterGuard, FakeSMC, FakeTimers, Clock) {
    let smc = FakeSMC(), timers = FakeTimers(), clock = Clock()
    return (AdapterGuard(smc: smc, schedule: timers.scheduler, now: { clock.now }), smc, timers, clock)
}

@Suite struct AdapterGuardTests {
    @Test func startupWritesAdapterOn() {
        let (g, smc, _, _) = makeGuard()
        smc.value = 0x08 // a previous run died mid-cut
        g.start()
        #expect(smc.writes == [0x00])
        #expect(g.status().adapterEnabled)
    }

    @Test func cutAlwaysCarriesALeaseAndExpiryRestores() {
        let (g, smc, timers, _) = makeGuard()
        #expect(g.setAdapter(enabled: false, leaseSeconds: 90) == .ok)
        #expect(smc.writes == [0x08])
        #expect(timers.live.count == 1 && timers.live[0].seconds == 90)
        timers.live[0].fire()
        #expect(smc.writes == [0x08, 0x00])
        #expect(timers.live.isEmpty)
    }

    @Test func repeatedCutRenewsTheLease() {
        let (g, smc, timers, clock) = makeGuard()
        _ = g.setAdapter(enabled: false, leaseSeconds: 90)
        let first = timers.all[0]
        clock.now += 30
        _ = g.setAdapter(enabled: false, leaseSeconds: 90)
        #expect(first.cancelled)
        first.fire() // even if the old timer fires late, it must not restore under a renewed lease
        #expect(smc.writes == [0x08, 0x08])
        #expect(g.status().leaseRemaining == 90)
        timers.live[0].fire()
        #expect(smc.writes.last == 0x00)
    }

    @Test func leaseIsClamped() {
        let (g, _, timers, _) = makeGuard()
        _ = g.setAdapter(enabled: false, leaseSeconds: 100_000)
        #expect(timers.live[0].seconds == AdapterLease.range.upperBound)
        _ = g.setAdapter(enabled: false, leaseSeconds: -5)
        #expect(timers.live[0].seconds == AdapterLease.range.lowerBound)
    }

    @Test func enableCancelsLeaseAndWritesOn() {
        let (g, smc, timers, _) = makeGuard()
        _ = g.setAdapter(enabled: false, leaseSeconds: 90)
        #expect(g.setAdapter(enabled: true, leaseSeconds: 0) == .ok)
        #expect(smc.writes == [0x08, 0x00])
        #expect(timers.live.isEmpty)
        #expect(g.status().leaseRemaining == 0)
    }

    @Test func failedCutRestoresAndReports() {
        let (g, smc, timers, _) = makeGuard()
        smc.failWrites = true
        #expect(g.setAdapter(enabled: false, leaseSeconds: 90) == .smcFailed)
        #expect(smc.attempts == [0x08, 0x00]) // the cut, then an immediate restore attempt
        #expect(timers.live.count == 1 && timers.live[0].seconds == 5) // and a retry armed, not the lease
        smc.failWrites = false
        timers.live[0].fire()
        #expect(smc.writes == [0x00])
        #expect(timers.live.isEmpty)
    }

    @Test func failedRestoreBacksOffAndKeepsRetrying() {
        let (g, smc, timers, _) = makeGuard()
        smc.failWrites = true
        #expect(g.restore(reason: "test") == .smcFailed)
        var delays: [Int] = []
        for _ in 0..<6 { let t = timers.live[0]; delays.append(t.seconds); t.fire() }
        #expect(delays == [5, 15, 60, 300, 300, 300])
        smc.failWrites = false
        timers.live[0].fire()
        #expect(smc.writes == [0x00] && timers.live.isEmpty)
        smc.failWrites = true
        _ = g.restore(reason: "again")
        #expect(timers.live[0].seconds == 5) // backoff resets after a success
    }

    @Test func staleRetryCannotUndoAFreshCut() {
        let (g, smc, timers, _) = makeGuard()
        smc.failWrites = true
        _ = g.restore(reason: "test")
        let retry = timers.live[0]
        smc.failWrites = false
        #expect(g.setAdapter(enabled: false, leaseSeconds: 90) == .ok)
        retry.fire() // fires late, after the new cut
        #expect(smc.value == 0x08)
        #expect(smc.writes == [0x08])
    }

    @Test func sleepRestoresAndRefusesCutsUntilPowerOn() {
        let (g, smc, timers, _) = makeGuard()
        _ = g.setAdapter(enabled: false, leaseSeconds: 90)
        g.systemWillSleep()
        #expect(smc.value == 0x00 && timers.live.isEmpty)
        #expect(g.setAdapter(enabled: false, leaseSeconds: 90) == .sleeping)
        #expect(smc.writes == [0x08, 0x00])
        g.systemDidWake()
        #expect(g.setAdapter(enabled: false, leaseSeconds: 90) == .ok)
    }

    @Test func leaseEndsInWallClockTimeEvenIfTheTimerSlept() {
        let (g, smc, timers, clock) = makeGuard()
        _ = g.setAdapter(enabled: false, leaseSeconds: 90)
        clock.now += 600 // the Mac slept; the timer never fired
        #expect(timers.live.count == 1)
        g.systemDidWake()
        #expect(smc.value == 0x00 && timers.live.isEmpty)
        _ = g.setAdapter(enabled: false, leaseSeconds: 90)
        clock.now += 91
        #expect(g.status().adapterEnabled) // any status read also ends an overdue lease
        #expect(smc.writes == [0x08, 0x00, 0x08, 0x00])
    }

    @Test func noChieKeyIsUnsupportedWithoutARetryLoop() {
        let (g, smc, timers, _) = makeGuard()
        smc.missingKey = true
        g.start()
        #expect(timers.live.isEmpty)
        #expect(g.setAdapter(enabled: false, leaseSeconds: 90) == .unsupported)
        #expect(timers.live.isEmpty)
        let s = g.status()
        #expect(!s.supported && s.chie == -1)
        nonisolated(unsafe) var code = -1
        HelperService(adapter: g).status { _, _, _, _, c in code = c }
        #expect(code == HelperErrorCode.unsupported.rawValue)
    }

    @Test func brokenConnectionIsReopenedOnRetry() {
        let smc = FakeSMC(), timers = FakeTimers()
        nonisolated(unsafe) var opens = 0
        nonisolated(unsafe) var canOpen = false
        let g = AdapterGuard(connect: { opens += 1; guard canOpen else { throw SMCError.unavailable }; return smc }, schedule: timers.scheduler)
        g.start()
        #expect(opens == 1 && timers.live[0].seconds == 5)
        canOpen = true
        timers.live[0].fire()
        #expect(opens == 2 && smc.writes == [0x00])
        smc.failWrites = true
        _ = g.restore(reason: "io error")
        smc.failWrites = false
        timers.live[0].fire()
        #expect(opens == 3) // the connection is dropped after an I/O error and opened again
    }

    @Test func onlyChieWithZeroOrEightIsAllowed() {
        #expect(SMCWhitelist.allows(key: "CHIE", value: 0x00))
        #expect(SMCWhitelist.allows(key: "CHIE", value: 0x08))
        for v: UInt8 in [0x01, 0x02, 0x04, 0x07, 0x09, 0x80, 0xFF] { #expect(!SMCWhitelist.allows(key: "CHIE", value: v)) }
        for k in ["CH0B", "CH0C", "CHTE", "F0Md", "chie", "CHIE ", ""] { #expect(!SMCWhitelist.allows(key: k, value: 0x00)) }
        #expect(throws: SMCError.refused) { try FakeSMC().write(key: "CH0B", value: 0x02) }
    }

    @Test func invalidationAndInterruptionRestore() {
        let (g, smc, timers, _) = makeGuard()
        let conn = NSXPCConnection(serviceName: "test.invalid")
        HelperListenerDelegate.attachRestore(to: conn, adapter: g)
        _ = g.setAdapter(enabled: false, leaseSeconds: 90)
        conn.invalidationHandler?()
        #expect(smc.writes == [0x08, 0x00])
        #expect(timers.live.isEmpty)
        _ = g.setAdapter(enabled: false, leaseSeconds: 90)
        conn.interruptionHandler?()
        #expect(smc.writes.last == 0x00)
    }

    @Test func sleepMessagesMapToRestoreAndWake() {
        #expect(PowerMessage.restoresAdapter(PowerMessage.systemWillSleep))
        #expect(!PowerMessage.restoresAdapter(PowerMessage.systemHasPoweredOn))
        #expect(PowerMessage.endsSleep(PowerMessage.systemHasPoweredOn) && PowerMessage.endsSleep(PowerMessage.systemWillPowerOn))
        #expect(!PowerMessage.endsSleep(PowerMessage.systemWillSleep))
        #expect(PowerMessage.needsAck(PowerMessage.canSystemSleep) && PowerMessage.needsAck(PowerMessage.systemWillSleep))
    }

    @Test func serviceRepliesWithPlainCodes() {
        let (g, smc, _, _) = makeGuard()
        let s = HelperService(adapter: g)
        nonisolated(unsafe) var code = -1
        s.setAdapter(enabled: false, leaseSeconds: 90) { code = $0 }
        #expect(code == 0 && smc.value == 0x08)
        s.resetAll { code = $0 }
        #expect(code == 0 && smc.value == 0x00)
        nonisolated(unsafe) var v = 0
        s.version { v = $0 }
        #expect(v == HelperIdentity.version)
    }
}

struct FakeChecker: CodeChecking {
    let allowed: Set<pid_t>
    func process(_ pid: pid_t, satisfies requirement: String) -> Bool {
        requirement.contains("identifier \"app.rarecreatures.applecart\"") && allowed.contains(pid)
    }
}

@Suite struct ClientGateTests {
    @Test func acceptsOnlyProcessesMeetingTheRequirement() {
        let gate = ClientGate(teamID: "KTV2G3Z883", checker: FakeChecker(allowed: [42]))
        #expect(gate.accepts(pid: 42))
        #expect(!gate.accepts(pid: 43))
        #expect(!gate.accepts(pid: 0))
    }

    @Test func missingOrBadTeamIDRejectsEveryone() {
        for team in [nil, "", "$(AC_TEAM_ID)", "ktv2g3z883", "KTV2G3Z88"] as [String?] {
            let gate = ClientGate(teamID: team, checker: FakeChecker(allowed: [42]))
            #expect(gate.requirement == nil)
            #expect(!gate.accepts(pid: 42))
        }
    }
}
