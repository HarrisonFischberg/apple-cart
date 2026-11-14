import Core
import SwiftUI

private let presets: [(label: String, seconds: TimeInterval?)] = [
    ("15 min", 900), ("30 min", 1800), ("1 hour", 3600), ("2 hours", 7200), ("4 hours", 14400), ("Until I stop", nil),
]

public struct KeepAwakeView: View {
    let keepAwake: KeepAwake
    @AppStorage("keepAwake.displayOn") private var displayOn = false
    @AppStorage("keepAwake.useLevel") private var useLevel = false
    @AppStorage("keepAwake.level") private var level = 20

    public init(keepAwake: KeepAwake) { self.keepAwake = keepAwake }

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                status
                card {
                    Toggle("Keep the display on too", isOn: $displayOn)
                    Toggle("Stop when the battery reaches", isOn: $useLevel)
                    if useLevel {
                        Stepper("\(level)% (only on battery)", value: $level, in: 5...80, step: 5)
                            .font(.callout)
                    }
                }
                Text("Start for").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(presets, id: \.label) { p in
                        Button(p.label) { start(p.seconds) }
                            .buttonStyle(PresetStyle())
                    }
                }
                if keepAwake.failed {
                    Text("macOS refused to keep this Mac awake. Try again.").font(.callout).foregroundStyle(.red)
                }
            }
            .padding(16)
        }
    }

    private var status: some View {
        card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(keepAwake.isActive ? "Staying awake" : "Sleeps as usual").font(.headline)
                    if keepAwake.isActive {
                        if let end = keepAwake.endDate {
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                Text(remaining(end, ctx.date)).font(.callout).monospacedDigit().foregroundStyle(Palette.secondary)
                            }
                        } else {
                            Text("Until you stop it").font(.callout).foregroundStyle(Palette.secondary)
                        }
                    } else if let why = keepAwake.lastStopReason {
                        Text(why).font(.callout).foregroundStyle(Palette.secondary)
                    }
                }
                Spacer()
                if keepAwake.isActive { Button("Stop") { keepAwake.stop() }.buttonStyle(.borderedProminent) }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func start(_ seconds: TimeInterval?) {
        keepAwake.start(.init(duration: seconds, stopBelowPercent: useLevel ? level : nil, keepDisplayOn: displayOn))
    }

    private func remaining(_ end: Date, _ now: Date) -> String {
        let s = max(0, Int(end.timeIntervalSince(now)))
        return String(format: "%d:%02d:%02d left", s / 3600, s % 3600 / 60, s % 60)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct PresetStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.callout).frame(maxWidth: .infinity, minHeight: 44)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(Palette.accent)
            .opacity(configuration.isPressed ? 0.6 : 1)
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
            VStack(spacing: 12) {
                if let r = sampler.latest {
                    meter("CPU", fraction: r.cpuPercent / 100, value: String(format: "%.0f%%", r.cpuPercent))
                    meter("Memory", fraction: r.memoryFraction,
                          value: "\(gb(r.memoryUsedBytes)) of \(gb(r.memoryTotalBytes))")
                    card {
                        row("Thermal state", thermal(r.thermal))
                        row("Up for", uptime(r.uptime))
                    }
                } else {
                    ProgressView().padding(40)
                }
            }
            .padding(16)
        }
        .task(id: active) { if active { sampler.hold("systemView") } else { sampler.release("systemView") } }
        .onDisappear { sampler.release("systemView") }
    }

    private func meter(_ title: String, fraction: Double, value: String) -> some View {
        card {
            HStack { Text(title).font(.headline); Spacer(); Text(value).monospacedDigit().foregroundStyle(Palette.secondary) }
            ProgressView(value: min(max(fraction, 0), 1)).tint(Palette.accent)
                .accessibilityLabel(title).accessibilityValue(value)
        }
    }

    private func row(_ t: String, _ v: String) -> some View {
        HStack { Text(t); Spacer(); Text(v).foregroundStyle(Palette.secondary) }.font(.callout)
            .accessibilityElement(children: .combine)
    }

    private func gb(_ b: UInt64) -> String { String(format: "%.1f GB", Double(b) / 1_073_741_824) }

    private func thermal(_ s: ProcessInfo.ThermalState) -> String {
        switch s { case .nominal: "Normal"; case .fair: "Slightly warm"; case .serious: "Hot, slowing down"; case .critical: "Critical"; @unknown default: "Unknown" }
    }

    private func uptime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        return m >= 1440 ? "\(m / 1440) d \(m % 1440 / 60) h" : "\(m / 60) h \(m % 60) min"
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
