import Foundation

/// Names shared by the app, the launchd plist and the helper. Keep in sync with
/// Helper/app.rarecreatures.applecart.helper.plist.
public enum HelperIdentity {
    public static let appBundleID = "app.rarecreatures.applecart"
    public static let helperBundleID = "app.rarecreatures.applecart.helper"
    public static let machService = "app.rarecreatures.applecart.helper"
    public static let plistName = "app.rarecreatures.applecart.helper.plist"
    /// Bump when the XPC surface or helper behavior changes; the app shows "outdated" on a mismatch.
    /// 3 added fan control (setFan, resetFan, fanStatus).
    public static let version = 3
    /// The charger calls (status, setAdapter, resetAll) are unchanged since 2, so a version 2 helper still drives the
    /// charge limit; only fan control needs `version`. A helper newer than the app is outdated for both.
    public static let chargeVersions = 2...version

    public static func supportsCharging(helperVersion v: Int) -> Bool { chargeVersions.contains(v) }
    public static func supportsFans(helperVersion v: Int) -> Bool { v == version }
    /// Info.plist key that carries the team ID from the AC_TEAM_ID build setting (the one place it lives).
    public static let teamIDInfoKey = "ACTeamID"
}

/// Small error codes so replies stay plain types. 0 is success.
@objc public enum HelperErrorCode: Int, Sendable {
    case ok = 0
    case outdated = 1
    case refused = 2
    case smcFailed = 3
    case notAllowed = 4
    /// Cut refused between "system will sleep" and power-on.
    case sleeping = 5
    /// This Mac has no CHIE key (or no SMC): charge control cannot work here.
    case unsupported = 6
    /// The SMC took the write but reads back something else (fan mode did not switch); the helper restored.
    case notApplied = 7
}

/// The whole XPC surface. Inputs are clamped on the helper side; nothing here is ever run as a shell string.
@objc public protocol AppleCartHelperXPC {
    func version(reply: @escaping @Sendable (Int) -> Void)
    /// adapterEnabled, raw CHIE value (-1 if it could not be read), helper version, lease seconds left (0 if none), error code.
    func status(reply: @escaping @Sendable (Bool, Int, Int, Int, Int) -> Void)
    /// enabled false cuts the adapter for at most `leaseSeconds` (clamped); the helper restores it by itself after that.
    func setAdapter(enabled: Bool, leaseSeconds: Int, reply: @escaping @Sendable (Int) -> Void)
    /// Adapter on, lease cancelled. Called on tool off, delete all data and helper removal.
    func resetAll(reply: @escaping @Sendable (Int) -> Void)

    /// Version 3. Every fan to manual at `rpm` for at most `leaseSeconds` (clamped like AdapterLease); the helper clamps
    /// rpm into each fan's own [minimum, maximum] read from the SMC and hands the fans back to macOS when the lease ends.
    /// rpm 0 or less means "nothing manual": the same as resetFan.
    func setFan(rpm: Int, leaseSeconds: Int, reply: @escaping @Sendable (Int) -> Void)
    /// Version 3. Fans back to macOS (system control), lease cancelled.
    func resetFan(reply: @escaping @Sendable (Int) -> Void)
    /// Version 3. supported, fan count, actual rpm (fastest fan), minimum rpm (highest fan minimum), maximum rpm (lowest fan
    /// maximum), manual active, manual target rpm (0 if none), lease seconds left, error code.
    func fanStatus(reply: @escaping @Sendable (Bool, Int, Int, Int, Int, Bool, Int, Int, Int) -> Void)
}

public enum AdapterLease {
    public static let defaultSeconds = 90
    public static let range = 10...300

    public static func clamped(_ seconds: Int) -> Int {
        min(max(seconds, range.lowerBound), range.upperBound)
    }
}

/// Code-signing requirements for both ends of the XPC connection. Returns nil for a missing or malformed
/// team ID so callers fail closed (no connection is accepted) instead of trusting everyone.
public enum CodeSigningRequirement {
    public static func make(identifier: String, teamID: String?) -> String? {
        guard let team = teamID, team.count == 10, team.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }),
              !identifier.isEmpty, identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
        else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// What the helper requires of its caller: the Apple Cart app signed by our team.
    public static func app(teamID: String?) -> String? { make(identifier: HelperIdentity.appBundleID, teamID: teamID) }
    /// What the app requires of the helper.
    public static func helper(teamID: String?) -> String? { make(identifier: HelperIdentity.helperBundleID, teamID: teamID) }
}
