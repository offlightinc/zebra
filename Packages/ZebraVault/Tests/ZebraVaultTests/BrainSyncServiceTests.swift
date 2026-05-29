import XCTest
@testable import ZebraVault

final class BrainSyncServiceTests: XCTestCase {
    func testAlreadyRunningReasonTagIsNotClassifiedAsSuccess() {
        let failure = BrainSyncService.classifyFailure(
            stderr: "[REASON:alreadyRunning] brain sync already running: lock=/tmp/zebra-brain-sync.1.lock age=42s",
            stdout: ""
        )

        XCTAssertEqual(failure.reason, .alreadyRunning)
        XCTAssertNil(failure.rawReasonId)
        XCTAssertTrue(failure.detail.contains("brain sync already running"))
    }

    func testAlreadyRunningFallbackTextClassifiesAsAlreadyRunning() {
        let failure = BrainSyncService.classifyFailure(
            stderr: "brain sync lock exists without owner metadata: lock=/tmp/zebra-brain-sync.1.lock",
            stdout: ""
        )

        XCTAssertEqual(failure.reason, .alreadyRunning)
        XCTAssertNil(failure.rawReasonId)
        XCTAssertTrue(failure.detail.contains("brain sync lock exists"))
    }

    func testUnknownReasonTagPreservesRawReasonId() {
        let failure = BrainSyncService.classifyFailure(
            stderr: "[REASON:credentialHelperBroken] git credential helper failed",
            stdout: ""
        )

        XCTAssertEqual(failure.reason, .unknown)
        XCTAssertEqual(failure.rawReasonId, "credentialHelperBroken")
        XCTAssertTrue(failure.detail.contains("git credential helper failed"))
    }
}
