import AppKit
import Core
import SwiftUI

public struct ClipboardView: View {
    let history: ClipboardHistory
    let close: () -> Void
    @State private var query = ""

    public init(history: ClipboardHistory, close: @escaping () -> Void) { self.history = history; self.close = close }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                    TextField("Search", text: $query).textFieldStyle(.plain).accessibilityLabel("Search clipboard history")
                }
                .padding(.leading, 14).padding(.trailing, 14).frame(minHeight: 44)
                .background(Palette.tile, in: Capsule())
                // Pinned items stay; the "Removed N. Undo" line below brings everything back.
                if history.items.contains(where: { !$0.pinned }) {
                    Button("Erase all") { history.clearAll() }
                        .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundStyle(.red)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(Palette.tile, in: Capsule())
                        .accessibilityHint("Removes every unpinned item. You can undo it.")
                }
            }
            ScrollView {
                VStack(spacing: 8) {
                    if let s = history.status { Text(s).font(.callout).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    if !history.lastDeleted.isEmpty {
                        HStack { Text("Removed \(history.lastDeleted.count).").foregroundStyle(Palette.secondary); Button("Undo") { history.undoDelete() }; Spacer() }
                    }
                    let shown = history.search(query)
                    if shown.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.on.clipboard").font(.system(size: 30)).foregroundStyle(Palette.secondary)
                            Text(query.isEmpty ? "Nothing copied yet. Copy something and it shows up here." : "No matches.").hint()
                                .multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                                if i > 0 { Divider() }
                                row(item)
                            }
                        }
                        .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        .toolPage()
    }

    private func row(_ item: ClipItem) -> some View {
        HStack(spacing: 10) {
            Button { history.paste(item); close() } label: {
                HStack(spacing: 10) {
                    preview(item)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Pastes this item")
            if item.pinned { Image(systemName: "pin.fill").foregroundStyle(Palette.accent).accessibilityLabel("Pinned") }
            Menu {
                Button("Paste") { history.paste(item); close() }
                Button("Copy") { history.paste(item, andSend: false) }
                Button(item.pinned ? "Unpin" : "Pin") { history.togglePin(item) }
                if let src = item.sourceBundleID { Button("Never store from this app") { history.neverStore(from: src) } }
                Divider()
                Button("Delete", role: .destructive) { history.delete(item) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More actions")
        }
        .padding(.horizontal, 14).padding(.vertical, 6).frame(minHeight: 48)
        .contextMenu {
            Button("Copy") { history.paste(item, andSend: false) }
            Button(item.pinned ? "Unpin" : "Pin") { history.togglePin(item) }
            Button("Delete", role: .destructive) { history.delete(item) }
        }
    }

    @ViewBuilder
    private func preview(_ item: ClipItem) -> some View {
        switch item.kind {
        case .image:
            if let u = history.imageURL(item), let img = NSImage(contentsOf: u) {
                Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: 120, maxHeight: 60).clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityLabel("Copied image")
            }
        case .url, .text:
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text ?? "").lineLimit(2).truncationMode(.tail).multilineTextAlignment(.leading)
                Text(item.copiedAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(Palette.secondary)
            }
        }
    }
}

public struct ScreenReadView: View {
    let reader: ScreenReader
    let mode: ScreenReader.Mode
    let start: () -> Void
    let openSettings: () -> Void

    public init(reader: ScreenReader, mode: ScreenReader.Mode, start: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.reader = reader; self.mode = mode; self.start = start; self.openSettings = openSettings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    StatusText(mode == .text ? "Copy text from the screen" : "Read a QR code")
                    Text(mode == .text ? "Drag a box around any text, even in an image or a video. It is read on this Mac and copied."
                                       : "Drag a box around a QR code or barcode. The result is copied. Links are never opened for you.")
                        .font(.callout).foregroundStyle(Palette.secondary)
                    Button("Select an area") { start() }.buttonStyle(ChipStyle(selected: true))
                    Text("Shortcut: ⌃⌥⌘\(mode == .text ? "T" : "Q")").font(.callout).foregroundStyle(Palette.secondary)
                    if reader.phase == .needsPermission {
                        Text("Screen Recording is off for Apple Cart. It is only used for the area you pick; nothing is recorded or saved.").foregroundStyle(Palette.secondary)
                        Button("Open Screen Recording settings", action: openSettings)
                    }
                    if reader.phase == .failed { Text("The screen could not be read. Try again.").foregroundStyle(Palette.secondary) }
                }
                .toolCard()
                result
            }
            .toolPage()
        }
    }

    @ViewBuilder private var result: some View {
        switch reader.last {
        case .text(let t) where mode == .text: card("Copied", t)
        case .codes(let c) where mode == .qr: card("Copied", c.joined(separator: "\n"))
        case .nothing(let m) where m == mode: Text(mode == .text ? "No text found in that area." : "No code found in that area.").foregroundStyle(Palette.secondary)
        default: EmptyView()
        }
    }

    private func card(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "checkmark.circle").font(.system(size: 15, weight: .medium))
            Text(body).lineLimit(8).textSelection(.enabled)
        }
        .toolCard()
    }
}
