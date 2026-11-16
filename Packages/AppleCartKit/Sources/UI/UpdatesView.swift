import Core
import SwiftUI

public struct UpdatesView: View {
    let checker: UpdateChecker
    public init(checker: UpdateChecker) { self.checker = checker }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        statusText
                        Spacer()
                        Button(checker.phase == .checking ? "Checking…" : "Check now") { Task { await checker.check() } }
                            .buttonStyle(ChipStyle(selected: true)).frame(width: 120)
                            .disabled(checker.phase == .checking)
                    }
                    section("macOS", source: checker.macOS, upToDate: "No macOS updates waiting.")
                    section("Homebrew", source: checker.homebrew, upToDate: "Everything from Homebrew is current.")
                }
                .toolCard()
                Text("Checks only when you press the button. The macOS check asks Apple's update service; Homebrew is compared with its last downloaded list, and nothing is installed.").hint()
            }
            .toolPage()
        }
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch checker.phase {
            case .done(let d):
                let n = [checker.macOS, checker.homebrew].reduce(0) { if case .outdated(let i) = $1 { $0 + i.count } else { $0 } }
                StatusText(n == 0 ? "Up to date" : "\(n) update\(n == 1 ? "" : "s") waiting")
                Text("Checked \(d.formatted(date: .omitted, time: .shortened))").hint()
            case .checking: StatusText("Checking…")
            default: StatusText("Not checked yet")
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, source: UpdateSource, upToDate: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
            switch source {
            case .notInstalled:
                Text("Homebrew is not installed on this Mac.").hint()
            case .upToDate:
                Text(checker.phase == .idle ? "Not checked yet." : upToDate).hint()
            case .failed(let m):
                Text(m).hint()
            case .outdated(let items):
                ForEach(items) { i in
                    HStack {
                        Text(i.name).lineLimit(1)
                        Spacer()
                        Text([i.installed, i.available].compactMap { $0 }.joined(separator: " → ")).font(.callout).foregroundStyle(Palette.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }
}

public struct FlushDNSView: View {
    let tool: FlushDNS
    public init(tool: FlushDNS) { self.tool = tool }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            StatusText(headline)
                            if let d = detail { Text(d).hint() }
                        }
                        Spacer()
                        Button(tool.phase == .running ? "Flushing…" : "Flush DNS") { Task { await tool.flush() } }
                            .buttonStyle(ChipStyle(selected: true)).frame(width: 120)
                            .disabled(tool.phase == .running)
                    }
                    Text("Helps when a website still goes to an old address. macOS will ask for your administrator password.").hint()
                }
                .toolCard()
            }
            .toolPage()
        }
    }

    private var headline: String {
        switch tool.phase {
        case .running: "Flushing…"
        case .done(let d): "Done at \(d.formatted(date: .omitted, time: .shortened))"
        case .cancelled: "Cancelled"
        case .failed: "Did not finish"
        default: "DNS cache ready to clear"
        }
    }

    private var detail: String? {
        switch tool.phase {
        case .cancelled: "Nothing changed."
        case .failed(let m): m
        default: nil
        }
    }
}
