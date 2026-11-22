import Foundation

/// The timing-sensitive part of the app's XPC client, kept here (no AppKit, no XPC) so it is tested (audit 17).
public enum HelperCall {
    /// Starts `start` and returns the first answer it delivers, or nil once `timeout` passes. `start` gets a `finish`
    /// callback that may be called any number of times from any thread (a reply, an XPC error handler, nothing at all):
    /// only the first call, or the timeout, wins, and the caller is resumed exactly once.
    public static func first<T: Sendable>(timeout: DispatchTimeInterval, queue: DispatchQueue = .global(),
                                          _ start: (@escaping @Sendable (T?) -> Void) -> Void) async -> T? {
        await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
            let once = ResumeOnce(cont)
            queue.asyncAfter(deadline: .now() + timeout) { once.resume(nil) }
            start { once.resume($0) }
        }
    }

    /// Maps a helper command's reply code (a `HelperErrorCode` raw value; nil when the helper did not answer) to what the
    /// tools show. `name` turns a code into its readable name for the error text.
    public static func result(code: Int?, name: (Int) -> String = { "\($0)" }) -> ChargeApplyResult {
        guard let code else { return .failed("The helper did not answer.") }
        switch code {
        case okCode: return .applied
        case sleepingCode: return .sleeping
        default: return .failed("Helper error \(name(code))")
        }
    }

    /// `HelperErrorCode.ok` and `.sleeping` (Core does not import HelperProtocol; a test pins these to the real enum).
    public static let okCode = 0
    public static let sleepingCode = 5
}

/// Resumes a continuation at most once, whoever calls first.
final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T?, Never>?
    init(_ cont: CheckedContinuation<T?, Never>) { self.cont = cont }
    func resume(_ value: T?) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(returning: value)
    }
}
