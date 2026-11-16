import Foundation
import HelperProtocol

/// A cancellable one-shot timer. The real one is a DispatchSourceTimer; tests use a fake they fire by hand.
public protocol LeaseTimer: Sendable { func cancel() }
public typealias LeaseScheduler = @Sendable (_ seconds: Int, _ fire: @escaping @Sendable () -> Void) -> LeaseTimer

/// Fires at whichever comes first: a wall-clock deadline (keeps counting through sleep) or an uptime deadline
/// (ignores the user changing the clock). Either alone could overrun a lease.
public final class DispatchLeaseTimer: LeaseTimer, @unchecked Sendable {
    private let wall: DispatchSourceTimer
    private let uptime: DispatchSourceTimer
    public init(seconds: Int, queue: DispatchQueue, fire: @escaping @Sendable () -> Void) {
        wall = DispatchSource.makeTimerSource(queue: queue)
        uptime = DispatchSource.makeTimerSource(queue: queue)
        wall.schedule(wallDeadline: .now() + .seconds(seconds))
        uptime.schedule(deadline: .now() + .seconds(seconds))
        let sources = [wall, uptime]
        for s in sources { s.setEventHandler { sources.forEach { $0.cancel() }; fire() } }
        wall.resume(); uptime.resume()
    }
    public func cancel() { wall.cancel(); uptime.cancel() }
}

/// Monotonic time that also counts sleep and never jumps with clock changes.
public func monotonicSeconds() -> Double { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1e9 }

/// Owns the adapter. Fail-safe default is adapter ON: an "off" only exists together with a running lease
/// timer, and every exit path (lease expiry, signal, XPC invalidation, sleep, startup) writes CHIE=00.
public final class AdapterGuard: @unchecked Sendable {
    public struct Status: Equatable, Sendable {
        public var adapterEnabled: Bool
        public var chie: Int // -1 when unreadable
        public var leaseRemaining: Int
        public var supported: Bool
    }

    /// Restore retries back off, then settle at every 5 minutes; capped at 60 s while the charger may still be cut.
    static let retryBackoff = [5, 15, 60, 300]
    static let retryCapWhileCut = 60
    /// A sleep that never reports power-on (aborted) stops blocking cuts after this long.
    static let sleepFlagTimeout: Double = 60
    private let connect: @Sendable () throws -> SMCWriting
    private let schedule: LeaseScheduler
    private let now: @Sendable () -> Date
    private let monotonic: @Sendable () -> Double
    private let log: @Sendable (String) -> Void
    private let lock = NSLock()
    private var smc: SMCWriting?
    private var lease: LeaseTimer?
    private var leaseEnd: Date?
    private var leaseEndMono: Double?
    private var generation = 0
    private var retries = 0
    private var sleepingSince: Double?
    private var unsupported = false
    /// True after a cut was written (or CHIE read 08) until a restore succeeds.
    private var mayBeCut = false

    /// `connect` opens the SMC; it is called again after an I/O failure, so a broken connection is reopened.
    public init(connect: @escaping @Sendable () throws -> SMCWriting, schedule: @escaping LeaseScheduler,
                now: @escaping @Sendable () -> Date = Date.init, monotonic: @escaping @Sendable () -> Double = monotonicSeconds,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.connect = connect
        self.schedule = schedule
        self.now = now
        self.monotonic = monotonic
        self.log = log
    }

    public convenience init(smc: SMCWriting, schedule: @escaping LeaseScheduler, now: @escaping @Sendable () -> Date = Date.init,
                            monotonic: @escaping @Sendable () -> Double = monotonicSeconds, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.init(connect: { smc }, schedule: schedule, now: now, monotonic: monotonic, log: log)
    }

    /// Helper start: whatever a previous run left behind, the adapter goes back on.
    public func start() { restore(reason: "helper start") }

    public func setAdapter(enabled: Bool, leaseSeconds: Int) -> HelperErrorCode {
        lock.lock(); defer { lock.unlock() }
        expireIfDueLocked()
        if enabled { return restoreLocked(reason: "app asked") }
        if unsupported { return .unsupported }
        if let since = sleepingSince {
            guard monotonic() - since > Self.sleepFlagTimeout else { log("cut refused: system is going to sleep"); return .sleeping }
            sleepingSince = nil // no power-on message ever came (aborted sleep)
        }
        let seconds = AdapterLease.clamped(leaseSeconds)
        // Arm the lease before writing so there is never an "off" without a timer behind it.
        generation += 1
        let gen = generation
        lease?.cancel()
        lease = schedule(seconds) { [weak self] in self?.timerFired(generation: gen, reason: "lease expired") }
        leaseEnd = now().addingTimeInterval(TimeInterval(seconds))
        leaseEndMono = monotonic() + Double(seconds)
        mayBeCut = true
        do {
            try write(SMCWhitelist.adapterOff)
            log("adapter off, lease \(seconds) s")
            return .ok
        } catch {
            log("adapter off failed: \(error); restoring")
            let restored = restoreLocked(reason: "cut failed")
            switch error as? SMCError {
            case .refused?: return .refused
            case .keyMissing?: return .unsupported
            default: return restored == .unsupported ? .unsupported : .smcFailed
            }
        }
    }

    @discardableResult
    public func restore(reason: String) -> HelperErrorCode {
        lock.lock(); defer { lock.unlock() }
        return restoreLocked(reason: reason)
    }

    /// Before acknowledging sleep: charger on, and refuse cuts until the system has powered on again.
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
        var raw = -1
        if !unsupported, let value = try? read() { raw = Int(value) }
        let wallLeft = leaseEnd.map { $0.timeIntervalSince(now()) }
        let monoLeft = leaseEndMono.map { $0 - monotonic() }
        let left = [wallLeft, monoLeft].compactMap { $0 }.min().map { max(0, Int($0.rounded(.up))) } ?? 0
        return Status(adapterEnabled: raw != Int(SMCWhitelist.adapterOff), chie: raw, leaseRemaining: left, supported: !unsupported)
    }

    private func read() throws -> UInt8 {
        do {
            let s = try smc ?? connect()
            smc = s
            let v = try s.read(key: SMCWhitelist.adapterKey)
            if v == SMCWhitelist.adapterOff { mayBeCut = true }
            return v
        } catch SMCError.keyMissing {
            unsupported = true
            throw SMCError.keyMissing
        } catch {
            smc = nil // reopen on the next attempt
            throw error
        }
    }

    private func write(_ value: UInt8) throws {
        do {
            let s = try smc ?? connect()
            smc = s
            try s.write(key: SMCWhitelist.adapterKey, value: value)
        } catch SMCError.keyMissing {
            unsupported = true
            throw SMCError.keyMissing
        } catch SMCError.refused {
            throw SMCError.refused
        } catch {
            smc = nil // reopen on the next attempt
            throw error
        }
    }

    /// A timer that slept past its deadline, or a clock set backwards, still ends the lease on time.
    private func expireIfDueLocked() {
        let wallDue = leaseEnd.map { now() >= $0 } ?? false
        let monoDue = leaseEndMono.map { monotonic() >= $0 } ?? false
        if wallDue || monoDue { _ = restoreLocked(reason: "lease expired (\(wallDue ? "wall clock" : "uptime"))") }
    }

    private func timerFired(generation gen: Int, reason: String) {
        lock.lock(); defer { lock.unlock() }
        guard gen == generation else { return } // a newer cut or restore superseded this timer
        _ = restoreLocked(reason: reason)
    }

    private func restoreLocked(reason: String) -> HelperErrorCode {
        generation += 1
        let gen = generation
        lease?.cancel(); lease = nil; leaseEnd = nil; leaseEndMono = nil
        do {
            try write(SMCWhitelist.adapterOn)
            retries = 0
            mayBeCut = false
            log("adapter on (\(reason))")
            return .ok
        } catch SMCError.keyMissing {
            log("no CHIE key on this Mac: charge control unsupported, nothing to restore")
            return .unsupported
        } catch {
            if !mayBeCut { _ = try? read() } // a previous run may have left 08 behind
            var delay = Self.retryBackoff[min(retries, Self.retryBackoff.count - 1)]
            if mayBeCut { delay = min(delay, Self.retryCapWhileCut) }
            retries += 1
            log("adapter on FAILED (\(reason)): \(error); retrying in \(delay) s")
            // Never leave a possible "off" without a timer: keep retrying the restore.
            lease = schedule(delay) { [weak self] in self?.timerFired(generation: gen, reason: "retry") }
            return .smcFailed
        }
    }
}
