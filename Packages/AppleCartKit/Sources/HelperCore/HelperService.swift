import Foundation
import HelperProtocol
import Security

/// Checks a caller process against a code-signing requirement. Fakes stand in for it in tests.
public protocol CodeChecking: Sendable {
    func process(_ pid: pid_t, satisfies requirement: String) -> Bool
}

public struct SecCodeChecker: CodeChecking {
    public init() {}
    public func process(_ pid: pid_t, satisfies requirement: String) -> Bool {
        var code: SecCode?
        var req: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code) == errSecSuccess,
              let code, SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req
        else { return false }
        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }
}

/// Second layer behind NSXPCListener.setConnectionCodeSigningRequirement (which the system enforces).
/// No requirement (missing or malformed team ID) means nobody gets in.
public struct ClientGate: Sendable {
    public let requirement: String?
    let checker: CodeChecking

    /// `developerIDOnly` is true in the Release helper: only the Developer ID signed app gets in (audit 10).
    public init(teamID: String?, developerIDOnly: Bool = false, checker: CodeChecking = SecCodeChecker()) {
        requirement = CodeSigningRequirement.app(teamID: teamID, developerIDOnly: developerIDOnly)
        self.checker = checker
    }

    public func accepts(pid: pid_t) -> Bool {
        guard let requirement, pid > 0 else { return false }
        return checker.process(pid, satisfies: requirement)
    }
}

/// The exported XPC object: maps the narrow protocol onto the guard. Inputs are clamped by the guard.
public final class HelperService: NSObject, AppleCartHelperXPC, @unchecked Sendable {
    let adapter: AdapterGuard
    let fan: FanGuard?
    let led: LEDGuard?
    public init(adapter: AdapterGuard, fan: FanGuard? = nil, led: LEDGuard? = nil) { self.adapter = adapter; self.fan = fan; self.led = led }

    public func version(reply: @escaping @Sendable (Int) -> Void) { reply(HelperIdentity.version) }

    public func status(reply: @escaping @Sendable (Bool, Int, Int, Int, Int) -> Void) {
        let s = adapter.status()
        let code: HelperErrorCode = !s.supported ? .unsupported : s.chie < 0 ? .smcFailed : .ok
        reply(s.adapterEnabled, s.chie, HelperIdentity.version, s.leaseRemaining, code.rawValue)
    }

    public func setAdapter(enabled: Bool, leaseSeconds: Int, reply: @escaping @Sendable (Int) -> Void) {
        reply(adapter.setAdapter(enabled: enabled, leaseSeconds: leaseSeconds).rawValue)
    }

    public func resetAll(reply: @escaping @Sendable (Int) -> Void) {
        reply(adapter.restore(reason: "reset all").rawValue)
    }

    public func setFan(rpm: Int, leaseSeconds: Int, reply: @escaping @Sendable (Int) -> Void) {
        reply((fan?.setFan(rpm: rpm, leaseSeconds: leaseSeconds) ?? .unsupported).rawValue)
    }

    public func resetFan(reply: @escaping @Sendable (Int) -> Void) {
        reply((fan?.restore(reason: "reset fan") ?? .unsupported).rawValue)
    }

    public func fanStatus(reply: @escaping @Sendable (Bool, Int, Int, Int, Int, Bool, Int, Int, Int) -> Void) {
        guard let s = fan?.status() else { return reply(false, 0, -1, 0, 0, false, 0, 0, HelperErrorCode.unsupported.rawValue) }
        reply(s.supported, s.count, s.actualRPM, s.minimumRPM, s.maximumRPM, s.manual, s.targetRPM, s.leaseRemaining, s.code.rawValue)
    }

    public func setLED(color: Int, leaseSeconds: Int, reply: @escaping @Sendable (Int) -> Void) {
        reply((led?.setLED(color: color, leaseSeconds: leaseSeconds) ?? .unsupported).rawValue)
    }

    public func resetLED(reply: @escaping @Sendable (Int) -> Void) {
        reply((led?.restore(reason: "reset led") ?? .unsupported).rawValue)
    }

    public func ledStatus(reply: @escaping @Sendable (Bool, Int, Int, Int, Int) -> Void) {
        guard let s = led?.status() else { return reply(false, -1, 0, 0, HelperErrorCode.unsupported.rawValue) }
        reply(s.supported, s.raw, s.wanted, s.leaseRemaining, s.code.rawValue)
    }
}

/// Live app connections, so the helper restores only when the last one ends (a second copy quitting does not undo the first).
final class LiveClients: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<ObjectIdentifier> = []
    func opened(_ id: ObjectIdentifier) { lock.withLock { _ = ids.insert(id) } }
    /// Marks the connection ended; true when no app connection is left.
    func ended(_ id: ObjectIdentifier) -> Bool { lock.withLock { ids.remove(id); return ids.isEmpty } }
}

public final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let gate: ClientGate
    let service: HelperService
    let clients = LiveClients()

    public init(gate: ClientGate, service: HelperService) {
        self.gate = gate
        self.service = service
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement = gate.requirement, gate.accepts(pid: connection.processIdentifier) else { return false }
        connection.setCodeSigningRequirement(requirement) // the system re-checks on every message
        connection.exportedInterface = NSXPCInterface(with: AppleCartHelperXPC.self)
        connection.exportedObject = service
        Self.attachRestore(to: connection, adapter: service.adapter, fan: service.fan, led: service.led, clients: clients)
        connection.resume()
        return true
    }

    /// The app went away (quit, crash, killed): put the adapter back and the fans and light to macOS now instead of waiting for
    /// the lease, unless another app connection is still live (its own lease still bounds any cut).
    static func attachRestore(to connection: NSXPCConnection, adapter: AdapterGuard, fan: FanGuard? = nil, led: LEDGuard? = nil,
                              clients: LiveClients = LiveClients()) {
        let id = ObjectIdentifier(connection)
        clients.opened(id)
        connection.invalidationHandler = {
            guard clients.ended(id) else { return }
            adapter.restore(reason: "connection invalidated"); fan?.restore(reason: "connection invalidated"); led?.restore(reason: "connection invalidated")
        }
        connection.interruptionHandler = {
            guard clients.ended(id) else { return }
            adapter.restore(reason: "connection interrupted"); fan?.restore(reason: "connection interrupted"); led?.restore(reason: "connection interrupted")
        }
    }
}
