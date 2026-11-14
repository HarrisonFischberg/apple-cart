import SwiftUI
import ConceptShared

enum PanelTab: String, CaseIterable, Identifiable {
    case battery = "Battery", system = "System", clean = "Clean", tools = "Clipboard & Tools"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .battery: "battery.75percent"
        case .system: "cpu"
        case .clean: "trash"
        case .tools: "doc.on.clipboard"
        }
    }
}

struct PanelView: View {
    @State var tab: PanelTab

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .battery: BatteryTab()
                case .system: SystemTab()
                default: emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Rectangle().fill(T.hair).frame(height: 1)
            tabBar
        }
        .background(T.ground)
        .foregroundStyle(T.ink)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: tab.symbol).font(.system(size: 28, weight: .regular)).foregroundStyle(T.ink2)
            Text(tab.rawValue).font(.system(size: 14, weight: .semibold))
            Text("This tab is not drawn in the concept preview.").font(.system(size: 12)).foregroundStyle(T.ink2)
        }.frame(maxHeight: .infinity)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(PanelTab.allCases) { t in
                Button { tab = t } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.symbol).font(.system(size: 16, weight: .regular)).frame(height: 20)
                        Text(t.rawValue).font(.system(size: 11, weight: t == tab ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .foregroundStyle(t == tab ? T.blueText : T.ink2)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t == tab ? T.blueFill.opacity(0.14) : .clear))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(t.rawValue)
                .accessibilityAddTraits(t == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }
}

/// Menu bar item: small battery glyph with the limit tick, then the readout.
struct StatusItemView: View {
    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5).strokeBorder(lineWidth: 1.1).frame(width: 21, height: 10)
                RoundedRectangle(cornerRadius: 1).frame(width: 17 * CGFloat(Mock.percent / 100), height: 6).padding(.leading, 2)
                Rectangle().fill(T.purple).frame(width: 1.6, height: 12).offset(x: 2 + 17 * CGFloat(Mock.limit) / 100)
            }
            .frame(width: 23, height: 12)
            Text("\(Int(Mock.percent))%").font(T.num(14, .semibold)).monospacedDigit()
        }
        .accessibilityLabel("Battery \(Int(Mock.percent)) percent")
    }
}
