import Core
import SwiftUI

/// Settings > Features (recon screen S06): one switch per tool, grouped by family.
public struct FeaturesSettingsView: View {
    private let registry: FeatureRegistry

    public init(registry: FeatureRegistry) { self.registry = registry }

    public var body: some View {
        Form {
            Section {
                Text("Every tool is off until you turn it on. A tool that is off does nothing and uses nothing.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondary)
            }
            ForEach(FeatureFamily.allCases, id: \.self) { family in
                Section(family.title) {
                    ForEach(family.features, id: \.self) { id in row(id) }
                }
            }
        }
        .formStyle(.grouped)
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
        .disabled(!available)
    }
}
