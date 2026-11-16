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

    public init(teamID: String?, checker: CodeChecking = SecCodeChecker()) {
        requirement = CodeSigningRequirement.app(teamID: teamID)
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
    public init(adapter: AdapterGuard) { self.adapter = adapter }

    public func version(reply: @escaping @Sendable (Int) -> Void) { reply(HelperIdentity.version) }

    public func status(reply: @escaping @Sendable (Bool, Int, Int, Int, Int) -> Void) {
        let s = adapter.status()
        reply(s.adapterEnabled, s.chie, HelperIdentity.version, s.leaseRemaining, s.chie < 0 ? HelperErrorCode.smcFailed.rawValue : 0)
    }

    public func setAdapter(enabled: Bool, leaseSeconds: Int, reply: @escaping @Sendable (Int) -> Void) {
        reply(adapter.setAdapter(enabled: enabled, leaseSeconds: leaseSeconds).rawValue)
    }

    public func resetAll(reply: @escaping @Sendable (Int) -> Void) {
        reply(adapter.restore(reason: "reset all").rawValue)
    }
}

public final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let gate: ClientGate
    let service: HelperService

    public init(gate: ClientGate, service: HelperService) {
        self.gate = gate
        self.service = service
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement = gate.requirement, gate.accepts(pid: connection.processIdentifier) else { return false }
        connection.setCodeSigningRequirement(requirement) // the system re-checks on every message
        connection.exportedInterface = NSXPCInterface(with: AppleCartHelperXPC.self)
        connection.exportedObject = service
        Self.attachRestore(to: connection, adapter: service.adapter)
        connection.resume()
        return true
    }

    /// The app went away (quit, crash, killed): put the adapter back now instead of waiting for the lease.
    static func attachRestore(to connection: NSXPCConnection, adapter: AdapterGuard) {
        connection.invalidationHandler = { adapter.restore(reason: "connection invalidated") }
        connection.interruptionHandler = { adapter.restore(reason: "connection interrupted") }
    }
}
