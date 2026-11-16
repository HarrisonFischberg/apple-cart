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
                case .scanning: ProgressView("Looking for leftovers…").frame(maxWidth: .infinity, minHeight: 160)
                case .preview(let plan): preview(plan)
                case .done(let report): done(report)
                }
            }
            .toolPage()
        }
    }

    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.app").font(.system(size: 28)).foregroundStyle(Palette.secondary)
                StatusText("Drop an app here")
                Button("Choose an app…") { choose() }.buttonStyle(ChipStyle(selected: true)).frame(width: 170)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [6])).opacity(targeted ? 1 : 0))
            .dropDestination(for: URL.self) { urls, _ in
                guard let u = urls.first else { return false }
                Task { await model.choose(u) }
                return true
            } isTargeted: { targeted = $0 }
            if case .refused(let r) = model.phase { Text(r.message).hint() }
            Text("You see everything first. Files go to the Trash, not deleted.").hint()
        }
    }

    private func preview(_ plan: UninstallPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusText("Remove \(plan.app.name)?")
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
            if plan.items.count == 1 { Text("No leftover files were found.").hint() }
            if model.protectedFoldersHidden {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Without Full Disk Access some protected leftovers can be missed.").hint()
                    Button("Open settings", action: openFullDiskAccess).buttonStyle(ChipStyle()).frame(width: 150)
                }
            }
            if model.appIsRunning {
                HStack { Text("\(plan.app.name) is open.").hint(); Spacer(); Button("Quit it") { model.quitApp() }.buttonStyle(ChipStyle()).frame(width: 100) }
            }
            HStack(spacing: 8) {
                Button("Cancel") { model.reset() }.buttonStyle(ChipStyle())
                Button("Move to Trash") { model.moveToTrash() }
                    .buttonStyle(ChipStyle(selected: true))
                    .disabled(model.appIsRunning || model.selected.isEmpty)
                    .opacity(model.appIsRunning || model.selected.isEmpty ? 0.4 : 1)
            }
        }
    }

    private func done(_ r: UninstallReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(r.undone ? "Put everything back." : "Moved \(r.moved.count) item\(r.moved.count == 1 ? "" : "s") to the Trash.", systemImage: r.undone ? "arrow.uturn.backward" : "checkmark.circle")
                .font(.system(size: 15, weight: .medium))
            if !r.failed.isEmpty { Text("\(r.failed.count) could not be moved: \(r.failed.map { $0.url.lastPathComponent }.joined(separator: ", ")).").hint() }
            HStack(spacing: 8) {
                if !r.undone && !r.moved.isEmpty { Button("Undo") { model.undo() }.buttonStyle(ChipStyle()) }
                Button("Remove another") { model.reset() }.buttonStyle(ChipStyle(selected: true))
            }
            if !r.undone { Text("They stay in the Trash until you empty it.").hint() }
        }
        .toolCard()
    }

    private func choose() {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowedContentTypes = [.application]
        NSApp.activate()
        if p.runModal() == .OK, let u = p.url { Task { await model.choose(u) } }
    }
}
