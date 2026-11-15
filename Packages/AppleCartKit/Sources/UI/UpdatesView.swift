import Core
import SwiftUI

public struct UpdatesView: View {
    let checker: UpdateChecker
    public init(checker: UpdateChecker) { self.checker = checker }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                section("macOS", symbol: "apple.logo", source: checker.macOS, upToDate: "No macOS updates waiting.")
                section("Homebrew", symbol: "shippingbox", source: checker.homebrew, upToDate: "Everything from Homebrew is current.")
                HStack {
                    Button(checker.phase == .checking ? "Checking…" : "Check now") { Task { await checker.check() } }
                        .disabled(checker.phase == .checking)
                    if case .done(let d) = checker.phase {
                        Text("Checked \(d.formatted(date: .omitted, time: .shortened))").font(.callout).foregroundStyle(Palette.secondary)
                    }
                }
                Text("Checks only when you press the button. The macOS check asks Apple's update service; Homebrew is compared with its last downloaded list, and nothing is installed.")
                    .font(.callout).foregroundStyle(Palette.secondary)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func section(_ title: String, symbol: String, source: UpdateSource, upToDate: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline)
            switch source {
            case .notInstalled:
                Text("Homebrew is not installed on this Mac.").foregroundStyle(Palette.secondary)
            case .upToDate:
                Text(checker.phase == .idle ? "Not checked yet." : upToDate).foregroundStyle(Palette.secondary)
            case .failed(let m):
                Text(m).foregroundStyle(Palette.secondary)
            case .outdated(let items):
                ForEach(items) { i in
                    HStack {
                        Text(i.name)
                        Spacer()
                        Text([i.installed, i.available].compactMap { $0 }.joined(separator: " → ")).font(.callout).foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

public struct FlushDNSView: View {
    let tool: FlushDNS
    public init(tool: FlushDNS) { self.tool = tool }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Clear the DNS cache").font(.headline)
                Text("Helps when a website still goes to an old address. macOS will ask for your administrator password.")
                    .font(.callout).foregroundStyle(Palette.secondary)
                Button(tool.phase == .running ? "Flushing…" : "Flush DNS") { Task { await tool.flush() } }
                    .disabled(tool.phase == .running)
                switch tool.phase {
                case .done(let d): Text("Done at \(d.formatted(date: .omitted, time: .shortened)).").foregroundStyle(Palette.secondary)
                case .cancelled: Text("Cancelled. Nothing changed.").foregroundStyle(Palette.secondary)
                case .failed(let m): Text(m).foregroundStyle(Palette.secondary)
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer()
        }
        .padding(16)
    }
}
