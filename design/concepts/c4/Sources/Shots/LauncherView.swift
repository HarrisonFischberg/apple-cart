import SwiftUI
import ConceptShared

struct Tool: Identifiable {
    let id: String, icon: String, shortcut: String
    var on = true
    var name: String { id }
}

enum Tools {
    static let all: [Tool] = [
        Tool(id: "Battery", icon: "battery.75percent", shortcut: "⌥⌘B"),
        Tool(id: "System", icon: "cpu", shortcut: "⌥⌘S"),
        Tool(id: "Keep awake", icon: "cup.and.saucer", shortcut: "⌥⌘K"),
        Tool(id: "Clipboard", icon: "list.clipboard", shortcut: "⌥⌘V"),
        Tool(id: "Copy text from screen", icon: "text.viewfinder", shortcut: "⌥⌘T"),
        Tool(id: "Read QR code", icon: "qrcode.viewfinder", shortcut: "⌥⌘R"),
        Tool(id: "Break reminders", icon: "timer", shortcut: "⌥⌘E"),
        Tool(id: "Uninstaller", icon: "trash", shortcut: "⌥⌘U"),
        Tool(id: "Cleaner", icon: "sparkles", shortcut: "⌥⌘C"),
        Tool(id: "Disk map", icon: "chart.pie", shortcut: "⌥⌘D"),
        Tool(id: "Updates", icon: "arrow.down.circle", shortcut: "⌥⌘J"),
        Tool(id: "Quick toggles", icon: "switch.2", shortcut: "⌥⌘Q"),
        Tool(id: "Volume guard", icon: "speaker.wave.2", shortcut: "⌥⌘G"),
        Tool(id: "Fan safe mode", icon: "fan", shortcut: "⌥⌘F", on: Mock.fanToolOn),
        Tool(id: "Cleaning mode", icon: "keyboard", shortcut: "⌥⌘L"),
        Tool(id: "Notifications", icon: "bell", shortcut: "⌥⌘N")
    ]
}

struct ToolTile: View {
    let tool: Tool?          // nil = Add tools
    var body: some View {
        let on = tool?.on ?? true
        let w = (T.inner - T.gap * 3) / 4
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: tool?.icon ?? "plus").font(.system(size: 18, weight: .medium))
                    .foregroundStyle(on ? T.text : T.secondary)
                Spacer(minLength: 0)
                if !on {
                    Text("Off").font(.system(size: 11, weight: .medium)).foregroundStyle(T.secondary)
                        .padding(.horizontal, 6).frame(height: 18)
                        .overlay(Capsule().strokeBorder(T.secondary.opacity(0.6), lineWidth: 1))
                }
            }
            Spacer(minLength: 4)
            Text(tool?.name ?? "Add tools").font(.system(size: 11, weight: .medium))
                .foregroundStyle(on ? T.text : T.secondary).lineLimit(2).multilineTextAlignment(.leading)
                .frame(minHeight: 30, alignment: .bottomLeading)
            Text(tool?.shortcut ?? "Browse").font(.system(size: 11)).foregroundStyle(T.secondary).padding(.top, 2)
        }
        .padding(8)
        .frame(width: w, height: 104, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? T.tile : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(T.border, style: StrokeStyle(lineWidth: 1, dash: on ? [] : [4, 3])))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tool.map { "\($0.name), shortcut \($0.shortcut)\($0.on ? "" : ", off")" } ?? "Add tools")
    }
}

struct LauncherView: View {
    var query: String
    var open: (String) -> Void
    static let rows = 5
    static var height: CGFloat { T.headerH + 104 * CGFloat(rows) + T.gap * CGFloat(rows - 1) + T.pad }
    var body: some View {
        let items = Tools.all.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        let cols = Array(repeating: GridItem(.fixed((T.inner - T.gap * 3) / 4), spacing: T.gap), count: 4)
        ScrollView {
            LazyVGrid(columns: cols, spacing: T.gap) {
                ForEach(items) { t in
                    Button { open(t.name) } label: { ToolTile(tool: t) }.buttonStyle(.plain)
                }
                if query.isEmpty { Button {} label: { ToolTile(tool: nil) }.buttonStyle(.plain) }
            }
            .padding(.horizontal, T.pad).padding(.bottom, T.pad)
        }
    }
}
