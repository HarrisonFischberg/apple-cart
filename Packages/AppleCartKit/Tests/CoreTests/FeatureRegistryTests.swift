import Foundation
import Testing
@testable import Core

@MainActor
@Suite struct FeatureRegistryTests {
    @Test func everythingIsOffByDefault() {
        let registry = FeatureRegistry(store: MemoryStore())
        #expect(registry.enabled.isEmpty)
        #expect(FeatureID.allCases.allSatisfy { !registry.isEnabled($0) && !registry.isActive($0) })
    }

    @Test func enablingStartsTheToolOnceAndDisablingStopsAndReleasesIt() async {
        let registry = FeatureRegistry(store: MemoryStore())
        weak var weakTool: FakeTool?
        var strongForTest: FakeTool?
        registry.register(.battery) {
            let t = FakeTool(); weakTool = t; strongForTest = t; return t
        }
        registry.setEnabled(true, for: .battery)
        registry.setEnabled(true, for: .battery) // second tap must not create a second instance
        #expect(strongForTest!.started == 1)
        #expect(registry.isActive(.battery))
        let ticker = strongForTest!.ticker!

        registry.setEnabled(false, for: .battery)
        #expect(strongForTest!.stopped == 1)
        #expect(ticker.isCancelled)
        #expect(!registry.isActive(.battery))

        strongForTest = nil
        #expect(weakTool == nil, "a switched-off tool must be released")
    }

    @Test func choicesSurviveRelaunchAndRestartTheTool() {
        let store = MemoryStore()
        let first = FeatureRegistry(store: store)
        first.register(.system) { FakeTool() }
        first.setEnabled(true, for: .system)

        let relaunched = FeatureRegistry(store: store)
        #expect(relaunched.isEnabled(.system))
        #expect(!relaunched.isActive(.system)) // not available until the tool is registered
        var created = 0
        relaunched.register(.system) { created += 1; return FakeTool() }
        #expect(created == 1)
        #expect(relaunched.isActive(.system))
    }

    @Test func aToolThatIsNotBuiltCannotBeSwitchedOn() {
        let store = MemoryStore()
        let registry = FeatureRegistry(store: store)
        registry.setEnabled(true, for: .fanSafeMode)
        #expect(!registry.isEnabled(.fanSafeMode))
        #expect(store.ids.isEmpty)
        // And it must not start by surprise once the tool exists.
        var created = 0
        registry.register(.fanSafeMode) { created += 1; return FakeTool() }
        #expect(created == 0)
    }

    @Test func userDefaultsStoreDropsUnknownIdsAndRoundTrips() {
        let suite = "applecart.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["battery", "notAToolAnymore"], forKey: "enabledFeatures")
        let store = UserDefaultsSettingsStore(defaults: defaults)
        #expect(store.enabledFeatures() == [.battery])
        store.setEnabledFeatures([.clipboard, .system])
        #expect(UserDefaultsSettingsStore(defaults: defaults).enabledFeatures() == [.clipboard, .system])
    }

    @Test func everyToolBelongsToExactlyOneFamily() {
        let grouped = FeatureFamily.allCases.flatMap(\.features)
        #expect(grouped.count == FeatureID.allCases.count)
        #expect(Set(grouped) == Set(FeatureID.allCases))
    }
}
