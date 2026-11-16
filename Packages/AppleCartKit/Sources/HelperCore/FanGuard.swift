import Foundation
import HelperProtocol

/// Owns the fans, modelled on AdapterGuard. Fail-safe default is system control (mode 0): manual mode only exists together
/// with a running lease timer, and every exit path (lease expiry, signal, XPC invalidation, sleep, startup, resetFan) hands
/// the fans back to macOS. The whole write sequence lives here, with key names and types read from the SMC first.
public final class FanGuard: @unchecked Sendable {
    public struct Status: Equatable, Sendable {
        public var supported: Bool
        public var count: Int
        public var actualRPM: Int      // fastest fan; -1 when unreadable
        public var minimumRPM: Int     // highest fan minimum; 0 when unknown
        public var maximumRPM: Int     // lowest fan maximum; 0 when unknown
        public var manual: Bool
        public var targetRPM: Int      // 0 when none
        public var leaseRemaining: Int
        public var code: HelperErrorCode
    }

    struct Fan: Equatable {
        var index: Int
        var modeKey: String
        var minimumRPM: Double
        var maximumRPM: Double
    }

    struct Layout: Equatable {
        var fans: [Fan]
        /// Written to 1 before manual mode and back to 0 on restore, only on Macs that have the key (Mac17,2 has none).
        var unlockKey: String?
    }

    static let retryBackoff = AdapterGuard.retryBackoff
    static let retryCapWhileManual = AdapterGuard.retryCapWhileCut
    static let sleepFlagTimeout = AdapterGuard.sleepFlagTimeout
    private let connect: @Sendable () throws -> FanSMC
    private let schedule: LeaseScheduler
    private let now: @Sendable () -> Date
    private let monotonic: @Sendable () -> Double
    private let log: @Sendable (String) -> Void
    /// A short pause between the writes and their read-back (the SMC applies a mode change asynchronously).
    private let settle: @Sendable () -> Void
    private let lock = NSLock()
    private var smc: FanSMC?
    private var layout: Layout?
    private var unsupported = false
    private var lease: LeaseTimer?
    private var leaseEnd: Date?
    private var leaseEndMono: Double?
    private var generation = 0
    private var retries = 0
    private var sleepingSince: Double?
    private var target: Int?
    /// True after a manual write was attempted (or a mode key read non-zero) until a restore succeeds.
    private var mayBeManual = false

    public static let settleSeconds = 0.15

    public init(connect: @escaping @Sendable () throws -> FanSMC, schedule: @escaping LeaseScheduler,
                now: @escaping @Sendable () -> Date = Date.init, monotonic: @escaping @Sendable () -> Double = monotonicSeconds,
                log: @escaping @Sendable (String) -> Void = { _ in },
                settle: @escaping @Sendable () -> Void = { Thread.sleep(forTimeInterval: FanGuard.settleSeconds) }) {
        self.settle = settle
        self.connect = connect
        self.schedule = schedule
        self.now = now
        self.monotonic = monotonic
        self.log = log
    }

    public convenience init(smc: FanSMC, schedule: @escaping LeaseScheduler, now: @escaping @Sendable () -> Date = Date.init,
                            monotonic: @escaping @Sendable () -> Double = monotonicSeconds, log: @escaping @Sendable (String) -> Void = { _ in },
                            settle: @escaping @Sendable () -> Void = { Thread.sleep(forTimeInterval: FanGuard.settleSeconds) }) {
        self.init(connect: { smc }, schedule: schedule, now: now, monotonic: monotonic, log: log, settle: settle)
    }

    /// Helper start: if a previous run left a fan in manual mode, hand it back to macOS.
    public func start() { restore(reason: "helper start") }

    public func setFan(rpm: Int, leaseSeconds: Int) -> HelperErrorCode {
        lock.lock(); defer { lock.unlock() }
        expireIfDueLocked()
        if rpm <= 0 { return restoreLocked(reason: "app asked") }
        if unsupported { return .unsupported }
        if let since = sleepingSince {
            guard monotonic() - since > Self.sleepFlagTimeout else { log("fan refused: system is going to sleep"); return .sleeping }
            sleepingSince = nil
        }
        let layout: Layout
        do { layout = try layoutLocked() } catch { return code(for: error) }
        let seconds = AdapterLease.clamped(leaseSeconds)
        // Arm the lease before writing so manual mode never exists without a timer behind it.
        generation += 1
        let gen = generation
        lease?.cancel()
        lease = schedule(seconds) { [weak self] in self?.timerFired(generation: gen, reason: "lease expired") }
        leaseEnd = now().addingTimeInterval(TimeInterval(seconds))
        leaseEndMono = monotonic() + Double(seconds)
        mayBeManual = true
        do {
            if let unlock = layout.unlockKey { try write(unlock, [FanWhitelist.manualMode]) }
            // Mode first, then the target. Verified on Mac17,2 / macOS 27: a target written while the mode is 0 is accepted
            // and then cleared to 0 when the mode switches to 1; mode 1 then target 2317 spun the fan from 0 to 2318 rpm.
            for fan in layout.fans { try write(fan.modeKey, [FanWhitelist.manualMode]) }
            var targets: [Int: Double] = [:]
            for fan in layout.fans {
                let clamped = Double(FanLimits.clampedMinimum(requested: rpm, systemMinimum: Int(fan.minimumRPM.rounded(.up)),
                                                              hardwareMaximum: Int(fan.maximumRPM.rounded(.down))))
                try write(FanWhitelist.targetKey(fan.index), FanBytes.bytes(clamped))
                targets[fan.index] = clamped
            }
            settle()
            for fan in layout.fans {
                let wanted = targets[fan.index] ?? 0
                var back = FanBytes.float(try read(FanWhitelist.targetKey(fan.index)))
                if back.map({ !Self.targetMatches($0, wanted) }) ?? true {
                    // One more try: the SMC may still have been switching modes when the first target landed.
                    log("fan \(fan.index) target reads back \(back.map { "\($0)" } ?? "?"); writing it once more")
                    try write(FanWhitelist.targetKey(fan.index), FanBytes.bytes(wanted))
                    settle()
                    back = FanBytes.float(try read(FanWhitelist.targetKey(fan.index)))
                }
                let mode = try read(fan.modeKey)
                log("fan \(fan.index) reads back mode \(mode), target \(back.map { "\($0)" } ?? "?") (wrote \(Int(wanted)))")
                guard mode == [FanWhitelist.manualMode], let back, Self.targetMatches(back, wanted) else { throw FanWriteError.notApplied }
            }
            let applied = Int(targets.values.max() ?? 0)
            target = applied
            log("fans manual at \(applied) rpm, lease \(seconds) s")
            return .ok
        } catch {
            log("fan manual failed: \(error); restoring")
            let restored = restoreLocked(reason: "manual failed")
            if case FanWriteError.notApplied = error { return .notApplied }
            if restored == .unsupported { return .unsupported }
            return code(for: error)
        }
    }

    @discardableResult
    public func restore(reason: String) -> HelperErrorCode {
        lock.lock(); defer { lock.unlock() }
        return restoreLocked(reason: reason)
    }

    public func systemWillSleep() {
        lock.lock(); defer { lock.unlock() }
        sleepingSince = monotonic()
        _ = restoreLocked(reason: "system will sleep")
    }

    public func systemDidWake() {
        lock.lock(); defer { lock.unlock() }
        sleepingSince = nil
        expireIfDueLocked()
    }

    public func status() -> Status {
        lock.lock(); defer { lock.unlock() }
        expireIfDueLocked()
        var s = Status(supported: !unsupported, count: 0, actualRPM: -1, minimumRPM: 0, maximumRPM: 0, manual: mayBeManual,
                       targetRPM: target ?? 0, leaseRemaining: leaseRemainingLocked(), code: .ok)
        if unsupported { s.code = .unsupported; return s }
        do {
            let layout = try layoutLocked()
            s.count = layout.fans.count
            s.minimumRPM = Int(layout.fans.map(\.minimumRPM).max()?.rounded(.up) ?? 0)
            s.maximumRPM = Int(layout.fans.map(\.maximumRPM).min()?.rounded(.down) ?? 0)
            var manual = false
            for fan in layout.fans {
                if let a = try? readFloat(FanWhitelist.actualKey(fan.index)), a.isFinite, a < 100_000 { s.actualRPM = max(s.actualRPM, max(0, Int(a.rounded()))) }
                if try read(fan.modeKey) != [FanWhitelist.systemMode] { manual = true }
            }
            if manual { mayBeManual = true }
            s.manual = manual
            if !manual { s.targetRPM = 0 }
        } catch {
            s.code = code(for: error)
            s.supported = !unsupported
        }
        return s
    }

    // MARK: Layout and I/O

    private enum FanWriteError: Error { case notApplied }

    /// A target read back within 25 rpm or 1% (whichever is larger) of what was written counts as applied.
    static func targetMatches(_ back: Double, _ wanted: Double) -> Bool {
        back.isFinite && abs(back - wanted) <= max(25, wanted * 0.01)
    }

    private func code(for error: Error) -> HelperErrorCode {
        switch error as? SMCError {
        case .keyMissing?, .typeMismatch?: return .unsupported
        case .refused?: return .refused
        default: return .smcFailed
        }
    }

    /// Reads the fan count and every fan's keys, checking each key's type before anything is written. A missing or
    /// differently typed key marks fans unsupported here (nothing is written); an I/O error is transient.
    private func layoutLocked() throws -> Layout {
        if let layout { return layout }
        do {
            try expect(FanWhitelist.countKey, .uint8)
            let count = Int(try read(FanWhitelist.countKey).first ?? 0)
            guard count > 0 else { log("FNum is 0: this Mac has no fan"); throw SMCError.keyMissing }
            var fans: [Fan] = []
            for i in 0..<min(count, FanWhitelist.maxFans) {
                var modeKey: String?
                for k in FanWhitelist.modeKeys(i) {
                    do { try expect(k, .uint8); modeKey = k; break } catch SMCError.keyMissing { continue }
                }
                guard let modeKey else { log("fan \(i): no mode key"); throw SMCError.keyMissing }
                try expect(FanWhitelist.targetKey(i), .float)
                let lo = try readFloat(FanWhitelist.minimumKey(i)), hi = try readFloat(FanWhitelist.maximumKey(i))
                guard lo.isFinite, hi.isFinite, lo > 0, hi > lo, hi <= 10_000 else { log("fan \(i): implausible range \(lo)-\(hi)"); throw SMCError.typeMismatch }
                fans.append(Fan(index: i, modeKey: modeKey, minimumRPM: lo, maximumRPM: hi))
            }
            var unlock: String?
            if let t = try? smcLocked().fanKeyType(FanWhitelist.unlockKey) {
                if t == .uint8 { unlock = FanWhitelist.unlockKey } else { log("Ftst has type \(t.type)/\(t.size); not used") }
            }
            let l = Layout(fans: fans, unlockKey: unlock)
            log("fans: \(fans.map { "\($0.index) \($0.modeKey) \(Int($0.minimumRPM))-\(Int($0.maximumRPM))" }), unlock \(unlock ?? "none")")
            layout = l
            return l
        } catch let e as SMCError where e == .keyMissing || e == .typeMismatch {
            unsupported = true
            throw e
        }
    }

    private func smcLocked() throws -> FanSMC {
        let s = try smc ?? connect()
        smc = s
        return s
    }

    private func expect(_ key: String, _ type: SMCKeyType) throws {
        let t = try io { try $0.fanKeyType(key) }
        guard t == type else { log("\(key) is \(t.type)/\(t.size), expected \(type.type)/\(type.size)"); throw SMCError.typeMismatch }
    }

    private func read(_ key: String) throws -> [UInt8] { try io { try $0.fanRead(key) } }

    private func readFloat(_ key: String) throws -> Double {
        try expect(key, .float)
        guard let v = FanBytes.float(try read(key)) else { throw SMCError.typeMismatch }
        return v
    }

    private func write(_ key: String, _ bytes: [UInt8]) throws {
        do {
            try io { try $0.fanWrite(key, bytes) }
            log("write \(key) \(bytes): ok")
        } catch {
            log("write \(key) \(bytes): \(error)")
            throw error
        }
    }

    /// Drops the connection after an I/O failure so the next attempt reopens it.
    private func io<T>(_ body: (FanSMC) throws -> T) throws -> T {
        do { return try body(try smcLocked()) } catch let e as SMCError where e == .keyMissing || e == .typeMismatch || e == .refused {
            throw e
        } catch {
            smc = nil
            throw error
        }
    }

    // MARK: Lease and restore

    private func leaseRemainingLocked() -> Int {
        let wallLeft = leaseEnd.map { $0.timeIntervalSince(now()) }
        let monoLeft = leaseEndMono.map { $0 - monotonic() }
        return [wallLeft, monoLeft].compactMap { $0 }.min().map { max(0, Int($0.rounded(.up))) } ?? 0
    }

    private func expireIfDueLocked() {
        let wallDue = leaseEnd.map { now() >= $0 } ?? false
        let monoDue = leaseEndMono.map { monotonic() >= $0 } ?? false
        if wallDue || monoDue { _ = restoreLocked(reason: "lease expired (\(wallDue ? "wall clock" : "uptime"))") }
    }

    private func timerFired(generation gen: Int, reason: String) {
        lock.lock(); defer { lock.unlock() }
        guard gen == generation else { return }
        _ = restoreLocked(reason: reason)
    }

    private func restoreLocked(reason: String) -> HelperErrorCode {
        generation += 1
        let gen = generation
        lease?.cancel(); lease = nil; leaseEnd = nil; leaseEndMono = nil
        target = nil
        do {
            let layout = try layoutLocked()
            if !mayBeManual {
                // Nothing of ours may be live: only write if a mode key is not already 0 (a previous run's leftover).
                let modes = try layout.fans.map { try read($0.modeKey) }
                let unlocked = try layout.unlockKey.map { try read($0) != [FanWhitelist.systemMode] } ?? false
                if modes.allSatisfy({ $0 == [FanWhitelist.systemMode] }) && !unlocked {
                    retries = 0
                    return .ok
                }
                mayBeManual = true
            }
            var firstError: Error?
            for fan in layout.fans {
                do { try write(fan.modeKey, [FanWhitelist.systemMode]) } catch { firstError = firstError ?? error }
            }
            if let unlock = layout.unlockKey {
                do { try write(unlock, [FanWhitelist.systemMode]) } catch { firstError = firstError ?? error }
            }
            if let firstError { throw firstError }
            settle() // the SMC applies a mode change asynchronously, as in setFan
            for fan in layout.fans where try read(fan.modeKey) != [FanWhitelist.systemMode] {
                log("fan \(fan.index) mode still non-zero after restore")
                throw FanWriteError.notApplied
            }
            retries = 0
            mayBeManual = false
            log("fans to system (\(reason))")
            return .ok
        } catch let e as SMCError where (e == .keyMissing || e == .typeMismatch) && !mayBeManual {
            log("fan control unsupported on this Mac (\(e)); nothing to restore")
            return .unsupported
        } catch {
            if case SMCError.keyMissing = error { unsupported = false }
            if case SMCError.typeMismatch = error { unsupported = false }
            // A previous run may have left manual mode on; if even the probe fails, assume it did.
            if !mayBeManual { mayBeManual = true }
            var delay = Self.retryBackoff[min(retries, Self.retryBackoff.count - 1)]
            if mayBeManual { delay = min(delay, Self.retryCapWhileManual) }
            retries += 1
            log("fans to system FAILED (\(reason)): \(error); retrying in \(delay) s")
            lease = schedule(delay) { [weak self] in self?.timerFired(generation: gen, reason: "retry") }
            return .smcFailed
        }
    }
}
