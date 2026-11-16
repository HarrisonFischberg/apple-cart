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

public enum SMCError: Error, Equatable {
    case refused, unavailable, io(Int32), smc(UInt8), keyMissing

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
public final class SMCConnection: SMCWriting, @unchecked Sendable {
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
}
