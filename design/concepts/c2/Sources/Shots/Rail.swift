import SwiftUI

enum Tab: CaseIterable {
    case battery, system, clean, tools
    var title: String { ["Battery", "System", "Clean", "Clipboard & Tools"][Tab.allCases.firstIndex(of: self)!] }
    var short: String { ["Battery", "System", "Clean", "Tools"][Tab.allCases.firstIndex(of: self)!] }
    var symbol: String { ["battery.75percent", "cpu", "trash", "doc.on.clipboard"][Tab.allCases.firstIndex(of: self)!] }
}

struct Rail: View {
    @Binding var tab: Tab
    var body: some View {
        VStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                let on = t == tab
                Button { tab = t } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.symbol).font(.system(size: 18, weight: .regular)).frame(height: 22)
                        Text(t.short).font(hn(11, on))
                    }
                    .foregroundStyle(on ? T.onOrange : T.ink2)
                    .frame(width: 54, height: 52)
                    .background(on ? T.orange : .clear, in: RoundedRectangle(cornerRadius: T.radius))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer()
            Button { } label: {
                VStack(spacing: 3) {
                    Image(systemName: "gearshape").font(.system(size: 18)).frame(height: 22)
                    Text("Settings").font(hn(11))
                }
                .foregroundStyle(T.ink2).frame(width: 54, height: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.vertical, 12)
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .background(T.rail)
    }
}
