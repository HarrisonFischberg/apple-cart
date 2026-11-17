import Foundation
import IOKit

/// The only SMC writes the helper may ever make. Proven on Mac17,2 / macOS 27.2.1 (docs/spikes/charge-control.md).
public enum SMCWhitelist {
    public static let adapterKey = "CHIE"
    public static let adapterOn: UInt8 = 0x00
    public static let adapterOff: UInt8 = 0x08

    public static func allows(key: String, value: UInt8) -> Bool {
        key == adapterKey && (value == adapterOn || value == adapterOff)
    }
}

/// The only fan keys the helper may touch. Writes: each fan's mode key (0 = macOS, 1 = manual), its target rpm (a float in
/// a sane range; FanGuard clamps it to the fan's own minimum and maximum first) and the unlock key Ftst (0 or 1), which is
/// written only on Macs that have it. Reads: these plus the fan count, actual, minimum and maximum rpm. Nothing else.
public enum FanWhitelist {
    public static let maxFans = 10
    public static let countKey = "FNum"
    public static let unlockKey = "Ftst"
    public static let manualMode: UInt8 = 1
    public static let systemMode: UInt8 = 0
    /// Lowercase "md" is what Apple silicon reports (Mac17,2); "Md" is the older spelling. Whichever exists is used.
    public static func modeKeys(_ fan: Int) -> [String] { ["F\(fan)md", "F\(fan)Md"] }
    public static func targetKey(_ fan: Int) -> String { "F\(fan)Tg" }
    public static func actualKey(_ fan: Int) -> String { "F\(fan)Ac" }
    public static func minimumKey(_ fan: Int) -> String { "F\(fan)Mn" }
    public static func maximumKey(_ fan: Int) -> String { "F\(fan)Mx" }

    private static func fanKey(_ key: String, suffixes: [String]) -> Bool {
        let c = Array(key.utf8)
        guard c.count == 4, c[0] == UInt8(ascii: "F"), (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(c[1]) else { return false }
        return suffixes.contains(String(decoding: c[2...], as: UTF8.self))
    }

    public static func allowsRead(key: String) -> Bool {
        key == countKey || key == unlockKey || fanKey(key, suffixes: ["md", "Md", "Tg", "Ac", "Mn", "Mx"])
    }

    public static func allowsWrite(key: String, bytes: [UInt8]) -> Bool {
        if key == unlockKey || fanKey(key, suffixes: ["md", "Md"]) { return bytes == [systemMode] || bytes == [manualMode] }
        if fanKey(key, suffixes: ["Tg"]) {
            guard let rpm = FanBytes.float(bytes) else { return false }
            return rpm.isFinite && rpm >= 1 && rpm <= 10_000
        }
        return false
    }
}

/// The only MagSafe light key the helper may touch: ACLC (ui8), written only with 3 (green) or 4 (orange), the two values
/// seen on Mac17,2 / macOS 27.2 (docs/spikes/led-write-probe-plan.md). Reads: ACLC only. Nothing else.
public enum LEDWhitelist {
    public static let key = "ACLC"
    public static let green: UInt8 = 3
    public static let orange: UInt8 = 4

    public static func allowsRead(key: String) -> Bool { key == Self.key }
    public static func allowsWrite(key: String, bytes: [UInt8]) -> Bool { key == Self.key && (bytes == [green] || bytes == [orange]) }
}

/// SMC "flt " values are 4 bytes, little endian (F0Mn reads 00 d0 10 45 = 2317 rpm on Mac17,2).
public enum FanBytes {
    public static func float(_ b: [UInt8]) -> Double? {
        guard b.count == 4 else { return nil }
        return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
    }

    public static func bytes(_ value: Double) -> [UInt8] {
        let u = Float(value).bitPattern
        return [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: u >> UInt32($0)) }
    }
}

/// An SMC key's type as the SMC reports it, e.g. "flt " size 4 or "ui8 " size 1.
public struct SMCKeyType: Equatable, Sendable {
    public var type: String
    public var size: Int
    public init(_ type: String, _ size: Int) { self.type = type; self.size = size }
    public static let float = SMCKeyType("flt ", 4)
    public static let uint8 = SMCKeyType("ui8 ", 1)
}

/// Narrow SMC surface for fans: key types, raw reads and whitelisted raw writes. Fakes implement this in tests.
public protocol FanSMC: Sendable {
    func fanKeyType(_ key: String) throws -> SMCKeyType
    func fanRead(_ key: String) throws -> [UInt8]
    func fanWrite(_ key: String, _ bytes: [UInt8]) throws
}

/// Narrow SMC surface for the MagSafe light (LEDWhitelist only). Fakes implement this in tests.
public protocol LEDSMC: Sendable {
    func ledKeyType(_ key: String) throws -> SMCKeyType
    func ledRead(_ key: String) throws -> [UInt8]
    func ledWrite(_ key: String, _ bytes: [UInt8]) throws
}

public enum SMCError: Error, Equatable {
    case refused, unavailable, io(Int32), smc(UInt8), keyMissing
    /// The key exists but its type or size is not what the write sequence expects: refused, nothing written.
    case typeMismatch

    /// The SMC answers a key-info call for an absent key with result 0x84 (kSMCKeyNotFound).
    public static let keyNotFound: UInt8 = 0x84

    /// What a failed key-info call means: 0x84 is "no such key", anything else stays a generic failure.
    public static func fromKeyInfo(_ e: SMCError) -> SMCError { e == .smc(keyNotFound) ? .keyMissing : e }
}

/// Narrow SMC surface: read and write one byte of the whitelisted key. Fakes implement this in tests.
public protocol SMCWriting: Sendable {
    func read(key: String) throws -> UInt8
    func write(key: String, value: UInt8) throws
}

/// AppleSMC user client, same struct layout and selectors as spikes/smc-probe/main.swift. Needs root to write.
public final class SMCConnection: SMCWriting, FanSMC, LEDSMC, @unchecked Sendable {
    private struct Vers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0; var attrs: UInt8 = 0 }
    private struct KeyData {
        var key: UInt32 = 0; var vers = Vers(); var pLimit = PLimit(); var info = KeyInfo(); var pad: UInt16 = 0
        var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0; var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }
    private static let readInfo: UInt8 = 9, readBytes: UInt8 = 5, writeBytes: UInt8 = 6

    private let lock = NSLock()
    private var conn: io_connect_t = 0

    public init() throws {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { throw SMCError.unavailable }
        defer { IOObjectRelease(svc) }
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { throw SMCError.unavailable }
        _ = IOConnectCallMethod(conn, 0, nil, 0, nil, 0, nil, nil, nil, nil) // user client open
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    private static func name(_ v: UInt32) -> String { String(decoding: (0..<4).map { UInt8((v >> UInt32(24 - 8 * $0)) & 0xff) }, as: UTF8.self) }

    private func call(_ input: inout KeyData) throws {
        var out = KeyData(); var size = MemoryLayout<KeyData>.size
        let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<KeyData>.size, &out, &size)
        guard r == KERN_SUCCESS else { throw SMCError.io(r) }
        guard out.result == 0 else { throw SMCError.smc(out.result) }
        input = out
    }

    private func oneByteInfo(_ key: UInt32) throws {
        var d = KeyData(); d.key = key; d.data8 = Self.readInfo
        do { try call(&d) } catch let e as SMCError { throw SMCError.fromKeyInfo(e) }
        guard d.info.dataSize == 1 else { throw SMCError.keyMissing }
    }

    public func read(key: String) throws -> UInt8 {
        guard key == SMCWhitelist.adapterKey else { throw SMCError.refused }
        lock.lock(); defer { lock.unlock() }
        let k = Self.fourCC(key)
        try oneByteInfo(k)
        var d = KeyData(); d.key = k; d.info.dataSize = 1; d.data8 = Self.readBytes
        try call(&d)
        return UInt8(truncatingIfNeeded: d.bytes.0)
    }

    public func write(key: String, value: UInt8) throws {
        guard SMCWhitelist.allows(key: key, value: value) else { throw SMCError.refused }
        lock.lock(); defer { lock.unlock() }
        let k = Self.fourCC(key)
        try oneByteInfo(k)
        var d = KeyData(); d.key = k; d.info.dataSize = 1; d.data8 = Self.writeBytes
        d.bytes.0 = UInt64(value)
        try call(&d)
    }

    private func keyInfo(_ key: UInt32) throws -> KeyInfo {
        var d = KeyData(); d.key = key; d.data8 = Self.readInfo
        do { try call(&d) } catch let e as SMCError { throw SMCError.fromKeyInfo(e) }
        return d.info
    }

    public func fanKeyType(_ key: String) throws -> SMCKeyType {
        guard FanWhitelist.allowsRead(key: key) else { throw SMCError.refused }
        return try keyType(key)
    }

    public func fanRead(_ key: String) throws -> [UInt8] {
        guard FanWhitelist.allowsRead(key: key) else { throw SMCError.refused }
        return try readRaw(key)
    }

    public func fanWrite(_ key: String, _ bytes: [UInt8]) throws {
        guard FanWhitelist.allowsWrite(key: key, bytes: bytes) else { throw SMCError.refused }
        try writeRaw(key, bytes)
    }

    public func ledKeyType(_ key: String) throws -> SMCKeyType {
        guard LEDWhitelist.allowsRead(key: key) else { throw SMCError.refused }
        return try keyType(key)
    }

    public func ledRead(_ key: String) throws -> [UInt8] {
        guard LEDWhitelist.allowsRead(key: key) else { throw SMCError.refused }
        return try readRaw(key)
    }

    public func ledWrite(_ key: String, _ bytes: [UInt8]) throws {
        guard LEDWhitelist.allowsWrite(key: key, bytes: bytes) else { throw SMCError.refused }
        try writeRaw(key, bytes)
    }

    // Callers check their whitelist first; these never run for a key that was not allowed.
    private func keyType(_ key: String) throws -> SMCKeyType {
        lock.lock(); defer { lock.unlock() }
        let i = try keyInfo(Self.fourCC(key))
        return SMCKeyType(Self.name(i.dataType), Int(i.dataSize))
    }

    private func readRaw(_ key: String) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        let k = Self.fourCC(key)
        let i = try keyInfo(k)
        guard (1...32).contains(i.dataSize) else { throw SMCError.typeMismatch }
        var d = KeyData(); d.key = k; d.info.dataSize = i.dataSize; d.data8 = Self.readBytes
        try call(&d)
        return withUnsafeBytes(of: d.bytes) { Array($0.prefix(Int(i.dataSize))) }
    }

    private func writeRaw(_ key: String, _ bytes: [UInt8]) throws {
        lock.lock(); defer { lock.unlock() }
        let k = Self.fourCC(key)
        guard Int(try keyInfo(k).dataSize) == bytes.count else { throw SMCError.typeMismatch }
        var d = KeyData(); d.key = k; d.info.dataSize = UInt32(bytes.count); d.data8 = Self.writeBytes
        withUnsafeMutableBytes(of: &d.bytes) { raw in for (j, b) in bytes.enumerated() { raw[j] = b } }
        try call(&d)
    }
}
