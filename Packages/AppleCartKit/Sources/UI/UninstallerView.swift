import AppKit
import Core
import SwiftUI

public struct UninstallerView: View {
    let model: UninstallerModel
    let openFullDiskAccess: () -> Void
    @State private var targeted = false

    public init(model: UninstallerModel, openFullDiskAccess: @escaping () -> Void) {
        self.model = model; self.openFullDiskAccess = openFullDiskAccess
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch model.phase {
                case .idle, .refused: dropZone
                case .scanning: ProgressView("Looking for leftovers…").frame(maxWidth: .infinity, minHeight: 200)
                case .preview(let plan): preview(plan)
                case .done(let report): done(report)
                }
            }
            .padding(16)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.app").font(.system(size: 34)).foregroundStyle(Palette.secondary)
                Text("Drop an app here").font(.headline)
                Button("Choose an app…") { choose() }
            }
            .frame(maxWidth: .infinity, minHeight: 190)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [6])).opacity(targeted ? 1 : 0))
            .dropDestination(for: URL.self) { urls, _ in
                guard let u = urls.first else { return false }
                Task { await model.choose(u) }
                return true
            } isTargeted: { targeted = $0 }
            if case .refused(let r) = model.phase { Text(r.message).foregroundStyle(Palette.secondary) }
            Text("You see everything first. Files go to the Trash, not deleted.")
                .font(.callout).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func preview(_ plan: UninstallPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remove \(plan.app.name)?").font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(plan.items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Divider() }
                    HStack(spacing: 10) {
                        Toggle("Move \(item.url.lastPathComponent)", isOn: Binding(get: { model.selected.contains(item.url) },
                                         set: { if $0 { model.selected.insert(item.url) } else { model.selected.remove(item.url) } }))
                            .toggleStyle(.checkbox).labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Text(item.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(item.bytes.formatted(.byteCount(style: .file))).font(.callout).foregroundStyle(Palette.secondary)
                    }
                    .frame(minHeight: 44).padding(.horizontal, 14)
                }
            }
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if plan.items.count == 1 { Text("No leftover files were found.").foregroundStyle(Palette.secondary) }
            if model.protectedFoldersHidden {
                HStack {
                    Text("Without Full Disk Access some protected leftovers can be missed.").font(.callout).foregroundStyle(Palette.secondary)
                    Button("Open settings", action: openFullDiskAccess)
                }
            }
            if model.appIsRunning {
                HStack { Text("\(plan.app.name) is open.").foregroundStyle(Palette.secondary); Button("Quit it") { model.quitApp() } }
            }
            HStack {
                Button("Cancel") { model.reset() }
                Button("Move to Trash") { model.moveToTrash() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.appIsRunning || model.selected.isEmpty)
            }
        }
    }

    private func done(_ r: UninstallReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(r.undone ? "Put everything back." : "Moved \(r.moved.count) item\(r.moved.count == 1 ? "" : "s") to the Trash.", systemImage: r.undone ? "arrow.uturn.backward" : "checkmark.circle")
                .font(.headline)
            if !r.failed.isEmpty { Text("\(r.failed.count) could not be moved: \(r.failed.map { $0.url.lastPathComponent }.joined(separator: ", ")).").foregroundStyle(Palette.secondary) }
            HStack {
                if !r.undone && !r.moved.isEmpty { Button("Undo") { model.undo() } }
                Button("Remove another") { model.reset() }
            }
            if !r.undone { Text("They stay in the Trash until you empty it.").font(.callout).foregroundStyle(Palette.secondary) }
        }
    }

    private func choose() {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowedContentTypes = [.application]
        NSApp.activate()
        if p.runModal() == .OK, let u = p.url { Task { await model.choose(u) } }
    }
}
