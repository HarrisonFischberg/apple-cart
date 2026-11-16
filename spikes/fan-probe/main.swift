// Spike: supervised fan write experiment. Needs root. Writes ONLY F0md (0/1) and F0Tg (2317...6550 rpm float),
// always restores F0md = 0 at the end, on error, and on Ctrl-C. Max 25 seconds.
// Usage: sudo fan-probe <md-first|tg-first|md-then-tg-delay> [rpm]
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

var conn: io_connect_t = 0
let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard svc != 0, IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { print("cannot open AppleSMC"); exit(1) }
_ = IOConnectCallMethod(conn, 0, nil, 0, nil, 0, nil, nil, nil, nil)
func call(_ i: inout KeyData) -> (kern_return_t, UInt8) {
    var o = KeyData(); var size = MemoryLayout<KeyData>.size
    let r = IOConnectCallStructMethod(conn, 2, &i, MemoryLayout<KeyData>.size, &o, &size)
    i = o; return (r, o.result)
}
func info(_ key: String) -> KeyInfo? {
    var d = KeyData(); d.key = fourCC(key); d.data8 = 9
    let (r, res) = call(&d); return r == KERN_SUCCESS && res == 0 ? d.info : nil
}
func readBytes(_ key: String) -> [UInt8]? {
    guard let ki = info(key) else { return nil }
    var d = KeyData(); d.key = fourCC(key); d.info.dataSize = ki.dataSize; d.data8 = 5
    let (r, res) = call(&d); guard r == KERN_SUCCESS, res == 0 else { return nil }
    return withUnsafeBytes(of: d.bytes) { Array($0.prefix(Int(ki.dataSize))) }
}
func write(_ key: String, _ bytes: [UInt8]) -> String {
    guard let ki = info(key), Int(ki.dataSize) == bytes.count else { return "refused: size/type" }
    var d = KeyData(); d.key = fourCC(key); d.info.dataSize = ki.dataSize; d.data8 = 6
    var b: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    withUnsafeMutableBytes(of: &b) { for (i, v) in bytes.enumerated() { $0[i] = v } }
    d.bytes = b
    let (r, res) = call(&d); return "io=\(String(format: "0x%x", UInt32(bitPattern: r))) smc=\(res)"
}
func float(_ key: String) -> Float? {
    guard let b = readBytes(key), b.count == 4 else { return nil }
    return b.withUnsafeBytes { $0.load(as: Float.self) }
}
func state(_ tag: String) {
    let md = readBytes("F0md").map { String($0[0]) } ?? "?"
    print(String(format: "%@ md=%@ target=%.0f actual=%.0f", tag, md, float("F0Tg") ?? -1, float("F0Ac") ?? -1))
}
func restore() { print("restore F0md=0:", write("F0md", [0])); print("restore F0Tg=0:", write("F0Tg", [0, 0, 0, 0])); state("after restore") }
signal(SIGINT) { _ in restore(); exit(1) }
signal(SIGTERM) { _ in restore(); exit(1) }

let mode = CommandLine.arguments.dropFirst().first ?? ""
let rpm = Float(CommandLine.arguments.dropFirst(2).first ?? "2317") ?? 2317
guard rpm >= 2317, rpm <= 6550, ["md-first", "tg-first", "md-then-tg-delay"].contains(mode) else {
    print("usage: sudo fan-probe <md-first|tg-first|md-then-tg-delay> [rpm 2317...6550]"); exit(2)
}
let tg = withUnsafeBytes(of: rpm) { Array($0) }
state("start")
switch mode {
case "md-first":
    print("F0md=1:", write("F0md", [1])); print("F0Tg:", write("F0Tg", tg))
case "tg-first":
    print("F0Tg:", write("F0Tg", tg)); print("F0md=1:", write("F0md", [1]))
default:
    print("F0md=1:", write("F0md", [1])); usleep(500_000); state("after mode"); print("F0Tg:", write("F0Tg", tg))
}
for s in 1...12 { usleep(2_000_000 / 1); state("t+\(s * 2)s"); if s == 4 { print("F0Tg again:", write("F0Tg", tg)) } }
restore()
