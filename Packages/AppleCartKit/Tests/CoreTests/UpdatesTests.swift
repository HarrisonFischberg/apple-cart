import Foundation
import Testing
@testable import Core

private struct FakeRunner: CommandRunner {
    var brew: CommandResult? = CommandResult(status: 0, output: #"{"formulae":[],"casks":[]}"#)
    var sys: CommandResult? = CommandResult(status: 0, output: "No new software available.")
    func run(_ path: String, _ args: [String], env: [String: String]) async -> CommandResult? { path.hasSuffix("brew") ? brew : sys }
}

private actor FlushFake: PrivilegedRunner {
    var result: PrivilegedResult
    var lines: [String] = []
    init(_ r: PrivilegedResult) { result = r }
    func run(_ shellLine: String) async -> PrivilegedResult { lines.append(shellLine); return result }
}

@MainActor
@Suite struct UpdatesTests {
    @Test func parsesBrewFormulaeAndCasks() {
        let j = #"{"formulae":[{"name":"uv","installed_versions":["0.1"],"current_version":"0.2"}],"casks":[{"name":"zed","installed_versions":"1","current_version":"2"}]}"#
        #expect(UpdateParser.brew(j) == .outdated([UpdateItem(name: "uv", installed: "0.1", available: "0.2"), UpdateItem(name: "zed", installed: "1", available: "2")]))
        #expect(UpdateParser.brew("not json") == .failed("Homebrew gave an answer this app could not read."))
    }

    @Test func parsesSoftwareUpdate() {
        let t = "Software Update Tool\n* Label: macOS 27.3-1\n\tTitle: macOS 27.3, Version: 27.3, Size: 3000KiB, Recommended: YES, Action: restart,\n"
        #expect(UpdateParser.softwareUpdate(t) == .outdated([UpdateItem(name: "macOS 27.3", installed: nil, available: "27.3")]))
        #expect(UpdateParser.softwareUpdate("No new software available.") == .upToDate)
    }

    @Test func absentHomebrewIsAnEmptyStateNotAnError() async {
        let c = UpdateChecker(runner: FakeRunner(), exists: { _ in false })
        await c.check()
        #expect(c.homebrew == .notInstalled && c.macOS == .upToDate && c.phase != .checking)
    }

    @Test func failuresAreShownPerSource() async {
        let c = UpdateChecker(runner: FakeRunner(brew: nil, sys: CommandResult(status: 1, output: "")), exists: { _ in true })
        await c.check()
        #expect(c.homebrew == .failed("Homebrew did not answer.") && c.macOS == .failed("macOS could not check for updates."))
    }

    @Test func flushRunsTheFixedCommandAndReportsEachOutcome() async {
        for (r, want) in [(PrivilegedResult.cancelled, FlushDNS.Phase.cancelled), (.failed("x"), .failed("x"))] {
            let f = FlushDNS(runner: FlushFake(r)); await f.flush(); #expect(f.phase == want)
        }
        let fake = FlushFake(.ok); let f = FlushDNS(runner: fake); await f.flush()
        if case .done = f.phase {} else { Issue.record("not done") }
        #expect(await fake.lines == [FlushDNS.command])
    }
}
