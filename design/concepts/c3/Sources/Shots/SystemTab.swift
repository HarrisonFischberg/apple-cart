import SwiftUI
import ConceptShared

struct SystemTab: View {
    @State private var keepAwake = false
    @State private var duration = Mock.keepAwakeSelected
    @State private var toggles: [Bool] = Mock.quickToggles.map(\.isOn) + [Mock.volumeGuardOn, Mock.bluetoothInSleepOn]

    private var toggleTitles: [String] {
        Mock.quickToggles.map(\.title) + ["Volume guard, cap \(Mock.volumeGuardCap)%", "Bluetooth off in sleep"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Monitor(series: Mock.cpu, yTop: "100%", yMax: 1, headValue: "23%", sub: nil)
                Monitor(series: Mock.gpu, yTop: "100%", yMax: 1, headValue: "8%", sub: nil)
            }
            HStack(alignment: .top, spacing: 12) {
                Monitor(series: Mock.memory, yTop: "24 GB", yMax: 1, headValue: "11.2 GB", sub: "of 24 GB")
                Monitor(series: Mock.network, yTop: netTop, yMax: 1, headValue: "1.2 MB/s", sub: "down · 0.2 up")
            }.padding(.top, 10)
            disk.padding(.top, 12)
            HStack(spacing: 12) {
                pair("SoC temperature", "\(Mock.socTempC) °C")
                pair("Fans", "idle, \(Mock.fanRPM) rpm")
            }.padding(.top, 6)
            keepAwakeBlock.padding(.top, 14)
            fanSafe.padding(.top, 12)
            toggleGrid.padding(.top, 10)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
    }

    // The network axis top is derived so the last sample equals the shown 1.2 MB/s.
    private var netMax: Double { 1.2 / (Mock.network.history.last ?? 0.14) }
    private var netTop: String { String(format: "%.0f MB/s", netMax) }

    private var disk: some View {
        HStack(spacing: 10) {
            Text("Disk").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(T.ink)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(T.hair)
                    Capsule().fill(T.blueFill).frame(width: g.size.width * CGFloat(Mock.diskUsedGB) / CGFloat(Mock.diskTotalGB))
                }
            }.frame(height: 8)
            Text("\(Mock.diskUsedGB) of \(Mock.diskTotalGB) GB").font(.system(size: 12)).monospacedDigit().foregroundStyle(T.ink)
        }
        .frame(height: 22)
        .accessibilityElement(children: .combine)
    }

    private func pair(_ l: String, _ v: String) -> some View {
        HStack {
            Text(l).foregroundStyle(T.ink2)
            Spacer(minLength: 6)
            Text(v).font(.system(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink)
        }.font(.system(size: 12)).frame(height: 20).frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var keepAwakeBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $keepAwake) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Keep awake").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.ink)
                    Text("Off. Your Mac sleeps as usual.").font(.system(size: 11.5)).foregroundStyle(T.ink2)
                }
            }.toggleStyle(PreviewSwitchStyle(tint: T.blueSolid, offTrack: T.ink.opacity(0.22)))
            HStack(spacing: 5) {
                ForEach(Mock.keepAwakeOptions.indices, id: \.self) { i in
                    Button { duration = i } label: {
                        Text(Mock.keepAwakeOptions[i]).font(.system(size: 12, weight: i == duration ? .semibold : .regular))
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 8).frame(maxWidth: .infinity).frame(height: 26)
                            .foregroundStyle(i == duration ? T.onBlue : T.ink)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(i == duration ? T.blueSolid : T.ink.opacity(0.08)))
                    }.buttonStyle(PressStyle())
                    .accessibilityAddTraits(i == duration ? .isSelected : [])
                }
            }
        }
    }

    private var fanSafe: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(T.hair).frame(height: 1)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "fan").font(.system(size: 18, weight: .regular)).foregroundStyle(T.ink2).frame(width: 24).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Fan safe mode").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.ink)
                        Spacer()
                        Text("Off").font(.system(size: 12)).foregroundStyle(T.ink2)
                    }
                    Text("Raises fan speed above the system curve, never below.").font(.system(size: 12)).foregroundStyle(T.ink)
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield").font(.system(size: 11, weight: .regular))
                        Text("Needs the admin helper.").font(.system(size: 11.5))
                    }.foregroundStyle(T.ink2)
                    Button { } label: {
                        Text("Turn on").font(.system(size: 12.5, weight: .medium)).padding(.horizontal, 14).frame(height: 26)
                            .foregroundStyle(T.ink).background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(T.ink.opacity(0.09)))
                    }.buttonStyle(PressStyle()).padding(.top, 3)
                }
            }.padding(.top, 10)
        }
    }

    private var toggleGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 4) {
            ForEach(toggles.indices, id: \.self) { i in
                Toggle(isOn: $toggles[i]) {
                    Text(toggleTitles[i]).font(.system(size: 12)).foregroundStyle(T.ink).lineLimit(1).minimumScaleFactor(0.9)
                }.toggleStyle(PreviewSwitchStyle(tint: T.blueSolid, offTrack: T.ink.opacity(0.22)))
                .frame(height: 24)
            }
        }
    }
}

/// One monitor: value in the header, 60 s history with labelled axes.
struct Monitor: View {
    let series: StatSeries
    let yTop: String
    let yMax: Double
    let headValue: String
    let sub: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(series.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(T.ink)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(headValue).font(T.num(20, .bold)).foregroundStyle(T.blueText)
                    Text(sub ?? " ").font(.system(size: 11)).foregroundStyle(T.ink2)
                }
            }.frame(height: 36)
            Canvas { ctx, size in
                let plot = CGRect(x: 40, y: 3, width: size.width - 40 - 3, height: size.height - 3 - 15)
                drawContours(&ctx, in: plot)
                for (f, t) in [(0.0, "0"), (1.0, yTop)] {
                    let yy = plot.maxY - plot.height * f
                    var l = Path(); l.move(to: CGPoint(x: plot.minX, y: yy)); l.addLine(to: CGPoint(x: plot.maxX, y: yy))
                    ctx.stroke(l, with: .color(T.hair), lineWidth: 0.5)
                    ctx.draw(Text(t).font(T.num(11, .medium)).foregroundStyle(T.ink2),
                             at: CGPoint(x: plot.minX - 5, y: f == 1 ? yy + 5 : yy), anchor: .trailing)
                }
                let h = series.history
                var line = Path(), area = Path()
                for (i, v) in h.enumerated() {
                    let pt = CGPoint(x: plot.minX + plot.width * CGFloat(i) / CGFloat(h.count - 1),
                                     y: plot.maxY - plot.height * CGFloat(v))
                    if i == 0 { line.move(to: pt); area.move(to: CGPoint(x: pt.x, y: plot.maxY)); area.addLine(to: pt) }
                    else { line.addLine(to: pt); area.addLine(to: pt) }
                }
                area.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY)); area.closeSubpath()
                ctx.fill(area, with: .color(T.blueFill.opacity(0.16)))
                ctx.stroke(line, with: .color(T.blueFill), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                ctx.draw(Text("60 s ago").font(T.num(11, .medium)).foregroundStyle(T.ink2), at: CGPoint(x: plot.minX, y: plot.maxY + 3), anchor: .topLeading)
                ctx.draw(Text("30 s").font(T.num(11, .medium)).foregroundStyle(T.ink2), at: CGPoint(x: plot.midX, y: plot.maxY + 3), anchor: .top)
                ctx.draw(Text("now").font(T.num(11, .medium)).foregroundStyle(T.ink2), at: CGPoint(x: plot.maxX, y: plot.maxY + 3), anchor: .topTrailing)
            }.frame(height: 66)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(series.name) \(headValue) \(sub ?? ""), last 60 seconds")
    }
}
