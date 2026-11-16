import Foundation
import HelperProtocol

/// A cancellable one-shot timer. The real one is a DispatchSourceTimer; tests use a fake they fire by hand.
public protocol LeaseTimer: Sendable { func cancel() }
public typealias LeaseScheduler = @Sendable (_ seconds: Int, _ fire: @escaping @Sendable () -> Void) -> LeaseTimer

/// Wall-clock deadline: a monotonic DispatchTime deadline stops counting while the Mac sleeps,
/// so a lease armed just before sleep would otherwise outlive it.
public final class DispatchLeaseTimer: LeaseTimer, @unchecked Sendable {
    private let source: DispatchSourceTimer
    public init(seconds: Int, queue: DispatchQueue, fire: @escaping @Sendable () -> Void) {
        source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(wallDeadline: .now() + .seconds(seconds))
        source.setEventHandler(handler: fire)
        source.resume()
    }
    public func cancel() { source.cancel() }
}

/// Owns the adapter. Fail-safe default is adapter ON: an "off" only exists together with a running lease
/// timer, and every exit path (lease expiry, signal, XPC invalidation, sleep, startup) writes CHIE=00.
public final class AdapterGuard: @unchecked Sendable {
    public struct Status: Equatable, Sendable {
        public var adapterEnabled: Bool
        public var chie: Int // -1 when unreadable
        public var leaseRemaining: Int
        public var supported: Bool
    }

    /// Restore retries back off, then settle at every 5 minutes.
    static let retryBackoff = [5, 15, 60, 300]
    private let connect: @Sendable () throws -> SMCWriting
    private let schedule: LeaseScheduler
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void
    private let lock = NSLock()
    private var smc: SMCWriting?
    private var lease: LeaseTimer?
    private var leaseEnd: Date?
    private var generation = 0
    private var retries = 0
    private var sleeping = false
    private var unsupported = false

    /// `connect` opens the SMC; it is called again after an I/O failure, so a broken connection is reopened.
    public init(connect: @escaping @Sendable () throws -> SMCWriting, schedule: @escaping LeaseScheduler,
                now: @escaping @Sendable () -> Date = Date.init, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.connect = connect
        self.schedule = schedule
        self.now = now
        self.log = log
    }

    public convenience init(smc: SMCWriting, schedule: @escaping LeaseScheduler, now: @escaping @Sendable () -> Date = Date.init,
                            log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.init(connect: { smc }, schedule: schedule, now: now, log: log)
    }

    /// Helper start: whatever a previous run left behind, the adapter goes back on.
    public func start() { restore(reason: "helper start") }

    public func setAdapter(enabled: Bool, leaseSeconds: Int) -> HelperErrorCode {
        lock.lock(); defer { lock.unlock() }
        expireIfDueLocked()
        if enabled { return restoreLocked(reason: "app asked") }
        if unsupported { return .unsupported }
        if sleeping { log("cut refused: system is going to sleep"); return .sleeping }
        let seconds = AdapterLease.clamped(leaseSeconds)
        // Arm the lease before writing so there is never an "off" without a timer behind it.
        generation += 1
        let gen = generation
        lease?.cancel()
        lease = schedule(seconds) { [weak self] in self?.timerFired(generation: gen, reason: "lease expired") }
        leaseEnd = now().addingTimeInterval(TimeInterval(seconds))
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
        sleeping = true
        _ = restoreLocked(reason: "system will sleep")
    }

    public func systemDidWake() {
        lock.lock(); defer { lock.unlock() }
        sleeping = false
        expireIfDueLocked()
    }

    public func status() -> Status {
        lock.lock(); defer { lock.unlock() }
        expireIfDueLocked()
        var raw = -1
        if !unsupported {
            do { raw = Int(try (smc ?? connect()).read(key: SMCWhitelist.adapterKey)) } catch SMCError.keyMissing { unsupported = true } catch {}
        }
        let left = leaseEnd.map { max(0, Int($0.timeIntervalSince(now()).rounded(.up))) } ?? 0
        return Status(adapterEnabled: raw != Int(SMCWhitelist.adapterOff), chie: raw, leaseRemaining: left, supported: !unsupported)
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

    /// A timer that slept past its deadline still ends the lease in real time.
    private func expireIfDueLocked() {
        if let end = leaseEnd, now() >= end { _ = restoreLocked(reason: "lease expired (wall clock)") }
    }

    private func timerFired(generation gen: Int, reason: String) {
        lock.lock(); defer { lock.unlock() }
        guard gen == generation else { return } // a newer cut or restore superseded this timer
        _ = restoreLocked(reason: reason)
    }

    private func restoreLocked(reason: String) -> HelperErrorCode {
        generation += 1
        let gen = generation
        lease?.cancel(); lease = nil; leaseEnd = nil
        do {
            try write(SMCWhitelist.adapterOn)
            retries = 0
            log("adapter on (\(reason))")
            return .ok
        } catch SMCError.keyMissing {
            log("no CHIE key on this Mac: charge control unsupported, nothing to restore")
            return .unsupported
        } catch {
            let delay = Self.retryBackoff[min(retries, Self.retryBackoff.count - 1)]
            retries += 1
            log("adapter on FAILED (\(reason)): \(error); retrying in \(delay) s")
            // Never leave a possible "off" without a timer: keep retrying the restore.
            lease = schedule(delay) { [weak self] in self?.timerFired(generation: gen, reason: "retry") }
            return .smcFailed
        }
    }
}
