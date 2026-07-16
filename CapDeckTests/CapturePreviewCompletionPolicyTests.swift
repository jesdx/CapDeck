@testable import CapDeck
import Foundation
import Testing

struct CapturePreviewCompletionPolicyTests {
    @Test
    func closesOnlyAfterSuccessfulCopy() {
        #expect(CapturePreviewCompletionPolicy.shouldCloseAfterCopy(succeeded: true))
        #expect(!CapturePreviewCompletionPolicy.shouldCloseAfterCopy(succeeded: false))
    }

    @Test
    func closesOnlyAfterSuccessfulSave() {
        let savedURL = URL(fileURLWithPath: "/tmp/CapDeck-test.png")

        #expect(CapturePreviewCompletionPolicy.shouldCloseAfterSave(.saved(savedURL)))
        #expect(!CapturePreviewCompletionPolicy.shouldCloseAfterSave(.discarded))
        #expect(!CapturePreviewCompletionPolicy.shouldCloseAfterSave(.failed("Disk full")))
        #expect(!CapturePreviewCompletionPolicy.shouldCloseAfterSave(.skipped))
    }
}
