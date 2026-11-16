import Core
import SwiftUI

private let presets: [(label: String, spoken: String, seconds: TimeInterval?)] = [
    ("15m", "15 minutes", 900), ("30m", "30 minutes", 1800), ("1h", "1 hour", 3600), ("2h", "2 hours", 7200),
    ("4h", "4 hours", 14400), ("8h", "8 hours", 28800), ("\u{221E}", "until I stop", nil),
]

public struct KeepAwakeView: View {
    let keepAwake: KeepAwake
    @AppStorage("keepAwake.displayOn") private var displayOn = false
    @AppStorage("keepAwake.useLevel") private var useLevel = false
    @AppStorage("keepAwake.level") private var level = 20

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
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Keep the display on too", isOn: $displayOn)
                        Toggle("Stop when the battery reaches", isOn: $useLevel)
                        if useLevel {
                            Stepper("\(level)% (only on battery)", value: $level, in: 5...80, step: 5).font(.callout)
                        }
                    }
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
                    Text("Active until you turn it off").font(.system(size: 15, weight: .medium))
                }
            } else {
                Text("Sleeps as usual").font(.system(size: 15, weight: .medium))
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
        keepAwake.start(.init(duration: seconds, stopBelowPercent: useLevel ? level : nil, keepDisplayOn: displayOn))
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

/// CPU, memory, thermal state. Samples only while `active`.
public struct SystemView: View {
    let sampler: SystemSampler
    let active: Bool

    public init(sampler: SystemSampler, active: Bool) {
        self.sampler = sampler
        self.active = active
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let r = sampler.latest {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            StatusText(thermal(r.thermal))
                            Spacer()
                            Text("Up \(uptime(r.uptime))").font(.callout).foregroundStyle(Palette.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        meter("CPU", fraction: r.cpuPercent / 100, value: String(format: "%.0f%%", r.cpuPercent))
                        meter("Memory", fraction: r.memoryFraction,
                              value: "\(gb(r.memoryUsedBytes)) of \(gb(r.memoryTotalBytes))")
                    }
                    .toolCard()
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .toolPage()
        }
        .task(id: active) { if active { sampler.hold("systemView") } else { sampler.release("systemView") } }
        .onDisappear { sampler.release("systemView") }
    }

    private func meter(_ title: String, fraction: Double, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { SectionLabel(title); Spacer(); Text(value).font(.callout).monospacedDigit().foregroundStyle(Palette.secondary) }
            ProgressView(value: min(max(fraction, 0), 1)).tint(Palette.accent)
                .accessibilityLabel(title).accessibilityValue(value)
        }
    }

    private func gb(_ b: UInt64) -> String { String(format: "%.1f GB", Double(b) / 1_073_741_824) }

    private func thermal(_ s: ProcessInfo.ThermalState) -> String {
        switch s { case .nominal: "Thermal state normal"; case .fair: "Slightly warm"; case .serious: "Hot, slowing down"; case .critical: "Critical heat"; @unknown default: "Thermal state unknown" }
    }

    private func uptime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        return m >= 1440 ? "\(m / 1440) d \(m % 1440 / 60) h" : "\(m / 60) h \(m % 60) min"
    }
}
