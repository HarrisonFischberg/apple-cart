import AppKit
import Core
import SwiftUI

/// The tools' own models that the Settings window needs for options.
public struct SettingsTools {
    public var clipboard: ClipboardHistory
    public var breaks: BreakReminders
    public var quickToggles: QuickToggles
    public var updateChecker: UpdateChecker
    public init(clipboard: ClipboardHistory, breaks: BreakReminders, quickToggles: QuickToggles, updateChecker: UpdateChecker) {
        self.clipboard = clipboard; self.breaks = breaks; self.quickToggles = quickToggles; self.updateChecker = updateChecker
    }
}

/// One tool's page: big switch on top, then only that tool's options (dimmed while it is off).
struct ToolSettingsPage: View {
    let id: FeatureID
    let registry: FeatureRegistry
    let permissions: PermissionsModel
    let readout: ReadoutSettings
    let tools: SettingsTools
    let open: (URL) -> Void

    var body: some View {
        let available = registry.isAvailable(id)
        let on = registry.isEnabled(id)
        VStack(alignment: .leading, spacing: 16) {
            header(available: available)
            VStack(alignment: .leading, spacing: 16) {
                options
                if let s = id.shortcut {
                    SettingsCard("Shortcut") { SettingsRow(s.label) { Text(s.keys).font(.system(.body, design: .rounded)).foregroundStyle(Palette.secondary) } }
                }
                permissionCard
            }
            .disabled(!on).opacity(on ? 1 : 0.45)
            if available && !on { Text("Turn this tool on to change its options.").hint() }
        }
        .task { await permissions.refresh() }
    }

    private func header(available: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: id.symbol).font(.system(size: 22)).foregroundStyle(Palette.accent)
                .frame(width: 44, height: 44).background(Palette.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(id.title).font(.system(size: 20, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text(available ? id.blurb : "Not built yet").hint()
            }
            Spacer(minLength: 8)
            Toggle(id.title, isOn: Binding(get: { registry.isEnabled(id) }, set: { registry.setEnabled($0, for: id) }))
                .toggleStyle(.switch).controlSize(.large).labelsHidden().tint(Palette.accent)
                .disabled(!available)
                .accessibilityHint(id.blurb)
        }
        .toolCard()
    }

    @ViewBuilder private var options: some View {
        switch id {
        case .battery:
            SettingsCard("Menu bar") { ReadoutRow(readout: readout) }
            BatteryEnergySettings()
            Text("Charge limit is set from the panel.").hint()
        case .keepAwake: KeepAwakeSettingsCards()
        case .clipboard: ClipboardOptions(history: tools.clipboard)
        case .breakReminders: BreakOptions(reminders: tools.breaks)
        case .cleaningMode: CleaningOptions()
        case .volumeGuard: VolumeOptions()
        case .quickToggles: QuickToggleOptions(toggles: tools.quickToggles)
        case .updates: UpdatesOptions(checker: tools.updateChecker)
        case .system: note("Nothing to set. The panel shows CPU, memory and thermal state while this is on.")
        case .flushDNS: note("Nothing to set. macOS asks for your administrator password each time you flush.")
        case .uninstaller, .cleaner, .diskMap: note("Nothing to set. Nothing is removed until you review a list and confirm it in the panel.")
        case .copyText, .readQR: note("Nothing else to set. Drag a box in the panel or use the shortcut.")
        case .fanSafeMode, .notifications: note("Not built yet.")
        }
    }

    private func note(_ text: String) -> some View { Text(text).hint() }

    @ViewBuilder private var permissionCard: some View {
        let needed = Permission.allCases.filter { $0.usedBy.contains(id) }
        if !needed.isEmpty {
            SettingsCard("Permissions") {
                ForEach(needed, id: \.self) { p in
                    SettingsRow(p.title) {
                        HStack(spacing: 10) {
                            status(permissions.status(p))
                            Button("Open Settings") { open(p.settingsURL) }.buttonStyle(ChipStyle()).frame(width: 120)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func status(_ s: PermissionStatus) -> some View {
        switch s {
        case .granted: Label("Granted", systemImage: "checkmark.circle.fill").symbolRenderingMode(.multicolor)
        case .notGranted: Label("Not granted", systemImage: "circle").foregroundStyle(Palette.secondary)
        case .unknown: Text("Checking…").foregroundStyle(Palette.secondary)
        }
    }
}

struct ReadoutRow: View {
    @Bindable var readout: ReadoutSettings
    var body: some View {
        SettingsRow("Next to the battery icon", detail: "Shows only while the Battery tool is on.") {
            Picker("Next to the battery icon", selection: $readout.readout) {
                ForEach(MenuBarReadout.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
        }
    }
}

private struct BatteryEnergySettings: View {
    @AppStorage(MenuBarReadout.hardwarePercentKey) private var hardware = false
    @AppStorage(EnergyThreshold.storageKey) private var threshold = EnergyThreshold.medium.rawValue
    @AppStorage(EnergyThreshold.backgroundKey) private var background = false

    var body: some View {
        SettingsCard("Percentage") {
            SettingsRow("Also show the battery's own percentage", detail: "Next to the macOS percent in the panel and the menu bar. Shows -- when unreadable.") {
                Toggle("Also show the battery's own percentage", isOn: $hardware).toggleStyle(.switch).labelsHidden()
            }
        }
        SettingsCard("Energy use") {
            SettingsRow("Show apps above", detail: "Based on CPU use, not macOS's energy impact: Low 5%, Medium 20%, High 40% of one core.") {
                Picker("Show apps above", selection: $threshold) {
                    ForEach(EnergyThreshold.allCases, id: \.rawValue) { Text($0 == .medium ? "Medium (macOS default)" : $0.title).tag($0.rawValue) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            SettingsRow("Include background processes", detail: "Adds helpers and system processes. Off lists only apps.") {
                Toggle("Include background processes", isOn: $background).toggleStyle(.switch).labelsHidden()
            }
        }
    }
}

private struct KeepAwakeSettingsCards: View {
    @AppStorage("keepAwake.displayOn") private var displayOn = false
    @AppStorage("keepAwake.useLevel") private var useLevel = false
    @AppStorage("keepAwake.level") private var level = KeepAwakeOptions.defaultLevel
    @AppStorage("keepAwake.endOnUnplug") private var endOnUnplug = false
    @AppStorage("keepAwake.untilLimit") private var untilLimit = false

    var body: some View {
        SettingsCard("When it starts") {
            SettingsRow("Keep the display on too") { Toggle("Keep the display on too", isOn: $displayOn).toggleStyle(.switch).labelsHidden() }
            SettingsRow("Disable sleep until the charge limit", detail: "Recommended. Ends when plugged in and the charge reaches your limit. At 100% it ends when full.") {
                Toggle("Disable sleep until the charge limit", isOn: $untilLimit).toggleStyle(.switch).labelsHidden()
            }
        }
        SettingsCard("Manual sleep control") {
            SettingsRow("Re-enable sleep at a battery level") { Toggle("Re-enable sleep at a battery level", isOn: $useLevel).toggleStyle(.switch).labelsHidden() }
            if useLevel {
                SettingsRow("Re-enable sleep at \(level)%", detail: "Only counts while on battery.") {
                    Slider(value: Binding(get: { Double(level) }, set: { level = Int($0) }),
                           in: Double(KeepAwakeOptions.levelRange.lowerBound)...Double(KeepAwakeOptions.levelRange.upperBound), step: 5)
                        .frame(width: 180).accessibilityLabel("Re-enable sleep at battery level").accessibilityValue("\(level) percent")
                }
            }
            SettingsRow("Re-enable sleep when unplugged") { Toggle("Re-enable sleep when unplugged", isOn: $endOnUnplug).toggleStyle(.switch).labelsHidden() }
        }
        Text("Start it from the panel by choosing a time.").hint()
    }
}

private struct ClipboardOptions: View {
    let history: ClipboardHistory

    var body: some View {
        SettingsCard("History") {
            SettingsRow("Keep items for", detail: "Pinned items stay.") {
                Stepper("\(history.retentionDays) day\(history.retentionDays == 1 ? "" : "s")",
                        value: Binding(get: { history.retentionDays }, set: { history.setRetention($0) }), in: 1...90).fixedSize()
            }
            SettingsRow("Remove tracking from copied links") {
                Toggle("Remove tracking from copied links", isOn: Binding(get: { history.cleanLinks }, set: { history.setCleanLinks($0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            SettingsRow("Clear the clipboard after a minute and on lock") {
                Toggle("Clear the clipboard after a minute and on lock", isOn: Binding(get: { history.autoClear }, set: { history.setAutoClear($0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
        }
        Text("Passwords and other items apps mark as secret are never saved.").hint()
        SettingsCard("Never stored from") {
            if history.excluded.isEmpty { Text("No apps are ignored.").hint() }
            ForEach(history.excluded.sorted(), id: \.self) { id in
                SettingsRow(id) { Button("Allow again") { history.allowAgain(id) } }
            }
            SettingsRow("Ignore an app") { Button("Choose…") { pickApp() } }
        }
        SettingsCard("Saved items") {
            SettingsRow("Clear history", detail: "Pinned items stay.") {
                Button("Clear history", role: .destructive) { history.clearAll() }
            }
            if !history.lastDeleted.isEmpty {
                SettingsRow("Removed \(history.lastDeleted.count).") { Button("Undo") { history.undoDelete() } }
            }
        }
    }

    private func pickApp() {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: "/Applications"); p.allowedContentTypes = [.application]
        NSApp.activate()
        if p.runModal() == .OK, let u = p.url, let id = Bundle(url: u)?.bundleIdentifier { history.neverStore(from: id) }
    }
}

private struct BreakOptions: View {
    let reminders: BreakReminders

    var body: some View {
        SettingsCard("Breaks") {
            ForEach(BreakKind.allCases, id: \.self) { kind in
                let c = reminders.config[kind] ?? BreakConfig(minutes: kind.defaultMinutes)
                SettingsRow(kind.title, detail: c.enabled ? "Every \(c.minutes) min" : nil) {
                    HStack(spacing: 12) {
                        if c.enabled {
                            Stepper("\(kind.title) interval", value: Binding(get: { c.minutes }, set: { reminders.setMinutes(kind, $0) }), in: 5...240, step: 5)
                                .labelsHidden()
                        }
                        Toggle(kind.title, isOn: Binding(get: { c.enabled }, set: { reminders.setEnabled(kind, $0) }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                }
            }
        }
        Text("A banner appears when a break is due, with a Snooze button. Times restart after your Mac sleeps, and nothing runs while every reminder is off.").hint()
    }
}

private struct CleaningOptions: View {
    @AppStorage("cleaning.seconds") private var seconds = 120

    var body: some View {
        SettingsCard("Cleaning mode") {
            SettingsRow("Lasts") {
                Picker("Lasts", selection: $seconds) {
                    ForEach([60, 120, 180, 300], id: \.self) { Text("\($0 / 60) min").tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }
        }
        Text("Start it from the panel. To leave early, hold Esc for 3 seconds.").hint()
    }
}

private struct VolumeOptions: View {
    @AppStorage("volumeGuard.max") private var maxPercent = 70

    var body: some View {
        SettingsCard("Limit") {
            SettingsRow("Highest volume", detail: "Applied when the speaker changes. Never raised.") {
                HStack {
                    Slider(value: Binding(get: { Double(maxPercent) }, set: { maxPercent = Int($0.rounded()) }), in: 10...100, step: 5)
                        .frame(width: 160).accessibilityLabel("Highest volume")
                    Text("\(maxPercent)%").monospacedDigit().foregroundStyle(Palette.secondary).frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}

private struct QuickToggleOptions: View {
    let toggles: QuickToggles

    var body: some View {
        SettingsCard("Switches") {
            ForEach(QuickToggle.allCases, id: \.self) { t in
                SettingsRow(t.title) {
                    Toggle(t.title, isOn: Binding(get: { toggles.states[t] ?? false }, set: { toggles.set(t, on: $0) }))
                        .toggleStyle(.switch).labelsHidden()
                }
            }
        }
        Text("Changing one restarts Finder or the Dock for a moment so it takes effect.").hint()
            .onAppear { toggles.refresh() }
    }
}

private struct UpdatesOptions: View {
    let checker: UpdateChecker

    var body: some View {
        SettingsCard("Check") {
            SettingsRow("macOS and Homebrew", detail: detail) {
                Button(checker.phase == .checking ? "Checking…" : "Check now") { Task { await checker.check() } }
                    .buttonStyle(ChipStyle(selected: true)).frame(width: 120).disabled(checker.phase == .checking)
            }
        }
        Text("Checks only when you press the button. The macOS check asks Apple's update service; Homebrew is compared with its last downloaded list, and nothing is installed. Results show in the panel.").hint()
    }

    private var detail: String {
        if case .done(let d) = checker.phase { return "Checked \(d.formatted(date: .omitted, time: .shortened))" }
        return checker.phase == .checking ? "Checking…" : "Not checked yet"
    }
}
