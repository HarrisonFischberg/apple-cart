import Core
import SwiftUI

public struct QuickTogglesView: View {
    let toggles: QuickToggles

    public init(toggles: QuickToggles) { self.toggles = toggles }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(QuickToggle.allCases.enumerated()), id: \.element) { i, t in
                        if i > 0 { Divider() }
                        HStack {
                            Label(t.title, systemImage: t.symbol).font(.system(size: 15))
                            Spacer()
                            Toggle(t.title, isOn: Binding(get: { toggles.states[t] ?? false }, set: { toggles.set(t, on: $0) }))
                                .toggleStyle(.switch).labelsHidden()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 14)
                    }
                }
                .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("Changing one restarts Finder or the Dock for a moment so it takes effect.").hint()
            }
            .toolPage()
        }
        .onAppear { toggles.refresh() }
    }
}

public struct VolumeGuardView: View {
    let guardTool: VolumeGuard
    @AppStorage("volumeGuard.max") private var maxPercent = 70

    public init(guardTool: VolumeGuard) { self.guardTool = guardTool }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        StatusText(guardTool.lastLowered.map { "Last time: lowered from \($0.from)% to \($0.to)%" } ?? "Capped at \(maxPercent)%")
                        Spacer()
                        Text("\(maxPercent)%").font(.callout).monospacedDigit().foregroundStyle(Palette.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    SectionLabel("Highest volume when the speaker changes")
                    Slider(value: Binding(get: { Double(maxPercent) }, set: { maxPercent = Int($0.rounded()) }), in: 10...100, step: 5)
                        .accessibilityLabel("Highest volume")
                    Text("When you plug in headphones or switch speakers, the volume is lowered to this if it was higher. It is never raised, and you can still turn it up afterwards.").hint()
                }
                .toolCard()
            }
            .toolPage()
        }
    }
}
