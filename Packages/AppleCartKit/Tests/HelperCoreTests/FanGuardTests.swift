import Foundation
import Testing
@testable import HelperCore
import HelperProtocol

/// An SMC with the fan keys Mac17,2 reports (one fan, 2317-6550 rpm, no Ftst). Records every write; refuses what the
/// real connection refuses.
final class FakeFanSMC: FanSMC, @unchecked Sendable {
    private let lock = NSLock()
    var keys: [String: (type: SMCKeyType, bytes: [UInt8])]
    private(set) var writes: [String] = []
    var failWrites = false
    var failReads = false
    /// The SMC takes mode writes but keeps reading the old value.
    var ignoreModeWrites = false
    /// Writes to this one key throw (half-success sequences).
    var failWriteKey: String?
    /// The target key reads back this rpm whatever was written.
    var targetReadsBack: Double?

    init(fans: Int = 1, unlock: Bool = false) {
        keys = ["FNum": (.uint8, [UInt8(fans)])]
        for i in 0..<fans {
            keys["F\(i)md"] = (.uint8, [0])
            keys["F\(i)Tg"] = (.float, FanBytes.bytes(0))
            keys["F\(i)Ac"] = (.float, FanBytes.bytes(0))
            keys["F\(i)Mn"] = (.float, [0x00, 0xd0, 0x10, 0x45]) // the bytes read on Mac17,2
            keys["F\(i)Mx"] = (.float, [0x00, 0xb0, 0xcc, 0x45])
        }
        if unlock { keys["Ftst"] = (.uint8, [0]) }
    }

    func value(_ key: String) -> [UInt8]? { lock.lock(); defer { lock.unlock() }; return keys[key]?.bytes }

    func fanKeyType(_ key: String) throws -> SMCKeyType {
        guard FanWhitelist.allowsRead(key: key) else { throw SMCError.refused }
        lock.lock(); defer { lock.unlock() }
        if failReads { throw SMCError.io(-536870212) }
        guard let k = keys[key] else { throw SMCError.keyMissing }
        return k.type
    }

    func fanRead(_ key: String) throws -> [UInt8] {
        guard FanWhitelist.allowsRead(key: key) else { throw SMCError.refused }
        lock.lock(); defer { lock.unlock() }
        if failReads { throw SMCError.io(-536870212) }
        guard let k = keys[key] else { throw SMCError.keyMissing }
        if let t = targetReadsBack, key.hasSuffix("Tg") { return FanBytes.bytes(t) }
        return k.bytes
    }

    func fanWrite(_ key: String, _ bytes: [UInt8]) throws {
        guard FanWhitelist.allowsWrite(key: key, bytes: bytes) else { throw SMCError.refused }
        lock.lock(); defer { lock.unlock() }
        guard let k = keys[key] else { throw SMCError.keyMissing }
        guard k.type.size == bytes.count else { throw SMCError.typeMismatch }
        if failWrites || key == failWriteKey { throw SMCError.smc(0x82) }
        let shown = k.type == .float ? "\(Int(FanBytes.float(bytes) ?? -1))" : "\(bytes[0])"
        writes.append("\(key)=\(shown)")
        if ignoreModeWrites && key.hasSuffix("md") { return }
        keys[key] = (k.type, bytes)
    }
}

private func makeFanGuard(_ smc: FakeFanSMC = FakeFanSMC()) -> (FanGuard, FakeFanSMC, FakeTimers, Clock) {
    let timers = FakeTimers(), clock = Clock()
    return (FanGuard(smc: smc, schedule: timers.scheduler, now: { clock.now }, monotonic: { clock.mono }), smc, timers, clock)
}

@Suite struct FanGuardTests {
    @Test func manualWritesModeThenClampedTargetUnderALease() {
        let (g, smc, timers, _) = makeFanGuard()
        #expect(g.setFan(rpm: 3500, leaseSeconds: 90) == .ok)
        #expect(smc.writes == ["F0Tg=3500", "F0md=1"]) // target first, never manual at a stale target
        #expect(timers.live.count == 1 && timers.live[0].seconds == 90)
        let s = g.status()
        #expect(s.manual && s.targetRPM == 3500 && s.minimumRPM == 2317 && s.maximumRPM == 6550 && s.count == 1)
    }

    @Test func rpmIsClampedIntoTheFansOwnRange() {
        let (g, smc, _, _) = makeFanGuard()
        _ = g.setFan(rpm: 1000, leaseSeconds: 90)
        #expect(smc.writes.first == "F0Tg=2317") // never below the minimum running speed
        _ = g.setFan(rpm: 99_999, leaseSeconds: 90)
        #expect(smc.writes.last(where: { $0.hasPrefix("F0Tg") }) == "F0Tg=6550") // never above the maximum
    }

    @Test func zeroRpmMeansSystem() {
        let (g, smc, timers, _) = makeFanGuard()
        _ = g.setFan(rpm: 3000, leaseSeconds: 90)
        #expect(g.setFan(rpm: 0, leaseSeconds: 90) == .ok)
        #expect(smc.writes.last == "F0md=0" && timers.live.isEmpty)
    }

    @Test func leaseIsClampedAndExpiryRestores() {
        let (g, smc, timers, _) = makeFanGuard()
        _ = g.setFan(rpm: 3000, leaseSeconds: 100_000)
        #expect(timers.live[0].seconds == AdapterLease.range.upperBound)
        _ = g.setFan(rpm: 3000, leaseSeconds: 1)
        #expect(timers.live[0].seconds == AdapterLease.range.lowerBound)
        timers.live[0].fire()
        #expect(smc.value("F0md") == [0] && timers.live.isEmpty)
        #expect(!g.status().manual)
    }

    @Test func leaseEndsOnWallClockOrUptime() {
        let (g, smc, _, clock) = makeFanGuard()
        _ = g.setFan(rpm: 3000, leaseSeconds: 30)
        clock.now -= 3600; clock.mono += 31 // clock set back while 31 real seconds pass
        #expect(!g.status().manual)
        #expect(smc.value("F0md") == [0])
        _ = g.setFan(rpm: 3000, leaseSeconds: 30)
        clock.advance(600) // slept, timer never fired
        g.systemDidWake()
        #expect(smc.value("F0md") == [0])
    }

    @Test func sleepRestoresAndRefusesUntilPowerOn() {
        let (g, smc, timers, clock) = makeFanGuard()
        _ = g.setFan(rpm: 3000, leaseSeconds: 90)
        g.systemWillSleep()
        #expect(smc.value("F0md") == [0] && timers.live.isEmpty)
        #expect(g.setFan(rpm: 3000, leaseSeconds: 90) == .sleeping)
        g.systemDidWake()
        #expect(g.setFan(rpm: 3000, leaseSeconds: 90) == .ok)
        g.systemWillSleep()
        clock.advance(61) // aborted sleep: no power-on message
        #expect(g.setFan(rpm: 3000, leaseSeconds: 90) == .ok)
    }

    @Test func startRestoresALeftoverManualModeButWritesNothingOtherwise() {
        let (g, smc, _, _) = makeFanGuard()
        g.start()
        #expect(smc.writes.isEmpty) // already system: no SMC write at all
        let (g2, smc2, _, _) = makeFanGuard()
        smc2.keys["F0md"] = (.uint8, [1]) // a previous run died in manual mode
        g2.start()
        #expect(smc2.writes == ["F0md=0"])
        _ = g
    }

    @Test func failedRestoreRetriesCappedAtAMinute() {
        let (g, smc, timers, _) = makeFanGuard()
        _ = g.setFan(rpm: 3000, leaseSeconds: 90)
        smc.failWrites = true
        #expect(g.restore(reason: "test") == .smcFailed)
        var delays: [Int] = []
        for _ in 0..<5 { let t = timers.live[0]; delays.append(t.seconds); t.fire() }
        #expect(delays == [5, 15, 60, 60, 60])
        smc.failWrites = false
        timers.live[0].fire()
        #expect(smc.value("F0md") == [0] && timers.live.isEmpty)
    }

    @Test func staleRetryCannotUndoAFreshManualSetting() {
        let (g, smc, timers, _) = makeFanGuard()
        smc.keys["F0md"] = (.uint8, [1])
        smc.failWrites = true
        g.start()
        let retry = timers.live[0]
        smc.failWrites = false
        #expect(g.setFan(rpm: 4000, leaseSeconds: 90) == .ok)
        retry.fire()
        #expect(smc.value("F0md") == [1])
    }

    @Test func failedManualWriteRestores() {
        let (g, smc, timers, _) = makeFanGuard()
        smc.failWrites = true
        #expect(g.setFan(rpm: 3000, leaseSeconds: 90) == .smcFailed)
        #expect(timers.live.count == 1 && timers.live[0].seconds == 5) // retrying the restore, not the lease
        smc.failWrites = false
        timers.live[0].fire()
        #expect(smc.writes == ["F0md=0"])
    }

    @Test func modeThatDoesNotStickIsReportedAndRestored() {
        let (g, smc, _, _) = makeFanGuard()
        smc.ignoreModeWrites = true
        #expect(g.setFan(rpm: 3000, leaseSeconds: 90) == .notApplied)
        #expect(smc.writes.last == "F0md=0")
        #expect(g.status().code == .ok && !g.status().manual)
    }

    @Test func targetThatReadsBackWrongIsRestored() {
        let (g, smc, timers, _) = makeFanGuard()
        smc.targetReadsBack = 2000 // wrote 3000
        #expect(g.setFan(rpm: 3000, leaseSeconds: 90) == .notApplied)
        #expect(smc.value("F0md") == [0] && smc.writes.last == "F0md=0")
        #expect(timers.live.isEmpty) // restored and verified, nothing left armed
        smc.targetReadsBack = 3010 // within 25 rpm: fine
        #expect(g.setFan(rpm: 3000, leaseSeconds: 90) == .ok)
        #expect(FanGuard.targetMatches(5000, 5049) && !FanGuard.targetMatches(5000, 5060) && !FanGuard.targetMatches(.nan, 3000))
    }

    @Test func halfSuccessIsRestored() {
        // The target lands and the mode write throws.
        let (g, smc, _, _) = makeFanGuard(FakeFanSMC(fans: 2))
        smc.failWriteKey = "F1md"
        #expect(g.setFan(rpm: 3000, leaseSeconds: 90) == .smcFailed)
        #expect(smc.value("F0md") == [0]) // F0 had switched to manual: back to macOS
        #expect(smc.writes.contains("F0md=1") && smc.writes.last(where: { $0.hasPrefix("F0md") }) == "F0md=0")
        // The mode lands and a later target write throws (second fan's target).
        let (g2, smc2, timers2, _) = makeFanGuard(FakeFanSMC(fans: 2))
        smc2.keys["F0md"] = (.uint8, [0])
        smc2.failWriteKey = "F1Tg"
        #expect(g2.setFan(rpm: 3000, leaseSeconds: 90) == .smcFailed)
        #expect(smc2.value("F0md") == [0] && smc2.value("F1md") == [0])
        #expect(timers2.live.isEmpty)
        // The mode lands and the target read-back fails outright.
        let (g3, smc3, _, _) = makeFanGuard()
        smc3.targetReadsBack = .nan
        #expect(g3.setFan(rpm: 3000, leaseSeconds: 90) == .notApplied)
        #expect(smc3.value("F0md") == [0])
    }

    @Test func typeMismatchRefusesWithoutWriting() {
        for (key, type) in [("F0md", SMCKeyType.float), ("F0Tg", SMCKeyType("fpe2", 2)), ("FNum", SMCKeyType("ui16", 2)), ("F0Mn", SMCKeyType("ui16", 2))] {
            let smc = FakeFanSMC()
            smc.keys[key] = (type, Array(repeating: 0, count: type.size))
            let (g, _, timers, _) = makeFanGuard(smc)
            #expect(g.setFan(rpm: 3000, leaseSeconds: 90) == .unsupported)
            #expect(smc.writes.isEmpty)
            #expect(timers.live.isEmpty)
            #expect(!g.status().supported)
        }
    }

    @Test func noFanMeansUnsupportedWithoutRetries() {
        let smc = FakeFanSMC()
        smc.keys = [:] // MacBook Air: no FNum
        let (g, _, timers, _) = makeFanGuard(smc)
        g.start()
        #expect(timers.live.isEmpty)
        #expect(g.setFan(rpm: 3000, leaseSeconds: 90) == .unsupported)
        #expect(g.status().code == .unsupported && smc.writes.isEmpty)
        let zero = FakeFanSMC(fans: 0)
        let (g0, _, _, _) = makeFanGuard(zero)
        #expect(g0.setFan(rpm: 3000, leaseSeconds: 90) == .unsupported)
    }

    @Test func everyFanIsDrivenAndRestored() {
        let (g, smc, _, _) = makeFanGuard(FakeFanSMC(fans: 2))
        _ = g.setFan(rpm: 3000, leaseSeconds: 90)
        #expect(smc.writes == ["F0Tg=3000", "F1Tg=3000", "F0md=1", "F1md=1"])
        _ = g.restore(reason: "test")
        #expect(smc.writes.suffix(2) == ["F0md=0", "F1md=0"])
    }

    @Test func unlockKeyIsUsedOnlyWhenPresent() {
        let (g, smc, _, _) = makeFanGuard(FakeFanSMC(unlock: true))
        _ = g.setFan(rpm: 3000, leaseSeconds: 90)
        #expect(smc.writes == ["Ftst=1", "F0Tg=3000", "F0md=1"])
        _ = g.restore(reason: "test")
        #expect(smc.writes.suffix(2) == ["F0md=0", "Ftst=0"])
    }

    @Test func whitelistAllowsOnlyFanModeTargetAndUnlock() {
        #expect(FanWhitelist.allowsWrite(key: "F0md", bytes: [0]) && FanWhitelist.allowsWrite(key: "F1md", bytes: [1]))
        #expect(FanWhitelist.allowsWrite(key: "Ftst", bytes: [1]))
        #expect(FanWhitelist.allowsWrite(key: "F0Tg", bytes: FanBytes.bytes(3000)))
        #expect(!FanWhitelist.allowsWrite(key: "F0md", bytes: [2]))
        #expect(!FanWhitelist.allowsWrite(key: "F0Tg", bytes: FanBytes.bytes(20_000)))
        #expect(!FanWhitelist.allowsWrite(key: "F0Tg", bytes: FanBytes.bytes(.nan)))
        for k in ["F0Mn", "F0Mx", "F0Ac", "FNum", "CHIE", "FAmd", "F0md ", "Fxmd", ""] {
            #expect(!FanWhitelist.allowsWrite(key: k, bytes: [0]))
            #expect(!FanWhitelist.allowsWrite(key: k, bytes: FanBytes.bytes(3000)))
        }
        #expect(!FanWhitelist.allowsRead(key: "CHIE") && !SMCWhitelist.allows(key: "F0md", value: 0))
        #expect(FanBytes.float([0x00, 0xd0, 0x10, 0x45]) == 2317)
    }

    @Test func serviceAndInvalidationCoverFans() {
        let (g, smc, _, _) = makeFanGuard()
        let adapter = AdapterGuard(smc: FakeSMC(), schedule: FakeTimers().scheduler)
        let service = HelperService(adapter: adapter, fan: g)
        nonisolated(unsafe) var code = -1
        service.setFan(rpm: 3200, leaseSeconds: 30) { code = $0 }
        #expect(code == 0 && smc.value("F0md") == [1])
        nonisolated(unsafe) var reply: (Bool, Int, Bool, Int) = (false, 0, false, 0)
        service.fanStatus { sup, count, _, _, _, manual, target, _, _ in reply = (sup, count, manual, target) }
        #expect(reply == (true, 1, true, 3200))
        service.resetFan { code = $0 }
        #expect(code == 0 && smc.value("F0md") == [0])
        _ = g.setFan(rpm: 3200, leaseSeconds: 30)
        let conn = NSXPCConnection(serviceName: "test.invalid")
        HelperListenerDelegate.attachRestore(to: conn, adapter: adapter, fan: g)
        conn.invalidationHandler?()
        #expect(smc.value("F0md") == [0])
        nonisolated(unsafe) var noFan = -1
        HelperService(adapter: adapter).setFan(rpm: 3000, leaseSeconds: 30) { noFan = $0 }
        #expect(noFan == HelperErrorCode.unsupported.rawValue)
    }

    @Test func nanReadingsNeverCrashTheHelper() {
        let (g, smc, _, _) = makeFanGuard()
        smc.keys["F0Ac"] = (.float, FanBytes.bytes(.nan))
        #expect(g.status().actualRPM == -1)
        let bad = FakeFanSMC()
        bad.keys["F0Mn"] = (.float, FanBytes.bytes(.nan))
        let (g2, _, _, _) = makeFanGuard(bad)
        #expect(g2.setFan(rpm: 3000, leaseSeconds: 90) == .unsupported && bad.writes.isEmpty)
    }

    @Test func transientReadErrorIsNotUnsupported() {
        let (g, smc, _, _) = makeFanGuard()
        smc.failReads = true
        let s = g.status()
        #expect(s.supported && s.code == .smcFailed)
        smc.failReads = false
        #expect(g.status().code == .ok)
    }
}
