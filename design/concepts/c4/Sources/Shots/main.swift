import SwiftUI
import ConceptShared

struct StatusItemView: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "battery.75percent").font(.system(size: 14, weight: .medium))
            Text("\(Int(Mock.percent))%").font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor func shot(_ name: String, _ route: Route, _ h: CGFloat, _ a: ShotAppearance) -> Shot {
    let panel = CGSize(width: T.panelW, height: h)
    return Shot(name: "c4-\(name)-\(a.rawValue)", size: ShotFrame<StatusItemView, PanelView>.canvas(for: panel), appearance: a,
                view: AnyView(ShotFrame(panelSize: panel, appearance: a, statusItem: { StatusItemView() }, panel: { PanelView(route: route) })
                    .environment(\.colorScheme, a == .dark ? .dark : .light)))
}

@MainActor func run() {
    var shots: [Shot] = []
    for a in ShotAppearance.allCases {
        shots.append(shot("home", .home, LauncherView.height, a))
        shots.append(shot("battery", .battery, BatteryView.height, a))
        shots.append(shot("system", .system, SystemView.height, a))
    }
    ShotRenderer.run(shots, outDir: ShotRenderer.outDir(from: CommandLine.arguments))
}
MainActor.assumeIsolated { run() }
