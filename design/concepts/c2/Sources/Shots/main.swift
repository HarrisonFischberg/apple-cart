import SwiftUI
import ConceptShared

let panel = CGSize(width: 460, height: 600)

func shot(_ name: String, _ tab: Tab, _ a: ShotAppearance) -> Shot {
    Shot(name: name,
         size: ShotFrame<StatusItemView, PanelView>.canvas(for: panel),
         appearance: a,
         view: AnyView(ShotFrame(panelSize: panel, appearance: a, statusItem: { StatusItemView() }, panel: { PanelView(initialTab: tab) })))
}

MainActor.assumeIsolated {
ShotRenderer.run([
        shot("c2-battery-light", .battery, .light),
        shot("c2-battery-dark", .battery, .dark),
        shot("c2-system-light", .system, .light),
        shot("c2-system-dark", .system, .dark),
    ], outDir: ShotRenderer.outDir(from: CommandLine.arguments))
}
