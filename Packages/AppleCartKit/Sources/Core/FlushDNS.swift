import Foundation
import Observation

public enum PrivilegedResult: Equatable, Sendable { case ok, cancelled, failed(String) }

/// Runs a shell line as root. The root helper (T009) replaces the admin prompt behind this.
public protocol PrivilegedRunner: Sendable {
    func run(_ shellLine: String) async -> PrivilegedResult
}

@MainActor @Observable
public final class FlushDNS {
    public enum Phase: Equatable { case idle, running, done(Date), cancelled, failed(String) }
    public private(set) var phase: Phase = .idle
    public static let command = "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"
    @ObservationIgnored private let runner: PrivilegedRunner

    public init(runner: PrivilegedRunner) { self.runner = runner }

    public func flush() async {
        guard phase != .running else { return }
        phase = .running
        switch await runner.run(Self.command) {
        case .ok: phase = .done(Date())
        case .cancelled: phase = .cancelled
        case .failed(let m): phase = .failed(m)
        }
    }
}

/// Asks macOS for an administrator password in its own dialog; the app never sees it.
public struct AdminPromptRunner: PrivilegedRunner {
    public init() {}
    public func run(_ shellLine: String) async -> PrivilegedResult {
        await Task.detached { () -> PrivilegedResult in
            let script = NSAppleScript(source: "do shell script \"\(shellLine)\" with administrator privileges with prompt \"Apple Cart wants to clear the DNS cache.\"")
            var err: NSDictionary?
            script?.executeAndReturnError(&err)
            guard let err else { return .ok }
            return (err[NSAppleScript.errorNumber] as? Int) == -128 ? .cancelled : .failed("macOS refused the request.")
        }.value
    }
}
