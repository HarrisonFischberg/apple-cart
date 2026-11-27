import Core
import SwiftUI

public struct MouseMoverView: View {
    let mover: MouseMover
    let start: () -> Void

    /// `start` closes the panel, then starts the countdown.
    public init(mover: MouseMover, start: @escaping () -> Void) { self.mover = mover; self.start = start }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    status
                    if mover.isMoving || isCountingDown {
                        Button("Stop") { mover.stop() }.buttonStyle(ChipStyle())
                    } else {
                        Button("Start now") { start() }.buttonStyle(ChipStyle(selected: true))
                    }
                    Text("The pointer glides around the screen like a screensaver. Move the mouse, touch the trackpad or press a key to stop it.").hint()
                }
                .toolCard()
                VStack(alignment: .leading, spacing: 0) { MouseMoverRows() }
                    .padding(.horizontal, 14).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .toolPage()
        }
    }

    private var isCountingDown: Bool { if case .countdown = mover.phase { true } else { false } }

    @ViewBuilder private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch mover.phase {
            case .moving: StatusText("Moving the pointer")
            case .countdown(let until):
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    StatusText("Starting in \(max(1, Int(until.timeIntervalSince(ctx.date).rounded(.up)))) s. Let go of the mouse.")
                }
            case .waiting, .off:
                let idle = MouseMoverOptions.stored().idleMinutes
                StatusText(idle.map { "Starts after \($0) min idle" } ?? "Starts only when you press Start")
                if let why = mover.lastStopReason { Text(why).hint() }
            }
        }
    }
}

/// Options shared by the panel and the Settings page.
struct MouseMoverRows: View {
    @AppStorage("mouseMover.idleMinutes") private var idleMinutes = MouseMoverOptions.defaultIdleMinutes
    @AppStorage("mouseMover.speed") private var speed = MouseMoverOptions.Speed.medium.rawValue
    @AppStorage("mouseMover.blackout") private var blackout = true

    var body: some View {
        row("Start by itself") {
            Picker("Start by itself", selection: $idleMinutes) {
                ForEach(MouseMoverOptions.idleChoices, id: \.self) { m in Text(m == 0 ? "Never" : "After \(m) min idle").tag(m) }
            }
            .labelsHidden().fixedSize()
        }
        row("Speed") {
            Picker("Speed", selection: $speed) {
                ForEach(MouseMoverOptions.Speed.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
            }
            .labelsHidden().pickerStyle(.segmented).fixedSize()
        }
        row("Black screen while it moves") {
            Toggle("Black screen while it moves", isOn: $blackout).toggleStyle(.switch).labelsHidden()
        }
    }

    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title).font(.system(size: 15))
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 44)
    }
}

struct MouseMoverOptionsCard: View {
    var body: some View {
        SettingsCard("Mouse mover") { MouseMoverRows() }
        Text("The black screen covers every display, so nothing static stays lit. Your Mac still turns the display off and sleeps on its usual schedule, which is the best protection of all. With Keep awake holding the display on, the mover keeps it moving instead.").hint()
    }
}
