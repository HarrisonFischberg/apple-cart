import SwiftUI
import ConceptShared

enum Tab: Int, CaseIterable {
    case battery, system, clean, tools
    var title: String { ["Battery", "System", "Clean", "Clipboard & Tools"][rawValue] }
    var icon: String { ["battery.75percent", "cpu", "trash", "doc.on.clipboard"][rawValue] }
}

struct PanelView: View {
    @State var tab: Tab

    var body: some View {
        VStack(spacing: 0) {
            strip
            Group {
                switch tab {
                case .battery: BatteryTab()
                case .system: SystemTab()
                default: empty
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .fillPanel(T.ground)
        .background(T.ground)
    }

    private var strip: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.rawValue) { t in
                let on = t == tab
                Button { tab = t } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.icon).font(.system(size: 16, weight: .medium)).frame(height: 20)
                        Text(t.title).font(.system(size: 11, weight: .semibold))
                            .multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
                    }
                    .foregroundStyle(on ? T.yellow : T.onYellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? T.onYellow : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(T.yellow)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: tab.icon).font(.system(size: 28)).foregroundStyle(T.ink2)
            Text("\(tab.title) is not part of this preview").font(T.label).foregroundStyle(T.ink)
        }
        .padding(.top, 120)
    }
}

struct StatusItem: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "battery.75percent").font(.system(size: 13, weight: .medium))
            Text("\(Int(Mock.percent))%").font(T.din(15))
        }
        .foregroundStyle(T.onYellow)
        .padding(.horizontal, 6).padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 5).fill(T.yellow))
        .accessibilityLabel("Battery \(Int(Mock.percent)) percent, charging paused by heat")
    }
}
