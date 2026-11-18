import Testing
@testable import Core

@MainActor
private final class FakePrefs: PreferenceAccess {
    var values: [String: Bool] = [:]
    var restarted: [String] = []
    func read(domain: String, key: String) -> Bool? { values[domain + "/" + key] }
    func write(domain: String, key: String, value: Bool) { values[domain + "/" + key] = value }
    func restart(_ processName: String) { restarted.append(processName) }
}

@MainActor
private final class FakeAudio: AudioOutput {
    var level: Float? = 0.9
    var handlers: [Int: @MainActor () -> Void] = [:]
    var next = 1
    func volume() -> Float? { level }
    func setVolume(_ v: Float) { level = v }
    func observeDeviceChanges(_ handler: @escaping @MainActor () -> Void) -> Int { defer { next += 1 }; handlers[next] = handler; return next }
    func stopObserving(_ token: Int) { handlers[token] = nil }
    func plugInHeadphones() { handlers.values.forEach { $0() } }
}

@MainActor
@Suite struct QuickToggleTests {
    @Test func missingKeysUseMacOSDefaults() {
        let t = QuickToggles(prefs: FakePrefs())
        #expect(t.states[.desktopIcons] == true)
        #expect(t.states[.hiddenFiles] == false && t.states[.dockAutoHide] == false)
    }

    @Test func settingWritesRestartsAndShowsTheSystemState() {
        let p = FakePrefs()
        let t = QuickToggles(prefs: p)
        t.set(.hiddenFiles, on: true)
        #expect(p.values["com.apple.finder/AppleShowAllFiles"] == true && p.restarted == ["Finder"])
        #expect(t.states[.hiddenFiles] == true)
        t.set(.dockAutoHide, on: true)
        #expect(p.restarted == ["Finder", "Dock"])
    }

    @Test func fileExtensionsWriteGlobalAndFinderSoAFinderCopyCannotOverrideIt() {
        let p = FakePrefs()
        p.values["com.apple.finder/AppleShowAllExtensions"] = true // left there by Finder settings
        let t = QuickToggles(prefs: p)
        #expect(t.states[.fileExtensions] == true)
        t.set(.fileExtensions, on: false)
        #expect(p.values["NSGlobalDomain/AppleShowAllExtensions"] == false)
        #expect(p.values["com.apple.finder/AppleShowAllExtensions"] == false)
        #expect(t.states[.fileExtensions] == false && p.restarted == ["Finder"])
    }

    @Test func stateComesFromTheSystemNotTheRequest() {
        final class Stubborn: PreferenceAccess {
            func read(domain: String, key: String) -> Bool? { false }
            func write(domain: String, key: String, value: Bool) {}
            func restart(_ processName: String) {}
        }
        let t = QuickToggles(prefs: Stubborn())
        t.set(.fileExtensions, on: true)
        #expect(t.states[.fileExtensions] == false)
    }

    @Test func volumeIsLoweredOnDeviceChangeButNeverRaised() {
        let a = FakeAudio()
        let g = VolumeGuard(audio: a, maxPercent: { 70 })
        g.start()
        a.plugInHeadphones()
        #expect(a.level == 0.7 && g.lastLowered?.from == 90 && g.lastLowered?.to == 70)
        a.level = 0.3
        a.plugInHeadphones()
        #expect(a.level == 0.3)
    }

    @Test func noVolumeControlMeansNothingHappens() {
        let a = FakeAudio(); a.level = nil
        let g = VolumeGuard(audio: a, maxPercent: { 50 })
        g.start(); a.plugInHeadphones()
        #expect(g.lastLowered == nil)
    }

    @Test func stoppingRemovesTheListener() {
        let a = FakeAudio()
        let g = VolumeGuard(audio: a, maxPercent: { 50 })
        g.start(); g.start()
        #expect(a.handlers.count == 1 && g.isWatching)
        g.stop()
        #expect(a.handlers.isEmpty && !g.isWatching)
        a.plugInHeadphones()
        #expect(a.level == 0.9)
    }
}
