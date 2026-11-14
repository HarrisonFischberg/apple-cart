import AppKit
import SwiftUI

public enum ShotAppearance: String, CaseIterable {
    case light, dark
    var nsName: NSAppearance.Name { self == .dark ? .darkAqua : .aqua }
    var scheme: ColorScheme { self == .dark ? .dark : .light }
}

/// A mock desktop with a menu bar and the panel hanging under the status item.
/// Wallpaper and neighbour menu bar items are generic stand-ins, not real branding.
public struct ShotFrame<StatusItem: View, Panel: View>: View {
    let panelSize: CGSize
    let appearance: ShotAppearance
    let statusItem: StatusItem
    let panel: Panel
    let panelCorner: CGFloat

    public init(panelSize: CGSize, appearance: ShotAppearance, panelCorner: CGFloat = 14,
                @ViewBuilder statusItem: () -> StatusItem, @ViewBuilder panel: () -> Panel) {
        self.panelSize = panelSize
        self.appearance = appearance
        self.panelCorner = panelCorner
        self.statusItem = statusItem()
        self.panel = panel()
    }

    public static var margin: CGFloat { 36 }
    public static var barHeight: CGFloat { 30 }

    public var body: some View {
        let dark = appearance == .dark
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: dark ? [Color(red: 0.10, green: 0.12, blue: 0.20), Color(red: 0.22, green: 0.14, blue: 0.26)]
                             : [Color(red: 0.62, green: 0.74, blue: 0.88), Color(red: 0.90, green: 0.80, blue: 0.84)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "apple.logo")
                    Text("Finder").fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "wifi")
                    Image(systemName: "magnifyingglass")
                    statusItem
                    Text(Mock.menuBarClock).monospacedDigit()
                }
                .font(.system(size: 13))
                .foregroundStyle(dark ? Color.white : Color.black)
                .padding(.horizontal, 14)
                .frame(height: Self.barHeight)
                .background(dark ? Color.black.opacity(0.35) : Color.white.opacity(0.45))
                Spacer(minLength: 0)
            }
            panel
                .frame(width: panelSize.width, height: panelSize.height)
                .clipShape(RoundedRectangle(cornerRadius: panelCorner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: panelCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(dark ? 0.18 : 0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 10)
                .padding(.top, Self.barHeight + 8)
                .padding(.trailing, 28)
        }
    }

    public static func canvas(for panel: CGSize) -> CGSize {
        CGSize(width: panel.width + 28 + margin + 48, height: panel.height + barHeight + 8 + margin)
    }
}

public struct Shot {
    public let name: String
    public let size: CGSize
    public let appearance: ShotAppearance
    public let view: AnyView
    public init(name: String, size: CGSize, appearance: ShotAppearance, view: AnyView) {
        self.name = name; self.size = size; self.appearance = appearance; self.view = view
    }
}

@MainActor
public enum ShotRenderer {
    /// Renders each shot through a real NSWindow so native controls draw. Writes PNGs (2x) into `outDir`.
    public static func run(_ shots: [Shot], outDir: URL) {
        NSApplication.shared.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for shot in shots {
            let host = NSHostingView(rootView: shot.view)
            host.frame = NSRect(origin: .zero, size: shot.size)
            let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.appearance = NSAppearance(named: shot.appearance.nsName)
            win.contentView = host
            win.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            NSApplication.shared.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                print("FAILED \(shot.name): no bitmap rep"); continue
            }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                print("FAILED \(shot.name): png"); continue
            }
            let url = outDir.appendingPathComponent(shot.name + ".png")
            do { try data.write(to: url); print("wrote \(url.path) \(rep.pixelsWide)x\(rep.pixelsHigh)") }
            catch { print("FAILED \(shot.name): \(error)") }
            win.orderOut(nil)
        }
    }

    public static func outDir(from args: [String]) -> URL {
        if let i = args.firstIndex(of: "--out"), i + 1 < args.count {
            return URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("shots", isDirectory: true)
    }
}
