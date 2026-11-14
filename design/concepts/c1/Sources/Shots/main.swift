import SwiftUI
import AppKit
import ConceptShared

@MainActor func shot(_ name: String, _ tab: Tab, _ a: ShotAppearance, height: CGFloat) -> Shot {
    let panel = CGSize(width: 360, height: height)
    return Shot(name: name, size: ShotFrame<StatusItem, PanelView>.canvas(for: panel), appearance: a,
                view: AnyView(ShotFrame(panelSize: panel, appearance: a) { StatusItem() } panel: { PanelView(tab: tab) }))
}

MainActor.assumeIsolated {
    ShotRenderer.run([
        shot("c1-battery-light", .battery, .light, height: 830),
        shot("c1-battery-dark", .battery, .dark, height: 830),
        shot("c1-system-light", .system, .light, height: 880),
        shot("c1-system-dark", .system, .dark, height: 880)
    ], outDir: ShotRenderer.outDir(from: CommandLine.arguments))
}
