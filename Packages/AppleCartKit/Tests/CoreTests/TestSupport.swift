import Foundation
@testable import Core

@MainActor
final class FakeTool: Tool {
    var started = 0
    var stopped = 0
    var ticker: Task<Void, Never>?

    func start() {
        started += 1
        ticker = Task { while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) } }
    }

    func stop() {
        stopped += 1
        ticker?.cancel()
    }
}

final class MemoryStore: SettingsStore {
    var ids: Set<FeatureID> = []
    var order: [FeatureID] = []
    var hidden: Set<FeatureID> = []
    func enabledFeatures() -> Set<FeatureID> { ids }
    func setEnabledFeatures(_ ids: Set<FeatureID>) { self.ids = ids }
    func launcherOrder() -> [FeatureID] { order }
    func setLauncherOrder(_ ids: [FeatureID]) { order = ids }
    func hiddenFeatures() -> Set<FeatureID> { hidden }
    func setHiddenFeatures(_ ids: Set<FeatureID>) { hidden = ids }
}
