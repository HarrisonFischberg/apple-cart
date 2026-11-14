import SwiftUI

enum Route { case home, battery, system
    var title: String { switch self { case .home: "Tools"; case .battery: "Battery"; case .system: "System" } }
}

struct PanelView: View {
    @State var route: Route
    @State private var searching = false
    @State private var query = ""
    var body: some View {
        VStack(spacing: 0) {
            Header(title: route.title, showBack: route != .home, onBack: { route = .home; searching = false; query = "" },
                   searching: $searching, query: $query)
            switch route {
            case .home: LauncherView(query: query) { name in
                if name == "Battery" { route = .battery } else if name == "System" { route = .system } }
            case .battery: BatteryView()
            case .system: SystemView()
            }
        }
        .fillPanel(T.ground)
    }
}
