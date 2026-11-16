import Core
import SwiftUI

/// Fan speed: live speed per fan, then System, Manual (one speed) or Curve (temperature to speed). Choosing Manual or
/// Curve only opens its editor; nothing is sent until Apply. System is applied at once (it is always safe).
public struct FanSpeedView: View {
    let runner: FanRunner
    @State private var tab: FanControlMode
    @State private var draftPercent: Int
    @State private var draftCurve: FanCurve
    private let pinnedTab: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `tab` picks the open editor, for previews; otherwise it opens on the applied mode.
    public init(runner: FanRunner, tab: FanControlMode? = nil) {
        self.runner = runner
        _tab = State(initialValue: tab ?? runner.settings.active)
        pinnedTab = tab != nil
        _draftPercent = State(initialValue: runner.settings.manualPercent)
        _draftCurve = State(initialValue: runner.settings.curve)
    }

    private var state: FanState { runner.state }
    private var settings: FanSettings { runner.settings }
    private var ready: Bool { state.helperStatus == .ready && !state.noFan }

    public var body: some View {
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
                    case .curve: curveEditor
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
        .onAppear { if !pinnedTab { tab = state.holdingRPM != nil ? state.holdingMode : settings.active } }
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
        let applied = settings.active == .system && state.holdingRPM == nil
        return VStack(alignment: .leading, spacing: 10) {
            Text("macOS decides the fan speed, including keeping the fan off when the Mac is cool.")
                .font(.system(size: 14)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            applyButton(applied ? "Applied" : "Apply system control", applied: applied, returnLink: false) { applySystem() }
        }
    }

    // MARK: Manual

    private var range: FanRange? { state.reading?.range }

    private var manualEditor: some View {
        let applied = settings.active == .manual && settings.manualPercent == draftPercent
        return VStack(alignment: .leading, spacing: 10) {
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
            applyButton(applied ? "Applied" : "Apply manual control", applied: applied) {
                settings.applyManual(percent: draftPercent)
                Task { await runner.applyChanged() }
            }
        }
    }

    // MARK: Curve

    private var curveEditor: some View {
        let applied = settings.active == .curve && settings.curve == draftCurve.validated
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(draftCurve.sensors.indices, id: \.self) { i in sensorRow(i) }
            CurveChart(curve: $draftCurve, current: draftCurve.temperature(state.temperatures))
                .frame(height: 150)
            pointColumns
            HStack(spacing: 16) {
                linkButton("Add point", symbol: "plus") {
                    guard let last = draftCurve.points.last else { return }
                    draftCurve.points.append(FanCurvePoint(min(last.tempC + 5, FanCurve.tempRange.upperBound), last.percent))
                    draftCurve = draftCurve.validated
                }
                .disabled(draftCurve.points.count >= FanCurve.maxPoints || (draftCurve.points.last?.tempC ?? 100) >= FanCurve.tempRange.upperBound)
                Spacer()
                linkButton("Reset to default", symbol: "arrow.counterclockwise") { draftCurve = .default }
            }
            if draftCurve.sensors.count < FanCurve.maxSensors {
                linkButton("Add sensor", symbol: "plus.circle") {
                    if let s = FanSensor.allCases.first(where: { !draftCurve.sensors.contains($0) }) { draftCurve.sensors.append(s) }
                }
                .accessibilityHint("Adds a second temperature. The curve follows whichever is hotter.")
            }
            applyButton(applied ? "Applied" : "Apply fan curve", applied: applied) {
                settings.applyCurve(draftCurve)
                draftCurve = settings.curve
                Task { await runner.applyChanged() }
            }
        }
    }

    private func sensorRow(_ i: Int) -> some View {
        let sensor = draftCurve.sensors[i]
        return HStack(spacing: 10) {
            Menu {
                ForEach(FanSensor.allCases, id: \.self) { s in
                    Button {
                        draftCurve.sensors[i] = s
                        draftCurve = draftCurve.validated
                    } label: {
                        Text(state.temperatures.value(s).map { "\(s.title)  \(FanText.celsius($0))" } ?? "\(s.title)  (not available)")
                    }
                }
            } label: {
                Text(sensor.title)
            }
            .menuStyle(.button).fixedSize()
            .accessibilityLabel("Curve sensor")
            .accessibilityValue(sensor.title)
            Text(state.temperatures.value(sensor).map { FanText.celsius($0) } ?? "—")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.secondary).monospacedDigit()
                .accessibilityLabel("\(sensor.title) temperature")
            Spacer()
            if i > 0 {
                Button { draftCurve.sensors.remove(at: i) } label: {
                    Image(systemName: "minus.circle").font(.system(size: 16)).foregroundStyle(Palette.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(sensor.title) sensor")
            }
        }
        .frame(minHeight: 44)
    }

    private var pointColumns: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Temperature (°C)")
                Spacer()
                Text("Fan speed")
            }
            .font(.system(size: 14)).foregroundStyle(Palette.secondary)
            ForEach(draftCurve.points.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Text("\(draftCurve.points[i].tempC)°").monospacedDigit().frame(width: 40, alignment: .trailing)
                    Stepper("Point \(i + 1) temperature", value: tempBinding(i), in: FanCurve.tempRange).labelsHidden()
                        .accessibilityValue("\(draftCurve.points[i].tempC) degrees Celsius")
                    if draftCurve.points.count > 2 {
                        Button { draftCurve.points.remove(at: i) } label: {
                            Image(systemName: "minus.circle").foregroundStyle(Palette.secondary).frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Remove point \(i + 1)")
                    }
                    Spacer()
                    Text(draftCurve.points[i].percent == 0 ? "macOS" : "\(draftCurve.points[i].percent)%").monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                    Stepper("Point \(i + 1) fan speed", value: percentBinding(i), in: FanCurve.percentRange, step: 5).labelsHidden()
                        .accessibilityValue(draftCurve.points[i].percent == 0 ? "macOS decides" : "\(draftCurve.points[i].percent) percent")
                }
                .font(.system(size: 15))
                .frame(minHeight: 44)
            }
            Text("0% lets macOS decide, so the fan can stay off when the Mac is cool.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Temperatures stay strictly increasing: a point cannot pass its neighbours.
    private func tempBinding(_ i: Int) -> Binding<Int> {
        Binding(get: { draftCurve.points[i].tempC }, set: { v in
            let lo = i > 0 ? draftCurve.points[i - 1].tempC + 1 : FanCurve.tempRange.lowerBound
            let hi = i + 1 < draftCurve.points.count ? draftCurve.points[i + 1].tempC - 1 : FanCurve.tempRange.upperBound
            draftCurve.points[i].tempC = min(max(v, lo), hi)
        })
    }

    private func percentBinding(_ i: Int) -> Binding<Int> {
        Binding(get: { draftCurve.points[i].percent }, set: { draftCurve.points[i].percent = min(max($0, 0), 100) })
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

    private func linkButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.system(size: 15)).frame(minHeight: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
    }
}

/// System | Manual | Curve, the selected segment a lighter raised pill. `pending`: the selected segment is not the mode
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

/// Temperature (40-100 C) across, fan speed (0-100%) up. Points can be dragged; the steppers below do the same.
private struct CurveChart: View {
    @Binding var curve: FanCurve
    let current: Double?
    private let tMin = Double(FanCurve.tempRange.lowerBound), tMax = Double(FanCurve.tempRange.upperBound)

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 12
            let w = geo.size.width - inset * 2, h = geo.size.height - inset * 2
            let point = { (p: FanCurvePoint) in
                CGPoint(x: inset + w * CGFloat((Double(p.tempC) - tMin) / (tMax - tMin)), y: inset + h * (1 - CGFloat(p.percent) / 100))
            }
            ZStack(alignment: .topLeading) {
                ForEach(1..<5) { i in
                    Path { p in let y = inset + h * CGFloat(i) / 5; p.move(to: CGPoint(x: inset, y: y)); p.addLine(to: CGPoint(x: inset + w, y: y)) }
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
                if let c = current, (tMin...tMax).contains(c) {
                    let x = inset + w * CGFloat((c - tMin) / (tMax - tMin))
                    Path { p in p.move(to: CGPoint(x: x, y: inset)); p.addLine(to: CGPoint(x: x, y: inset + h)) }
                        .stroke(Palette.amber.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                Path { p in p.addLines(curve.points.map(point)) }
                    .stroke(Palette.flowLight, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                ForEach(curve.points.indices, id: \.self) { i in
                    Circle().fill(Palette.flowLight).overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .frame(width: 14, height: 14)
                        .frame(width: 30, height: 30).contentShape(Circle())
                        .position(point(curve.points[i]))
                        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                            let t = tMin + Double((g.location.x - inset) / max(w, 1)) * (tMax - tMin)
                            let pct = Double(1 - (g.location.y - inset) / max(h, 1)) * 100
                            let lo = i > 0 ? curve.points[i - 1].tempC + 1 : FanCurve.tempRange.lowerBound
                            let hi = i + 1 < curve.points.count ? curve.points[i + 1].tempC - 1 : FanCurve.tempRange.upperBound
                            curve.points[i].tempC = min(max(Int(t.rounded()), lo), hi)
                            curve.points[i].percent = min(max(Int((pct / 5).rounded()) * 5, 0), 100)
                        })
                        .accessibilityHidden(true)
                }
                Text("40°").font(.system(size: 10)).foregroundStyle(Palette.secondary).position(x: inset + 8, y: inset + h + 2)
                Text("100°").font(.system(size: 10)).foregroundStyle(Palette.secondary).position(x: inset + w - 10, y: inset + h + 2)
            }
        }
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fan curve")
        .accessibilityValue(curve.points.map { "\($0.tempC) degrees, \($0.percent == 0 ? "macOS" : "\($0.percent) percent")" }.joined(separator: "; "))
        .accessibilityHint("Change the points with the steppers below.")
    }
}
