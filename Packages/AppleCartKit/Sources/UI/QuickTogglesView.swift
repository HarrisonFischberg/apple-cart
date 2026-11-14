import Core
import SwiftUI

public struct QuickTogglesView: View {
    let toggles: QuickToggles

    public init(toggles: QuickToggles) { self.toggles = toggles }

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(QuickToggle.allCases.enumerated()), id: \.element) { i, t in
                        if i > 0 { Divider() }
                        Toggle(isOn: Binding(get: { toggles.states[t] ?? false }, set: { toggles.set(t, on: $0) })) {
                            Label(t.title, systemImage: t.symbol)
                        }
                        .toggleStyle(.switch)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 14)
                    }
                }
                .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("Changing one restarts Finder or the Dock for a moment so it takes effect.")
                    .font(.callout).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
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
                VStack(alignment: .leading, spacing: 10) {
                    Text("Highest volume when the speaker changes").font(.headline)
                    HStack {
                        Slider(value: Binding(get: { Double(maxPercent) }, set: { maxPercent = Int($0.rounded()) }), in: 10...100, step: 5)
                            .accessibilityLabel("Highest volume")
                        Text("\(maxPercent)%").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                    Text("When you plug in headphones or switch speakers, the volume is lowered to this if it was higher. It is never raised, and you can still turn it up afterwards.")
                        .font(.callout).foregroundStyle(Palette.secondary)
                }
                .padding(14)
                .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if let l = guardTool.lastLowered {
                    Text("Last time: lowered from \(l.from)% to \(l.to)%.").font(.callout).foregroundStyle(Palette.secondary)
                }
            }
            .padding(16)
        }
    }
}
