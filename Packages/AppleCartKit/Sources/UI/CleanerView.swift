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
                        Text("Clear caches and logs").font(.headline)
                        Text("Finds app caches, logs and Xcode build files (macOS's own caches are left alone). Apps rebuild these on their own. You see the list first and everything goes to the Trash.")
                            .font(.callout).foregroundStyle(Palette.secondary)
                        Button("Scan") { model.scan() }
                    }
                case .scanning:
                    HStack { ProgressView().controlSize(.small); Text("Scanning…"); Spacer(); Button("Stop") { model.cancel() } }
                        .padding(14).background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                case .preview(let items): preview(items)
                case .done(let r): done(r)
                }
            }
            .padding(16)
        }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10, content: c).frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func preview(_ items: [CleanItem]) -> some View {
        let picked = items.filter { model.selected.contains($0.url) }.reduce(Int64(0)) { $0 + $1.bytes }
        return VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty { Text("Nothing to clear.").foregroundStyle(Palette.secondary) }
            ForEach(Array(Dictionary(grouping: items, by: \.group).keys.sorted()), id: \.self) { group in
                Text(group).font(.headline)
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
            HStack {
                Button("Cancel") { model.reset() }
                Button("Move \(picked.formatted(.byteCount(style: .file))) to Trash") { model.moveToTrash() }
                    .buttonStyle(.borderedProminent).disabled(model.selected.isEmpty)
            }
        }
    }

    private func done(_ r: UninstallReport) -> some View {
        card {
            Label(r.undone ? "Put everything back." : "Moved \(r.moved.count) item\(r.moved.count == 1 ? "" : "s") to the Trash.", systemImage: r.undone ? "arrow.uturn.backward" : "checkmark.circle").font(.headline)
            if !r.failed.isEmpty { Text("\(r.failed.count) could not be moved (in use or protected): \(r.failed.map { $0.url.lastPathComponent }.joined(separator: ", ")).").foregroundStyle(Palette.secondary) }
            HStack {
                if !r.undone && !r.moved.isEmpty { Button("Undo") { model.undo() } }
                Button("Scan again") { model.reset(); model.scan() }
            }
            if !r.undone { Text("Space comes back when you empty the Trash.").font(.callout).foregroundStyle(Palette.secondary) }
        }
    }
}

public struct DiskMapView: View {
    let model: DiskMapModel
    public init(model: DiskMapModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { model.up() } label: { Image(systemName: "chevron.left") }.disabled(model.path.count < 2).accessibilityLabel("Up one folder")
                Text(model.current.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.headline).lineLimit(1).truncationMode(.head)
                Spacer()
                if model.scanning { Button("Stop") { model.stop() } } else { Button("Rescan") { model.scan() } }
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
                Text("Read only. Folders macOS protects can look smaller without Full Disk Access.").font(.callout).foregroundStyle(Palette.secondary)
            }
        }
        .padding(16)
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
