import SwiftUI
import ConceptShared

struct SystemTab: View {
    @State private var awake = Mock.keepAwakeSelected
    @State private var flags: [String: Bool] = {
        var d = Dictionary(uniqueKeysWithValues: Mock.quickToggles.map { ($0.id, $0.isOn) })
        d["volume"] = Mock.volumeGuardOn; d["bt"] = Mock.bluetoothInSleepOn
        return d
    }()

    private var toggles: [(String, String)] {
        Mock.quickToggles.map { ($0.id, $0.title) } + [("volume", "Volume guard, \(Mock.volumeGuardCap)%"), ("bt", "Bluetooth off in sleep")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 16) { tile(Mock.cpu, "100%"); tile(Mock.gpu, "100%") }
                HStack(alignment: .top, spacing: 16) { tile(Mock.memory, "24 GB"); tile(Mock.network, "8 MB/s") }
            }
            VStack(spacing: 6) {
                HStack {
                    Text("Disk").font(hn(12)).foregroundStyle(T.ink2)
                    Spacer()
                    Text("\(Mock.diskUsedGB) of \(Mock.diskTotalGB) GB").font(hn(13, true)).foregroundStyle(T.ink).monospacedDigit()
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(T.line)
                        RoundedRectangle(cornerRadius: 2).fill(T.ink).frame(width: g.size.width * CGFloat(Mock.diskUsedGB) / CGFloat(Mock.diskTotalGB))
                    }
                }.frame(height: 6)
                HStack(spacing: 16) {
                    Reading(label: "SoC temperature", value: "\(Mock.socTempC) °C")
                    Reading(label: "Fans", value: "Idle, \(Mock.fanRPM) rpm")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Keep awake").font(hn(13, true)).foregroundStyle(T.ink)
                    Spacer()
                    Text("Off").font(hn(12)).foregroundStyle(T.ink2)
                }
                HStack(spacing: 4) {
                    ForEach(Array(Mock.keepAwakeOptions.enumerated()), id: \.offset) { i, o in
                        Button { awake = i } label: {
                            Text(o).font(hn(12, i == awake)).lineLimit(1).fixedSize()
                                .foregroundStyle(i == awake ? T.bg : T.ink)
                                .padding(.horizontal, 8).frame(height: 28)
                                .background(i == awake ? T.ink : T.surface, in: RoundedRectangle(cornerRadius: T.radius))
                                .overlay(RoundedRectangle(cornerRadius: T.radius).strokeBorder(T.line, lineWidth: i == awake ? 0 : T.hair))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(i == awake ? .isSelected : [])
                    }
                }
            }

            Grouped {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text("Fan safe mode").font(hn(13, true)); Text("Off").font(hn(12)).foregroundStyle(T.ink2) }
                        Text("Raises fan speed above the system curve, never below.").font(hn(12)).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
                        Text("Needs the admin helper.").font(hn(12)).foregroundStyle(T.ink2)
                    }
                    .foregroundStyle(T.ink)
                    Spacer(minLength: 0)
                    Button("Turn on") { }.buttonStyle(InkButtonStyle())
                }
                .padding(12)
            }

            let rows = stride(from: 0, to: toggles.count, by: 2).map { Array(toggles[$0..<min($0 + 2, toggles.count)]) }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
                    Hair()
                    HStack(spacing: 0) {
                        ForEach(Array(pair.enumerated()), id: \.offset) { j, t in
                            Toggle(isOn: Binding(get: { flags[t.0] ?? false }, set: { flags[t.0] = $0 })) {
                                Text(t.1).font(hn(12)).foregroundStyle(T.ink).lineLimit(1)
                            }
                            .toggleStyle(switchStyle())
                            .padding(.leading, j == 0 ? 0 : 10).padding(.trailing, j == 0 ? 10 : 0)
                            .frame(maxWidth: .infinity)
                            if j == 0 && pair.count > 1 { VHair() }
                        }
                        if pair.count == 1 { Spacer().frame(maxWidth: .infinity) }
                    }
                    .frame(height: 32)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func tile(_ s: StatSeries, _ top: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Hair().padding(.bottom, 6)
            Text(s.name).font(hn(12)).foregroundStyle(T.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(s.value).font(hn(20, true)).foregroundStyle(T.ink).monospacedDigit()
                Text(s.unit).font(hn(11)).foregroundStyle(T.ink2).lineLimit(1)
            }
            MonitorChart(series: s.history, top: top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
