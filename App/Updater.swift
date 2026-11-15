import AppKit
import Core
import ServiceManagement
import Sparkle

/// Sparkle, switched on only when the app carries an update signing key. Without one the updater never starts.
@MainActor
final class Updater: NSObject {
    private var controller: SPUStandardUpdaterController?

    var isConfigured: Bool { (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String).map { !$0.isEmpty } ?? false }

    override init() {
        super.init()
        if isConfigured { controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) }
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    var automaticChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}

@MainActor
final class SMLoginItem: LoginItem {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func set(_ on: Bool) throws { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
}
