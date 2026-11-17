// Spike: supervised MagSafe LED write experiment. Needs root. Writes ONLY ACLC, and only 3 (green) or 4 (orange).
// Restores the original value at the end, on error, on Ctrl-C and after 60 seconds at the latest.
// Usage: sudo led-probe read            (no write)
//        sudo led-probe <3|4> [seconds] (write, watch, restore; seconds 10...50, default 35)
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
func aclc() -> String { readBytes("ACLC").map { String(format: "%02x", $0[0]) } ?? "?" }
var original: UInt8?
var restored = false
func restore() {
    guard !restored, let o = original else { return }
    restored = true
    print("restore ACLC=\(o):", write("ACLC", [o])); print("after restore ACLC=\(aclc())")
}
signal(SIGINT) { _ in restore(); exit(1) }
signal(SIGTERM) { _ in restore(); exit(1) }

let args = Array(CommandLine.arguments.dropFirst())
guard let first = args.first, first == "read" || first == "3" || first == "4" else {
    print("usage: sudo led-probe read | sudo led-probe <3|4> [seconds 10...50]"); exit(2)
}
guard let ki = info("ACLC"), ki.dataSize == 1, let now = readBytes("ACLC") else { print("ACLC not readable as one byte; stopping"); exit(1) }
print("ACLC attrs=0x\(String(ki.attrs, radix: 16)) value=\(String(format: "%02x", now[0])) (03 green, 04 orange)")
if first == "read" { exit(0) }
let want = UInt8(first)!
let secs = min(max(Int(args.dropFirst().first ?? "35") ?? 35, 10), 50)
original = now[0]
print("writing ACLC=\(want):", write("ACLC", [want]))
let t0 = Date()
// 60 s hard stop in case anything hangs.
DispatchQueue.global().asyncAfter(deadline: .now() + 60) { restore(); exit(1) }
var marks: [Double] = [0, 0.5, 2, 5, 10, 20, 30, 40, 50].filter { $0 <= Double(secs) }
if marks.last != Double(secs) { marks.append(Double(secs)) }
for m in marks {
    let wait = m - Date().timeIntervalSince(t0)
    if wait > 0 { usleep(UInt32(wait * 1_000_000)) }
    print(String(format: "t+%.1fs ACLC=%@", m, aclc()) + ((m == 5 || m == Double(secs)) ? "   <-- LOOK AT THE LIGHT NOW" : ""))
}
restore()
