import Foundation
import Testing
@testable import Core

@MainActor
private final class FakeNotifier: BreakNotifier {
    var sent: [BreakKind] = []
    var onSend: (() -> Void)?
    var prepared = 0
    func prepare() async { prepared += 1 }
    func send(_ kind: BreakKind) async { sent.append(kind); onSend?() }
}

@MainActor
private final class FakeBlocker: InputBlocker {
    var canBlock = true, startOK = true, started = 0, stopped = 0
    var exit: (@MainActor () -> Void)?
    func start(onExitHeld: @escaping @MainActor () -> Void) -> Bool { started += 1; exit = onExitHeld; return startOK }
    func stop() { stopped += 1 }
}

private final class Clock: @unchecked Sendable { var t = Date(timeIntervalSince1970: 1_000_000) }

@MainActor
@Suite struct BreaksTests {
    private func make(_ n: FakeNotifier, clock: Clock = Clock()) -> (BreakReminders, UserDefaults) {
        let d = UserDefaults(suiteName: "breaks-" + UUID().uuidString)!
        // The sleeper never returns on its own, so only explicit fireDue() sends.
        return (BreakReminders(defaults: d, notifier: n, now: { clock.t }, sleep: { _ in try await Task.sleep(for: .seconds(3600)) }), d)
    }

    @Test func nothingIsScheduledUntilStartedAndEnabled() {
        let n = FakeNotifier(); let (b, _) = make(n)
        b.setEnabled(.eyes, true)
        #expect(b.nextDue.isEmpty)
        b.start()
        #expect(b.nextDue.keys.sorted { $0.rawValue < $1.rawValue } == [.eyes])
        b.stop()
        #expect(b.nextDue.isEmpty && !b.running)
    }

    @Test func dueBreaksAreSentOnceThenRescheduled() async {
        let n = FakeNotifier(); let clock = Clock(); let (b, _) = make(n, clock: clock)
        b.start(); b.setEnabled(.eyes, true); b.setEnabled(.water, true)
        await b.fireDue()
        #expect(n.sent.isEmpty) // not due yet
        clock.t += 21 * 60
        await b.fireDue()
        #expect(n.sent == [.eyes])
        await b.fireDue()
        #expect(n.sent == [.eyes]) // rescheduled, not repeated
        #expect(b.nextDue[.eyes] == clock.t + 20 * 60)
        b.stop()
    }

    @Test func snoozeDelaysTenMinutes() {
        let n = FakeNotifier(); let clock = Clock(); let (b, _) = make(n, clock: clock)
        b.start(); b.setEnabled(.stretch, true)
        b.snooze(.stretch)
        #expect(b.nextDue[.stretch] == clock.t + 600)
        b.stop()
    }

    @Test func settingsAreRememberedAndMinutesAreClamped() {
        let n = FakeNotifier(); let (b, d) = make(n)
        b.setEnabled(.water, true); b.setMinutes(.water, 9999)
        #expect(b.config[.water] == BreakConfig(enabled: true, minutes: 240))
        let again = BreakReminders(defaults: d, notifier: n)
        #expect(again.config[.water]?.enabled == true && again.config[.eyes]?.enabled == false)
    }

    @Test func pauseClearsAndResumeStartsFreshIntervals() {
        let n = FakeNotifier(); let clock = Clock(); let (b, _) = make(n, clock: clock)
        b.start(); b.setEnabled(.eyes, true)
        b.pause(); #expect(b.nextDue.isEmpty)
        clock.t += 3600; b.resume()
        #expect(b.nextDue[.eyes] == clock.t + 20 * 60)
        b.stop()
    }

    @Test func cleaningModeNeedsPermissionThenLocksAndExitsOnHold() {
        let blk = FakeBlocker(); blk.canBlock = false
        let c = CleaningMode(blocker: blk, sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        c.start(seconds: 60)
        #expect(c.phase == .needsAccessibility && blk.started == 0)
        blk.canBlock = true
        var changes: [Bool] = []; c.onChange = { changes.append($0) }
        c.start(seconds: 60)
        #expect(c.isActive && blk.started == 1)
        blk.exit?()
        #expect(c.phase == .idle && blk.stopped == 1 && changes == [true, false])
    }

    @Test func cleaningModeEndsOnItsOwnAndHasAHardCap() async throws {
        let blk = FakeBlocker()
        let c = CleaningMode(blocker: blk, sleep: { _ in })  // timer fires immediately
        c.start(seconds: 99_999)
        try await Task.sleep(for: .milliseconds(100))
        #expect(c.phase == .idle && blk.stopped == 1)
        let c2 = CleaningMode(blocker: blk, sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        c2.start(seconds: 99_999)
        if case .active(let end) = c2.phase { #expect(end.timeIntervalSinceNow <= Double(CleaningMode.maxSeconds) + 1) }
        c2.stop()
        blk.startOK = false; c2.start(seconds: 30)
        #expect(c2.phase == .failed)
    }
}
