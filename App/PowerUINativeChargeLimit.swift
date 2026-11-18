import Core
import Foundation
import ObjectiveC

/// macOS's own charge limit, set through PowerUI's `PowerUISmartChargeClient` (the private client System Settings uses for
/// Battery > Charging > Charge Limit) and read back with `pmset -g battlimit`. Needs no root and no helper.
///
/// The calls match what other open-source limiters use on macOS 27, where the SMC charge-inhibit keys are gone:
/// `initWithClientName:`, `isMCLSupported`, `isMCLCurrentlyEnabled:`, `enableMCL:`, `disableMCL:` and `setMCLLimit:error:`
/// (80...100; it crashes below 80, so the range is checked first). Every selector and its type encoding is checked at
/// run time before it is called; anything missing or unexpected means "not supported" and the app keeps cutting the charger.
final class PowerUINativeChargeLimit: NativeChargeLimit, @unchecked Sendable {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/PowerUI.framework"
    private let queue = DispatchQueue(label: "app.rarecreatures.applecart.native-limit")
    private var client: NSObject?
    private var loaded = false

    func isSupported() async -> Bool {
        await run { self.withClient { c in self.callBool(c, "isMCLSupported") ?? false } ?? false }
    }

    func current() async -> NativeLimitReading? {
        await run { self.withClient { c in self.reading(c) } ?? nil }
    }

    func setLimit(_ percent: Int) async -> NativeLimitReading? {
        guard NativeChargeLimits.range.contains(percent) else { return nil }
        return await run {
            self.withClient { c -> NativeLimitReading? in
                if percent >= 100 {
                    guard self.callError(c, "disableMCL:") == true else { return nil }
                } else {
                    guard self.callSetLimit(c, percent) else { return nil }
                    if self.callError(c, "isMCLCurrentlyEnabled:") != true, self.callError(c, "enableMCL:") != true { return nil }
                }
                // macOS applies it asynchronously; give it a moment before reading back.
                var back = self.reading(c)
                for _ in 0..<5 where back?.confirms(percent) != true {
                    Thread.sleep(forTimeInterval: 0.2)
                    back = self.reading(c)
                }
                // pmset may list the limit only while it is capping the charge. When it lists none but macOS says the limit is
                // on, the accepted write is the best evidence of the percent.
                if var b = back, percent < 100, b.enabled, b.limit == nil { b.limit = percent; return b }
                return back
            } ?? nil
        }
    }

    /// The limit as macOS reports it: on or off from the client (pmset's listing when the client cannot say), the percent
    /// from pmset.
    private func reading(_ c: NSObject) -> NativeLimitReading? {
        let soc = pmsetLimit()
        guard let on = callError(c, "isMCLCurrentlyEnabled:") ?? soc.map({ $0 < 100 }) else { return nil }
        return NativeLimitReading(enabled: on, limit: on ? soc : nil)
    }

    // MARK: Plumbing (all on `queue`)

    private func run<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in queue.async { cont.resume(returning: body()) } }
    }

    private func withClient<T>(_ body: (NSObject) -> T) -> T? {
        if client == nil, !loaded {
            loaded = true
            guard let bundle = Bundle(path: Self.frameworkPath), bundle.load(),
                  let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type else { return nil }
            let initSel = NSSelectorFromString("initWithClientName:")
            guard cls.instancesRespond(to: initSel),
                  // alloc's +1 is consumed by init, which hands back its own +1.
                  let allocated = (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
                  let made = allocated.perform(initSel, with: "Apple Cart" as NSString)?.takeRetainedValue() as? NSObject else { return nil }
            client = made
        }
        return client.map(body)
    }

    /// The argument types of `selector` as the runtime reports them (after self and _cmd), or nil when it does not exist.
    private func argumentTypes(_ obj: NSObject, _ selector: Selector) -> [String]? {
        guard let method = class_getInstanceMethod(type(of: obj), selector) else { return nil }
        let count = method_getNumberOfArguments(method)
        return (2..<count).map { i in
            guard let p = method_copyArgumentType(method, i) else { return "" }
            defer { free(p) }
            return String(cString: p)
        }
    }

    private func returnsBool(_ obj: NSObject, _ selector: Selector) -> Bool {
        guard let method = class_getInstanceMethod(type(of: obj), selector) else { return false }
        let p = method_copyReturnType(method)
        defer { free(p) }
        return ["B", "c", "C"].contains(String(cString: p))
    }

    private func callBool(_ obj: NSObject, _ name: String) -> Bool? {
        let sel = NSSelectorFromString(name)
        guard argumentTypes(obj, sel) == [], returnsBool(obj, sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(obj.method(for: sel), to: Fn.self)(obj, sel)
    }

    /// `- (BOOL)name:(NSError **)error`
    private func callError(_ obj: NSObject, _ name: String) -> Bool? {
        let sel = NSSelectorFromString(name)
        guard let args = argumentTypes(obj, sel), args.count == 1, args[0].hasPrefix("^"), returnsBool(obj, sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
        var error: NSError?
        return unsafeBitCast(obj.method(for: sel), to: Fn.self)(obj, sel, &error)
    }

    /// `- (BOOL)setMCLLimit:(<integer>)limit error:(NSError **)error`. Only integer argument types are accepted: they all travel
    /// in a general register, so passing an Int is correct for any of them; a float or object argument is refused.
    private func callSetLimit(_ obj: NSObject, _ percent: Int) -> Bool {
        let sel = NSSelectorFromString("setMCLLimit:error:")
        guard let args = argumentTypes(obj, sel), args.count == 2, args[1].hasPrefix("^"), returnsBool(obj, sel),
              let first = args[0].last, "cCsSiIlLqQ".contains(first) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, Int, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
        var error: NSError?
        return unsafeBitCast(obj.method(for: sel), to: Fn.self)(obj, sel, percent, &error)
    }

    private func pmsetLimit() -> Int? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "battlimit"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return NativeChargeLimits.manualLimit(fromPmset: String(decoding: data, as: UTF8.self))
    }
}
