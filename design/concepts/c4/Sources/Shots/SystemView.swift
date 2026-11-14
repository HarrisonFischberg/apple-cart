import SwiftUI
import ConceptShared

struct ToggleTile: View {
    let icon: String, title: String
    @State var on: Bool
    var detail: String
    var body: some View {
        Tile(icon: icon, title: title) {
            Spacer(minLength: 0)
            Toggle(isOn: $on) { Caption(detail, color: T.text) }
                .toggleStyle(T.switchStyle()).accessibilityLabel("\(title), \(detail)")
        }
    }
}

struct NetChart: View {
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack { Text("Peak"); Spacer(); Text("0") }
                .font(.system(size: 11)).foregroundStyle(T.secondary).frame(width: 28, height: 52, alignment: .trailing)
            VStack(spacing: 2) {
                Canvas { ctx, size in
                    let h = Mock.network.history
                    var p = Path()
                    for (i, v) in h.enumerated() {
                        let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(h.count - 1), y: size.height * (1 - v))
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                    var base = Path(); base.move(to: CGPoint(x: 0, y: size.height)); base.addLine(to: CGPoint(x: size.width, y: size.height))
                    ctx.stroke(base, with: .color(T.track), lineWidth: 1)
                    ctx.stroke(p, with: .color(T.blue), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }.frame(height: 52)
                HStack { Text("60 s ago"); Spacer(); Text("now") }.font(.system(size: 11)).foregroundStyle(T.secondary)
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Download speed over the last 60 seconds")
    }
}

struct SystemView: View {
    @State var toggles = Mock.quickToggles.map(\.isOn)
    @State var awake = Mock.keepAwakeSelected
    static let rows: [CGFloat] = [120, 148, 128, 84, 168, 200]
    static var height: CGFloat { T.shotHeight(rows: rows) }
    var body: some View {
        ScrollView {
            VStack(spacing: T.gap) {
                TileRow(height: Self.rows[0]) {
                    stat("cpu", Mock.cpu); stat("display", Mock.gpu)
                    Tile(icon: "memorychip", title: "Memory") {
                        Spacer(minLength: 0)
                        Value(text: Mock.memory.value); Caption("of 24 GB")
                        Bar(fraction: 11.2 / 24)
                    }
                }
                TileRow(height: Self.rows[1]) {
                    Tile(icon: "arrow.up.arrow.down", title: "Network", span: .two) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Value(text: Mock.network.value, suffix: " MB/s"); Caption("down, 0.2 up")
                            }.frame(width: 98, alignment: .leading)
                            NetChart()
                        }
                    }
                    Tile(icon: "internaldrive", title: "Disk") {
                        Spacer(minLength: 0)
                        Value(text: "\(Mock.diskUsedGB)"); Caption("of \(Mock.diskTotalGB) GB")
                        Bar(fraction: Double(Mock.diskUsedGB) / Double(Mock.diskTotalGB))
                        Caption("\(Mock.diskTotalGB - Mock.diskUsedGB) GB free")
                    }
                }
                TileRow(height: Self.rows[2]) {
                    Tile(icon: "powerplug", title: "Power") {
                        Value(text: String(format: "%.1f", Mock.wattsToMac), suffix: " W"); Caption("to Mac")
                        Caption("\(Mock.adapterRatedWatts) W adapter")
                    }
                    Tile(icon: "thermometer.medium", title: "Thermals", span: .two) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) { Value(text: "\(Mock.socTempC)", suffix: " °C"); Caption("SoC temperature") }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Value(text: "\(Mock.fanRPM)", suffix: " rpm"); Caption("Fans idle")
                                Bar(fraction: Double(Mock.fanRPM) / Double(Mock.fanMaxRPM), tint: T.green)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                TileRow(height: Self.rows[3]) {
                    Tile(icon: "cup.and.saucer", title: "Keep awake", span: .three, trailing: { Caption("Off") }) {
                        HStack(spacing: 6) {
                            ForEach(Array(Mock.keepAwakeOptions.enumerated()), id: \.offset) { i, o in
                                Button { awake = i } label: { Chip(text: o, selected: i == awake) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                TileRow(height: Self.rows[4]) {
                    Tile(icon: "fan", title: "Fan safe mode", span: .two, trailing: { Caption("Off") }) {
                        Text("Raises fan speed above the system curve, never below.").font(.system(size: 12)).foregroundStyle(T.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Caption("Needs the admin helper.")
                        Spacer(minLength: 0)
                        SmallButton(title: "Turn on", filled: true).frame(width: 96)
                    }
                    VStack(spacing: T.gap) {
                        ToggleTile(icon: "speaker.wave.2", title: "Volume guard", on: Mock.volumeGuardOn, detail: "Cap \(Mock.volumeGuardCap)%")
                        ToggleTile(icon: "dot.radiowaves.left.and.right", title: "Bluetooth", on: Mock.bluetoothInSleepOn, detail: "Off in sleep")
                    }
                }
                TileRow(height: Self.rows[5]) {
                    Tile(icon: "switch.2", title: "Quick toggles", span: .three) {
                        VStack(spacing: 0) {
                            ForEach(Array(Mock.quickToggles.enumerated()), id: \.offset) { i, t in
                                Toggle(isOn: $toggles[i]) {
                                    Text(t.title).font(.system(size: 13)).foregroundStyle(T.text)
                                }
                                .toggleStyle(T.switchStyle()).accessibilityLabel(t.title).frame(height: 30)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, T.pad).padding(.bottom, T.pad)
        }
    }
    private func stat(_ icon: String, _ s: StatSeries) -> some View {
        Tile(icon: icon, title: s.name) {
            Spacer(minLength: 0)
            Value(text: s.value, suffix: s.unit)
            Bar(fraction: (Double(s.value) ?? 0) / 100)
        }
    }
}
