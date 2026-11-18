import AppKit
import Core
import SwiftUI

/// The tools' own models that the Settings window needs for options.
public struct SettingsTools {
    public var clipboard: ClipboardHistory
    public var breaks: BreakReminders
    public var quickToggles: QuickToggles
    public var updateChecker: UpdateChecker
    public var chargeLimit: ChargeLimitSettings?
    public var chargeLimiter: ChargeLimiter?
    public var chargeHelper: ChargeHelperActions?
    public var battery: BatterySampler?
    public var fanRunner: FanRunner?
    public var ledRunner: LEDRunner?
    public init(clipboard: ClipboardHistory, breaks: BreakReminders, quickToggles: QuickToggles, updateChecker: UpdateChecker,
                chargeLimit: ChargeLimitSettings? = nil, chargeLimiter: ChargeLimiter? = nil, fanRunner: FanRunner? = nil,
                ledRunner: LEDRunner? = nil, chargeHelper: ChargeHelperActions? = nil, battery: BatterySampler? = nil) {
        self.clipboard = clipboard; self.breaks = breaks; self.quickToggles = quickToggles; self.updateChecker = updateChecker
        self.chargeLimit = chargeLimit; self.chargeLimiter = chargeLimiter; self.chargeHelper = chargeHelper; self.battery = battery
        self.fanRunner = fanRunner; self.ledRunner = ledRunner
    }
}

/// Install, repair and remove the root charging helper (SMAppService lives in the app). Each returns an error message or nil.
public struct ChargeHelperActions {
    public var install: @MainActor () async -> String?
    public var repair: @MainActor () async -> String?
    public var remove: @MainActor () async -> String?
    public var openLoginItems: @MainActor () -> Void
    public init(install: @escaping @MainActor () async -> String?, repair: @escaping @MainActor () async -> String?,
                remove: @escaping @MainActor () async -> String?, openLoginItems: @escaping @MainActor () -> Void) {
        self.install = install; self.repair = repair; self.remove = remove; self.openLoginItems = openLoginItems
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
            // Outside the dimmed group: removing the helper must work with the tool off too.
            if id == .battery, let limiter = tools.chargeLimiter, let actions = tools.chargeHelper {
                ChargeHelperCard(status: limiter.state.helperStatus, refresh: { await limiter.refreshHelperStatus() }, actions: actions)
            }
            if id == .fanSafeMode, let runner = tools.fanRunner, let actions = tools.chargeHelper {
                ChargeHelperCard(status: runner.state.helperStatus, refresh: { await runner.refreshHelperStatus() }, actions: actions, fans: true)
            }
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
            if let s = tools.chargeLimit {
                ChargeControlOptions(settings: s, limiter: tools.chargeLimiter, battery: tools.battery, led: tools.ledRunner)
            } else {
                Text("Charge limit is set from the panel.").hint()
            }
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
        case .fanSafeMode:
            if let runner = tools.fanRunner { FanOptions(settings: runner.settings) } else { note("Fan speed is set from the panel.") }
        case .notifications: note("Not built yet.")
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

/// Charge Control: typed limit, below-80 rule, Automatic Discharge, Sailing Mode, Heat Protection, the MagSafe light and
/// Indicate charge limit.
struct ChargeControlOptions: View {
    let settings: ChargeLimitSettings
    let limiter: ChargeLimiter?
    let battery: BatterySampler?
    var led: LEDRunner?

    var body: some View {
        SettingsCard("Charge control") {
            SettingsRow("Charge limit", detail: "0-100%, in steps of 5. Also set from the panel.") {
                HStack(spacing: 4) {
                    TextField("Charge limit", value: Binding(get: { settings.limit }, set: { settings.setLimit($0); changed() }), format: .number)
                        .multilineTextAlignment(.trailing).frame(width: 56).textFieldStyle(.roundedBorder)
                        .accessibilityValue("\(settings.limit) percent")
                    Text("%").foregroundStyle(Palette.secondary)
                }
            }
            SettingsRow("Automatic discharge", detail: "Above the limit while plugged in, run from the battery down to the limit. Limits of 80% and up are held by macOS's own charge limit with the Mac on the charger; below 80% a pause also runs from the battery.") {
                Toggle("Automatic discharge", isOn: Binding(get: { settings.autoDischarge }, set: { settings.setAutoDischarge($0); changed() }))
                    .toggleStyle(.switch).labelsHidden()
            }
            SettingsRow("Sailing mode", detail: "After reaching the limit, wait until the battery drops by the difference before charging again.") {
                Toggle("Sailing mode", isOn: Binding(get: { settings.sailing }, set: { settings.setSailing($0); changed() }))
                    .toggleStyle(.switch).labelsHidden()
            }
            if settings.sailing {
                SettingsRow("Difference", detail: settings.topUpActive ? "Off while Top Up runs." : "Will sail to \(limiter?.shownSailFloor ?? settings.sailFloor)%") {
                    Stepper("\(settings.sailingDifference) %", value: Binding(get: { settings.sailingDifference }, set: { settings.setSailingDifference($0); changed() }),
                            in: ChargeLimitSettings.sailingRange).fixedSize()
                }
            }
            if limiter != nil, settings.limit < 100, limiter?.usesMacOSLimit != true {
                DimmingTip()
            }
            heat
            if let r = battery?.latest, r.magSafeLight != .notAvailable {
                SettingsRow("MagSafe light", detail: settings.indicateChargeLimit
                            ? "macOS sets the light unless your limit holds charging or heat protection pauses it."
                            : "macOS sets the light: orange below 100% and green when full.") {
                    Text(r.magSafeLight.text(pluggedIn: r.isPluggedIn)).foregroundStyle(Palette.secondary)
                        .accessibilityLabel("MagSafe light")
                }
                SettingsRow("Indicate charge limit", detail: led?.helperStatus == .outdated
                            ? "The helper is out of date for this. In Settings, Remove it, then Install it again."
                            : "Green while your limit holds charging, orange while heat protection pauses it. Needs the charging helper.") {
                    Toggle("Indicate charge limit", isOn: Binding(get: { settings.indicateChargeLimit },
                                                                  set: { settings.setIndicateChargeLimit($0); Task { await led?.evaluate() } }))
                        .toggleStyle(.switch).labelsHidden()
                }
            }
        }
        .task {
            battery?.hold("chargeSettings") // for the current temperature
        }
        .onDisappear { battery?.release("chargeSettings") }
    }

    @ViewBuilder private var heat: some View {
        if let t = battery?.latest?.temperatureC {
            SettingsRow("Heat protection", detail: "Pause charging while the battery is warmer than the max, for at least 5 minutes at a time. Battery now \(Self.temp(t)).") {
                Toggle("Heat protection", isOn: Binding(get: { settings.heatProtection }, set: { settings.setHeatProtection($0); changed() }))
                    .toggleStyle(.switch).labelsHidden()
            }
            if settings.heatProtection {
                SettingsRow("Max temperature") {
                    Stepper(Self.temp(settings.heatMaxC), value: Binding(get: { settings.heatMaxC }, set: { settings.setHeatMaxC($0); changed() }),
                            in: ChargeLimitSettings.heatRangeC, step: 1).fixedSize()
                }
            }
        } else {
            SettingsRow("Heat protection", detail: "Not available on this Mac.") {
                Toggle("Heat protection", isOn: .constant(false)).toggleStyle(.switch).labelsHidden().disabled(true)
            }
        }
    }

    /// Stored in Celsius, shown in the user's unit.
    static func temp(_ c: Double) -> String {
        Measurement(value: c, unit: UnitTemperature.celsius).formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private func changed() { Task { await limiter?.reevaluate() } }
}

/// Install, repair and remove the root helper. It is shared: the Battery page shows it for the charge limit, the Fan
/// speed page for the fans (a version 2 helper still charges but is out of date for fans).
struct ChargeHelperCard: View {
    let status: ChargeHelperStatus
    let refresh: @MainActor () async -> Void
    let actions: ChargeHelperActions
    var fans = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        SettingsCard(fans ? "Helper" : "Charging helper") {
            SettingsRow("Status", detail: detail(status)) {
                HStack(spacing: 10) {
                    if status == .notInstalled {
                        button("Install", actions.install)
                    } else {
                        if status == .needsApproval { Button("Open Login Items") { actions.openLoginItems() }.buttonStyle(ChipStyle()).frame(width: 150) }
                        if status == .outdated || status == .unreachable { button("Repair", actions.repair) }
                        button("Remove", actions.remove)
                    }
                }
                .disabled(working)
            }
        }
        if let error { Text(error).hint() }
        Text(fans
             ? "The same helper as the charge limit. It runs on this Mac only and never uses the network. It can only pause or resume the charger and set the fans and the MagSafe light, and all of them go back to macOS by themselves if Apple Cart stops. Remove hands everything back first."
             : "The helper runs on this Mac only and never uses the network. It can only pause or resume the charger and set the MagSafe light, and both go back to normal by themselves if Apple Cart stops. Remove turns charging back to normal first.").hint()
            .task { await refresh() }
    }

    private func detail(_ s: ChargeHelperStatus) -> String {
        switch s {
        case .notInstalled: fans ? "Not installed. Fan control needs it." : "Not installed. The charge limit needs it."
        case .needsApproval: "Installed. Approve Apple Cart in Login Items to turn it on."
        case .ready: "Installed and working."
        case .outdated: "Out of date. Repair installs the version that came with this app."
        case .unreachable: "Installed but not answering. Try Repair. It only works in a build signed with the Apple Cart team."
        case .unsupported: fans ? "Fan control is not supported on this Mac." : "Not supported on this Mac. Charge control needs a charger key this Mac does not have."
        }
    }

    private func button(_ title: String, _ action: @escaping @MainActor () async -> String?) -> some View {
        Button(title) {
            working = true
            Task {
                error = await action()
                await refresh()
                working = false
            }
        }
        .buttonStyle(ChipStyle()).frame(width: 110)
    }
}

/// Fan speed: Resume and the safety rules. The mode and speed are set in the panel.
private struct FanOptions: View {
    let settings: FanSettings

    var body: some View {
        SettingsCard("Fan speed") {
            SettingsRow("Mode", detail: "Choose System or Manual in the panel.") { Text(settings.active.title).foregroundStyle(Palette.secondary) }
            SettingsRow("Resume after restart or sleep", detail: "Off: every restart and sleep gives the fans back to macOS until you apply again.") {
                Toggle("Resume after restart or sleep", isOn: Binding(get: { settings.resume }, set: { settings.setResume($0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
        }
        Text("Fans return to macOS when Apple Cart quits, when the Mac sleeps, when a temperature cannot be read and whenever anything fails. At 90 °C on the hottest chip sensor, or when macOS reports thermal pressure, macOS takes the fans for at least 2 minutes and until the chip is below 80 °C. If the fan does not follow a speed within 15 seconds, it goes back to macOS. A manual speed never goes below the fan's slowest running speed.").hint()
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
    var body: some View { Text("Keep awake options are in the panel, under the time buttons.").hint() }
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
        Text("This goes by the app in front when you copy.").hint()
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
