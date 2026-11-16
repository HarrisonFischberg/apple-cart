import AppKit
import Core
import SwiftUI

/// "Using significant energy": apps over the chosen CPU threshold, in a raised card with each app's icon.
struct EnergyAppsSection: View {
    let users: [EnergyUser]
    @AppStorage(EnergyThreshold.storageKey) private var thresholdRaw = EnergyThreshold.medium.rawValue
    @AppStorage(EnergyThreshold.backgroundKey) private var includeBackground = false

    var body: some View {
        let shown = EnergyApps.filter(users, threshold: EnergyThreshold(rawValue: thresholdRaw) ?? .medium, includeBackground: includeBackground)
        VStack(alignment: .leading, spacing: 10) {
            Text("Using significant energy").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary)
                .accessibilityAddTraits(.isHeader)
            if users.isEmpty {
                Text("Measuring…").hint()
            } else if shown.isEmpty {
                Text("No apps using significant energy").hint()
            }
            ForEach(shown) { u in
                HStack(spacing: 10) {
                    icon(u)
                    Text(u.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f%% CPU", u.cpu)).font(.callout).monospacedDigit().foregroundStyle(Palette.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.12)))
    }

    /// The running app's own icon; helpers and bare processes get a generic one.
    @ViewBuilder private func icon(_ u: EnergyUser) -> some View {
        if let image = NSRunningApplication(processIdentifier: pid_t(u.pid))?.icon {
            Image(nsImage: image).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
        } else {
            Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                .frame(width: 28, height: 28).accessibilityHidden(true)
        }
    }
}
