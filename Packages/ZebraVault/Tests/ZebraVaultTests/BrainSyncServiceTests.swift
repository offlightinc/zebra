import XCTest
@testable import ZebraVault

final class BrainSyncServiceTests: XCTestCase {
    func testAlreadyRunningReasonTagIsNotClassifiedAsSuccess() {
        let (reason, detail) = BrainSyncService.classifyFailure(
            stderr: "[REASON:alreadyRunning] brain sync already running: lock=/tmp/zebra-brain-sync.1.lock age=42s",
            stdout: ""
        )

        XCTAssertEqual(reason, .alreadyRunning)
        XCTAssertTrue(detail.contains("brain sync already running"))
    }

    func testAlreadyRunningFallbackTextClassifiesAsAlreadyRunning() {
        let (reason, detail) = BrainSyncService.classifyFailure(
            stderr: "brain sync lock exists without owner metadata: lock=/tmp/zebra-brain-sync.1.lock",
            stdout: ""
        )

        XCTAssertEqual(reason, .alreadyRunning)
        XCTAssertTrue(detail.contains("brain sync lock exists"))
    }
}
