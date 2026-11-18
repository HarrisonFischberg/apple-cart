import Foundation
import Testing
@testable import Core

@Suite struct PowerFlowPixelTests {
    @Test func theEightBitMapIsTheDefaultStyle() {
        #expect(FlowStyle.allCases.first == .pixel && FlowStyle.pixel.title == "8-bit")
    }

    @Test func wiresGoAcrossThenDownAndTouchBothEnds() {
        let w = PixelFlow.wire(PixelPoint(2, 3), PixelPoint(6, 1))
        #expect(w.first == PixelPoint(2, 3) && w.last == PixelPoint(6, 1) && w.count == 7)
        #expect(w[4] == PixelPoint(6, 3)) // the corner
        for (a, b) in zip(w, w.dropFirst()) { #expect(abs(a.x - b.x) + abs(a.y - b.y) == 1) } // no gaps
        #expect(PixelFlow.wire(PixelPoint(5, 5), PixelPoint(5, 5)) == [PixelPoint(5, 5)])
    }

    @Test func routesDropIntoTheLowerBodyFromAboveWhicheverWayPowerGoes() {
        let mac = PixelPoint(50, 20), battery = PixelPoint(30, 60)
        let drain = PixelFlow.route(from: battery, to: mac), charge = PixelFlow.route(from: mac, to: battery)
        #expect(drain.first == battery && drain.last == mac && drain == charge.reversed())
        // Nothing runs below the Mac (where its label is): the vertical leg is at the battery's x.
        #expect(drain.allSatisfy { $0.y == mac.y || $0.x == battery.x })
    }

    @Test func moreWattsMeanDenserFasterPacketsAndNoneWhenIdle() {
        #expect(PixelFlow.gap(40) < PixelFlow.gap(2) && PixelFlow.speed(40) > PixelFlow.speed(2))
        #expect(PixelFlow.packets(length: 30, watts: 0, t: 5).isEmpty)
        let p = PixelFlow.packets(length: 30, watts: 20, t: 3.3)
        #expect(!p.isEmpty && p.allSatisfy { $0 >= 0 && $0 < 30 })
        #expect(Set(zip(p, p.dropFirst()).map { $1 - $0 }) == [PixelFlow.gap(20)])
    }

    @Test func homesFitTheGridAndOutsideDevicesStackOnTheRight() {
        let streams = [PowerStream(title: "USB", watts: 7), PowerStream(title: "SoC", watts: nil), PowerStream(title: "Charger loss", watts: 2)]
        let c = PixelFlow.columns(width: 340)
        let h = PixelFlow.homes(columns: c, streams: streams)
        #expect(Set(h.keys) == [.charger, .mac, .battery, .stream("USB"), .stream("Charger loss")])
        for p in h.values { #expect(p.x > 0 && p.x < c && p.y > 0 && p.y < PixelFlow.rows) }
        #expect(h[.stream("USB")]!.x > h[.mac]!.x && h[.stream("Charger loss")]!.y > h[.stream("USB")]!.y)
        // Alone, the charger, battery and Mac spread across the width, the battery between the other two.
        let alone = PixelFlow.homes(columns: c, streams: [])
        #expect(alone[.mac]!.x > c * 3 / 4 && alone[.charger]!.x < c / 4)
        #expect(alone[.battery]!.x > alone[.charger]!.x && alone[.battery]!.x < alone[.mac]!.x)
    }

    @Test func batteryCellsAndTheFontCoverWhatTheMapShows() {
        #expect(PixelFlow.cells(percent: 79) == 4 && PixelFlow.cells(percent: 100) == 5 && PixelFlow.cells(percent: 3) == 0)
        let lit = PixelFlow.batteryCells(5, at: PixelPoint(40, 40))
        #expect(lit.count == 40 && Set(lit.map(\.x)).count == 10) // five separate 2-wide cells
        #expect(lit.allSatisfy { $0.x > 40 - 9 && $0.x < 40 + 8 })   // inside the shell
        for ch in "CHARGER MAC HELD IDLE USB SOC OTHER LOSS MORE 0123456789.%+-W" { #expect(PixelFlow.glyphs[ch] != nil) }
        let t = PixelFlow.text("79.0%")
        #expect(t.width == 3 + 1 + 3 + 1 + 1 + 1 + 3 + 1 + 3 && t.cells.allSatisfy { $0.y >= 0 && $0.y < 5 })
    }

    @Test func zoomStepsBetweenTheEndsAndOddSavedValuesFallBackToTheDefault() {
        #expect(PixelFlow.zoom(3, by: 1) == 3.5 && PixelFlow.zoom(3, by: -1) == 2.5)
        #expect(PixelFlow.zoom(4, by: 1) == 4 && PixelFlow.zoom(2, by: -1) == 2)
        #expect(PixelFlow.zoom(7.3) == PixelFlow.cell && PixelFlow.zoom(7.3, by: 1) == 3.5)
        // Smaller cells mean more of them across the same panel, so everything draws smaller.
        #expect(PixelFlow.columns(width: 340, cell: 2) > PixelFlow.columns(width: 340, cell: 4))
    }

    @Test func draggedPlacesRoundTripAndStayInsideTheGrid() {
        let p = PixelPlaces([.charger: PixelPoint(10, 12), .stream("USB"): PixelPoint(90, 40)])
        #expect(PixelPlaces(json: p.json) == p)
        #expect(PixelPlaces().json == "" && PixelPlaces(json: "junk").isEmpty)
        let homes = PixelFlow.homes(columns: 100, streams: [])
        let far = PixelPlaces([.mac: PixelPoint(900, -50)]).resolved(homes: homes, columns: 100)
        #expect(far[.mac]!.x < 100 && far[.mac]!.y > 0 && far[.battery] == homes[.battery])
    }
}
