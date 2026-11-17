import Core
import SwiftUI

private let presets: [(label: String, spoken: String, seconds: TimeInterval?)] = [
    ("15m", "15 minutes", 900), ("30m", "30 minutes", 1800), ("1h", "1 hour", 3600), ("2h", "2 hours", 7200),
    ("4h", "4 hours", 14400), ("8h", "8 hours", 28800), ("\u{221E}", "until I stop", nil),
]

public struct KeepAwakeView: View {
    let keepAwake: KeepAwake
    @AppStorage("keepAwake.displayOn") private var displayOn = true
    @AppStorage("keepAwake.untilLimit") private var untilLimit = false
    @AppStorage("keepAwake.useLevel") private var useLevel = false
    @AppStorage("keepAwake.level") private var level = KeepAwakeOptions.defaultLevel
    @AppStorage("keepAwake.endOnUnplug") private var endOnUnplug = false

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
                    Text("Click a time to start. Click it again to stop.").font(.callout).foregroundStyle(Palette.secondary)
                    if keepAwake.failed {
                        Text("macOS refused to keep this Mac awake. Try again.").font(.callout).foregroundStyle(.red)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                optionsCard
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    /// Display and battery options, applied the next time a session starts (the display option also applies live).
    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            optionRow("Keep the display on too", isOn: $displayOn)
            optionRow("Stop at the charge limit", isOn: $untilLimit)
            optionRow("Stop at a battery level", isOn: $useLevel)
            if useLevel {
                HStack {
                    Text("Stop at \(level)% (on battery)").font(.callout).foregroundStyle(Palette.secondary)
                    Slider(value: Binding(get: { Double(level) }, set: { level = Int($0) }),
                           in: Double(KeepAwakeOptions.levelRange.lowerBound)...Double(KeepAwakeOptions.levelRange.upperBound), step: 5)
                        .accessibilityLabel("Stop at battery level").accessibilityValue("\(level) percent")
                }
                .frame(minHeight: 44)
            }
            optionRow("Stop when unplugged", isOn: $endOnUnplug)
        }
        .padding(.horizontal, 14).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func optionRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 15))
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
        .frame(minHeight: 44)
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
