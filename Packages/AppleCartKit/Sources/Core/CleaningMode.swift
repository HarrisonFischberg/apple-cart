import Foundation
import Observation

/// Swallows keyboard and trackpad input. The real one is an event tap; tests use a fake.
@MainActor
public protocol InputBlocker: AnyObject {
    var canBlock: Bool { get }
    /// `onExitHeld` is called when the exit key has been held long enough. Returns false if blocking could not start.
    func start(onExitHeld: @escaping @MainActor () -> Void) -> Bool
    func stop()
}

/// Black screen, input locked for wiping the keyboard. It always ends: Esc held for 3 seconds, or the timer.
@MainActor @Observable
public final class CleaningMode {
    public enum Phase: Equatable { case idle, active(endsAt: Date), needsAccessibility, failed }
    public static let maxSeconds = 300
    public static let exitHoldSeconds = 3
    public private(set) var phase: Phase = .idle
    @ObservationIgnored private let blocker: InputBlocker
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async throws -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored public var onChange: (@MainActor (Bool) -> Void)?   // overlay windows follow this

    public init(blocker: InputBlocker, now: @escaping () -> Date = Date.init,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.blocker = blocker; self.now = now; self.sleep = sleep
    }

    public var isActive: Bool { if case .active = phase { true } else { false } }

    public func start(seconds: Int) {
        guard !isActive else { return }
        guard blocker.canBlock else { phase = .needsAccessibility; return }
        let length = min(max(seconds, 10), Self.maxSeconds)
        guard blocker.start(onExitHeld: { [weak self] in self?.stop() }) else { phase = .failed; return }
        phase = .active(endsAt: now().addingTimeInterval(Double(length)))
        onChange?(true)
        task = Task { [weak self, sleep] in
            do { try await sleep(Double(length)) } catch { return }
            self?.stop()
        }
    }

    public func stop() {
        task?.cancel(); task = nil
        guard isActive else { return }
        blocker.stop()
        phase = .idle
        onChange?(false)
    }

    public func clearMessage() { if !isActive { phase = .idle } }
}
