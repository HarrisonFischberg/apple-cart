import Core
import Foundation
import HelperProtocol
import ServiceManagement

/// Talks to the root helper over one shared NSXPCConnection. Ready only when the daemon is registered,
/// approved, answers status() with our version and can read the charger key.
final class HelperChargeController: ChargeController, @unchecked Sendable {
    private struct StatusReply: Sendable { var adapterEnabled: Bool, chie: Int, version: Int, code: Int }

    static var service: SMAppService { .daemon(plistName: HelperIdentity.plistName) }
    private static let timeout: DispatchTimeInterval = .seconds(5)

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    /// Nil when the team ID build setting is missing: then we never connect (fail closed).
    private let requirement = CodeSigningRequirement.helper(teamID: Bundle.main.object(forInfoDictionaryKey: HelperIdentity.teamIDInfoKey) as? String)

    func status() async -> ChargeHelperReport {
        switch Self.service.status {
        case .notRegistered, .notFound: return ChargeHelperReport(.notInstalled)
        case .requiresApproval: return ChargeHelperReport(.needsApproval)
        case .enabled:
            let reply: StatusReply? = await call({ p, done in
                p.status { enabled, chie, version, _, code in done(StatusReply(adapterEnabled: enabled, chie: chie, version: version, code: code)) }
            })
            guard let reply else { return ChargeHelperReport(.unreachable) }
            guard reply.version == HelperIdentity.version else { return ChargeHelperReport(.outdated) }
            // No CHIE key, or the SMC cannot be read: never report ready, so the runner never cuts.
            if reply.code == HelperErrorCode.unsupported.rawValue || reply.chie < 0 { return ChargeHelperReport(.unsupported) }
            return ChargeHelperReport(.ready, adapterCut: !reply.adapterEnabled)
        @unknown default: return ChargeHelperReport(.unreachable)
        }
    }

    func apply(_ decision: ChargeDecision) async -> ChargeApplyResult {
        let enabled: Bool
        switch decision {
        case .allowCharging: enabled = true
        case .holdCharging, .discharge: enabled = false
        }
        return await command { p, done in p.setAdapter(enabled: enabled, leaseSeconds: AdapterLease.defaultSeconds, reply: done) }
    }

    func resetAll() async -> ChargeApplyResult {
        await command { p, done in p.resetAll(reply: done) }
    }

    private func command(_ body: @escaping @Sendable (AppleCartHelperXPC, @escaping @Sendable (Int) -> Void) -> Void) async -> ChargeApplyResult {
        guard Self.service.status == .enabled else { return .unavailable }
        guard let code: Int = await call(body) else { return .failed("The charging helper did not answer.") }
        if code == HelperErrorCode.ok.rawValue { return .applied }
        return .failed("Helper error \(HelperErrorCode(rawValue: code).map { "\($0)" } ?? "\(code)")")
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
    private func call<T: Sendable>(_ body: @escaping @Sendable (AppleCartHelperXPC, @escaping @Sendable (T) -> Void) -> Void) async -> T? {
        guard let conn = connect() else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
            let once = Once(cont)
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) { once.resume(nil) }
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ _ in once.resume(nil) }) as? AppleCartHelperXPC else {
                once.resume(nil); return
            }
            body(proxy) { once.resume($0) }
        }
    }
}

private final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T?, Never>?
    init(_ cont: CheckedContinuation<T?, Never>) { self.cont = cont }
    func resume(_ value: T?) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(returning: value)
    }
}

/// Install, repair and remove through SMAppService. Remove puts the adapter back on first.
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

    static func remove(controller: ChargeController) async -> String? {
        _ = await controller.resetAll()
        do { try await HelperChargeController.service.unregister(); return nil } catch { return error.localizedDescription }
    }

    static func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
