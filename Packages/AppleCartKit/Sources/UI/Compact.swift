import SwiftUI

extension View {
    /// The one card each tool view sits in.
    func toolCard() -> some View {
        padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Page padding shared by every tool view (same as Keep awake).
    func toolPage() -> some View { padding(.horizontal, 16).padding(.vertical, 12) }
}

/// Small uppercase label that names a block inside a tool view.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(0.6)
            .foregroundStyle(Palette.secondary).accessibilityAddTraits(.isHeader)
    }
}

/// The headline of a card: what is going on right now.
struct StatusText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 15, weight: .medium)) }
}

extension Text {
    func hint() -> some View { font(.callout).foregroundStyle(Palette.secondary) }
}
