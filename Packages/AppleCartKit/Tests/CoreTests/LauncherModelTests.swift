import Testing
@testable import Core

@MainActor
private func make(enabled: [FeatureID], store: MemoryStore = MemoryStore()) -> (LauncherModel, FeatureRegistry, MemoryStore) {
    store.ids = Set(enabled)
    let registry = FeatureRegistry(store: store)
    for id in FeatureID.allCases { registry.register(id) { FakeTool() } }
    return (LauncherModel(registry: registry, store: store), registry, store)
}

@MainActor
@Suite struct LauncherModelTests {
    @Test func showsOnlyToolsThatAreOnInDefaultOrder() {
        let (launcher, _, _) = make(enabled: [.clipboard, .battery, .system])
        #expect(launcher.tiles == [.battery, .system, .clipboard])
        let (empty, _, _) = make(enabled: [])
        #expect(empty.tiles.isEmpty)
    }

    @Test func reorderPersistsAcrossRelaunch() {
        let (launcher, _, store) = make(enabled: [.battery, .system, .clipboard])
        launcher.move(.clipboard, before: .battery)
        #expect(launcher.tiles == [.clipboard, .battery, .system])

        let (relaunched, _, _) = make(enabled: [.battery, .system, .clipboard], store: store)
        #expect(relaunched.tiles == [.clipboard, .battery, .system])
    }

    @Test func aToolTurnedOnLaterTakesItsSavedPosition() {
        let (launcher, registry, _) = make(enabled: [.battery, .system])
        launcher.move(.keepAwake, before: .battery)
        registry.setEnabled(true, for: .keepAwake)
        #expect(launcher.tiles == [.keepAwake, .battery, .system])
    }

    @Test func hidingRemovesTheTileAndPersistsUntilShown() {
        let (launcher, _, store) = make(enabled: [.battery, .system])
        launcher.hide(.system)
        #expect(launcher.tiles == [.battery])
        #expect(launcher.hiddenCount == 1)
        let (relaunched, _, _) = make(enabled: [.battery, .system], store: store)
        #expect(relaunched.tiles == [.battery])
        relaunched.showAllHidden()
        #expect(relaunched.tiles == [.battery, .system])
    }

    @Test func searchFiltersByTitleAndBlocksReordering() {
        let (launcher, _, _) = make(enabled: [.battery, .system, .clipboard, .copyText])
        launcher.searchText = "CLIP"
        #expect(launcher.tiles == [.clipboard])
        launcher.searchText = "zzz"
        #expect(launcher.tiles.isEmpty)
        launcher.searchText = "c"
        let before = launcher.order
        launcher.move(.battery, before: .system)
        #expect(launcher.order == before)
    }

    @Test func arrowNavigationStaysInsideTheGrid() {
        let (launcher, _, _) = make(enabled: [.battery, .system, .keepAwake, .clipboard, .copyText])
        // Four columns: battery system keepAwake clipboard / copyText
        #expect(launcher.neighbor(of: .battery, columns: 4, .right) == .system)
        #expect(launcher.neighbor(of: .battery, columns: 4, .left) == nil)
        #expect(launcher.neighbor(of: .clipboard, columns: 4, .right) == nil)
        #expect(launcher.neighbor(of: .battery, columns: 4, .down) == .copyText)
        #expect(launcher.neighbor(of: .system, columns: 4, .down) == nil)
        #expect(launcher.neighbor(of: .copyText, columns: 4, .up) == .battery)
    }

    @Test func closingTheLauncherResetsSearchAndRouteUnlessKeptOpen() {
        let (launcher, _, _) = make(enabled: [.battery])
        let panel = PanelModel()
        panel.open(.battery)
        launcher.searchText = "bat"
        panel.panelDidClose(launcher: launcher)
        #expect(panel.route == nil)
        #expect(launcher.searchText.isEmpty)

        panel.keepOpen = true
        panel.open(.battery)
        panel.panelDidClose(launcher: launcher)
        #expect(panel.route == .battery)
    }
}
