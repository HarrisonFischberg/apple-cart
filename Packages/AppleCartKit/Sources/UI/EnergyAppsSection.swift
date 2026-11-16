import Core
import SwiftUI

/// "Using the most energy": apps over the chosen CPU threshold.
struct EnergyAppsSection: View {
    let users: [EnergyUser]
    @AppStorage(EnergyThreshold.storageKey) private var thresholdRaw = EnergyThreshold.medium.rawValue
    @AppStorage(EnergyThreshold.backgroundKey) private var includeBackground = false

    var body: some View {
        let shown = EnergyApps.filter(users, threshold: EnergyThreshold(rawValue: thresholdRaw) ?? .medium, includeBackground: includeBackground)
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Using the most energy")
            if users.isEmpty {
                Text("Measuring…").hint()
            } else if shown.isEmpty {
                Text("No apps using significant energy").hint()
            }
            ForEach(shown) { u in
                HStack(spacing: 8) {
                    Text(u.name).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f%% CPU", u.cpu)).monospacedDigit().foregroundStyle(Palette.secondary)
                }
                .font(.callout)
            }
        }
    }
}
