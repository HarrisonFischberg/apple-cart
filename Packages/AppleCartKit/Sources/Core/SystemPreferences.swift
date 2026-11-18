import CoreFoundation
import Foundation

/// Real preferences through CFPreferences, then a Finder or Dock restart so the change shows.
@MainActor
public final class SystemPreferences: PreferenceAccess {
    public init() {}

    /// The literal text "NSGlobalDomain" or "kCFPreferencesAnyApplication" would name an ordinary app domain
    /// (its own plist that nothing reads), so the global domain must be the CF constant.
    private func cfDomain(_ domain: String) -> CFString {
        domain == globalPreferenceDomain ? kCFPreferencesAnyApplication : domain as CFString
    }

    public func read(domain: String, key: String) -> Bool? {
        CFPreferencesAppSynchronize(cfDomain(domain))
        return (CFPreferencesCopyAppValue(key as CFString, cfDomain(domain)) as? NSNumber)?.boolValue
    }

    public func write(domain: String, key: String, value: Bool) {
        CFPreferencesSetAppValue(key as CFString, value as CFBoolean, cfDomain(domain))
        CFPreferencesAppSynchronize(cfDomain(domain))
    }

    public func restart(_ processName: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = [processName]
        try? p.run() // launchd relaunches Finder and Dock by itself
    }
}
