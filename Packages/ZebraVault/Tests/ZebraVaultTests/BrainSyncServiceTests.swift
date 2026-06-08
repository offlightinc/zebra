import XCTest
@testable import ZebraVault

@MainActor
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

    func testGitDnsFailureWithoutReasonTagClassifiesAsOffline() {
        let failure = BrainSyncService.classifyFailure(
            stderr: "fatal: unable to access 'https://github.com/offlightinc/b-brain-offlight.git/': Could not resolve host: github.com",
            stdout: "[zebra-brain-sync] phase: fetch"
        )

        XCTAssertEqual(failure.reason, .offline)
        XCTAssertNil(failure.rawReasonId)
        XCTAssertTrue(failure.detail.contains("Could not resolve host: github.com"))
    }

    func testLegacyUnknownReasonTagFallsBackToGitOutputClassification() {
        let failure = BrainSyncService.classifyFailure(
            stderr: "[REASON:unknown] git fetch failed (see stderr above for cause)",
            stdout: """
            [zebra-brain-sync] phase: fetch
            fatal: unable to access 'https://github.com/offlightinc/b-brain-offlight.git/': Could not resolve host: github.com
            """
        )

        XCTAssertEqual(failure.reason, .offline)
        XCTAssertNil(failure.rawReasonId)
        XCTAssertTrue(failure.detail.contains("Could not resolve host: github.com"))
    }

    func testGitAuthFailureWithoutReasonTagClassifiesAsAuthExpired() {
        let failure = BrainSyncService.classifyFailure(
            stderr: "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
            stdout: "[zebra-brain-sync] phase: fetch"
        )

        XCTAssertEqual(failure.reason, .authExpired)
        XCTAssertNil(failure.rawReasonId)
        XCTAssertTrue(failure.detail.contains("could not read Username"))
    }

    func testGitPermissionFailureWithoutReasonTagClassifiesAsPermissionDenied() {
        let failure = BrainSyncService.classifyFailure(
            stderr: "remote: Permission to offlightinc/b-brain-offlight.git denied to zebra-bot.",
            stdout: "[zebra-brain-sync] phase: push"
        )

        XCTAssertEqual(failure.reason, .permissionDenied)
        XCTAssertNil(failure.rawReasonId)
        XCTAssertTrue(failure.detail.contains("Permission to offlightinc"))
    }

    func testGitRateLimitFailureWithoutReasonTagClassifiesAsRateLimit() {
        let failure = BrainSyncService.classifyFailure(
            stderr: "remote: API rate limit exceeded for user ID 12345.",
            stdout: "[zebra-brain-sync] phase: fetch"
        )

        XCTAssertEqual(failure.reason, .rateLimit)
        XCTAssertNil(failure.rawReasonId)
        XCTAssertTrue(failure.detail.contains("rate limit exceeded"))
    }

    func testGitPushRejectedWithoutReasonTagClassifiesAsPushRejected() {
        let failure = BrainSyncService.classifyFailure(
            stderr: """
            ! [rejected] main -> main (fetch first)
            error: failed to push some refs to 'https://github.com/offlightinc/b-brain-offlight.git'
            """,
            stdout: "[zebra-brain-sync] phase: push"
        )

        XCTAssertEqual(failure.reason, .pushRejected)
        XCTAssertNil(failure.rawReasonId)
        XCTAssertTrue(failure.detail.contains("failed to push some refs"))
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
