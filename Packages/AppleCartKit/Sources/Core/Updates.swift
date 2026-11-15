import Foundation
import Observation

public struct CommandResult: Sendable { public let status: Int32; public let output: String
    public init(status: Int32, output: String) { self.status = status; self.output = output } }

/// Runs one command. nil means it could not start or timed out.
public protocol CommandRunner: Sendable {
    func run(_ path: String, _ args: [String], env: [String: String]) async -> CommandResult?
}

public struct UpdateItem: Equatable, Sendable, Identifiable {
    public let name: String, installed: String?, available: String
    public var id: String { name }
    public init(name: String, installed: String?, available: String) { self.name = name; self.installed = installed; self.available = available }
}

public enum UpdateSource: Equatable, Sendable {
    case notInstalled, upToDate, outdated([UpdateItem]), failed(String)
}

public enum UpdateParser {
    /// `brew outdated --json=v2`
    public static func brew(_ json: String) -> UpdateSource {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return .failed("Homebrew gave an answer this app could not read.") }
        var items: [UpdateItem] = []
        for kind in ["formulae", "casks"] {
            for e in obj[kind] as? [[String: Any]] ?? [] {
                guard let name = e["name"] as? String, let cur = e["current_version"] as? String else { continue }
                let inst = e["installed_versions"]
                items.append(UpdateItem(name: name, installed: (inst as? [String])?.last ?? inst as? String, available: cur))
            }
        }
        return items.isEmpty ? .upToDate : .outdated(items.sorted { $0.name < $1.name })
    }

    /// `softwareupdate --list`: "* Label: X" then "Title: X, Version: Y, Size: ...".
    public static func softwareUpdate(_ text: String) -> UpdateSource {
        var items: [UpdateItem] = []
        for line in text.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("Title:") else { continue }
            let fields = l.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            func value(_ k: String) -> String? { fields.first { $0.hasPrefix(k + ":") }.map { String($0.dropFirst(k.count + 1)).trimmingCharacters(in: .whitespaces) } }
            if let title = value("Title") { items.append(UpdateItem(name: title, installed: nil, available: value("Version") ?? "")) }
        }
        return items.isEmpty ? .upToDate : .outdated(items)
    }
}

/// Checks only when asked: nothing runs in the background.
@MainActor @Observable
public final class UpdateChecker {
    public enum Phase: Equatable { case idle, checking, done(Date) }
    public private(set) var phase: Phase = .idle
    public private(set) var homebrew: UpdateSource = .notInstalled
    public private(set) var macOS: UpdateSource = .upToDate
    @ObservationIgnored private let runner: CommandRunner
    @ObservationIgnored private let brewPath: String
    @ObservationIgnored private let exists: @Sendable (String) -> Bool

    public init(runner: CommandRunner, brewPath: String = "/opt/homebrew/bin/brew",
                exists: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.runner = runner; self.brewPath = brewPath; self.exists = exists
    }

    public func check() async {
        guard phase != .checking else { return }
        phase = .checking
        async let brew = checkBrew()
        async let sys = checkSystem()
        (homebrew, macOS) = await (brew, sys)
        phase = .done(Date())
    }

    private func checkBrew() async -> UpdateSource {
        guard exists(brewPath) else { return .notInstalled }
        // Local index only: an update check must not change the user's Homebrew.
        guard let r = await runner.run(brewPath, ["outdated", "--json=v2"], env: ["HOMEBREW_NO_AUTO_UPDATE": "1"]) else { return .failed("Homebrew did not answer.") }
        return r.status == 0 ? UpdateParser.brew(r.output) : .failed("Homebrew reported a problem.")
    }

    private func checkSystem() async -> UpdateSource {
        guard let r = await runner.run("/usr/sbin/softwareupdate", ["--list"], env: [:]) else { return .failed("macOS did not answer.") }
        return r.status == 0 ? UpdateParser.softwareUpdate(r.output) : .failed("macOS could not check for updates.")
    }
}

public struct ProcessRunner: CommandRunner {
    let timeout: TimeInterval
    public init(timeout: TimeInterval = 120) { self.timeout = timeout }

    public func run(_ path: String, _ args: [String], env: [String: String]) async -> CommandResult? {
        await Task.detached { () -> CommandResult? in
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: path); p.arguments = args
            p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
            p.standardOutput = pipe; p.standardError = pipe
            do { try p.run() } catch { return nil }
            let killer = DispatchWorkItem { p.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            killer.cancel()
            if p.terminationReason == .uncaughtSignal { return nil }
            return CommandResult(status: p.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }.value
    }
}
