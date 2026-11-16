// Apple Cart root helper (launchd daemon registered with SMAppService.daemon). It can only turn the
// charger (SMC key CHIE) off on a lease or back on; every way out puts the charger back on.
import Foundation
import HelperCore
import HelperProtocol
import os

private struct NoSMC: SMCWriting {
    func read(key: String) throws -> UInt8 { throw SMCError.unavailable }
    func write(key: String, value: UInt8) throws { throw SMCError.unavailable }
}

let queue = DispatchQueue(label: "app.rarecreatures.applecart.helper")
let smc: SMCWriting
do { smc = try SMCConnection() } catch {
    Logger(subsystem: HelperIdentity.helperBundleID, category: "helper").error("AppleSMC unavailable: \(String(describing: error), privacy: .public)")
    smc = NoSMC() // stay up and answer smcFailed instead of crash-looping under KeepAlive
}
let adapter = AdapterGuard(
    smc: smc,
    schedule: { seconds, fire in DispatchLeaseTimer(seconds: seconds, queue: queue, fire: fire) },
    log: { Logger(subsystem: HelperIdentity.helperBundleID, category: "helper").notice("\($0, privacy: .public)") })
adapter.start()

// launchd stops us with SIGTERM (unregister, shutdown); Ctrl-C when run by hand. Restore, then exit cleanly.
let signalSources = [SIGTERM, SIGINT].map { sig in
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: queue)
    src.setEventHandler { adapter.restore(reason: "signal \(sig)"); exit(0) }
    src.resume()
    return src
}
let power = SystemPowerWatcher(adapter: adapter, queue: queue)

let gate = ClientGate(teamID: Bundle.main.object(forInfoDictionaryKey: HelperIdentity.teamIDInfoKey) as? String)
let listener = NSXPCListener(machServiceName: HelperIdentity.machService)
if let requirement = gate.requirement { listener.setConnectionCodeSigningRequirement(requirement) }
let delegate = HelperListenerDelegate(gate: gate, service: HelperService(adapter: adapter))
listener.delegate = delegate
listener.resume()
withExtendedLifetime((signalSources, power, delegate)) { dispatchMain() }
