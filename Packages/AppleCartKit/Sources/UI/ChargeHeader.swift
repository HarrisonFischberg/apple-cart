import Core
import SwiftUI

/// Top row of the panel while Battery is on: Limit on the left, Top Up and Settings on the right.
struct ChargeHeader: View {
    let settings: ChargeLimitSettings
    let limiter: ChargeLimiter?
    let openSettings: () -> Void
    @State private var showLimit = false

    var body: some View {
        let state = limiter?.state ?? ChargeLimitState()
        VStack(spacing: 0) {
            row
            if state.chargingNotResumed || (settings.topUpActive && state.helperStatus != .ready) {
                Label(state.reasonText, systemImage: state.chargingNotResumed ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 6).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            pill("Limit \(settings.limit)%", symbol: nil, selected: false) { showLimit = true }
                .accessibilityLabel("Charge limit")
                .accessibilityValue("\(settings.limit) percent")
                .accessibilityHint("Choose the highest charge level")
                .popover(isPresented: $showLimit, arrowEdge: .bottom) {
                    LimitPopover(settings: settings, limiter: limiter)
                }
            Spacer(minLength: 0)
            pill(settings.topUpActive ? "Topping up" : "Top Up", symbol: settings.topUpActive ? "bolt.fill" : "plus.circle", selected: settings.topUpActive) {
                settings.setTopUp(!settings.topUpActive)
                Task { await limiter?.reevaluate() }
            }
            .disabled(settings.limit >= 100 && !settings.topUpActive)
            .accessibilityLabel("Top Up to 100 percent")
            .accessibilityValue(settings.topUpActive ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            .help(settings.limit >= 100 ? "The limit is already 100%" : "Charge to 100% this time, then go back to the limit")
            SettingsGlyphButton(action: openSettings)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    private func pill(_ title: String, symbol: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).monospacedDigit().lineLimit(1)
                if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .medium)) }
            }
            .font(.system(size: 14, weight: .semibold))
            // A symbol marks an action pill (Top Up): its label takes the control blue, as in the owner's target.
            .foregroundStyle(selected || symbol != nil ? Palette.accent : Color.primary)
            .padding(.horizontal, 14).frame(height: 32)
            // Selected (Top Up on) is a blue tint, not a solid fill, so the label keeps the same blue.
            .background(selected ? Palette.accent.opacity(0.18) : Palette.tile, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Palette.accent.opacity(0.6) : .primary.opacity(0.12)))
            .frame(minHeight: 44) // 44 pt target around the 32 pt pill
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFade())
    }
}

struct SettingsGlyphButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "square.grid.2x2").font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .frame(width: 32, height: 32)
                .background(Palette.tile, in: Circle())
                .overlay(Circle().strokeBorder(.primary.opacity(0.08)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFade())
        .accessibilityLabel("Settings")
        .help("Settings")
    }
}

private struct PressFade: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(!enabled ? 0.45 : configuration.isPressed ? 0.6 : 1)
    }
}

/// Chips for the upper charge limit, Sailing mode, plus one honest caption from the runner's confirmed state.
struct LimitPopover: View {
    let settings: ChargeLimitSettings
    let limiter: ChargeLimiter?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stop charging at").font(.system(size: 13, weight: .semibold))
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ChargeLimitSettings.choices, id: \.self) { p in
                    Button("\(p)%") { settings.setLimit(p); Task { await limiter?.reevaluate() } }
                        .buttonStyle(ChipStyle(selected: settings.limit == p))
                        .accessibilityLabel("\(p) percent")
                        .accessibilityAddTraits(settings.limit == p ? .isSelected : [])
                }
            }
            let state = limiter?.state ?? ChargeLimitState()
            Toggle("Automatic discharge", isOn: Binding(get: { settings.autoDischarge }, set: { settings.setAutoDischarge($0); Task { await limiter?.reevaluate() } }))
                .toggleStyle(.switch).font(.system(size: 13))
            Toggle("Sailing mode", isOn: Binding(get: { settings.sailing }, set: { settings.setSailing($0); Task { await limiter?.reevaluate() } }))
                .toggleStyle(.switch).font(.system(size: 13))
                .help("After reaching the limit, let the battery drop by the difference before charging again")
            if settings.sailing {
                Stepper(value: Binding(get: { settings.sailingDifference }, set: { settings.setSailingDifference($0); Task { await limiter?.reevaluate() } }),
                        in: ChargeLimitSettings.sailingRange) {
                    Text("Difference \(settings.sailingDifference)%").font(.system(size: 13)).monospacedDigit()
                }
                .accessibilityValue("\(settings.sailingDifference) percent")
                Text(settings.topUpActive ? "Off while Top Up runs." : "Will sail to \(settings.sailFloor)%").hint()
            }
            // Reference behavior: the Discharge button is hidden while Automatic Discharge is on.
            if !settings.autoDischarge, state.helperStatus == .ready, settings.dischargeActive || (state.level ?? 0) > settings.effectiveLimit {
                Button(settings.dischargeActive ? "Stop discharging" : "Discharge to \(settings.limit)%") {
                    settings.setDischarge(!settings.dischargeActive)
                    Task { await limiter?.reevaluate() }
                }
                .buttonStyle(ChipStyle(selected: settings.dischargeActive))
            }
            Text(state.reasonText)
                .font(.callout).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            if settings.topUpActive && state.helperStatus != .ready {
                Text("Top Up is on. It takes effect once the helper is ready.").hint().fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14).frame(width: 240)
    }
}
