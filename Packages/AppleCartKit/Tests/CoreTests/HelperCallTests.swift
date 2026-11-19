import Foundation
import Testing
@testable import Core
import HelperProtocol

@Suite struct HelperCallTests {
    @Test func replyBeforeTimeoutIsReturned() async {
        let v: Int? = await HelperCall.first(timeout: .seconds(5)) { finish in finish(7) }
        #expect(v == 7)
    }

    @Test func replyFromAnotherThreadIsReturned() async {
        let v: Int? = await HelperCall.first(timeout: .seconds(5)) { finish in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(20)) { finish(3) }
        }
        #expect(v == 3)
    }

    @Test func noReplyTimesOutWithNil() async {
        let start = Date()
        let v: Int? = await HelperCall.first(timeout: .milliseconds(100)) { _ in }
        #expect(v == nil)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func errorHandlerFirstWinsOverALateReply() async {
        let v: Int? = await HelperCall.first(timeout: .seconds(5)) { finish in
            finish(nil)            // XPC error handler
            finish(1)              // reply arriving afterwards must not resume again (would crash)
        }
        #expect(v == nil)
    }

    @Test func lateReplyAfterTimeoutIsIgnored() async throws {
        let v: Int? = await HelperCall.first(timeout: .milliseconds(50)) { finish in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(300)) { finish(9) }
        }
        #expect(v == nil)
        try await Task.sleep(for: .milliseconds(400)) // the late finish fires here; resuming twice would trap
    }

    @Test func manyConcurrentFinishesResumeOnce() async {
        let v: Int? = await HelperCall.first(timeout: .seconds(5)) { finish in
            DispatchQueue.concurrentPerform(iterations: 64) { finish($0) }
        }
        #expect(v != nil)
    }

    @Test func replyCodesMapToResults() {
        #expect(HelperCall.result(code: HelperErrorCode.ok.rawValue) == .applied)
        #expect(HelperCall.result(code: HelperErrorCode.sleeping.rawValue) == .sleeping)
        #expect(HelperCall.result(code: nil) == .failed("The helper did not answer."))
        #expect(HelperCall.result(code: HelperErrorCode.notApplied.rawValue, name: HelperErrorCode.name(for:))
                == .failed("Helper error notApplied"))
        #expect(HelperCall.result(code: 99) == .failed("Helper error 99"))
        #expect(HelperCall.result(code: 99, name: HelperErrorCode.name(for:)) == .failed("Helper error 99"))
        #expect(HelperErrorCode.smcFailed.name == "smcFailed")
    }

    @Test func coreCodesMatchTheHelperProtocol() {
        #expect(HelperCall.okCode == HelperErrorCode.ok.rawValue)
        #expect(HelperCall.sleepingCode == HelperErrorCode.sleeping.rawValue)
    }
}
