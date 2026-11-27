import CoreGraphics
import Foundation
import Testing
@testable import Core

@MainActor
private final class FakePointer: PointerDriver {
    var location = CGPoint(x: 100, y: 100)
    var screens = [CGRect(x: 0, y: 0, width: 1512, height: 982)]
    var idle: TimeInterval = 0
    var warps: [CGPoint] = []
    func warp(to point: CGPoint) { location = point; warps.append(point) }
    func displays() -> [CGRect] { screens }
    func secondsSinceInput() -> TimeInterval { idle }
}

/// A clock the test moves by hand.
private final class RoamClock: @unchecked Sendable {
    var t = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ s: TimeInterval) { t = t.addingTimeInterval(s) }
}

@MainActor
private func makeMover(_ p: FakePointer, _ c: RoamClock, _ o: MouseMoverOptions = .init(idleMinutes: 5)) -> MouseMover {
    // Long tick and watch so the background loops never run during a test; steps are driven by hand.
    MouseMover(driver: p, options: { o }, now: { c.t }, tick: .seconds(3600), watchEvery: .seconds(3600))
}

@MainActor
@Suite struct MouseMoverTests {
    @Test func bounceStaysInsideAndReflects() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 50)
        var p = CGPoint(x: 95, y: 45), v = CGVector(dx: 20, dy: 20)
        (p, v) = BouncePath.step(p, v, in: r, dt: 0.5)
        #expect(p == CGPoint(x: 95, y: 45)) // 105 reflects to 95, 55 reflects to 45
        #expect(v.dx < 0 && v.dy < 0)
        for _ in 0..<10_000 {
            (p, v) = BouncePath.step(p, v, in: r, dt: 0.1)
            #expect(r.contains(p) || p.x == r.maxX || p.y == r.maxY)
        }
    }

    @Test func pathCoversTheWholeScreen() {
        // After a few minutes at medium speed the pointer has been in every cell of a 6 x 4 grid.
        let r = BouncePath.area(CGRect(x: 0, y: 0, width: 1512, height: 982))
        var p = CGPoint(x: r.midX, y: r.midY), v = CGVector(dx: 160 * 0.832, dy: 160 * 0.555)
        var seen = Set<Int>()
        for _ in 0..<(60 * 300) {
            (p, v) = BouncePath.step(p, v, in: r, dt: 1.0 / 60)
            let col = min(5, Int((p.x - r.minX) / r.width * 6)), row = min(3, Int((p.y - r.minY) / r.height * 4))
            seen.insert(row * 6 + col)
        }
        #expect(seen.count == 24)
    }

    @Test func offUntilEnabledAndStartsAfterIdle() {
        let p = FakePointer(), c = RoamClock(), m = makeMover(p, c)
        #expect(m.phase == .off)
        m.enable()
        #expect(m.phase == .waiting)
        p.idle = 299
        #expect(!m.checkIdle() && m.phase == .waiting)
        p.idle = 300
        #expect(m.checkIdle() && m.phase == .moving)
    }

    @Test func neverStartsByItselfWhenIdleStartIsOff() {
        let p = FakePointer(), c = RoamClock(), m = makeMover(p, c, .init(idleMinutes: nil))
        m.enable()
        p.idle = 100_000
        #expect(!m.checkIdle() && m.phase == .waiting)
    }

    @Test func movesTheRealPointerEachStep() {
        let p = FakePointer(), c = RoamClock(), m = makeMover(p, c)
        m.enable(); m.begin()
        let first = p.location
        for _ in 0..<30 { c.advance(1.0 / 60); p.idle += 1.0 / 60; #expect(m.step()) }
        #expect(p.location != first)
        #expect(p.warps.count == 31)
        #expect(p.warps.allSatisfy { BouncePath.area(p.screens[0]).insetBy(dx: -0.5, dy: -0.5).contains($0) })
    }

    @Test func movingTheMouseStopsIt() {
        let p = FakePointer(), c = RoamClock(), m = makeMover(p, c)
        m.enable(); m.begin()
        c.advance(0.016); #expect(m.step())
        p.location.x += 40 // the owner grabbed the mouse
        c.advance(0.016)
        #expect(!m.step())
        #expect(m.phase == .waiting) // still on, watching for the next idle spell
        #expect(m.lastStopReason != nil)
    }

    @Test func aKeyPressOrClickStopsIt() {
        let p = FakePointer(), c = RoamClock(), m = makeMover(p, c)
        m.enable(); p.idle = 300; m.begin()
        for _ in 0..<60 { c.advance(1.0 / 60); p.idle += 1.0 / 60; #expect(m.step()) }
        p.idle = 0 // a key press: the pointer did not move
        c.advance(1.0 / 60)
        #expect(!m.step() && m.phase == .waiting)
    }

    @Test func blackScreenFollowsTheRun() {
        let p = FakePointer(), c = RoamClock(), m = makeMover(p, c)
        var shown: [Bool] = []
        m.onBlackoutChange = { shown.append($0) }
        m.enable(); m.begin()
        m.stop()
        #expect(shown == [true, false])
        let plain = makeMover(p, c, .init(idleMinutes: 5, blackout: false))
        var plainShown: [Bool] = []
        plain.onBlackoutChange = { plainShown.append($0) }
        plain.enable(); plain.begin(); plain.stop()
        #expect(plainShown.isEmpty)
    }

    @Test func turningTheToolOffStopsEverything() {
        let p = FakePointer(), c = RoamClock(), m = makeMover(p, c)
        var black = false
        m.onBlackoutChange = { black = $0 }
        m.enable(); m.begin()
        #expect(black)
        m.disable()
        #expect(m.phase == .off && !black)
        #expect(!m.step())
        p.idle = 100_000
        #expect(!m.checkIdle())
    }

    @Test func startSoonCountsDownAndCanBeCancelled() {
        let p = FakePointer(), c = RoamClock(), m = makeMover(p, c)
        m.enable()
        m.startSoon()
        guard case .countdown(let until) = m.phase else { Issue.record("no countdown"); return }
        #expect(until.timeIntervalSince(c.t) == MouseMover.countdownSeconds)
        m.stop()
        #expect(m.phase == .waiting && p.warps.isEmpty)
    }

    @Test func visitsEachDisplayInTurn() {
        let p = FakePointer(), c = RoamClock(), m = makeMover(p, c)
        p.screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1080)]
        m.enable(); m.begin()
        #expect(p.screens[0].contains(p.location))
        c.advance(MouseMover.secondsPerDisplay); p.idle += MouseMover.secondsPerDisplay
        #expect(m.step())
        #expect(p.screens[1].contains(p.location))
    }

    @Test func aStallDoesNotMakeItJump() {
        let p = FakePointer(), c = RoamClock(), m = makeMover(p, c)
        m.enable(); m.begin()
        let before = p.location
        c.advance(20); p.idle += 20 // busy main thread or a long frame
        #expect(m.step())
        #expect(hypot(p.location.x - before.x, p.location.y - before.y) <= 160 * 0.1 + 0.01)
    }

    @Test func noScreensMeansNoRun() {
        let p = FakePointer(), c = RoamClock(), m = makeMover(p, c)
        p.screens = []
        m.enable(); m.begin()
        #expect(m.phase == .waiting && p.warps.isEmpty)
    }

    @Test func storedOptionsDefaultToFiveMinutesMediumAndBlack() {
        let d = UserDefaults(suiteName: "MouseMoverTests")!
        d.removePersistentDomain(forName: "MouseMoverTests")
        #expect(MouseMoverOptions.stored(d) == .init(idleMinutes: 5, speed: .medium, blackout: true))
        d.set(0, forKey: "mouseMover.idleMinutes"); d.set("fast", forKey: "mouseMover.speed"); d.set(false, forKey: "mouseMover.blackout")
        #expect(MouseMoverOptions.stored(d) == .init(idleMinutes: nil, speed: .fast, blackout: false))
    }
}
