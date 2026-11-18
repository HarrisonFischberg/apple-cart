import CoreGraphics
import Foundation
import Testing
@testable import Core

private func charging() -> FlowLayout {
    let d: [String: Any] = ["CurrentCapacity": 62, "ExternalConnected": 1, "IsCharging": 1, "Voltage": 12000,
                            "InstantAmperage": NSNumber(value: UInt64(bitPattern: 800)),
                            "PowerTelemetryData": ["SystemLoad": 13300, "AdapterEfficiencyLoss": 2100],
                            "AdapterDetails": ["Watts": 60], "PowerOutDetails": [["Watts": 1800]]]
    let r = BatteryReading(properties: d)!
    let streams = PowerFlows.streams(r)
    return FlowLayout.make(state: FlowState(r), flows: PowerFlows(r), streams: streams, rest: PowerFlows.rest(r, streams: streams), width: 320)
}

@Suite struct PowerFlowDragTests {
    @Test func noOffsetsLeavesTheLayoutExactlyAsItWas() {
        let base = charging()
        #expect(base.applying(FlowOffsets()) == base)
        #expect(base.applying(FlowOffsets([.mac: .zero])) == base)
    }

    @Test func aDraggedTileMovesAndItsRibbonsFollow() {
        let base = charging()
        let moved = base.applying(FlowOffsets([.charger: CGSize(width: 10, height: 30)]))
        let from = base.node(.charger)!.rect, to = moved.node(.charger)!.rect
        #expect(to.minX == from.minX + 10 && to.minY == from.minY + 30)
        for l in moved.links where l.id.from == .charger {
            #expect(abs(l.start.x - to.maxX) < 0.01)                 // still leaves the charger's right edge
            #expect(l.start.y >= to.minY && l.start.y <= to.maxY)
        }
        // Ribbons between tiles that did not move are untouched.
        for l in moved.links where l.id.from != .charger && l.id.to != .charger { #expect(base.link(l.id) == l) }
    }

    @Test func tilesStayInsideTheMap() {
        let base = charging()
        let moved = base.applying(FlowOffsets([.mac: CGSize(width: 900, height: -900)]))
        let r = moved.node(.mac)!.rect
        #expect(r.maxX <= base.size.width + 0.01 && r.minY >= -0.01)
    }

    @Test func droppingPastAnEdgeKeepsOnlyTheDistanceTheTileReallyMoved() {
        let base = charging()
        let o = FlowOffsets().dropping(.mac, by: CGSize(width: 0, height: -500), base: base)
        #expect(o[.mac].height == -base.node(.mac)!.rect.minY)
    }

    @Test func ribbonsTurnToFacingEdgesWhenATileGoesBelowOrBehind() {
        let a = CGRect(x: 100, y: 0, width: 80, height: 40)
        let (s1, e1, v1) = FlowLayout.facing(a, CGRect(x: 100, y: 120, width: 80, height: 40))
        #expect(v1 && s1.y == 40 && e1.y == 120)                         // stacked: bottom edge to top edge
        let (s2, e2, v2) = FlowLayout.facing(a, CGRect(x: 0, y: 0, width: 60, height: 40))
        #expect(!v2 && s2.x == 100 && e2.x == 60)                         // behind: left edge to right edge
    }

    @Test func offsetsRoundTripThroughTheirSavedForm() {
        let o = FlowOffsets([.charger: CGSize(width: 4, height: -2), .stream("USB"): CGSize(width: -12.5, height: 8), .mac: .zero])
        let back = FlowOffsets(json: o.json)
        #expect(back[.charger] == CGSize(width: 4, height: -2) && back[.stream("USB")] == CGSize(width: -12.5, height: 8))
        #expect(back.byNode[.mac] == nil)
        #expect(FlowOffsets(json: "not json").isEmpty && FlowOffsets().json == "")
        for id: FlowNodeID in [.charger, .mac, .battery, .more, .stream("Charger loss")] { #expect(FlowNodeID(storageKey: id.storageKey) == id) }
    }
}

@Suite struct PowerFlowOrbitTests {
    private func orbit(_ state: FlowState = .charging, offsets: FlowOffsets = FlowOffsets()) -> FlowLayout {
        var f = PowerFlows(nil); f.chargerToMac = 20; f.chargerToBattery = 4; f.batteryToMac = 0
        return FlowLayout.orbit(state: state, flows: f, streams: [PowerStream(title: "USB", watts: 15.5)], width: 340, offsets: offsets)
    }

    @Test func theMacSitsInTheMiddleWithEveryCardInsideTheMap() {
        let l = orbit()
        let hub = l.node(.mac)!.rect
        #expect(abs(hub.midX - 170) < 0.01)
        for n in l.nodes { #expect(CGRect(origin: .zero, size: l.size).insetBy(dx: -0.01, dy: -0.01).contains(n.rect)) }
        #expect(Set(l.nodes.map(\.id)) == [.mac, .charger, .battery, .stream("USB")])
    }

    @Test func arcsMeetThePlanetsDialAndTheCardsEdges() {
        let l = orbit()
        let hub = l.node(.mac)!.rect, m = CGPoint(x: hub.midX, y: hub.midY)
        let supply = l.link(FlowLinkID(.charger, .mac))!
        #expect(abs(hypot(supply.end.x - m.x, supply.end.y - m.y) - (FlowLayout.planet + 10)) < 0.01)
        let card = l.node(.charger)!.rect
        let onEdge = abs(supply.start.x - card.maxX) < 0.01 || abs(supply.start.y - card.maxY) < 0.01
        #expect(onEdge)
        #expect(l.link(FlowLinkID(.mac, .stream("USB")))?.watts == 15.5)
    }

    @Test func draggingACardMovesItsArcAndTheSameOffsetsWorkAsInTheColumnMap() {
        let moved = orbit(offsets: FlowOffsets([.charger: CGSize(width: 0, height: 120)]))
        let base = orbit()
        #expect(moved.node(.charger)!.rect.minY == base.node(.charger)!.rect.minY + 120)
        #expect(moved.link(FlowLinkID(.charger, .mac))!.start != base.link(FlowLinkID(.charger, .mac))!.start)
        // A drop past the bottom keeps only what fits.
        let o = FlowOffsets().dropping(.charger, by: CGSize(width: 0, height: 900), base: base)
        #expect(base.applying(o).node(.charger)!.rect.maxY <= base.size.height + 0.01)
    }

    @Test func onBatteryTheChargerIsDimmedAndTheBatteryFeedsTheMac() {
        let l = orbit(.onBattery)
        #expect(l.node(.charger)!.dimmed)
        #expect(l.link(FlowLinkID(.battery, .mac))?.kind == .drain && l.link(FlowLinkID(.charger, .mac)) == nil)
    }

    @Test func ringDustSplitsIntoNearAndFarHalvesAndInnerGrainsLead() {
        let near = OrbitRing.grain(u: 0, a: .pi / 2, size: 30, t: 0, omega: 1)
        let far = OrbitRing.grain(u: 0, a: -.pi / 2, size: 30, t: 0, omega: 1)
        #expect(near.front && !far.front)
        // Over a short time the inner edge sweeps further than the outer edge (measured as the distance moved / radius).
        func swept(_ u: Double) -> Double {
            let a = OrbitRing.grain(u: u, a: 0, size: 1, t: 0, omega: 1), b = OrbitRing.grain(u: u, a: 0, size: 1, t: 0.01, omega: 1)
            return hypot(b.dx - a.dx, b.dy - a.dy) / (OrbitRing.dustInner + u * OrbitRing.dustSpan)
        }
        #expect(swept(0) > swept(1))
        #expect(OrbitRing.spin(80) > OrbitRing.spin(5) && OrbitRing.spin(nil) > 0)
    }
}
