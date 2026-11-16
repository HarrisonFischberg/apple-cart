import Observation

public enum GridDirection: Sendable { case left, right, up, down }

/// What the launcher shows: the tools that are on, minus hidden ones, in the user's order.
@MainActor @Observable
public final class LauncherModel {
    public var searchText = ""
    public private(set) var order: [FeatureID]
    public private(set) var hidden: Set<FeatureID>

    @ObservationIgnored private let registry: FeatureRegistry
    @ObservationIgnored private let store: SettingsStore

    public init(registry: FeatureRegistry, store: SettingsStore) {
        self.registry = registry
        self.store = store
        self.order = store.launcherOrder()
        self.hidden = store.hiddenFeatures()
    }

    /// Saved order first, then any tool not seen yet in the default order.
    private var fullOrder: [FeatureID] {
        order + FeatureID.allCases.filter { !order.contains($0) }
    }

    /// Tools on and not hidden, in order, ignoring the search.
    public var allTiles: [FeatureID] {
        fullOrder.filter { registry.isEnabled($0) && !hidden.contains($0) }
    }

    public var tiles: [FeatureID] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allTiles }
        return allTiles.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    public var hiddenCount: Int { fullOrder.filter { registry.isEnabled($0) && hidden.contains($0) }.count }
    public var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Puts `id` just before `target`. Does nothing while a search is filtering the grid.
    public func move(_ id: FeatureID, before target: FeatureID) {
        guard !isSearching, id != target else { return }
        var list = fullOrder
        list.removeAll { $0 == id }
        let at = list.firstIndex(of: target) ?? list.endIndex
        list.insert(id, at: at)
        order = list
        store.setLauncherOrder(list)
    }

    public func hide(_ id: FeatureID) {
        hidden.insert(id)
        store.setHiddenFeatures(hidden)
    }

    public func showAllHidden() {
        hidden = []
        store.setHiddenFeatures(hidden)
    }

    /// Arrow-key neighbour in a grid of `columns` columns; nil at an edge.
    public func neighbor(of id: FeatureID, columns: Int, _ direction: GridDirection) -> FeatureID? {
        let list = tiles
        guard let i = list.firstIndex(of: id), columns > 0 else { return nil }
        let target: Int
        switch direction {
        case .left: target = i % columns == 0 ? -1 : i - 1
        case .right: target = (i % columns == columns - 1) ? -1 : i + 1
        case .up: target = i - columns
        case .down: target = i + columns
        }
        return list.indices.contains(target) ? list[target] : nil
    }
}

/// True while the owner drags the panel's edge; animated views hold still until it ends.
@MainActor @Observable
public final class LiveResize {
    public static let shared = LiveResize()
    public var active = false
    public init() {}
}

/// Where the panel is: launcher (route nil) or a tool's view. Resets when it closes, unless kept open.
@MainActor @Observable
public final class PanelModel {
    public private(set) var route: FeatureID?
    public var keepOpen = false
    /// True while the window is on screen; tool views use it to stop work when hidden.
    public var isOpen = false
    /// The window is in its large size (the Expand button's state).
    public var expanded = false

    public init() {}

    public func open(_ id: FeatureID) { route = id }
    public func back() { route = nil }

    public func panelDidClose(launcher: LauncherModel) {
        isOpen = false
        launcher.searchText = ""
        if !keepOpen { route = nil }
    }
}
