import Foundation
import Observation

public enum BreakKind: String, CaseIterable, Codable, Sendable {
    case eyes, stretch, water

    public var title: String { switch self { case .eyes: "Rest your eyes"; case .stretch: "Stretch"; case .water: "Drink water" } }
    public var message: String {
        switch self {
        case .eyes: "Look at something 20 feet away for 20 seconds."
        case .stretch: "Stand up and stretch for a minute."
        case .water: "Time for a glass of water."
        }
    }
    public var symbol: String { switch self { case .eyes: "eye"; case .stretch: "figure.walk"; case .water: "drop" } }
    public var defaultMinutes: Int { switch self { case .eyes: 20; case .stretch: 45; case .water: 60 } }
}

public struct BreakConfig: Codable, Equatable, Sendable {
    public var enabled = false
    public var minutes: Int
    public init(enabled: Bool = false, minutes: Int) { self.enabled = enabled; self.minutes = minutes }
}

@MainActor
public protocol BreakNotifier: AnyObject {
    /// Asks macOS for notification permission, at the moment the user turns a reminder on.
    func prepare() async
    /// Shows a banner with a Snooze action.
    func send(_ kind: BreakKind) async
}

@MainActor @Observable
public final class BreakReminders: Tool {
    public static let snoozeMinutes = 10
    public private(set) var config: [BreakKind: BreakConfig]
    public private(set) var nextDue: [BreakKind: Date] = [:]
    public private(set) var running = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifier: BreakNotifier
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async throws -> Void
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(defaults: UserDefaults = .standard, notifier: BreakNotifier, now: @escaping () -> Date = Date.init,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.defaults = defaults; self.notifier = notifier; self.now = now; self.sleep = sleep
        let saved = (defaults.data(forKey: "breaks.config")).flatMap { try? JSONDecoder().decode([BreakKind: BreakConfig].self, from: $0) } ?? [:]
        config = Dictionary(uniqueKeysWithValues: BreakKind.allCases.map { ($0, saved[$0] ?? BreakConfig(minutes: $0.defaultMinutes)) })
    }

    // MARK: Tool
    public func start() { running = true; resume() }
    public func stop() { running = false; task?.cancel(); task = nil; nextDue = [:] }

    /// A fresh interval from now. Used on start and after the Mac wakes: time asleep is not time worked.
    public func resume() {
        guard running else { return }
        let t = now()
        nextDue = Dictionary(uniqueKeysWithValues: BreakKind.allCases.filter { config[$0]!.enabled }.map { ($0, t.addingTimeInterval(Double(config[$0]!.minutes) * 60)) })
        rearm()
    }

    public func pause() { task?.cancel(); task = nil; nextDue = [:] }

    public func setEnabled(_ kind: BreakKind, _ on: Bool) {
        config[kind]!.enabled = on; save(); schedule(kind)
        if on { Task { await notifier.prepare() } }
    }
    public func setMinutes(_ kind: BreakKind, _ minutes: Int) { config[kind]!.minutes = min(max(minutes, 1), 240); save(); schedule(kind) }

    public func snooze(_ kind: BreakKind) {
        guard running else { return }
        nextDue[kind] = now().addingTimeInterval(Double(Self.snoozeMinutes) * 60); rearm()
    }

    /// Sends everything that is due and sets the next time for each.
    public func fireDue() async {
        let t = now()
        for kind in BreakKind.allCases where (nextDue[kind].map { $0 <= t } ?? false) {
            nextDue[kind] = t.addingTimeInterval(Double(config[kind]!.minutes) * 60)
            await notifier.send(kind)
        }
        rearm()
    }

    private func schedule(_ kind: BreakKind) {
        guard running else { return }
        nextDue[kind] = config[kind]!.enabled ? now().addingTimeInterval(Double(config[kind]!.minutes) * 60) : nil
        rearm()
    }

    private func save() { defaults.set(try? JSONEncoder().encode(config), forKey: "breaks.config") }

    /// One sleep until the earliest due time; no polling.
    private func rearm() {
        task?.cancel(); task = nil
        guard running, let next = nextDue.values.min() else { return }
        let wait = max(0, next.timeIntervalSince(now()))
        task = Task { [weak self, sleep] in
            do { try await sleep(wait) } catch { return }
            await self?.fireDue()
        }
    }
}
