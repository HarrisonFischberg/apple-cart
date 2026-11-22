import Foundation

/// Names shared by the app, the launchd plist and the helper. Keep in sync with
/// Helper/app.rarecreatures.applecart.helper.plist.
public enum HelperIdentity {
    public static let appBundleID = "app.rarecreatures.applecart"
    public static let helperBundleID = "app.rarecreatures.applecart.helper"
    public static let machService = "app.rarecreatures.applecart.helper"
    public static let plistName = "app.rarecreatures.applecart.helper.plist"
    /// Bump when the XPC surface or helper behavior changes; the app shows "outdated" on a mismatch.
    /// 3 added fan control (setFan, resetFan, fanStatus). 4 added the MagSafe light (setLED, resetLED, ledStatus).
    /// A helper from before 4 is not replaced in place: Remove, then Install.
    public static let version = 4
    /// The charger calls (status, setAdapter, resetAll) are unchanged since 2 and the fan calls since 3, so an older helper
    /// still drives what it has; only the MagSafe light needs `version`. A helper newer than the app is outdated for all.
    public static let chargeVersions = 2...version
    public static let fanVersions = 3...version

    public static func supportsCharging(helperVersion v: Int) -> Bool { chargeVersions.contains(v) }
    public static func supportsFans(helperVersion v: Int) -> Bool { fanVersions.contains(v) }
    public static func supportsLED(helperVersion v: Int) -> Bool { v == version }
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

    /// Readable name for error text. String interpolation of an @objc enum prints "HelperErrorCode(rawValue: 7)".
    public var name: String {
        switch self {
        case .ok: "ok"
        case .outdated: "outdated"
        case .refused: "refused"
        case .smcFailed: "smcFailed"
        case .notAllowed: "notAllowed"
        case .sleeping: "sleeping"
        case .unsupported: "unsupported"
        case .notApplied: "notApplied"
        }
    }

    /// Name for any reply code, including ones this build does not know.
    public static func name(for code: Int) -> String { HelperErrorCode(rawValue: code)?.name ?? "\(code)" }
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

    /// Version 4. Force the MagSafe light to `color` (3 green, 4 orange; anything else is refused) for at most
    /// `leaseSeconds` (clamped like AdapterLease). The helper keeps writing it back while macOS changes it, and hands the
    /// light back to macOS when the lease ends.
    func setLED(color: Int, leaseSeconds: Int, reply: @escaping @Sendable (Int) -> Void)
    /// Version 4. Stop forcing the light, lease cancelled. Writes nothing when nothing is forced.
    func resetLED(reply: @escaping @Sendable (Int) -> Void)
    /// Version 4. supported, raw ACLC value (-1 if unreadable), forced colour (0 if none), lease seconds left, error code.
    func ledStatus(reply: @escaping @Sendable (Bool, Int, Int, Int, Int) -> Void)
}

/// One lease length and range for every helper command: the charger cut, manual fans and the forced MagSafe light.
public enum AdapterLease {
    public static let defaultSeconds = 90
    public static let range = 10...300

    public static func clamped(_ seconds: Int) -> Int {
        min(max(seconds, range.lowerBound), range.upperBound)
    }
}

/// Code-signing requirements for both ends of the XPC connection. Returns nil for a missing or malformed
/// team ID so callers fail closed (no connection is accepted) instead of trusting everyone.
///
/// `developerIDOnly` (Release builds) also requires a Developer ID Application certificate issued through Apple's
/// Developer ID intermediate, so Apple Development builds (which carry get-task-allow and can be attached to by any
/// process of the same user) are not a valid key to the root helper. Debug builds pass false so the owner's
/// Apple Development builds keep working on both ends.
public enum CodeSigningRequirement {
    /// Apple's Developer ID Application leaf marker and the Developer ID CA intermediate marker, as in Apple's own
    /// designated requirement for Developer ID signed code.
    static let developerIDClause = "certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]"

    public static func make(identifier: String, teamID: String?, developerIDOnly: Bool = false) -> String? {
        guard let team = teamID, team.count == 10, team.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }),
              !identifier.isEmpty, identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
        else { return nil }
        let base = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        return developerIDOnly ? "\(base) and \(developerIDClause)" : base
    }

    /// What the helper requires of its caller: the Apple Cart app signed by our team.
    public static func app(teamID: String?, developerIDOnly: Bool = false) -> String? {
        make(identifier: HelperIdentity.appBundleID, teamID: teamID, developerIDOnly: developerIDOnly)
    }
    /// What the app requires of the helper.
    public static func helper(teamID: String?, developerIDOnly: Bool = false) -> String? {
        make(identifier: HelperIdentity.helperBundleID, teamID: teamID, developerIDOnly: developerIDOnly)
    }

    /// True in Release builds of the app and the helper (both pass their own `#if DEBUG` result in, because the flag must
    /// follow the target's build configuration).
    public static func developerIDOnly(debugBuild: Bool) -> Bool { !debugBuild }
}
