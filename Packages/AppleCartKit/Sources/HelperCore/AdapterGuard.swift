import Foundation
import HelperProtocol

/// A cancellable one-shot timer. The real one is a DispatchSourceTimer; tests use a fake they fire by hand.
public protocol LeaseTimer: Sendable { func cancel() }
public typealias LeaseScheduler = @Sendable (_ seconds: Int, _ fire: @escaping @Sendable () -> Void) -> LeaseTimer

public final class DispatchLeaseTimer: LeaseTimer, @unchecked Sendable {
    private let source: DispatchSourceTimer
    public init(seconds: Int, queue: DispatchQueue, fire: @escaping @Sendable () -> Void) {
        source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + .seconds(seconds))
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
    }

    static let retrySeconds = 5
    private let smc: SMCWriting
    private let schedule: LeaseScheduler
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void
    private let lock = NSLock()
    private var lease: LeaseTimer?
    private var leaseEnd: Date?
    private var generation = 0

    public init(smc: SMCWriting, schedule: @escaping LeaseScheduler, now: @escaping @Sendable () -> Date = Date.init,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.smc = smc
        self.schedule = schedule
        self.now = now
        self.log = log
    }

    /// Helper start: whatever a previous run left behind, the adapter goes back on.
    public func start() { restore(reason: "helper start") }

    public func setAdapter(enabled: Bool, leaseSeconds: Int) -> HelperErrorCode {
        lock.lock(); defer { lock.unlock() }
        if enabled { return restoreLocked(reason: "app asked") }
        let seconds = AdapterLease.clamped(leaseSeconds)
        // Arm the lease before writing so there is never an "off" without a timer behind it.
        generation += 1
        let gen = generation
        lease?.cancel()
        lease = schedule(seconds) { [weak self] in self?.leaseExpired(generation: gen) }
        leaseEnd = now().addingTimeInterval(TimeInterval(seconds))
        do {
            try smc.write(key: SMCWhitelist.adapterKey, value: SMCWhitelist.adapterOff)
            log("adapter off, lease \(seconds) s")
            return .ok
        } catch {
            log("adapter off failed: \(error); restoring")
            _ = restoreLocked(reason: "cut failed")
            return error as? SMCError == .refused ? .refused : .smcFailed
        }
    }

    @discardableResult
    public func restore(reason: String) -> HelperErrorCode {
        lock.lock(); defer { lock.unlock() }
        return restoreLocked(reason: reason)
    }

    public func status() -> Status {
        lock.lock(); defer { lock.unlock() }
        let raw = (try? smc.read(key: SMCWhitelist.adapterKey)).map(Int.init) ?? -1
        let left = leaseEnd.map { max(0, Int($0.timeIntervalSince(now()).rounded(.up))) } ?? 0
        return Status(adapterEnabled: raw != Int(SMCWhitelist.adapterOff), chie: raw, leaseRemaining: left)
    }

    private func leaseExpired(generation gen: Int) {
        lock.lock(); defer { lock.unlock() }
        guard gen == generation else { return } // a newer cut renewed the lease
        _ = restoreLocked(reason: "lease expired")
    }

    private func restoreLocked(reason: String) -> HelperErrorCode {
        generation += 1
        lease?.cancel(); lease = nil; leaseEnd = nil
        do {
            try smc.write(key: SMCWhitelist.adapterKey, value: SMCWhitelist.adapterOn)
            log("adapter on (\(reason))")
            return .ok
        } catch {
            log("adapter on FAILED (\(reason)): \(error); retrying in \(Self.retrySeconds) s")
            // Never leave a possible "off" without a timer: keep retrying the restore.
            lease = schedule(Self.retrySeconds) { [weak self] in self?.restore(reason: "retry") }
            return .smcFailed
        }
    }
}
