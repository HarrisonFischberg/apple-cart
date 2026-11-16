import Core
import SwiftUI

private let presets: [(label: String, spoken: String, seconds: TimeInterval?)] = [
    ("15m", "15 minutes", 900), ("30m", "30 minutes", 1800), ("1h", "1 hour", 3600), ("2h", "2 hours", 7200),
    ("4h", "4 hours", 14400), ("8h", "8 hours", 28800), ("\u{221E}", "until I stop", nil),
]

public struct KeepAwakeView: View {
    let keepAwake: KeepAwake
    @AppStorage("keepAwake.customAmount") private var customAmount = 45
    @AppStorage("keepAwake.customHours") private var customHours = false

    public init(keepAwake: KeepAwake) { self.keepAwake = keepAwake }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        statusText
                        Spacer()
                        Toggle("Keep awake", isOn: Binding(get: { keepAwake.isActive }, set: { $0 ? start(nil) : keepAwake.stop() }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(presets, id: \.label) { p in
                            Button(p.label) { chipTapped(p.seconds) }
                                .buttonStyle(ChipStyle(selected: isSelected(p.seconds)))
                                .accessibilityLabel(p.spoken)
                                .accessibilityAddTraits(isSelected(p.seconds) ? .isSelected : [])
                        }
                    }
                    customRow
                    Text("Click a time to start. Click it again to stop.").font(.callout).foregroundStyle(Palette.secondary)
                    Text("Display and battery options are in Settings.").font(.callout).foregroundStyle(Palette.secondary)
                    if keepAwake.failed {
                        Text("macOS refused to keep this Mac awake. Try again.").font(.callout).foregroundStyle(.red)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 2) {
            if keepAwake.isActive {
                if let end = keepAwake.endDate {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(remaining(end, ctx.date)).font(.system(size: 15, weight: .medium)).monospacedDigit()
                    }
                } else {
                    Text("Keeping your Mac awake").font(.system(size: 15, weight: .medium))
                }
            } else {
                Text("Keep awake is off").font(.system(size: 15, weight: .medium))
                if let why = keepAwake.lastStopReason { Text(why).font(.callout).foregroundStyle(Palette.secondary) }
            }
        }
    }

    /// Type any number of minutes or hours; the same Settings options apply.
    private var customRow: some View {
        HStack(spacing: 8) {
            TextField("Custom", value: $customAmount, format: .number)
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 64, height: 44)
                .accessibilityLabel("Custom time amount")
            Picker("Unit", selection: $customHours) {
                Text("minutes").tag(false); Text("hours").tag(true)
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 140).accessibilityLabel("Custom time unit")
            Button("Start") {
                if let s = KeepAwakeOptions.customSeconds(customAmount, hours: customHours) { start(s) }
            }
            .buttonStyle(ChipStyle(selected: customIsSelected))
            .disabled(KeepAwakeOptions.customSeconds(customAmount, hours: customHours) == nil)
            .accessibilityLabel("Start custom time")
        }
    }

    private var customIsSelected: Bool {
        guard let d = keepAwake.options?.duration else { return false }
        return d == KeepAwakeOptions.customSeconds(customAmount, hours: customHours) && !presets.contains { $0.seconds == d }
    }

    private func isSelected(_ seconds: TimeInterval?) -> Bool {
        guard let o = keepAwake.options else { return false }
        return o.duration == seconds
    }

    private func chipTapped(_ seconds: TimeInterval?) {
        if isSelected(seconds) { keepAwake.stop() } else { start(seconds) }
    }

    private func start(_ seconds: TimeInterval?) {
        keepAwake.start(.stored(duration: seconds))
    }

    private func remaining(_ end: Date, _ now: Date) -> String {
        let s = max(0, Int(end.timeIntervalSince(now)))
        return String(format: "%d:%02d:%02d left", s / 3600, s % 3600 / 60, s % 60)
    }
}

/// Compact pill for a choice in a row of choices; the chosen one is filled.
struct ChipStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? Palette.accent : Palette.ground, in: Capsule())
            .foregroundStyle(selected ? Color.white : Color.primary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Capsule())
    }
}
