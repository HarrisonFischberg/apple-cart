import Foundation
import HelperProtocol

/// Owns the MagSafe light, modelled on FanGuard. Fail-safe default is "macOS owns the light": a forced colour only exists
/// together with a running lease timer, and every exit path (lease expiry, signal, XPC invalidation, sleep, startup,
/// resetLED) stops forcing it. macOS rewrites ACLC itself on an adapter event (verified: back to 4 within ~10 s of a
/// replug), so while a colour is wanted a 1 s tick reads the key and writes the colour again when macOS changed it.
///
/// Restore limit: ACLC has no "macOS decides" value. Restoring writes back the last value macOS itself set (captured at the
/// first arm, updated whenever the tick sees macOS change it) and stops correcting; macOS rewrites the key on its next event
/// anyway. After a helper restart nothing was captured, so a colour left by a crashed run stays until that next event.
public final class LEDGuard: @unchecked Sendable {
    public struct Status: Equatable, Sendable {
        public var supported: Bool
        public var raw: Int            // current ACLC value; -1 when unreadable
        public var wanted: Int         // forced colour (3 or 4); 0 when none
        public var leaseRemaining: Int
        public var code: HelperErrorCode
    }

    static let retryBackoff = AdapterGuard.retryBackoff
    static let retryCapWhileForced = AdapterGuard.retryCapWhileCut
    static let sleepFlagTimeout = AdapterGuard.sleepFlagTimeout
    /// How often the tick checks the key while a colour is wanted.
    public static let tickSeconds = 1
    /// Corrections are logged at most this often (an adapter event can trigger one every tick for a few seconds).
    static let correctionLogEvery: Double = 10
    /// The SMC applies an ACLC write after about 0.5 s: a read straight after the write still shows the old value.
    public static let settleSeconds = 0.6

    private let connect: @Sendable () throws -> LEDSMC
    private let schedule: LeaseScheduler
    private let now: @Sendable () -> Date
    private let monotonic: @Sendable () -> Double
    private let log: @Sendable (String) -> Void
    private let settle: @Sendable () -> Void
    private let lock = NSLock()
    private var smc: LEDSMC?
    private var unsupported = false
    private var lease: LeaseTimer?
    private var tick: LeaseTimer?
    private var leaseEnd: Date?
    private var leaseEndMono: Double?
    private var generation = 0
    private var retries = 0
    private var sleepingSince: Double?
    private var wanted: UInt8?
    /// The last value macOS set, written back on restore.
    private var macOSValue: UInt8?
    /// True after a colour write was attempted until a restore succeeds.
    private var mayBeForced = false
    private var lastCorrectionLog: Double?

    public init(connect: @escaping @Sendable () throws -> LEDSMC, schedule: @escaping LeaseScheduler,
                now: @escaping @Sendable () -> Date = Date.init, monotonic: @escaping @Sendable () -> Double = monotonicSeconds,
                log: @escaping @Sendable (String) -> Void = { _ in },
                settle: @escaping @Sendable () -> Void = { Thread.sleep(forTimeInterval: LEDGuard.settleSeconds) }) {
        self.connect = connect
        self.schedule = schedule
        self.now = now
        self.monotonic = monotonic
        self.log = log
        self.settle = settle
    }

    public convenience init(smc: LEDSMC, schedule: @escaping LeaseScheduler, now: @escaping @Sendable () -> Date = Date.init,
                            monotonic: @escaping @Sendable () -> Double = monotonicSeconds, log: @escaping @Sendable (String) -> Void = { _ in },
                            settle: @escaping @Sendable () -> Void = { Thread.sleep(forTimeInterval: LEDGuard.settleSeconds) }) {
        self.init(connect: { smc }, schedule: schedule, now: now, monotonic: monotonic, log: log, settle: settle)
    }

    /// Helper start: nothing of this run is forced, so nothing is written and nothing ticks (see the restore limit above).
    public func start() { restore(reason: "helper start") }

    /// `color` is 3 (green) or 4 (orange); anything else is refused with nothing written.
    public func setLED(color: Int, leaseSeconds: Int) -> HelperErrorCode {
        lock.lock(); defer { lock.unlock() }
        expireIfDueLocked()
        guard color == Int(LEDWhitelist.green) || color == Int(LEDWhitelist.orange) else { log("led refused: colour \(color)"); return .refused }
        if unsupported { return .unsupported }
        if let since = sleepingSince {
            guard monotonic() - since > Self.sleepFlagTimeout else { log("led refused: system is going to sleep"); return .sleeping }
            sleepingSince = nil
        }
        let value = UInt8(color)
        do { try expectKey() } catch { return code(for: error) }
        let seconds = AdapterLease.clamped(leaseSeconds)
        // Arm the lease before writing so a forced colour never exists without a timer behind it. A second call replaces it.
        generation += 1
        let gen = generation
        lease?.cancel(); tick?.cancel(); tick = nil
        lease = schedule(seconds) { [weak self] in self?.timerFired(generation: gen, reason: "lease expired") }
        leaseEnd = now().addingTimeInterval(TimeInterval(seconds))
        leaseEndMono = monotonic() + Double(seconds)
        do {
            let current = try read()
            // The first arm captures macOS's own value; a renewal while we are forcing must not capture ours.
            if wanted == nil { macOSValue = current }
            wanted = value
            mayBeForced = true
            if current != value {
                try write(value)
                settle()
                let back = try read()
                guard back == value else {
                    log("ACLC reads back \(back) after writing \(value); restoring")
                    wanted = nil
                    _ = restoreLocked(reason: "colour not applied")
                    return .notApplied
                }
            }
            armTickLocked(generation: gen)
            log("led forced to \(value), lease \(seconds) s")
            return .ok
        } catch {
            log("led write failed: \(error); restoring")
            wanted = nil
            let restored = restoreLocked(reason: "write failed")
            return restored == .unsupported ? .unsupported : code(for: error)
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
        var s = Status(supported: !unsupported, raw: -1, wanted: Int(wanted ?? 0), leaseRemaining: leaseRemainingLocked(), code: .ok)
        if unsupported { s.code = .unsupported; return s }
        do {
            try expectKey()
            s.raw = Int(try read())
        } catch {
            s.code = code(for: error)
            s.supported = !unsupported
        }
        return s
    }

    // MARK: I/O

    private func code(for error: Error) -> HelperErrorCode {
        switch error as? SMCError {
        case .keyMissing?, .typeMismatch?: return .unsupported
        case .refused?: return .refused
        default: return .smcFailed
        }
    }

    /// ACLC must be ui8 size 1 before anything is written; missing or different marks the light unsupported here.
    private func expectKey() throws {
        do {
            let t = try io { try $0.ledKeyType(LEDWhitelist.key) }
            guard t == .uint8 else { log("ACLC is \(t.type)/\(t.size), expected ui8 /1"); throw SMCError.typeMismatch }
        } catch let e as SMCError where e == .keyMissing || e == .typeMismatch {
            unsupported = true
            throw e
        }
    }

    private func read() throws -> UInt8 {
        let b = try io { try $0.ledRead(LEDWhitelist.key) }
        guard b.count == 1 else { throw SMCError.typeMismatch }
        return b[0]
    }

    private func write(_ value: UInt8) throws {
        do {
            try io { try $0.ledWrite(LEDWhitelist.key, [value]) }
            log("write ACLC \(value): ok")
        } catch {
            log("write ACLC \(value): \(error)")
            throw error
        }
    }

    /// Drops the connection after an I/O failure so the next attempt reopens it.
    private func io<T>(_ body: (LEDSMC) throws -> T) throws -> T {
        do {
            let s = try smc ?? connect()
            smc = s
            return try body(s)
        } catch let e as SMCError where e == .keyMissing || e == .typeMismatch || e == .refused {
            throw e
        } catch {
            smc = nil
            throw error
        }
    }

    // MARK: Tick, lease and restore

    private func armTickLocked(generation gen: Int) {
        tick?.cancel()
        tick = schedule(Self.tickSeconds) { [weak self] in self?.tickFired(generation: gen) }
    }

    /// While a colour is wanted and the lease is live: if macOS changed the key, note its value and write ours again.
    private func tickFired(generation gen: Int) {
        lock.lock(); defer { lock.unlock() }
        guard gen == generation, let value = wanted else { return }
        expireIfDueLocked()
        guard gen == generation else { return } // the lease just ran out
        do {
            let current = try read()
            if current != value {
                macOSValue = current
                let t = monotonic()
                if lastCorrectionLog.map({ t - $0 >= Self.correctionLogEvery }) ?? true {
                    lastCorrectionLog = t
                    log("macOS set ACLC to \(current); writing \(value) again")
                }
                try io { try $0.ledWrite(LEDWhitelist.key, [value]) }
            }
        } catch {
            log("led tick: \(error)") // transient: the next tick tries again
        }
        armTickLocked(generation: gen)
    }

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

    /// Stops forcing at once (no more ticks), then writes macOS's last value back if the key still shows ours.
    private func restoreLocked(reason: String) -> HelperErrorCode {
        generation += 1
        let gen = generation
        lease?.cancel(); lease = nil; tick?.cancel(); tick = nil; leaseEnd = nil; leaseEndMono = nil
        wanted = nil
        guard mayBeForced else { retries = 0; return unsupported ? .unsupported : .ok } // nothing of ours: write nothing
        do {
            if let original = macOSValue, LEDWhitelist.allowsWrite(key: LEDWhitelist.key, bytes: [original]), try read() != original {
                try write(original)
                settle()
                let back = try read()
                // macOS may have written its own value meanwhile; either way it owns the light again.
                if back != original { log("ACLC reads \(back) after restoring \(original)") }
            }
            retries = 0
            mayBeForced = false
            macOSValue = nil
            log("led back to macOS (\(reason))")
            return .ok
        } catch {
            var delay = Self.retryBackoff[min(retries, Self.retryBackoff.count - 1)]
            delay = min(delay, Self.retryCapWhileForced)
            retries += 1
            log("led back to macOS FAILED (\(reason)): \(error); retrying in \(delay) s")
            lease = schedule(delay) { [weak self] in self?.timerFired(generation: gen, reason: "retry") }
            return .smcFailed
        }
    }
}
