import AppKit
import SwiftUI

/// The Shortcuts actions Apple Cart offers. Write actions are listed so they are not a surprise later.
struct ShortcutsCard: View {
    private static let read: [(String, String)] = [
        ("Get Battery Percentage", "The charge level as a number."),
        ("Get Charge Limit", "The charge limit you saved."),
        ("Get Charging State", "Charging, plugged in not charging, or on battery."),
        ("Get Battery Temperature", "Degrees Celsius, when macOS provides it."),
    ]
    private static let write = ["Top Up", "Pause Charging", "Start Discharge", "Set Charge Limit", "Start Calibration",
                                "Set MagSafe LED", "Set Low Power Mode", "Set High Power Mode"]

    var body: some View {
        SettingsCard("Shortcuts") {
            ForEach(Self.read, id: \.0) { name, line in SettingsRow(name, detail: line) { EmptyView() } }
            ForEach(Self.write, id: \.self) { name in
                SettingsRow(name, detail: "Needs the charging helper. Not built yet.") { EmptyView() }.foregroundStyle(Palette.secondary)
            }
            SettingsRow("Use these actions in the Shortcuts app.") {
                Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                    .buttonStyle(ChipStyle()).frame(width: 140)
            }
        }
    }
}
