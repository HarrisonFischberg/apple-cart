import SwiftUI
import AppKit
import ConceptShared

/// The last 24 hours drawn as the map. The purple dashed line is the limit and can be dragged.
struct CourseMap: View {
    @Binding var limit: Int
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let left: CGFloat = 32, right: CGFloat = 16, top: CGFloat = 8, bottom: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(x: left, y: top, width: geo.size.width - left - right,
                              height: geo.size.height - top - bottom)
            let x = { (h: Double) in plot.minX + CGFloat((24 - h) / 24) * plot.width }
            let y = { (p: Double) in plot.maxY - CGFloat(p / 100) * plot.height }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in draw(&ctx, plot: plot, x: x, y: y) }
                    .accessibilityLabel("Charge over the last 24 hours, now 74 percent")

                // Drag layer: the whole plot sets the limit, snapping to 5.
                Color.clear
                    .frame(width: plot.width, height: plot.height + 12)
                    .position(x: plot.midX, y: plot.midY)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let p = (1 - (v.location.y - plot.minY) / plot.height) * 100
                        set(Int((p / 5).rounded()) * 5)
                    })
                    .focusable()
                    .focused($focused)
                    .onKeyPress(.upArrow) { set(limit + 5); return .handled }
                    .onKeyPress(.downArrow) { set(limit - 5); return .handled }
                    .accessibilityElement()
                    .accessibilityLabel("Charge limit")
                    .accessibilityValue("\(limit) percent")
                    .accessibilityAdjustableAction { d in set(limit + (d == .increment ? 5 : -5)) }

                ForEach(Mock.events) { e in
                    ControlMark(n: e.id, style: e.id == Mock.events.count ? .active : .done, size: 18)
                        .position(x: x(e.hoursAgo), y: y(e.percent))
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 10, weight: .regular))
                    Text("Limit \(limit)%").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                }
                .foregroundStyle(T.onPurple)
                .padding(.horizontal, 7).frame(height: 19)
                .background(Capsule().fill(T.purple))
                .position(x: plot.minX + 46, y: y(Double(limit)))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func set(_ v: Int) {
        let n = min(100, max(20, v))
        guard n != limit else { return }
        if reduceMotion { limit = n } else { withAnimation(.snappy(duration: 0.15)) { limit = n } }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    private func draw(_ ctx: inout GraphicsContext, plot: CGRect, x: (Double) -> CGFloat, y: (Double) -> CGFloat) {
        drawContours(&ctx, in: plot)

        // Plugged-in spans: blue wash plus a solid blue bar on the baseline.
        let hist = Mock.history
        var i = 0
        while i < hist.count {
            guard hist[i].pluggedIn else { i += 1; continue }
            var j = i
            while j + 1 < hist.count && hist[j + 1].pluggedIn { j += 1 }
            let r = CGRect(x: x(hist[i].hoursAgo), y: plot.minY,
                           width: x(hist[j].hoursAgo) - x(hist[i].hoursAgo), height: plot.height)
            ctx.fill(Path(r), with: .color(T.blueFill.opacity(0.16)))
            ctx.fill(Path(CGRect(x: r.minX, y: plot.maxY - 3, width: r.width, height: 3)), with: .color(T.blueFill))
            i = j + 1
        }
        // Heat pause: from control 5 to now.
        if let e = Mock.events.last {
            let r = CGRect(x: x(e.hoursAgo), y: plot.minY, width: plot.maxX - x(e.hoursAgo), height: plot.height)
            ctx.fill(Path(r), with: .color(T.oliveFill.opacity(0.3)))
        }

        // Axes.
        for p in stride(from: 0, through: 100, by: 25) {
            var l = Path(); l.move(to: CGPoint(x: plot.minX, y: y(Double(p)))); l.addLine(to: CGPoint(x: plot.maxX, y: y(Double(p))))
            ctx.stroke(l, with: .color(T.hair), lineWidth: 0.5)
            ctx.draw(Text("\(p)").font(T.num(11, .medium)).foregroundStyle(T.ink2),
                     at: CGPoint(x: plot.minX - 6, y: y(Double(p))), anchor: .trailing)
        }
        for (k, h) in [24.0, 18, 12, 6, 0].enumerated() {
            let anchor: UnitPoint = k == 0 ? .topLeading : (k == 4 ? .topTrailing : .top)
            ctx.draw(Text(Mock.clock(hoursAgo: h)).font(T.num(11, .medium)).foregroundStyle(T.ink2),
                     at: CGPoint(x: x(h), y: plot.maxY + 3), anchor: anchor)
        }

        // Limit line (the course).
        var lim = Path(); lim.move(to: CGPoint(x: plot.minX, y: y(Double(limit)))); lim.addLine(to: CGPoint(x: plot.maxX, y: y(Double(limit))))
        ctx.stroke(lim, with: .color(T.purple), style: StrokeStyle(lineWidth: 1.6, dash: [6, 3]))

        // Charge curve.
        var c = Path()
        for (k, p) in hist.enumerated() {
            let pt = CGPoint(x: x(p.hoursAgo), y: y(p.percent))
            if k == 0 { c.move(to: pt) } else { c.addLine(to: pt) }
        }
        ctx.stroke(c, with: .color(T.ink), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))

        // Now marker.
        ctx.fill(Path(CGRect(x: plot.maxX - 1.5, y: plot.minY, width: 3, height: plot.height)), with: .color(T.yellow))
    }
}

/// Key for the chart's non-control marks.
struct MapKey: View {
    var body: some View {
        HStack(spacing: 14) {
            item(RoundedRectangle(cornerRadius: 1).fill(T.blueFill.opacity(0.35)).overlay(alignment: .bottom) {
                Rectangle().fill(T.blueFill).frame(height: 2) }, "Plugged in")
            item(RoundedRectangle(cornerRadius: 1).fill(T.oliveFill.opacity(0.5)), "Heat pause")
            item(Line().stroke(T.purple, style: StrokeStyle(lineWidth: 1.6, dash: [4, 2])), "Charge limit")
            item(Rectangle().fill(T.yellow), "Now")
            Spacer(minLength: 0)
        }
        .font(.system(size: 11)).foregroundStyle(T.ink2)
    }
    private func item<S: View>(_ s: S, _ t: String) -> some View {
        HStack(spacing: 5) { s.frame(width: 14, height: 10); Text(t) }
    }
    private struct Line: Shape {
        func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
    }
}
