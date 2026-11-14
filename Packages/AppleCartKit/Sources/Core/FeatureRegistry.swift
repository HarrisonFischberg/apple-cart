import Observation

/// A tool owns timers, observers and system hooks. `stop()` must cancel all of them.
@MainActor
public protocol Tool: AnyObject {
    func start()
    func stop()
}

/// Every tool is off until the user turns it on. Turning one off stops it and releases it,
/// so a tool that is off costs nothing (blueprint section 5, "Unload rule").
@MainActor @Observable
public final class FeatureRegistry {
    public private(set) var enabled: Set<FeatureID>

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private var factories: [FeatureID: @MainActor () -> any Tool] = [:]
    @ObservationIgnored private var active: [FeatureID: any Tool] = [:]

    public init(store: SettingsStore) {
        self.store = store
        self.enabled = store.enabledFeatures()
    }

    /// Makes a tool available. If the user already had it on, it starts now (relaunch).
    public func register(_ id: FeatureID, factory: @escaping @MainActor () -> any Tool) {
        factories[id] = factory
        if enabled.contains(id) { activate(id) }
    }

    public func isAvailable(_ id: FeatureID) -> Bool { factories[id] != nil }
    public func isEnabled(_ id: FeatureID) -> Bool { enabled.contains(id) }
    public func isActive(_ id: FeatureID) -> Bool { active[id] != nil }

    /// Turning on a tool that is not built yet is ignored, so it can never start by surprise later.
    public func setEnabled(_ on: Bool, for id: FeatureID) {
        if on {
            guard isAvailable(id) else { return }
            enabled.insert(id)
            activate(id)
        } else {
            enabled.remove(id)
            deactivate(id)
        }
        store.setEnabledFeatures(enabled)
    }

    private func activate(_ id: FeatureID) {
        guard active[id] == nil, let make = factories[id] else { return }
        let tool = make()
        active[id] = tool
        tool.start()
    }

    private func deactivate(_ id: FeatureID) {
        active.removeValue(forKey: id)?.stop()
    }
}
