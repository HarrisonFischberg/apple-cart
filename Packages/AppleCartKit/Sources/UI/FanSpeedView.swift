import Core
import SwiftUI

/// Fan speed: live speed per fan, then System or Manual (one speed). Choosing Manual
/// only opens its editor; nothing is sent until Apply. System is applied at once (it is always safe).
public struct FanSpeedView: View {
    let runner: FanRunner
    @State private var tab: FanControlMode
    @State private var draftPercent: Int
    private let pinnedTab: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `tab` picks the open editor, for previews; otherwise it opens on the applied mode.
    public init(runner: FanRunner, tab: FanControlMode? = nil) {
        self.runner = runner
        _tab = State(initialValue: tab ?? runner.settings.active)
        pinnedTab = tab != nil
        _draftPercent = State(initialValue: runner.settings.manualPercent)
    }

    private var state: FanState { runner.state }
    private var settings: FanSettings { runner.settings }
    private var ready: Bool { state.helperStatus == .ready && !state.noFan }

    public var body: some View {
        VStack(spacing: 0) {
            scrollContent
            if !state.noFan { applyFooter }
        }
        .onAppear { if !pinnedTab { tab = state.holdingRPM != nil ? state.holdingMode : settings.active } }
    }

    /// The Apply button stays in view under the scrolling card, whatever the panel height.
    @ViewBuilder private var applyFooter: some View {
        switch tab {
        case .system:
            let applied = settings.active == .system && state.holdingRPM == nil
            applyButton(applied ? "Applied" : "Apply system control", applied: applied, returnLink: false) { applySystem() }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 8)
        case .manual:
            let applied = settings.active == .manual && settings.manualPercent == draftPercent
            applyButton(applied ? "Applied" : "Apply manual control", applied: applied) {
                settings.applyManual(percent: draftPercent)
                Task { await runner.applyChanged() }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 8)
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if state.noFan {
                    Label("This Mac has no fan. macOS cools it without one, so there is nothing to set.", systemImage: "wind")
                        .font(.system(size: 14)).foregroundStyle(Palette.secondary)
                } else {
                    fanRows
                    Text(state.statusText).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Status: \(state.statusText)")
                    ModePicker(selection: tab, pending: tab != settings.active, choose: choose)
                        .disabled(!ready)
                    switch tab {
                    case .system: systemEditor
                    case .manual: manualEditor
                    }
                    if tab != .system { resumeRow }
                    Text("Control stays on until you return to System. macOS takes the fans back by itself if Apple Cart disconnects, the Mac sleeps (unless Resume is on), a temperature cannot be read, the chip reaches 90 °C or macOS reports thermal pressure.")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let card = RoundedRectangle(cornerRadius: 18, style: .continuous)
                card.fill(Palette.tile)
                    .overlay(card.fill(LinearGradient(colors: [Palette.flow.opacity(0.07), .clear], startPoint: .top, endPoint: .bottom)))
                    .overlay(card.strokeBorder(.primary.opacity(0.06)))
            }
            .toolPage()
        }
    }

    // MARK: Header and fans

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "fan").font(.system(size: 26, weight: .regular)).foregroundStyle(Palette.secondary)
                .frame(width: 40, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Fan control").font(.system(size: 19, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text("BETA").font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Palette.accent, in: Capsule())
                        .accessibilityLabel("Beta")
                }
                Text(state.noFan ? "No fan" : state.subtitle).font(.system(size: 14)).foregroundStyle(Palette.secondary)
                    .accessibilityLabel("Mode: \(state.noFan ? "No fan" : state.subtitle)")
            }
        }
    }

    @ViewBuilder private var fanRows: some View {
        let rpms = state.reading?.rpms ?? [nil]
        VStack(spacing: 8) {
            ForEach(rpms.indices, id: \.self) { i in
                HStack {
                    Text("Fan \(i + 1)").foregroundStyle(Palette.secondary)
                    Spacer()
                    if state.reading == nil {
                        Text("Current 0,000 RPM").redacted(reason: .placeholder)
                    } else {
                        Text(FanText.current(rpms[i])).fontWeight(.semibold).monospacedDigit()
                    }
                }
                .font(.system(size: 15))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Fan \(i + 1)")
                .accessibilityValue(state.reading == nil ? "Reading" : FanText.current(rpms[i]))
            }
        }
    }

    /// Picking a segment only changes what the card shows; nothing is sent until Apply, for System too.
    private func choose(_ m: FanControlMode) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { tab = m }
    }

    private func applySystem() {
        tab = .system
        Task { await runner.applySystem() }
    }

    // MARK: System

    private var systemEditor: some View {
        Text("macOS decides the fan speed, including keeping the fan off when the Mac is cool.")
            .font(.system(size: 14)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Manual

    private var range: FanRange? { state.reading?.range }

    private var manualEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fan speed").font(.system(size: 15)).foregroundStyle(Palette.secondary)
                Spacer()
                if let range { Text(FanText.rpm(range.rpm(percent: Double(draftPercent)))).font(.system(size: 13)).foregroundStyle(Palette.secondary).monospacedDigit() }
                Text("\(draftPercent)%").font(.system(size: 15, weight: .semibold)).monospacedDigit()
            }
            .accessibilityHidden(true)
            HStack(spacing: 8) {
                ForEach(FanPreset.allCases, id: \.self) { p in
                    Button(p.title) { draftPercent = p.percent }
                        .buttonStyle(ChipStyle(selected: draftPercent == p.percent))
                        .accessibilityLabel("\(p.title) speed")
                }
            }
            Slider(value: Binding(get: { Double(draftPercent) }, set: { draftPercent = Int($0.rounded()) }), in: 0...100)
                .tint(Palette.flow)
                .frame(minHeight: 44)
                .accessibilityLabel("Fan speed")
                .accessibilityValue("\(draftPercent) percent" + (range.map { ", about \(FanText.rpm($0.rpm(percent: Double(draftPercent))))" } ?? ""))
            Text("0% is the slowest speed the fan runs at, 100% its maximum.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }
    }

    // MARK: Shared pieces

    private var resumeRow: some View {
        HStack {
            Text("Resume after restart or sleep").font(.system(size: 15))
            Spacer(minLength: 8)
            Toggle("Resume after restart or sleep", isOn: Binding(get: { settings.resume }, set: { settings.setResume($0) }))
                .toggleStyle(.switch).labelsHidden().tint(Palette.accent)
                .accessibilityHint("When off, the fans go back to macOS after a restart or sleep and stay there.")
        }
        .frame(minHeight: 44)
    }

    private func applyButton(_ title: String, applied: Bool, returnLink: Bool = true, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Text(title).font(.system(size: 16, weight: .medium)).frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(applied ? Color.primary : .white)
                    .background(applied ? AnyShapeStyle(Palette.raised) : AnyShapeStyle(Palette.flow), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(applied || !ready)
            .opacity(!ready ? 0.5 : 1)
            if applied && returnLink {
                Button("Return to System") { applySystem() }
                    .buttonStyle(.plain).foregroundStyle(Palette.accent).frame(minHeight: 44)
            }
        }
    }
}

/// System | Manual, the selected segment a lighter raised pill. `pending`: the selected segment is not the mode
/// that is applied, so it carries a small "Not applied yet" note.
private struct ModePicker: View {
    let selection: FanControlMode
    var pending = false
    let choose: (FanControlMode) -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        VStack(spacing: 4) {
            segments
            if pending {
                HStack(spacing: 0) {
                    ForEach(FanControlMode.allCases, id: \.self) { m in
                        Text(m == selection ? "Not applied yet" : " ").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.amberText).frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(selection.title) is not applied yet")
            }
        }
    }

    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(FanControlMode.allCases, id: \.self) { m in
                Button { choose(m) } label: {
                    Text(m.title).font(.system(size: 15, weight: selection == m ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selection == m {
                                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.raisedTop)
                                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.primary.opacity(0.08)))
                            }
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == m ? .isSelected : [])
                .accessibilityHint("Shows the \(m.title.lowercased()) settings. Nothing changes until you apply.")
            }
        }
        .padding(.horizontal, 4)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .opacity(enabled ? 1 : 0.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fan mode")
    }
}
