import Foundation
import Testing
@testable import Core

@Suite struct EnergyAppsTests {
    private let users = [
        EnergyUser(pid: 1, name: "Big", cpu: 80, isApp: true), EnergyUser(pid: 2, name: "Mid", cpu: 25, isApp: true),
        EnergyUser(pid: 3, name: "Small", cpu: 6, isApp: true), EnergyUser(pid: 4, name: "WindowServer", cpu: 50),
        EnergyUser(pid: 5, name: "Tiny", cpu: 1, isApp: true),
    ]

    @Test func thresholdsChooseWhichAppsAreListed() {
        func names(_ t: EnergyThreshold, bg: Bool = false) -> [String] { EnergyApps.filter(users, threshold: t, includeBackground: bg).map(\.name) }
        #expect(names(.low) == ["Big", "Mid", "Small"])
        #expect(names(.medium) == ["Big", "Mid"])
        #expect(names(.high) == ["Big"])
        #expect(EnergyThreshold.medium.cpuPercent == 20)
    }

    @Test func backgroundProcessesOnlyWhenAsked() {
        #expect(EnergyApps.filter(users, threshold: .medium, includeBackground: true).map(\.name) == ["Big", "WindowServer", "Mid"])
        #expect(EnergyApps.filter(users, threshold: .medium, includeBackground: false).contains { $0.name == "WindowServer" } == false)
    }

    @Test func listStaysCompactAndCanBeEmpty() {
        let many = (0..<9).map { EnergyUser(pid: $0, name: "A\($0)", cpu: 90, isApp: true) }
        #expect(EnergyApps.filter(many, threshold: .low, includeBackground: false).count == 5)
        #expect(EnergyApps.filter(users, threshold: .high, includeBackground: false, limit: 5).count == 1)
        #expect(EnergyApps.filter([], threshold: .low, includeBackground: true).isEmpty)
    }

    @Test func parseMarksBundledAppsAndNeverQuitList() {
        let u = EnergyUsers.parse("10 50.0 /Applications/Foo.app/Contents/MacOS/Foo\n12 70.0 /usr/sbin/WindowServer")
        #expect(u.first { $0.name == "Foo" }?.isApp == true && u.first { $0.name == "WindowServer" }?.isApp == false)
        #expect(EnergyApps.neverQuit(bundleID: "com.apple.finder"))
        #expect(EnergyApps.neverQuit(bundleID: "com.apple.dock"))
        #expect(EnergyApps.neverQuit(bundleID: "app.me.cart", ownBundleID: "app.me.cart"))
        #expect(EnergyApps.neverQuit(bundleID: nil))
        #expect(!EnergyApps.neverQuit(bundleID: "com.foo.bar", ownBundleID: "app.me.cart"))
    }
}
