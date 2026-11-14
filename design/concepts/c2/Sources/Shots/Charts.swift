import SwiftUI
import ConceptShared

/// 24 h charge history: plugged-in spans, charge line, dashed limit line, axis values.
struct HistoryChart: View {
    let limit: Int
    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: 36, y: 6, width: size.width - 40, height: size.height - 28)
            func x(_ h: Double) -> CGFloat { plot.minX + plot.width * CGFloat((24 - h) / 24) }
            func y(_ p: Double) -> CGFloat { plot.maxY - plot.height * CGFloat(p / 100) }
            for v in [0.0, 50, 100] {
                var g = Path(); g.move(to: CGPoint(x: plot.minX, y: y(v))); g.addLine(to: CGPoint(x: plot.maxX, y: y(v)))
                ctx.stroke(g, with: .color(T.line), lineWidth: T.hair)
                ctx.draw(Text("\(Int(v))%").font(hn(11)).foregroundColor(T.ink2), at: CGPoint(x: plot.minX - 5, y: y(v)), anchor: .trailing)
            }
            // plugged-in spans
            var start: Double? = nil
            let pts = Mock.history
            for (i, p) in pts.enumerated() {
                if p.pluggedIn, start == nil { start = p.hoursAgo }
                if let s = start, !p.pluggedIn || i == pts.count - 1 {
                    ctx.fill(Path(CGRect(x: x(s), y: plot.minY, width: x(p.hoursAgo) - x(s), height: plot.height)), with: .color(T.ink.opacity(0.10)))
                    start = nil
                }
            }
            var line = Path()
            for (i, p) in pts.enumerated() { i == 0 ? line.move(to: CGPoint(x: x(p.hoursAgo), y: y(p.percent))) : line.addLine(to: CGPoint(x: x(p.hoursAgo), y: y(p.percent))) }
            ctx.stroke(line, with: .color(T.ink), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            var lim = Path(); lim.move(to: CGPoint(x: plot.minX, y: y(Double(limit)))); lim.addLine(to: CGPoint(x: plot.maxX, y: y(Double(limit))))
            ctx.stroke(lim, with: .color(T.ink), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            for (h, anchor) in [(24.0, UnitPoint.leading), (18, .center), (12, .center), (6, .center), (0, .trailing)] {
                let label = h == 0 ? "Now" : Mock.clock(hoursAgo: h)
                let px = anchor == .leading ? plot.minX : (anchor == .trailing ? plot.maxX : x(h))
                ctx.draw(Text(label).font(hn(11)).foregroundColor(T.ink2), at: CGPoint(x: px, y: size.height - 7), anchor: anchor)
            }
        }
        .frame(height: 120)
        .accessibilityElement()
        .accessibilityLabel("Charge over the last 24 hours, from \(Int(Mock.history.first!.percent)) to \(Int(Mock.percent)) percent, limit \(limit) percent")
    }
}

/// 60 s monitor chart with axis values.
struct MonitorChart: View {
    let series: [Double]
    let top: String
    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: 40, y: 5, width: size.width - 42, height: size.height - 24)
            for (v, t) in [(0.0, "0"), (1.0, top)] {
                let yy = plot.maxY - plot.height * v
                var g = Path(); g.move(to: CGPoint(x: plot.minX, y: yy)); g.addLine(to: CGPoint(x: plot.maxX, y: yy))
                ctx.stroke(g, with: .color(T.line), lineWidth: T.hair)
                ctx.draw(Text(t).font(hn(11)).foregroundColor(T.ink2), at: CGPoint(x: plot.minX - 5, y: yy), anchor: .trailing)
            }
            var p = Path()
            for (i, v) in series.enumerated() {
                let q = CGPoint(x: plot.minX + plot.width * CGFloat(i) / CGFloat(series.count - 1), y: plot.maxY - plot.height * v)
                i == 0 ? p.move(to: q) : p.addLine(to: q)
            }
            ctx.stroke(p, with: .color(T.ink), style: StrokeStyle(lineWidth: 1.25, lineJoin: .round))
            ctx.draw(Text("60 s ago").font(hn(11)).foregroundColor(T.ink2), at: CGPoint(x: plot.minX, y: size.height - 6), anchor: .leading)
            ctx.draw(Text("Now").font(hn(11)).foregroundColor(T.ink2), at: CGPoint(x: plot.maxX, y: size.height - 6), anchor: .trailing)
        }
        .frame(height: 52)
    }
}
