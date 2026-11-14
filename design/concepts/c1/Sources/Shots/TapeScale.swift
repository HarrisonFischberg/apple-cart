import SwiftUI
import ConceptShared

/// The signature control: a tape measure from 0 to 100. Yellow blade = charge, black lock tab = limit.
struct TapeScale: View {
    @Binding var limit: Int
    let charge: Double
    let heatPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging = false
    @FocusState private var focused: Bool

    static let detents = [20, 50, 80, 100]
    static let bladeH: CGFloat = 30
    static let tabW: CGFloat = 34

    private func snap(_ v: Int) -> Int {
        let v = min(max(v, 20), 100)
        if let d = Self.detents.min(by: { abs($0 - v) < abs($1 - v) }), abs(d - v) <= 3 { return d }
        return v
    }

    private func set(_ v: Int) {
        if reduceMotion { limit = v } else { withAnimation(.spring(duration: 0.2, bounce: 0.2)) { limit = v } }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = { (v: Double) -> CGFloat in w * CGFloat(v / 100) }
            ZStack(alignment: .topLeading) {
                // track
                Rectangle().fill(T.well).frame(width: w, height: Self.bladeH).offset(y: 22)
                // blade = charge
                Rectangle().fill(T.yellow).frame(width: x(charge), height: Self.bladeH).offset(y: 22)
                if heatPaused {
                    // heat-pause cap at the end of the blade
                    Rectangle().fill(T.red).frame(width: 3, height: Self.bladeH).offset(x: x(charge) - 3, y: 22)
                }
                // ticks and numerals
                Canvas { ctx, size in
                    for i in 0...100 {
                        let len: CGFloat = i % 10 == 0 ? 15 : (i % 5 == 0 ? 10 : 5)
                        let px = min(max(CGFloat(i) / 100 * size.width, 0.5), size.width - 0.5)
                        var path = Path()
                        path.move(to: CGPoint(x: px, y: 22 + Self.bladeH))
                        path.addLine(to: CGPoint(x: px, y: 22 + Self.bladeH - len))
                        let onBlade = Double(i) <= charge
                        ctx.stroke(path, with: .color(onBlade ? T.onYellow : T.ink2), lineWidth: 1)
                    }
                }
                .frame(width: w, height: 22 + Self.bladeH)
                .allowsHitTesting(false)
                ForEach(Array(stride(from: 0, through: 100, by: 10)), id: \.self) { n in
                    Text("\(n)").font(T.din(13)).foregroundStyle(T.ink2).fixedSize()
                        .position(x: min(max(x(Double(n)), 8), w - 8), y: 22 + Self.bladeH + 11)
                }
                // lock tab
                lockTab
                    .offset(x: min(max(x(Double(limit)) - Self.tabW / 2, 0), w - Self.tabW), y: 0)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tape"))
                        .onChanged { g in
                            dragging = true
                            focused = true
                            let raw = Int((g.location.x / w * 100).rounded())
                            let v = snap(raw)
                            if v != limit { set(v) }
                        }
                        .onEnded { _ in dragging = false })
            }
            .coordinateSpace(name: "tape")
        }
        .frame(height: 22 + Self.bladeH + 22)
        .focusable()
        .focused($focused)
        .onKeyPress(.leftArrow) { set(max(20, limit - 1)); return .handled }
        .onKeyPress(.rightArrow) { set(min(100, limit + 1)); return .handled }
        .accessibilityElement()
        .accessibilityLabel("Charge limit")
        .accessibilityValue("\(limit) percent")
        .accessibilityHint("Adjustable. Swipe up or down to change, or use the arrow keys.")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: set(Self.detents.first(where: { $0 > limit }) ?? 100)
            case .decrement: set(Self.detents.last(where: { $0 < limit }) ?? 20)
            @unknown default: break
            }
        }
    }

    private var lockTab: some View {
        VStack(spacing: 0) {
            // live readout while dragging, otherwise the resting label
            Text("\(limit)")
                .font(T.din(17)).foregroundStyle(T.lockText)
                .frame(width: Self.tabW, height: 22)
                .background(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4).fill(T.lockFill))
            Rectangle().fill(T.lockFill).frame(width: 3, height: Self.bladeH)
        }
        .overlay(alignment: .top) {
            if dragging {
                Text("Limit \(limit)%").font(T.din(15)).foregroundStyle(T.lockText)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(T.lockFill))
                    .fixedSize().offset(y: -20)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(focused ? T.yellow : .clear, lineWidth: 2).frame(width: Self.tabW + 4, height: 26).offset(y: -2), alignment: .top)
        .frame(width: Self.tabW)
        .contentShape(Rectangle())
    }
}
