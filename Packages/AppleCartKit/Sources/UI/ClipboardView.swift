import AppKit
import Core
import SwiftUI

public struct ClipboardView: View {
    let history: ClipboardHistory
    let close: () -> Void
    @State private var query = ""
    @State private var showSettings = false

    public init(history: ClipboardHistory, close: @escaping () -> Void) { self.history = history; self.close = close }

    public var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                TextField("Search", text: $query).textFieldStyle(.plain).accessibilityLabel("Search clipboard history")
                Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).accessibilityLabel("Clipboard settings")
            }
            .padding(10).background(Palette.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if showSettings { settings }
            if let s = history.status { Text(s).font(.callout).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            if !history.lastDeleted.isEmpty {
                HStack { Text("Removed \(history.lastDeleted.count).").foregroundStyle(Palette.secondary); Button("Undo") { history.undoDelete() }; Spacer() }
            }
            let shown = history.search(query)
            if shown.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 30)).foregroundStyle(Palette.secondary)
                    Text(query.isEmpty ? "Nothing copied yet. Copy something and it shows up here." : "No matches.").foregroundStyle(Palette.secondary)
                }.frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollView {
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
        .padding(16)
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

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stepper("Keep for \(history.retentionDays) day\(history.retentionDays == 1 ? "" : "s") (pinned stay)", value: Binding(get: { history.retentionDays }, set: { history.setRetention($0) }), in: 1...90)
            Toggle("Remove tracking from copied links", isOn: Binding(get: { history.cleanLinks }, set: { history.setCleanLinks($0) }))
            Toggle("Clear the clipboard after a minute and on lock", isOn: Binding(get: { history.autoClear }, set: { history.setAutoClear($0) }))
            Text("Passwords and other items apps mark as secret are never saved.").font(.callout).foregroundStyle(Palette.secondary)
            if !history.excluded.isEmpty {
                Text("Never stored from").font(.headline)
                ForEach(history.excluded.sorted(), id: \.self) { id in
                    HStack { Text(id).font(.callout); Spacer(); Button("Allow again") { history.allowAgain(id) } }
                }
            }
            HStack {
                Button("Ignore an app…") { pickApp() }
                Button("Clear history", role: .destructive) { history.clearAll() }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func pickApp() {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: "/Applications"); p.allowedContentTypes = [.application]
        NSApp.activate()
        if p.runModal() == .OK, let u = p.url, let id = Bundle(url: u)?.bundleIdentifier { history.neverStore(from: id) }
    }
}
