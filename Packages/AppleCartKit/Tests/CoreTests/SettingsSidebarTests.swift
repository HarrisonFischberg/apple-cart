import Foundation
import Testing
@testable import Core

@Suite struct SettingsSidebarTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "settings-sidebar-" + UUID().uuidString)! }

    @Test func everyToolAppearsOnceExceptNotifications() {
        let tools = SettingsSidebar.pages.compactMap { page -> FeatureID? in if case .tool(let f) = page { f } else { nil } }
        #expect(Set(tools).count == tools.count)
        #expect(Set(tools) == Set(FeatureID.allCases).subtracting([.notifications]))
    }

    @Test func pageIDsAreUniqueAndRoundTrip() {
        let ids = SettingsSidebar.pages.map(\.id)
        #expect(Set(ids).count == ids.count)
        for p in SettingsSidebar.pages { #expect(SettingsPage(id: p.id) == p) }
    }

    @Test func groupOrderAndHeadings() {
        #expect(SettingsSidebar.groups.map(\.title) == ["General", "Battery", "System", "Clean", "Clipboard", "Screen", "Wellness", "About"])
        #expect(SettingsSidebar.groups[0].pages == [.general, .menuBar, .permissions])
    }

    @Test func selectionDefaultsToGeneralAndIsRemembered() {
        let d = defaults()
        let s = SettingsSelection(defaults: d)
        #expect(s.load() == .general)
        s.save(.tool(.keepAwake))
        #expect(SettingsSelection(defaults: d).load() == .tool(.keepAwake))
    }

    @Test func unknownSavedPageFallsBackToGeneral() {
        let d = defaults()
        d.set("tool.gone", forKey: "settings.page")
        #expect(SettingsSelection(defaults: d).load() == .general)
        d.set("tool.notifications", forKey: "settings.page") // real id, but not in the sidebar
        #expect(SettingsSelection(defaults: d).load() == .general)
    }
}
