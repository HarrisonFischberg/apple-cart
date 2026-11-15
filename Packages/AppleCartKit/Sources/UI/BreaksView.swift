import Core
import SwiftUI

public struct BreaksView: View {
    let reminders: BreakReminders
    public init(reminders: BreakReminders) { self.reminders = reminders }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(BreakKind.allCases.enumerated()), id: \.element) { i, kind in
                        if i > 0 { Divider() }
                        row(kind)
                    }
                }
                .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("A banner appears when a break is due, with a Snooze button. Times restart after your Mac sleeps, and nothing runs while every reminder is off.")
                    .font(.callout).foregroundStyle(Palette.secondary)
            }
            .padding(16)
        }
    }

    private func row(_ kind: BreakKind) -> some View {
        let c = reminders.config[kind] ?? BreakConfig(minutes: kind.defaultMinutes)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(kind.title, systemImage: kind.symbol)
                Spacer()
                Toggle(kind.title, isOn: Binding(get: { c.enabled }, set: { reminders.setEnabled(kind, $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            if c.enabled {
                HStack {
                    Stepper("Every \(c.minutes) min", value: Binding(get: { c.minutes }, set: { reminders.setMinutes(kind, $0) }), in: 5...240, step: 5)
                    Spacer(minLength: 8)
                    if let due = reminders.nextDue[kind] {
                        Text("Next \(due.formatted(date: .omitted, time: .shortened))").font(.callout).foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
        .padding(14).frame(minHeight: 44)
    }
}

public struct CleaningModeView: View {
    let mode: CleaningMode
    let openAccessibility: () -> Void
    @AppStorage("cleaning.seconds") private var seconds = 120

    public init(mode: CleaningMode, openAccessibility: @escaping () -> Void) { self.mode = mode; self.openAccessibility = openAccessibility }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Wipe your keyboard and trackpad").font(.headline)
                Text("The screen goes black and the keyboard and trackpad stop responding. To leave, hold Esc for 3 seconds. It also ends by itself when the time is up.")
                    .font(.callout).foregroundStyle(Palette.secondary)
                Picker("Lasts", selection: $seconds) {
                    ForEach([60, 120, 180, 300], id: \.self) { Text("\($0 / 60) min").tag($0) }
                }
                .pickerStyle(.segmented)
                Button("Start cleaning mode") { mode.start(seconds: seconds) }
                    .buttonStyle(.borderedProminent)
                switch mode.phase {
                case .needsAccessibility:
                    Text("Allow Apple Cart in Accessibility so it can pause the keyboard.").foregroundStyle(Palette.secondary)
                    Button("Open Accessibility settings", action: openAccessibility)
                case .failed: Text("macOS would not let the keyboard be paused. Nothing changed.").foregroundStyle(Palette.secondary)
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer()
        }
        .padding(16)
    }
}

/// Shown full screen while cleaning mode is on. The way out is always on screen.
public struct CleaningOverlayView: View {
    let mode: CleaningMode
    public init(mode: CleaningMode) { self.mode = mode }

    public var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 14) {
                Text("Cleaning mode").font(.system(size: 28, weight: .semibold))
                Text("Hold Esc for 3 seconds to leave").font(.title3)
                if case .active(let end) = mode.phase {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let left = max(0, Int(end.timeIntervalSince(ctx.date).rounded(.up)))
                        Text("Ends by itself in \(left / 60):\(String(format: "%02d", left % 60))").monospacedDigit().foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
    }
}
