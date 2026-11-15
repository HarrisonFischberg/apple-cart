// T002 spike: READ-ONLY SMC key lister. Never writes. Usage: smc-probe [prefix...]
import Foundation
import IOKit

struct Vers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0; var attrs: UInt8 = 0 }
struct KeyData {
    var key: UInt32 = 0; var vers = Vers(); var pLimit = PLimit(); var info = KeyInfo(); var pad: UInt16 = 0
    var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0; var data32: UInt32 = 0
    var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
}

func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
func str(_ v: UInt32) -> String { String(decoding: (0..<4).map { UInt8((v >> UInt32(24 - 8 * $0)) & 0xff) }, as: UTF8.self) }

var conn: io_connect_t = 0
let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard svc != 0, IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { print("cannot open AppleSMC"); exit(1) }

_ = IOConnectCallMethod(conn, 0, nil, 0, nil, 0, nil, nil, nil, nil) // user client open
func call(_ i: inout KeyData) -> (kern_return_t, UInt8) {
    var o = KeyData(); var size = MemoryLayout<KeyData>.size
    let r = IOConnectCallStructMethod(conn, 2, &i, MemoryLayout<KeyData>.size, &o, &size)
    i = o; return (r, o.result)
}
func info(_ key: UInt32) -> (KeyInfo, UInt8)? {
    var d = KeyData(); d.key = key; d.data8 = 9
    let (r, res) = call(&d); return r == KERN_SUCCESS ? (d.info, res) : nil
}
func read(_ key: UInt32, _ ki: KeyInfo) -> (String, UInt8) {
    var d = KeyData(); d.key = key; d.info.dataSize = ki.dataSize; d.data8 = 5
    let (r, res) = call(&d)
    guard r == KERN_SUCCESS else { return ("io error \(r)", res) }
    let b = withUnsafeBytes(of: d.bytes) { Array($0.prefix(Int(min(ki.dataSize, 32)))) }
    return (b.map { String(format: "%02x", $0) }.joined(), res)
}

var kd = KeyData(); kd.key = fourCC("#KEY"); kd.info.dataSize = 4; kd.data8 = 5
_ = call(&kd)
let count = withUnsafeBytes(of: kd.bytes) { $0.load(as: UInt32.self).bigEndian }
print("SMC reports \(count) keys")
let prefixes = CommandLine.arguments.dropFirst().map { $0 }
let want = prefixes.isEmpty ? ["CH", "BC", "BA", "AC", "B0", "TB", "F0", "FN", "MS", "CL"] : prefixes
for i in 0..<count {
    var d = KeyData(); d.data8 = 8; d.data32 = i
    guard call(&d).0 == KERN_SUCCESS else { continue }
    let name = str(d.key)
    guard want.contains(where: { name.hasPrefix($0) }) else { continue }
    guard let (ki, res) = info(d.key) else { print(name, "no info"); continue }
    let (val, rres) = read(d.key, ki)
    print("\(name) type=\(str(ki.dataType)) size=\(ki.dataSize) attrs=0x\(String(ki.attrs, radix: 16)) infoResult=\(res) readResult=\(rres) value=\(val)")
}
if CommandLine.arguments.contains("--debug") {
    print("layout size", MemoryLayout<KeyData>.size, "stride", MemoryLayout<KeyData>.stride)
    var d = KeyData(); d.key = fourCC("#KEY"); d.data8 = 9
    let r = call(&d); print("info call", r, "size", d.info.dataSize, "type", str(d.info.dataType))
    print("#KEY read", read(fourCC("#KEY"), d.info))
}
if CommandLine.arguments.contains("--sizes") {
    for sel: UInt32 in [2, 0, 1, 5] {
        for insz in [76, 80, 84, 88] {
            var buf = [UInt8](repeating: 0, count: 128)
            buf[0] = 0x23; buf[1] = 0x4b; buf[2] = 0x45; buf[3] = 0x59 // not byte-exact layout, just probing error codes
            var o = [UInt8](repeating: 0, count: 128); var os = 80
            let r = IOConnectCallStructMethod(conn, sel, &buf, insz, &o, &os)
            print("sel", sel, "in", insz, "->", String(format: "0x%x", UInt32(bitPattern: r)))
        }
    }
}

// Guarded write: only CHIE (adapter disable), only 00 (adapter on) or 08 (adapter off). Needs root.
if let i = CommandLine.arguments.firstIndex(of: "--set-chie"), i + 1 < CommandLine.arguments.count {
    let v = CommandLine.arguments[i + 1]
    guard v == "00" || v == "08", let byte = UInt8(v, radix: 16) else { print("refused: only 00 or 08"); exit(2) }
    let key = fourCC("CHIE")
    guard let (ki, _) = info(key), ki.dataSize == 1 else { print("CHIE not found"); exit(1) }
    var d = KeyData(); d.key = key; d.info.dataSize = 1; d.data8 = 6
    d.bytes.0 = UInt64(byte)
    let (r, res) = call(&d)
    print("write CHIE=\(v): io=\(String(format: "0x%x", UInt32(bitPattern: r))) smcResult=\(res)")
    print("readback: \(read(key, ki).0)")
    exit(r == KERN_SUCCESS && res == 0 ? 0 : 1)
}
