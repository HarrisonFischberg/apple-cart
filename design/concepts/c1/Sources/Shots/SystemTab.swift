import SwiftUI
import ConceptShared

struct SystemTab: View {
    @State private var awake = Mock.keepAwakeSelected
    @State private var keepAwakeRunning = false
    @State private var toggles: [String: Bool] = Dictionary(uniqueKeysWithValues: Mock.quickToggles.map { ($0.id, $0.isOn) })
    @State private var volumeGuard = Mock.volumeGuardOn
    @State private var btSleep = Mock.bluetoothInSleepOn

    private var sw: PreviewSwitchStyle { PreviewSwitchStyle(tint: T.yellow, offTrack: T.rule) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Grid(horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    monitor(Mock.cpu, y: [(0, "0%"), (1, "100%")])
                    monitor(Mock.gpu, y: [(0, "0%"), (1, "100%")])
                }
                GridRow {
                    monitor(Mock.memory, y: [(0, "0"), (1, "24 GB")])
                    monitor(Mock.network, y: [(0, "0"), (1, "peak")])
                }
            }
            .padding(.horizontal, T.pad).padding(.top, 14)
            disk.padding(.horizontal, T.pad).padding(.top, 14)
            keepAwake.padding(.horizontal, T.pad).padding(.top, 18)
            fanSafe.padding(.horizontal, T.pad).padding(.top, 18)
            toggleList.padding(.horizontal, T.pad).padding(.top, 18)
            Spacer(minLength: 0)
        }
    }

    private func monitor(_ s: StatSeries, y: [(Double, String)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline) {
                Text(s.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(T.ink)
                Spacer()
                Text(s.value).font(T.din(24)).foregroundStyle(T.ink)
            }
            HStack {
                Spacer()
                Text(s.unit).font(T.small).foregroundStyle(T.ink2).lineLimit(1)
            }
            AxisChart(yLabels: y, xLabels: [(0, "60 s"), (1, "now")], height: 40, yWidth: 34) {
                Canvas { ctx, size in
                    var line = Path(), fill = Path()
                    let n = s.history.count
                    for (i, v) in s.history.enumerated() {
                        let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(n - 1), y: size.height * (1 - CGFloat(v)))
                        i == 0 ? line.move(to: pt) : line.addLine(to: pt)
                    }
                    fill = line
                    fill.addLine(to: CGPoint(x: size.width, y: size.height))
                    fill.addLine(to: CGPoint(x: 0, y: size.height))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .color(T.yellow.opacity(0.55)))
                    ctx.stroke(line, with: .color(T.ink), lineWidth: 1.25)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var disk: some View {
        let used = Double(Mock.diskUsedGB) / Double(Mock.diskTotalGB)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Disk").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.ink)
                Spacer()
                Text("\(Mock.diskUsedGB)").font(T.din(17)).foregroundStyle(T.ink)
                Text("of \(Mock.diskTotalGB) GB used").font(T.small).foregroundStyle(T.ink2)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(T.well)
                    Rectangle().fill(T.yellow).frame(width: g.size.width * used)
                }
            }
            .frame(height: 10)
            .overlay(Rectangle().strokeBorder(T.ink2.opacity(0.6), lineWidth: 1))
            HStack {
                Text("SoC temperature").font(T.label).foregroundStyle(T.ink)
                Spacer()
                Text("\(Mock.socTempC) °C").font(T.din(17)).foregroundStyle(T.ink)
            }.padding(.top, 5)
            HStack {
                Text("Fans").font(T.label).foregroundStyle(T.ink)
                Text("idle").font(T.small).foregroundStyle(T.ink2)
                Spacer()
                Text("\(Mock.fanRPM) rpm").font(T.din(17)).foregroundStyle(T.ink)
            }
        }
    }

    private var keepAwake: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keep awake").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.ink)
                Spacer()
                Text(keepAwakeRunning ? "Running" : "Off").font(T.small).foregroundStyle(T.ink2)
            }
            HStack(spacing: 4) {
                ForEach(Mock.keepAwakeOptions.indices, id: \.self) { i in
                    Button { awake = i } label: {
                        Text(Mock.keepAwakeOptions[i])
                            .font(.system(size: 11, weight: awake == i ? .semibold : .regular))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(awake == i ? T.onYellow : T.ink)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(RoundedRectangle(cornerRadius: 5).fill(awake == i ? T.yellow : T.well))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(awake == i ? T.onYellow.opacity(0.0) : T.rule, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Keep awake \(Mock.keepAwakeOptions[i])")
                    .accessibilityAddTraits(awake == i ? .isSelected : [])
                }
            }
        }
    }

    private var fanSafe: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Fan safe mode").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.ink)
                Spacer()
                Text("Off").font(T.small).foregroundStyle(T.ink2)
            }
            Text("Raises fan speed above the system curve, never below.")
                .font(T.label).foregroundStyle(T.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("Needs the admin helper.").font(T.small).foregroundStyle(T.ink2)
                Spacer()
                Button("Turn on") {}.buttonStyle(SecondaryButton()).frame(width: 90)
            }
            .padding(.top, 4)
        }
    }

    private var toggleList: some View {
        VStack(spacing: 0) {
            ForEach(Mock.quickToggles) { t in
                toggleRow(title: t.title, detail: t.detail,
                          isOn: Binding(get: { toggles[t.id] ?? false }, set: { toggles[t.id] = $0 }))
                Rule()
            }
            toggleRow(title: "Volume guard", detail: "Cap at \(Mock.volumeGuardCap)%", isOn: $volumeGuard)
            Rule()
            toggleRow(title: "Bluetooth off in sleep", detail: "Saves battery overnight", isOn: $btSleep)
        }
    }
    private func toggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(T.label).foregroundStyle(T.ink)
                Text(detail).font(T.small).foregroundStyle(T.ink2)
            }
        }
        .toggleStyle(PreviewSwitchStyle(tint: T.yellow, offTrack: T.ink2.opacity(0.55)))
        .padding(.vertical, 4)
    }
}
