import SwiftUI
import AppKit
import ConceptShared

MainActor.assumeIsolated {
    let size = CGSize(width: 400, height: 680)
    func shot(_ name: String, _ tab: PanelTab, _ ap: ShotAppearance) -> Shot {
        Shot(name: name, size: ShotFrame<StatusItemView, PanelView>.canvas(for: size), appearance: ap,
             view: AnyView(ShotFrame(panelSize: size, appearance: ap, statusItem: { StatusItemView() }) {
                 PanelView(tab: tab)
             }))
    }
    ShotRenderer.run([
        shot("c3-battery-light", .battery, .light), shot("c3-battery-dark", .battery, .dark),
        shot("c3-system-light", .system, .light), shot("c3-system-dark", .system, .dark),
    ], outDir: ShotRenderer.outDir(from: CommandLine.arguments))
}
