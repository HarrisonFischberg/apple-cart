import Foundation
import IOKit
import IOKit.pwr_mgt

/// IOKit power messages (the C macros are not imported into Swift).
public enum PowerMessage {
    public static let canSystemSleep: UInt32 = 0xE000_0270
    public static let systemWillSleep: UInt32 = 0xE000_0280
    public static let systemHasPoweredOn: UInt32 = 0xE000_0300
    public static let systemWillPowerOn: UInt32 = 0xE000_0320

    /// Before sleep the adapter goes back on and cuts are refused until power-on.
    public static func restoresAdapter(_ message: UInt32) -> Bool { message == systemWillSleep }
    /// Cuts are allowed again once the system is powering on.
    public static func endsSleep(_ message: UInt32) -> Bool { message == systemWillPowerOn || message == systemHasPoweredOn }
    /// Messages that must be acknowledged or sleep is delayed.
    public static func needsAck(_ message: UInt32) -> Bool { message == canSystemSleep || message == systemWillSleep }
}

/// Registers for system sleep and restores the adapter and the fans before acknowledging it. Keep the instance alive.
public final class SystemPowerWatcher: @unchecked Sendable {
    private var root: io_connect_t = 0
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private let adapter: AdapterGuard
    private let fan: FanGuard?

    public init?(adapter: AdapterGuard, fan: FanGuard? = nil, queue: DispatchQueue) {
        self.adapter = adapter
        self.fan = fan
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        root = IORegisterForSystemPower(ctx, &port, { ctx, _, message, argument in
            guard let ctx else { return }
            let me = Unmanaged<SystemPowerWatcher>.fromOpaque(ctx).takeUnretainedValue()
            if PowerMessage.restoresAdapter(message) { me.adapter.systemWillSleep(); me.fan?.systemWillSleep() }
            if PowerMessage.endsSleep(message) { me.adapter.systemDidWake(); me.fan?.systemDidWake() }
            if PowerMessage.needsAck(message) { IOAllowPowerChange(me.root, Int(bitPattern: argument)) }
        }, &notifier)
        guard root != 0, let port else { return nil }
        IONotificationPortSetDispatchQueue(port, queue)
    }
}
