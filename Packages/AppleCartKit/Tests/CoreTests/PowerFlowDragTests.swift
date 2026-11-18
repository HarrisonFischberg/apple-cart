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
