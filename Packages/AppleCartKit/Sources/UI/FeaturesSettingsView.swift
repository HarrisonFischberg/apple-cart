import Core
import SwiftUI

/// Settings > Features (recon screen S06): one switch per tool, grouped by family.
public struct FeaturesSettingsView: View {
    private let registry: FeatureRegistry

    public init(registry: FeatureRegistry) { self.registry = registry }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Every tool is off until you turn it on. A tool that is off does nothing and uses nothing.").hint()
                ForEach(FeatureFamily.allCases, id: \.self) { family in
                    SectionLabel(family.title)
                    VStack(spacing: 0) {
                        ForEach(Array(family.features.enumerated()), id: \.element) { i, id in
                            if i > 0 { Divider() }
                            row(id).padding(.horizontal, 14)
                        }
                    }
                    .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .toolPage()
        }
        .background(Palette.ground)
    }

    private func row(_ id: FeatureID) -> some View {
        let available = registry.isAvailable(id)
        return Toggle(isOn: Binding(
            get: { registry.isEnabled(id) },
            set: { registry.setEnabled($0, for: id) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(id.title)
                if !available {
                    Text("Not built yet")
                        .font(.caption)
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(Palette.accent)
        .frame(minHeight: 44)
        .disabled(!available)
    }
}
