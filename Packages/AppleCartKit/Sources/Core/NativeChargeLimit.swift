import Foundation

/// macOS's own charge limit (System Settings > Battery > Charging > Charge Limit, macOS 26.4 and later).
///
/// Why it matters: a hold made by cutting the charger (the helper's CHIE write) makes macOS switch to battery power while the
/// charger is still plugged in, so "Slightly dim the display on battery" dims the screen at the limit and the Mac drains.
/// On macOS 27 firmware (seen on an M5) the old charge-inhibit keys (CH0B, CH0C, CHTE) are gone and CHIE is the only
/// writable charger key, so the SMC alone cannot pause charging while staying on the charger. macOS's own limit can: the
/// firmware stops charging and the Mac runs from the charger ("Not Charging", AC power), exactly as at a full charge.
/// Its range is 80...100 (100 = no limit), so only limits of 80% and up can use it.
public protocol NativeChargeLimit: Sendable {
    /// The macOS limit exists on this Mac and OS.
    func isSupported() async -> Bool
    /// The limit macOS is applying now. Nil when it could not be read.
    func current() async -> NativeLimitReading?
    /// Set the limit (80...100; 100 turns it off) and read it back. Nil when the call failed or could not be checked.
    func setLimit(_ percent: Int) async -> NativeLimitReading?
}

public struct NativeLimitReading: Equatable, Sendable, Codable {
    /// The macOS limit is on.
    public var enabled: Bool
    /// The percent it holds at, when on.
    public var limit: Int?
    public init(enabled: Bool, limit: Int?) { self.enabled = enabled; self.limit = limit }

    public static let off = NativeLimitReading(enabled: false, limit: nil)

    /// What a write of `percent` should read back as.
    public func confirms(_ percent: Int) -> Bool {
        percent >= 100 ? !enabled : (enabled && limit == percent)
    }
}

public enum NativeChargeLimits {
    /// macOS rejects anything lower (the private call crashes below 80, so it is never sent).
    public static let minimum = 80
    public static let range = minimum...100

    /// Reads the user's limit from `pmset -g battlimit`. The output lists one or more property-list style blocks; the user's
    /// limit is the block whose `chargeSocLimitReason` is `manualChargeLimit`, and its `chargeSocLimitSoc` is the percent.
    /// Nil when no such block is listed (other reasons, such as Optimized Battery Charging, are macOS's own, not a limit).
    public static func manualLimit(fromPmset text: String) -> Int? {
        var reason: String?
        var soc: Int?
        func value(_ line: String) -> String? {
            guard let eq = line.firstIndex(of: "=") else { return nil }
            return line[line.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: " \t;\""))
        }
        func found() -> Int? { reason?.contains("manualChargeLimit") == true ? soc : nil }
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix("{") { reason = nil; soc = nil }
            if line.hasPrefix("chargeSocLimitReason") { reason = value(line) }
            if line.hasPrefix("chargeSocLimitSoc") { soc = value(line).flatMap { Int($0) } }
            if line.hasPrefix("}") {
                if let n = found() { return n }
                reason = nil; soc = nil
            }
        }
        return found() // a block without braces
    }
}

/// The value to give macOS's limit on each pass, with Sailing done the way the firmware allows it: once the battery
/// reaches the limit, the macOS limit follows the battery down (it is set to the current level, so the charger keeps
/// running the Mac but does not top the battery up); when the level reaches the sailing floor the limit goes back up
/// and charging resumes. macOS cannot hold below 80%, so the floor never goes under 80.
public enum NativeChargePlan {
    public static func floor(limit: Int, sailFloor: Int?) -> Int {
        guard let f = sailFloor, f < limit else { return limit }
        return max(f, NativeChargeLimits.minimum)
    }

    /// `latched` is true while the battery is sailing (it reached the limit and has not yet fallen to the floor).
    public static func target(level: Int?, limit: Int, floor: Int, latched: inout Bool) -> Int {
        let limit = min(max(limit, NativeChargeLimits.minimum), 100)
        guard limit < 100 else { latched = false; return 100 }
        guard floor < limit, let level else { latched = false; return limit }
        if level >= limit { latched = true } else if level <= floor { latched = false }
        return latched ? min(max(level, floor), limit) : limit
    }
}

/// What the macOS limit was before Apple Cart first changed it, so turning the limit off or quitting gives the person their
/// own System Settings choice back. Kept in UserDefaults so a crash or relaunch still restores it.
public struct NativeLimitSnapshotStore: @unchecked Sendable {
    static let key = "chargeNativeLimitSnapshot"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> NativeLimitReading? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(NativeLimitReading.self, from: data)
    }

    public func save(_ r: NativeLimitReading) {
        if let data = try? JSONEncoder().encode(r) { defaults.set(data, forKey: Self.key) }
    }

    public func clear() { defaults.removeObject(forKey: Self.key) }
}
