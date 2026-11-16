import AppKit
import Core
import SwiftUI

public struct CleanerView: View {
    let model: CleanerModel
    public init(model: CleanerModel) { self.model = model }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                switch model.phase {
                case .idle:
                    card {
                        StatusText("Ready to scan")
                        Button("Scan") { model.scan() }.buttonStyle(ChipStyle(selected: true))
                        Text("Finds app caches, logs and Xcode build files (macOS's own caches are left alone). Apps rebuild these on their own. You see the list first and everything goes to the Trash.").hint()
                    }
                case .scanning:
                    card {
                        HStack { ProgressView().controlSize(.small); StatusText("Scanning…"); Spacer() }
                        Button("Stop") { model.cancel() }.buttonStyle(ChipStyle())
                    }
                case .preview(let items): preview(items)
                case .done(let r): done(r)
                }
            }
            .toolPage()
        }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12, content: c).toolCard()
    }

    private func preview(_ items: [CleanItem]) -> some View {
        let picked = items.filter { model.selected.contains($0.url) }.reduce(Int64(0)) { $0 + $1.bytes }
        return VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty { Text("Nothing to clear.").foregroundStyle(Palette.secondary) }
            ForEach(Array(Dictionary(grouping: items, by: \.group).keys.sorted()), id: \.self) { group in
                SectionLabel(group)
                VStack(spacing: 0) {
                    ForEach(Array(items.filter { $0.group == group }.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { Divider() }
                        HStack(spacing: 10) {
                            Toggle("Move \(item.url.lastPathComponent)", isOn: Binding(get: { model.selected.contains(item.url) },
                                set: { if $0 { model.selected.insert(item.url) } else { model.selected.remove(item.url) } }))
                                .toggleStyle(.checkbox).labelsHidden()
                            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(item.bytes.formatted(.byteCount(style: .file))).font(.callout).foregroundStyle(Palette.secondary)
                        }
                        .frame(minHeight: 44).padding(.horizontal, 14)
                    }
                }
                .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack(spacing: 8) {
                Button("Cancel") { model.reset() }.buttonStyle(ChipStyle())
                Button("Move \(picked.formatted(.byteCount(style: .file))) to Trash") { model.moveToTrash() }
                    .buttonStyle(ChipStyle(selected: true)).disabled(model.selected.isEmpty)
                    .opacity(model.selected.isEmpty ? 0.4 : 1)
            }
        }
    }

    private func done(_ r: UninstallReport) -> some View {
        card {
            Label(r.undone ? "Put everything back." : "Moved \(r.moved.count) item\(r.moved.count == 1 ? "" : "s") to the Trash.", systemImage: r.undone ? "arrow.uturn.backward" : "checkmark.circle").font(.system(size: 15, weight: .medium))
            if !r.failed.isEmpty { Text("\(r.failed.count) could not be moved (in use or protected): \(r.failed.map { $0.url.lastPathComponent }.joined(separator: ", ")).").hint() }
            HStack(spacing: 8) {
                if !r.undone && !r.moved.isEmpty { Button("Undo") { model.undo() }.buttonStyle(ChipStyle()) }
                Button("Scan again") { model.reset(); model.scan() }.buttonStyle(ChipStyle(selected: true))
            }
            if !r.undone { Text("Space comes back when you empty the Trash.").hint() }
        }
    }
}

public struct DiskMapView: View {
    let model: DiskMapModel
    public init(model: DiskMapModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { model.up() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).disabled(model.path.count < 2).accessibilityLabel("Up one folder")
                StatusText(model.current.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 0)
                if model.scanning { Button("Stop") { model.stop() }.buttonStyle(ChipStyle()).frame(width: 84) }
                else { Button("Rescan") { model.scan() }.buttonStyle(ChipStyle()).frame(width: 84) }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.entries.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { Divider() }
                        row(e)
                    }
                    if model.entries.isEmpty && !model.scanning { Text("Nothing here.").foregroundStyle(Palette.secondary).padding(14) }
                }
                .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if model.scanning { ProgressView().controlSize(.small).padding(8) }
                Text("Read only. Folders macOS protects can look smaller without Full Disk Access.").hint()
            }
        }
        .toolPage()
        .onAppear { if model.entries.isEmpty && !model.scanning { model.scan() } }
    }

    private func row(_ e: DiskEntry) -> some View {
        let frac = model.largest > 0 ? CGFloat(e.bytes) / CGFloat(model.largest) : 0
        return HStack(spacing: 10) {
            Image(systemName: e.isFolder ? "folder" : "doc").foregroundStyle(Palette.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                GeometryReader { g in Capsule().fill(Palette.accent.opacity(0.6)).frame(width: max(2, g.size.width * frac), height: 4) }.frame(height: 4)
            }
            Text(e.bytes.formatted(.byteCount(style: .file))).font(.callout).foregroundStyle(Palette.secondary).frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14).frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { model.open(e) }
        .contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([e.url]) } }
        .accessibilityElement(children: .combine)
        .accessibilityHint(e.isFolder ? "Opens the folder" : "")
        .accessibilityAddTraits(e.isFolder ? .isButton : [])
    }
}
