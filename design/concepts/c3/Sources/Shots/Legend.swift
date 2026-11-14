import SwiftUI
import ConceptShared

/// Orienteering description sheet: number, symbol, text, time right-aligned.
struct Legend: View {
    private let pastSymbols = ["powerplug.fill", "arrow.up.to.line", "bolt.slash.fill", "powerplug.fill", "thermometer.medium"]
    private let futureSymbols = ["arrow.up.to.line", "arrow.triangle.2.circlepath", "arrow.down.to.line"]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Mock.events) { e in
                row(n: e.id, style: e.id == Mock.events.count ? .active : .done,
                    symbol: pastSymbols[e.id - 1], text: e.title, time: Mock.clock(hoursAgo: e.hoursAgo))
            }
            Rectangle().fill(T.hair).frame(height: 1).padding(.vertical, 3)
            ForEach(Mock.schedule) { s in
                row(n: Mock.events.count + s.id, style: .future,
                    symbol: futureSymbols[s.id - 1], text: s.action, time: s.when)
            }
        }
    }

    private func row(n: Int, style: ControlStyle, symbol: String, text: String, time: String) -> some View {
        HStack(spacing: 0) {
            ControlMark(n: n, style: style, size: 17).frame(width: 30)
            Image(systemName: symbol).font(.system(size: 12, weight: .regular))
                .foregroundStyle(style == .future ? T.ink2 : T.ink).frame(width: 26)
            Text(text).font(.system(size: 12.5, weight: style == .active ? .semibold : .regular))
                .foregroundStyle(T.ink).lineLimit(1)
            Spacer(minLength: 8)
            Text(time).font(.system(size: 12)).monospacedDigit().foregroundStyle(T.ink2).lineLimit(1)
        }
        .frame(height: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Control \(n), \(text), \(time)\(style == .future ? ", scheduled" : "")")
    }
}
