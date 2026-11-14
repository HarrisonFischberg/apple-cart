import CoreAudio
import Foundation

@MainActor
public protocol AudioOutput: AnyObject {
    /// Current output volume 0...1, nil when the device has no volume control (HDMI, some DACs).
    func volume() -> Float?
    func setVolume(_ v: Float)
    /// Calls `handler` whenever the default output device changes. Returns a token for `stopObserving`.
    func observeDeviceChanges(_ handler: @escaping @MainActor () -> Void) -> Int
    func stopObserving(_ token: Int)
}

/// When the output device changes (headphones plugged in, speaker switched), lowers the volume to the limit
/// if it is above it. Never raises it. Event driven: no timer.
@MainActor
public final class VolumeGuard: Tool {
    private let audio: AudioOutput
    private let maxPercent: () -> Int
    private var token: Int?
    public private(set) var lastLowered: (from: Int, to: Int)?

    public init(audio: AudioOutput, maxPercent: @escaping () -> Int) {
        self.audio = audio
        self.maxPercent = maxPercent
    }

    public var isWatching: Bool { token != nil }

    public func start() {
        guard token == nil else { return }
        token = audio.observeDeviceChanges { [weak self] in self?.deviceChanged() }
    }

    public func stop() {
        if let token { audio.stopObserving(token) }
        token = nil
    }

    func deviceChanged() {
        let limit = Float(min(max(maxPercent(), 0), 100)) / 100
        guard let v = audio.volume(), v > limit + 0.005 else { return }
        audio.setVolume(limit)
        lastLowered = (Int((v * 100).rounded()), Int((limit * 100).rounded()))
    }
}

@MainActor
public final class CoreAudioOutput: AudioOutput {
    private var listeners: [Int: AudioObjectPropertyListenerBlock] = [:]
    private var next = 1

    public init() {}

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    private func device() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = Self.defaultDeviceAddress
        let ok = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return ok == noErr && id != 0 ? id : nil
    }

    private func volumeAddress(_ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    /// Main element if the device has one, else the two stereo channels.
    private func elements(_ dev: AudioDeviceID) -> [UInt32] {
        var main = volumeAddress(kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(dev, &main) { return [kAudioObjectPropertyElementMain] }
        return [1, 2].filter { var a = volumeAddress($0); return AudioObjectHasProperty(dev, &a) }
    }

    public func volume() -> Float? {
        guard let dev = device() else { return nil }
        let values: [Float] = elements(dev).compactMap {
            var a = volumeAddress($0); var v = Float32(0); var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr ? v : nil
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }

    public func setVolume(_ v: Float) {
        guard let dev = device() else { return }
        for e in elements(dev) {
            var a = volumeAddress(e); var value = Float32(v)
            AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    public func observeDeviceChanges(_ handler: @escaping @MainActor () -> Void) -> Int {
        let block: AudioObjectPropertyListenerBlock = { _, _ in Task { @MainActor in handler() } }
        var addr = Self.defaultDeviceAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
        let t = next; next += 1
        listeners[t] = block
        return t
    }

    public func stopObserving(_ token: Int) {
        guard let block = listeners.removeValue(forKey: token) else { return }
        var addr = Self.defaultDeviceAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
    }
}
