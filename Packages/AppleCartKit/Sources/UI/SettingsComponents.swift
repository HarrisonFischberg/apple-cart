import Core
import SwiftUI

/// A titled rounded card whose children are rows separated by dividers.
struct SettingsCard<Content: View>: View {
    let title: String?
    let content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { SectionLabel(title) }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows.indices, id: \.self) { i in
                        if i > 0 { Divider() }
                        rows[i].padding(.horizontal, 14).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
            }
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Label on the left (with an optional line under it), control or value on the right.
struct SettingsRow<Control: View>: View {
    let label: String
    let detail: String?
    let control: Control
    init(_ label: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label; self.detail = detail; self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let detail { Text(detail).font(.callout).foregroundStyle(Palette.secondary) }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

extension SettingsRow where Control == Text {
    init(_ label: String, value: String) {
        self.init(label) { Text(value).foregroundStyle(Palette.secondary) }
    }
}

/// Large title at the top of the pages that are not tools.
struct PageTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 22, weight: .semibold)).accessibilityAddTraits(.isHeader) }
}

extension SettingsPage {
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .permissions: "hand.raised"
        case .about: "info.circle"
        case .tool(let f): f.symbol
        }
    }
}

extension FeatureID {
    /// One line under the tool's name at the top of its Settings page.
    var blurb: String {
        switch self {
        case .battery: "Charge level, power flow and battery health."
        case .system: "CPU, memory and thermal state."
        case .keepAwake: "Keeps your Mac from sleeping for a time you pick."
        case .clipboard: "A searchable history of what you copy, kept on this Mac."
        case .copyText: "Drag a box around text on the screen and copy it."
        case .readQR: "Read a QR code or barcode from the screen."
        case .breakReminders: "Banners for eye, stretch and water breaks."
        case .uninstaller: "Remove an app together with its leftover files."
        case .cleaner: "Find caches and logs you can clear."
        case .diskMap: "See which folders take the most space."
        case .updates: "Check macOS and Homebrew for updates."
        case .quickToggles: "Hidden Finder and Dock options in one place."
        case .volumeGuard: "Lowers the volume when you switch speakers or plug in headphones."
        case .fanSafeMode: "Leave the fans to macOS, or set one speed or a temperature curve."
        case .cleaningMode: "Locks the keyboard and trackpad while you wipe them."
        case .notifications: "Not built yet."
        case .flushDNS: "Clears the DNS cache when a site still goes to an old address."
        }
    }

    /// Shortcut that exists while the tool is on, as registered in the app.
    var shortcut: (label: String, keys: String)? {
        switch self {
        case .clipboard: ("Paste as plain text", "⌃⌥⌘V")
        case .copyText: ("Copy text from screen", "⌃⌥⌘T")
        case .readQR: ("Read QR code", "⌃⌥⌘Q")
        default: nil
        }
    }
}
