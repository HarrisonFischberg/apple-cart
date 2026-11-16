import CoreGraphics
import Foundation
import Testing
@testable import Core

private func reading(plugged: Bool, amps: Int64, system: Int? = 13300, usb: Int? = 1800, loss: Int? = 2100) -> BatteryReading {
    var tele: [String: Any] = [:]
    if let system { tele["SystemLoad"] = system }
    if let loss { tele["AdapterEfficiencyLoss"] = loss }
    var d: [String: Any] = ["CurrentCapacity": 62, "ExternalConnected": plugged ? 1 : 0, "IsCharging": amps > 0 ? 1 : 0, "Voltage": 12000,
                            "InstantAmperage": NSNumber(value: UInt64(bitPattern: amps)), "PowerTelemetryData": tele,
                            "AdapterDetails": ["Watts": 60]]
    if let usb { d["PowerOutDetails"] = [["Watts": usb]] }
    return BatteryReading(properties: d)!
}

private let samples: [(String, BatteryReading?)] = [
    ("charging", reading(plugged: true, amps: 800)),
    ("idle", reading(plugged: true, amps: 0)),
    ("battery", reading(plugged: false, amps: -1100)),
    ("weak", reading(plugged: true, amps: -500)),
    ("none", nil),
]

private func layout(_ r: BatteryReading?, width: CGFloat, soc: Double? = nil, other: Double? = nil) -> FlowLayout {
    let streams = PowerFlows.streams(r, socWatts: soc, otherWatts: other)
    return FlowLayout.make(state: FlowState(r), flows: PowerFlows(r), streams: streams, rest: PowerFlows.rest(r, streams: streams), width: width)
}

@MainActor
@Suite struct PowerFlowLayoutTests {
    @Test func stateFollowsTheReading() {
        #expect(samples.map { FlowState($0.1) } == [.charging, .pluggedIdle, .onBattery, .chargerTooWeak, .noData])
    }

    @Test func ribbonWidthIsClampedAndZeroWhenIdleOrUnknown() {
        #expect(FlowMotion.ribbonWidth(nil) == 0 && FlowMotion.ribbonWidth(0) == 0 && FlowMotion.ribbonWidth(0.04) == 0)
        #expect(FlowMotion.ribbonWidth(1) == FlowMotion.minWidth)
        #expect(FlowMotion.ribbonWidth(200) == FlowMotion.maxWidth)
        #expect(FlowMotion.ribbonWidth(10) < FlowMotion.ribbonWidth(20))
    }

    @Test func particlesTrickleAtOneWattAndHurryAtThirty() {
        #expect(FlowMotion.speed(0) == 0)
        #expect(FlowMotion.speed(30) > FlowMotion.speed(1) * 4)
        #expect(FlowMotion.speed(100) == FlowMotion.speed(40)) // capped
        func lit(_ w: Double, at d: Double) -> [Double] { var out: [Double] = []; FlowMotion.particles(distance: d, length: 200, watts: w) { out.append($0) }; return out }
        #expect(lit(1, at: 0).count < lit(30, at: 0).count)
        #expect(lit(30, at: 5).allSatisfy { (0...1).contains($0) })
        #expect(lit(0, at: 5).isEmpty)
        // Moving forward shifts every lit particle forward by the same amount (no jumps).
        let a = lit(30, at: 0), b = lit(30, at: 4)
        #expect(zip(a, b).allSatisfy { abs(($1 - $0) * 200 - 4) < 0.001 })
    }

    @Test func clockKeepsDistanceContinuousWhenSpeedChanges() {
        let id = FlowLinkID(.charger, .mac)
        var c = ParticleClock()
        c.update(speeds: [id: 10], at: 100)
        #expect(c.distance(id, at: 102) == 20)
        c.update(speeds: [id: 50], at: 102)
        #expect(c.distance(id, at: 102) == 20)
        #expect(c.distance(id, at: 103) == 70)
    }

    @Test func progressEasesFromZeroToOne() {
        #expect(FlowMotion.progress(elapsed: -1) == 0 && FlowMotion.progress(elapsed: 0) == 0)
        #expect(FlowMotion.progress(elapsed: FlowMotion.transition / 2) == 0.5)
        #expect(FlowMotion.progress(elapsed: 10) == 1)
    }

    @Test func stackKeepsOrderAndFitsTheSpan() {
        let ys = FlowLayout.stack([20, 20, 20, 20, 20], mid: 50, span: 64)
        #expect(ys == ys.sorted())
        let scale = 64.0 / 112 // five 20 pt ribbons plus gaps squeezed into 64 pt
        #expect(ys.first! - 10 * scale >= 50 - 32 - 0.001 && ys.last! + 10 * scale <= 50 + 32 + 0.001)
        #expect(FlowLayout.stack([], mid: 0, span: 10).isEmpty)
    }

    @Test func eachStateDrawsItsOwnRibbons() {
        func ids(_ i: Int) -> Set<FlowLinkID> { Set(layout(samples[i].1, width: 320).links.filter { $0.kind != .stream }.map(\.id)) }
        #expect(ids(0) == [FlowLinkID(.charger, .mac), FlowLinkID(.charger, .battery)])
        #expect(ids(1) == [FlowLinkID(.charger, .mac)])
        #expect(ids(2) == [FlowLinkID(.battery, .mac)]) // nothing from the unplugged charger
        #expect(ids(3) == [FlowLinkID(.charger, .mac), FlowLinkID(.battery, .mac)])
        let battery = layout(samples[2].1, width: 320)
        #expect(battery.node(.charger)!.dimmed && battery.node(.battery)!.rect.minX == 0) // battery takes the source slot
        #expect(layout(nil, width: 320).links.allSatisfy { $0.watts == nil })
    }

    @Test func forkHasOneToFourStreamsPlusMoreAndNeverCrosses() {
        for (soc, other) in [(nil, nil), (4.0, nil), (4.0, 2.0), (0.2, 0.3)] as [(Double?, Double?)] {
            let l = layout(samples[0].1, width: 320, soc: soc, other: other)
            let fork = l.links.filter { $0.kind == .stream }
            #expect(fork.map(\.start.y) == fork.map(\.start.y).sorted())
            #expect(fork.map(\.end.y) == fork.map(\.end.y).sorted())
        }
        // Rest of the Mac = load minus SoC/USB/Other; charger loss is not part of the load.
        let r = reading(plugged: true, amps: 0)
        #expect(abs(PowerFlows.rest(r, streams: PowerFlows.streams(r))! - 11.5) < 0.001)
        #expect(PowerFlows.rest(reading(plugged: true, amps: 0, system: nil), streams: []) == nil)
    }

    /// The render check we can run without a window: every state at the card width (320) and the panel width (348).
    @Test(arguments: [CGFloat(320), 348])
    func layoutsStayInsideAndDoNotOverlap(width: CGFloat) {
        for (name, r) in samples {
            for (soc, other) in [(nil, nil), (5.0, 3.0)] as [(Double?, Double?)] {
                let l = layout(r, width: width, soc: soc, other: other)
                let bounds = CGRect(origin: .zero, size: l.size).insetBy(dx: -0.001, dy: -0.001)
                for n in l.nodes {
                    #expect(bounds.contains(n.rect), "\(name): \(n.id) outside")
                    #expect(n.rect.width >= 68 && n.rect.height >= 36, "\(name): \(n.id) too small for its label")
                }
                for (i, a) in l.nodes.enumerated() {
                    for b in l.nodes[(i + 1)...] {
                        #expect(!a.rect.insetBy(dx: 0.5, dy: 0.5).intersects(b.rect), "\(name): \(a.id) overlaps \(b.id)")
                    }
                }
                for k in l.links {
                    #expect(bounds.contains(k.start) && bounds.contains(k.end), "\(name): ribbon outside")
                    // Every ribbon gap leaves room for a visible curve.
                    #expect(k.vertical ? k.end.y < k.start.y - 20 : k.end.x > k.start.x + 30, "\(name): ribbon too short")
                }
            }
        }
    }

    @Test func lerpMorphsBetweenStates() {
        let a = layout(samples[0].1, width: 320), b = layout(samples[2].1, width: 320)
        #expect(FlowLayout.lerp(a, b, 0).node(.battery) == a.node(.battery).map { var n = $0; n.dimmed = b.node(.battery)!.dimmed; return n })
        #expect(FlowLayout.lerp(a, b, 1) == b)
        let mid = FlowLayout.lerp(a, b, 0.5)
        #expect(mid.link(FlowLinkID(.charger, .mac))!.watts! < a.link(FlowLinkID(.charger, .mac))!.watts!) // fading out
        #expect(mid.link(FlowLinkID(.battery, .mac)) != nil)
    }

    @Test func summaryReadsTheWholeMap() {
        let s = FlowSummary.text(samples[1].1, streams: PowerFlows.streams(samples[1].1), rest: nil)
        #expect(s == "Charger supplies 13.3 watts. The Mac uses 13.3 watts. SoC not reported by macOS. USB 1.8 watts. Other not reported by macOS. Charger loss 2.1 watts. Battery idle, 62 percent.")
        #expect(FlowSummary.text(samples[2].1, streams: [], rest: nil).hasPrefix("On battery. Charger not connected. The battery supplies 13.2 watts."))
        #expect(FlowSummary.text(nil, streams: [], rest: nil) == "Power flow. No data.")
    }
}
