import Foundation

/// Where the on/off choices live. A protocol so tests can use an isolated store.
public protocol SettingsStore: AnyObject {
    func enabledFeatures() -> Set<FeatureID>
    func setEnabledFeatures(_ ids: Set<FeatureID>)
}

public final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults
    private let key = "enabledFeatures"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func enabledFeatures() -> Set<FeatureID> {
        // Unknown ids (from a newer or older build) are dropped, never trusted.
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(FeatureID.init(rawValue:)))
    }

    public func setEnabledFeatures(_ ids: Set<FeatureID>) {
        defaults.set(ids.map(\.rawValue).sorted(), forKey: key)
    }
}
