import Core
import Foundation
import HelperProtocol
import ServiceManagement

/// One NSXPCConnection to the root helper, shared by the charge and fan controllers so that the helper's
/// "connection went away" restore means the app really went away.
final class HelperClient: @unchecked Sendable {
    static let shared = HelperClient()
    static var service: SMAppService { .daemon(plistName: HelperIdentity.plistName) }
    private static let timeout: DispatchTimeInterval = .seconds(5)

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    /// Nil when the team ID build setting is missing: then we never connect (fail closed). Release builds also require the
    /// helper to be Developer ID signed (audit 10).
    private let requirement = CodeSigningRequirement.helper(
        teamID: Bundle.main.object(forInfoDictionaryKey: HelperIdentity.teamIDInfoKey) as? String,
        developerIDOnly: CodeSigningRequirement.developerIDOnly(debugBuild: HelperClient.debugBuild))

    #if DEBUG
    static let debugBuild = true
    #else
    static let debugBuild = false
    #endif

    /// Helper status before any XPC call: nil when registered and enabled (then ask the helper itself).
    static var registrationStatus: ChargeHelperStatus? {
        switch service.status {
        case .notRegistered, .notFound: .notInstalled
        case .requiresApproval: .needsApproval
        case .enabled: nil
        @unknown default: .unreachable
        }
    }

    /// A command's reply code as an apply result.
    func command(_ body: @escaping @Sendable (AppleCartHelperXPC, @escaping @Sendable (Int) -> Void) -> Void) async -> ChargeApplyResult {
        guard Self.service.status == .enabled else { return .unavailable }
        let code: Int? = await call(body)
        return HelperCall.result(code: code, name: { HelperErrorCode(rawValue: $0).map { "\($0)" } ?? "\($0)" })
    }

    private func connect() -> NSXPCConnection? {
        lock.lock(); defer { lock.unlock() }
        if let connection { return connection }
        guard let requirement else { return nil }
        let c = NSXPCConnection(machServiceName: HelperIdentity.machService, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: AppleCartHelperXPC.self)
        c.setCodeSigningRequirement(requirement) // only our own signed helper may answer
        c.invalidationHandler = { [weak self] in self?.dropConnection() }
        c.resume()
        connection = c
        return c
    }

    private func dropConnection() {
        lock.lock(); connection = nil; lock.unlock()
    }

    /// One XPC round trip; nil on error, invalidation or timeout. Resumes exactly once.
    func call<T: Sendable>(_ body: @escaping @Sendable (AppleCartHelperXPC, @escaping @Sendable (T) -> Void) -> Void) async -> T? {
        guard let conn = connect() else { return nil }
        return await HelperCall.first(timeout: Self.timeout) { finish in
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ _ in finish(nil) }) as? AppleCartHelperXPC else {
                finish(nil); return
            }
            body(proxy) { finish($0) }
        }
    }
}

/// Talks to the root helper through the shared HelperClient. Ready only when the daemon is registered, approved,
/// answers status() with a version that has the charger calls (2 to 4: an older helper keeps charging working
/// until it is repaired) and can read the charger key.
final class HelperChargeController: ChargeController, @unchecked Sendable {
    private struct StatusReply: Sendable { var adapterEnabled: Bool, chie: Int, version: Int, code: Int }

    static var service: SMAppService { HelperClient.service }
    private let client: HelperClient
    init(client: HelperClient = .shared) { self.client = client }

    func status() async -> ChargeHelperReport {
        if let s = HelperClient.registrationStatus { return ChargeHelperReport(s) }
        let reply: StatusReply? = await client.call({ p, done in
            p.status { enabled, chie, version, _, code in done(StatusReply(adapterEnabled: enabled, chie: chie, version: version, code: code)) }
        })
        guard let reply else { return ChargeHelperReport(.unreachable) }
        guard HelperIdentity.supportsCharging(helperVersion: reply.version) else { return ChargeHelperReport(.outdated) }
        // Only the helper's explicit "unsupported" (no CHIE key) means this Mac cannot do it; a failed read is transient.
        if reply.code == HelperErrorCode.unsupported.rawValue { return ChargeHelperReport(.unsupported) }
        return ChargeHelperReport(.ready, adapterCut: reply.chie < 0 ? nil : !reply.adapterEnabled)
    }

    func apply(_ decision: ChargeDecision) async -> ChargeApplyResult {
        let enabled: Bool
        switch decision {
        case .allowCharging: enabled = true
        case .holdCharging, .discharge: enabled = false
        }
        return await client.command { p, done in p.setAdapter(enabled: enabled, leaseSeconds: AdapterLease.defaultSeconds, reply: done) }
    }

    func resetAll() async -> ChargeApplyResult {
        await client.command { p, done in p.resetAll(reply: done) }
    }
}

/// Fan commands over the same connection. Needs a version 3 or later helper: an older one shows "outdated" (Repair installs the
/// one inside this app) and fan calls are never sent to it.
final class HelperFanController: FanController, @unchecked Sendable {
    private struct FanReply: Sendable { var supported: Bool, manual: Bool, target: Int, code: Int }
    private let client: HelperClient
    init(client: HelperClient = .shared) { self.client = client }

    private func version() async -> Int? {
        await client.call { p, done in p.status { _, _, version, _, _ in done(version) } }
    }

    func status() async -> FanHelperReport {
        if let s = HelperClient.registrationStatus { return FanHelperReport(s) }
        guard let v = await version() else { return FanHelperReport(.unreachable) }
        guard HelperIdentity.supportsFans(helperVersion: v) else { return FanHelperReport(.outdated) }
        let reply: FanReply? = await client.call({ p, done in
            p.fanStatus { supported, _, _, _, _, manual, target, _, code in done(FanReply(supported: supported, manual: manual, target: target, code: code)) }
        })
        guard let reply else { return FanHelperReport(.unreachable) }
        if !reply.supported || reply.code == HelperErrorCode.unsupported.rawValue { return FanHelperReport(.unsupported) }
        return FanHelperReport(.ready, manual: reply.code == HelperErrorCode.ok.rawValue ? reply.manual : nil, targetRPM: reply.target)
    }

    func setFan(rpm: Int) async -> ChargeApplyResult {
        // The runner only sends after a ready status (version 3 or 4), so a version 2 helper never sees this selector.
        await client.command { p, done in p.setFan(rpm: rpm, leaseSeconds: AdapterLease.defaultSeconds, reply: done) }
    }

    func resetFan() async -> ChargeApplyResult {
        guard let v = await version(), HelperIdentity.supportsFans(helperVersion: v) else { return .unavailable }
        return await client.command { p, done in p.resetFan(reply: done) }
    }
}

/// MagSafe light commands over the same connection. Needs a version 4 helper: an older one is "outdated" here (Remove, then
/// Install, puts in the one inside this app) and light calls are never sent to it.
final class HelperLEDController: LEDController, @unchecked Sendable {
    private struct LEDReply: Sendable { var supported: Bool, code: Int }
    private let client: HelperClient
    init(client: HelperClient = .shared) { self.client = client }

    private func version() async -> Int? {
        await client.call { p, done in p.status { _, _, version, _, _ in done(version) } }
    }

    func status() async -> ChargeHelperStatus {
        if let s = HelperClient.registrationStatus { return s }
        guard let v = await version() else { return .unreachable }
        guard HelperIdentity.supportsLED(helperVersion: v) else { return .outdated }
        let reply: LEDReply? = await client.call({ p, done in
            p.ledStatus { supported, _, _, _, code in done(LEDReply(supported: supported, code: code)) }
        })
        guard let reply else { return .unreachable }
        return !reply.supported || reply.code == HelperErrorCode.unsupported.rawValue ? .unsupported : .ready
    }

    func setLED(_ color: LEDColor) async -> ChargeApplyResult {
        let value: Int
        switch color {
        case .green: value = 3
        case .orange: value = 4
        case .system: return await resetLED()
        }
        // The runner only sends after a ready status (version 4), so an older helper never sees this selector.
        return await client.command { p, done in p.setLED(color: value, leaseSeconds: AdapterLease.defaultSeconds, reply: done) }
    }

    func resetLED() async -> ChargeApplyResult {
        guard let v = await version(), HelperIdentity.supportsLED(helperVersion: v) else { return .unavailable }
        return await client.command { p, done in p.resetLED(reply: done) }
    }
}

/// Install, repair and remove through SMAppService. Remove puts the adapter back on and the fans and light back to macOS first.
@MainActor
enum ChargeHelperInstaller {
    static func install() async -> String? {
        do { try HelperChargeController.service.register(); return nil } catch {
            // Registering succeeds but throws while it still needs the owner's approval in Login Items.
            return HelperChargeController.service.status == .requiresApproval ? nil : error.localizedDescription
        }
    }

    static func repair() async -> String? {
        try? await HelperChargeController.service.unregister()
        return await install()
    }

    static func remove(controller: ChargeController, fans: FanController, led: LEDController) async -> String? {
        _ = await controller.resetAll()
        _ = await fans.resetFan()
        _ = await led.resetLED()
        do { try await HelperChargeController.service.unregister(); return nil } catch { return error.localizedDescription }
    }

    static func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
