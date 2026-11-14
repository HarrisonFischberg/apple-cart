import SwiftUI
import ConceptShared

struct PanelView: View {
    @State private var tab: Tab
    init(initialTab: Tab) { _tab = State(initialValue: initialTab) }

    var body: some View {
        HStack(spacing: 0) {
            Rail(tab: $tab)
            VHair()
            Group {
                switch tab {
                case .battery: BatteryTab()
                case .system: SystemTab()
                default: empty
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(T.bg)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: tab.symbol).font(.system(size: 22)).foregroundStyle(T.ink2)
            Text("\(tab.title) is not part of this preview.").font(hn(13)).foregroundStyle(T.ink)
            Text("Battery and System show the full layout.").font(hn(12)).foregroundStyle(T.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatusItemView: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "battery.75percent").font(.system(size: 14))
            Text("\(Int(Mock.percent))%").font(hn(13, true)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
