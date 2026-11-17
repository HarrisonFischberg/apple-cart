// Apple Cart root helper (launchd daemon registered with SMAppService.daemon). It can only turn the
// charger (SMC key CHIE) off on a lease or back on, put the fans in manual mode on a lease or back to macOS
// (FanWhitelist keys only), and force the MagSafe light green or orange on a lease (ACLC 3 or 4 only); every way out puts
// the charger back on and the fans and the light back to macOS.
import Foundation
import HelperCore
import HelperProtocol
import os

let queue = DispatchQueue(label: "app.rarecreatures.applecart.helper")
let adapter = AdapterGuard(
    // Reopened after an I/O failure; if AppleSMC cannot be opened at all, restores back off and status reports chie -1.
    connect: { try SMCConnection() },
    schedule: { seconds, fire in DispatchLeaseTimer(seconds: seconds, queue: queue, fire: fire) },
    log: { Logger(subsystem: HelperIdentity.helperBundleID, category: "helper").notice("\($0, privacy: .public)") })
adapter.start()
let fan = FanGuard(
    connect: { try SMCConnection() },
    schedule: { seconds, fire in DispatchLeaseTimer(seconds: seconds, queue: queue, fire: fire) },
    log: { Logger(subsystem: HelperIdentity.helperBundleID, category: "fan").notice("\($0, privacy: .public)") })
fan.start()
let led = LEDGuard(
    connect: { try SMCConnection() },
    schedule: { seconds, fire in DispatchLeaseTimer(seconds: seconds, queue: queue, fire: fire) },
    log: { Logger(subsystem: HelperIdentity.helperBundleID, category: "led").notice("\($0, privacy: .public)") })
led.start()

// launchd stops us with SIGTERM (unregister, shutdown); Ctrl-C when run by hand. Restore, then exit.
// A failed restore exits non-zero so KeepAlive (SuccessfulExit = false) starts us again to retry.
let signalSources = [SIGTERM, SIGINT].map { sig in
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: queue)
    src.setEventHandler {
        let charger = adapter.restore(reason: "signal \(sig)"), fans = fan.restore(reason: "signal \(sig)")
        let light = led.restore(reason: "signal \(sig)")
        exit(charger == .smcFailed || fans == .smcFailed || light == .smcFailed ? 1 : 0)
    }
    src.resume()
    return src
}
let power = SystemPowerWatcher(adapter: adapter, fan: fan, led: led, queue: queue)
if power == nil {
    Logger(subsystem: HelperIdentity.helperBundleID, category: "helper")
        .error("IORegisterForSystemPower failed: no restore before sleep; the wall-clock lease still ends any cut")
}

let gate = ClientGate(teamID: Bundle.main.object(forInfoDictionaryKey: HelperIdentity.teamIDInfoKey) as? String)
let listener = NSXPCListener(machServiceName: HelperIdentity.machService)
if let requirement = gate.requirement { listener.setConnectionCodeSigningRequirement(requirement) }
let delegate = HelperListenerDelegate(gate: gate, service: HelperService(adapter: adapter, fan: fan, led: led))
listener.delegate = delegate
listener.resume()
withExtendedLifetime((signalSources, power, delegate)) { dispatchMain() }
