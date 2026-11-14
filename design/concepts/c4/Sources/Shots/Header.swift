import SwiftUI

struct HeaderButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .foregroundStyle(T.text).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct Header: View {
    let title: String
    let showBack: Bool
    var onBack: () -> Void
    @Binding var searching: Bool
    @Binding var query: String
    var body: some View {
        HStack(spacing: 4) {
            if showBack { HeaderButton(symbol: "chevron.left", label: "Back to tools", action: onBack) }
            if searching {
                TextField("Search tools", text: $query).textFieldStyle(.plain).font(.system(size: 15))
                    .foregroundStyle(T.text)
            } else {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(T.text).lineLimit(1)
            }
            Spacer(minLength: 8)
            HeaderButton(symbol: "magnifyingglass", label: searching ? "Close search" : "Search") {
                searching.toggle(); if !searching { query = "" }
            }
            Menu {
                Button("Keep open", systemImage: "pin") {}
                Button("Settings...", systemImage: "gearshape") {}
                Button("Collapse", systemImage: "chevron.up") {}
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(T.text).frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, T.pad - 4).frame(height: T.headerH)
    }
}
