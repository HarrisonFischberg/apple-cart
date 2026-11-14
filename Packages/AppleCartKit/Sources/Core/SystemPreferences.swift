import CoreFoundation
import Foundation

/// Real preferences through CFPreferences, then a Finder or Dock restart so the change shows.
@MainActor
public final class SystemPreferences: PreferenceAccess {
    public init() {}

    public func read(domain: String, key: String) -> Bool? {
        CFPreferencesAppSynchronize(domain as CFString)
        return (CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber)?.boolValue
    }

    public func write(domain: String, key: String, value: Bool) {
        CFPreferencesSetAppValue(key as CFString, value as CFBoolean, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
    }

    public func restart(_ processName: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = [processName]
        try? p.run() // launchd relaunches Finder and Dock by itself
    }
}
