import AppKit
import Core
import SwiftUI

/// Temperatures, CPU and GPU load with live graphs, memory, uptime. Samples only while `active`.
public struct SystemView: View {
    let sampler: SystemSampler
    let active: Bool
    @State private var expanded: Set<Row> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Row: Hashable { case cpu, gpu, memory }

    /// `expandAll` opens every app list, for previews.
    public init(sampler: SystemSampler, active: Bool, expandAll: Bool = false) {
        self.sampler = sampler
        self.active = active
        _expanded = State(initialValue: expandAll ? [.cpu, .gpu, .memory] : [])
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let r = sampler.latest {
                    VStack(alignment: .leading, spacing: 14) {
                        temperatures(r)
                        divider
                        usage(r)
                        divider
                        memory(r)
                        divider
                        footer(r)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        // Same card as the battery view: the tile with a faint wash of the flow blue from the top.
                        let card = RoundedRectangle(cornerRadius: 18, style: .continuous)
                        card.fill(Palette.tile)
                            .overlay(card.fill(LinearGradient(colors: [Palette.flow.opacity(0.07), .clear], startPoint: .top, endPoint: .bottom)))
                            .overlay(card.strokeBorder(.primary.opacity(0.06)))
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .toolPage()
        }
        .task(id: active) { if active { sampler.hold("systemView") } else { sampler.release("systemView") } }
        .onDisappear { sampler.release("systemView") }
    }

    private var divider: some View { Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1).accessibilityHidden(true) }

    private func header(_ title: String) -> some View {
        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.secondary).accessibilityAddTraits(.isHeader)
    }

    // MARK: Temperatures

    private func temperatures(_ r: SystemReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Temperatures")
            HStack(spacing: 10) {
                tempTile("CPU", symbol: "cpu", r.cpuTemperature)
                tempTile("GPU", symbol: "memorychip", r.gpuTemperature)
            }
        }
    }

    private func tempTile(_ title: String, symbol: String, _ c: Double?) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary)
            if let c {
                Text(SystemText.temperature(c)).font(.system(size: 24, weight: .bold)).monospacedDigit()
            } else {
                Text("Not available on this Mac").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) temperature")
        .accessibilityValue(c.map { SystemText.temperature($0) } ?? "Not available on this Mac")
    }

    // MARK: Hardware usage

    private func usage(_ r: SystemReading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                header("Hardware usage")
                Spacer()
                Button(action: openActivityMonitor) {
                    Image(systemName: "arrow.up.forward.square").font(.system(size: 16)).foregroundStyle(Palette.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -12).padding(.trailing, -12) // 44 pt target without pushing the layout
                .help("Open Activity Monitor")
                .accessibilityLabel("Open Activity Monitor")
            }
            usageRow(.cpu, title: "CPU", percent: r.cpuPercent, color: Palette.accent, history: sampler.cpuHistory)
            usageRow(.gpu, title: "GPU", percent: r.gpuPercent, color: Palette.flowLight, history: sampler.gpuHistory)
        }
    }

    private func usageRow(_ row: Row, title: String, percent: Double?, color: Color, history: SampleHistory) -> some View {
        let open = expanded.contains(row)
        let value = percent.map(SystemText.percent) ?? "—"
        return VStack(alignment: .leading, spacing: 2) {
            Button { toggle(row) } label: {
                HStack(spacing: 10) {
                    chevron(open)
                    Text(title).font(.system(size: 15)).frame(width: 40, alignment: .leading)
                    UsageBar(fraction: (percent ?? 0) / 100, color: color)
                    Text(value).font(.system(size: 15)).monospacedDigit().frame(minWidth: 44, alignment: .trailing)
                }
                .frame(minHeight: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) usage")
            .accessibilityValue(percent == nil ? "Measuring" : "\(Int(percent!.rounded())) percent")
            .accessibilityHint(open ? "Hides the apps using the \(title)" : "Shows the apps using the \(title)")
            if open { appList(row) }
            Sparkline(values: history.values, capacity: SystemSampler.historyLength, color: color)
                .frame(height: 52)
                .accessibilityElement()
                .accessibilityLabel("\(title) usage, last 2 minutes")
                .accessibilityValue(history.summary)
        }
    }

    // MARK: Memory

    private func memory(_ r: SystemReading) -> some View {
        let open = expanded.contains(.memory)
        return VStack(alignment: .leading, spacing: 6) {
            header("Memory")
            Button { toggle(.memory) } label: {
                HStack(spacing: 10) {
                    chevron(open)
                    Text("Pressure").font(.system(size: 15))
                    if let p = r.pressure { PressurePill(pressure: p) }
                    Spacer(minLength: 4)
                    if let m = r.memory {
                        Text("\(SystemText.bytes(m.used)) / \(SystemText.bytes(m.total))").font(.system(size: 15)).monospacedDigit()
                    }
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Memory pressure")
            .accessibilityValue([r.pressure?.title, r.memory.map { "\(SystemText.bytes($0.used)) of \(SystemText.bytes($0.total)) used" }]
                .compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint(open ? "Hides the apps using memory" : "Shows the apps using the most memory")
            if open { appList(.memory) }
            if let m = r.memory {
                VStack(spacing: 8) {
                    detail("Compressed", m.compressed)
                    detail("Cached files", m.cached)
                    detail("Swap used", m.swapUsed)
                }
                .padding(.leading, 24).padding(.bottom, 4)
            }
            Sparkline(values: sampler.memoryHistory.values, capacity: SystemSampler.historyLength, color: Palette.teal)
                .frame(height: 52)
                .accessibilityElement()
                .accessibilityLabel("Memory used, last 2 minutes")
                .accessibilityValue(sampler.memoryHistory.summary)
        }
    }

    private func detail(_ title: String, _ bytes: UInt64) -> some View {
        HStack { Text(title).foregroundStyle(Palette.secondary); Spacer(); Text(SystemText.bytes(bytes)).monospacedDigit() }
            .font(.system(size: 14))
            .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    private func footer(_ r: SystemReading) -> some View {
        Label(r.uptime.map(SystemText.uptime) ?? "Uptime unknown", systemImage: "clock")
            .font(.system(size: 14)).foregroundStyle(Palette.secondary)
    }

    // MARK: Apps

    @ViewBuilder private func appList(_ row: Row) -> some View {
        let apps: [AppUsage]? = switch row { case .cpu: sampler.cpuApps; case .gpu: sampler.gpuApps; case .memory: sampler.memoryApps }
        VStack(alignment: .leading, spacing: 4) {
            if let apps {
                if row != .memory && !sampler.hasRates {
                    Text("Measuring…").hint()
                } else if apps.isEmpty {
                    Text(row == .memory ? "No apps could be read." : "Nothing is using the \(row == .cpu ? "CPU" : "GPU") right now.").hint()
                }
                ForEach(apps) { a in
                    HStack(spacing: 8) {
                        AppIcon(bundlePath: a.bundlePath)
                        Text(a.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(row == .memory ? SystemText.bytes(UInt64(a.value)) : SystemText.appPercent(a.value))
                            .monospacedDigit().foregroundStyle(Palette.secondary)
                    }
                    .font(.system(size: 13))
                    .frame(minHeight: 24)
                    .accessibilityElement(children: .combine)
                }
                if row != .gpu && !apps.isEmpty {
                    Text("System processes Apple Cart cannot read are left out.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            } else {
                Text("Per-app GPU use is not available on this Mac.").hint()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.leading, 24).padding(.bottom, 6)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }

    private func chevron(_ open: Bool) -> some View {
        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
            .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 14).accessibilityHidden(true)
    }

    private func toggle(_ row: Row) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) {
            if expanded.contains(row) { expanded.remove(row) } else { expanded.insert(row) }
        }
    }

    private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Thin track with a fill for a 0...1 share.
private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(color).frame(width: max(fraction > 0 ? 6 : 0, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// Recent history as a line with a soft fill under it, newest at the right, and a dashed 100% line.
private struct Sparkline: View {
    let values: [Double]
    let capacity: Int
    let color: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let top: CGFloat = 8, bottom = h - 1
                let step = w / CGFloat(max(capacity - 1, 1))
                let points = values.enumerated().map { i, v in
                    CGPoint(x: w - CGFloat(values.count - 1 - i) * step, y: bottom - (bottom - top) * CGFloat(min(max(v, 0), 100) / 100))
                }
                Path { p in p.move(to: CGPoint(x: 0, y: top)); p.addLine(to: CGPoint(x: w, y: top)) }
                    .stroke(Color.primary.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Path { p in p.move(to: CGPoint(x: 0, y: h - 0.5)); p.addLine(to: CGPoint(x: w, y: h - 0.5)) }
                    .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                if points.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: points[0].x, y: bottom))
                        points.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: points[points.count - 1].x, y: bottom))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.32), color.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                    Path { p in p.addLines(points) }
                        .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
            Text("100%").font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(Palette.secondary)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

private struct PressurePill: View {
    let pressure: MemoryPressure

    var body: some View {
        let (dot, text): (Color, Color) = switch pressure {
        case .normal: (Palette.green, Palette.green)
        case .warning: (Palette.amber, Palette.amberText)
        case .critical: (Palette.critical, Palette.critical)
        }
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(pressure.title).font(.system(size: 14, weight: .medium)).foregroundStyle(text)
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(dot.opacity(0.16), in: Capsule())
    }
}

/// The app's own icon from its bundle; bare processes get a generic one.
private struct AppIcon: View {
    let bundlePath: String?

    var body: some View {
        Group {
            if let bundlePath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: bundlePath)).resizable()
            } else {
                Image(systemName: "gearshape").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}
