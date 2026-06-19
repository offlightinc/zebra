import XCTest
@testable import ZebraVault

final class BrainSaveStatusServiceTests: XCTestCase {
    func testGBrainActiveLockMapsToSaving() {
        let snapshot = BrainSaveStatusMapper.map(gbrain: .success(report(activeLocks: 1)))

        XCTAssertEqual(snapshot.status, .saving(startedAt: nil))
    }

    func testGBrainActiveQueueMapsToSaving() {
        let snapshot = BrainSaveStatusMapper.map(gbrain: .success(report(active: 2)))

        XCTAssertEqual(snapshot.status, .saving(startedAt: nil))
    }

    func testGBrainFailedQueueMapsToSaveFailed() {
        let snapshot = BrainSaveStatusMapper.map(gbrain: .success(report(failed: 1)))

        guard case .failed(_, let reason) = snapshot.status else {
            return XCTFail("Expected failed status")
        }
        XCTAssertEqual(reason.source, .gbrainStatus)
    }

    func testGBrainDeadQueueMapsToSaveFailed() {
        let snapshot = BrainSaveStatusMapper.map(gbrain: .success(report(dead: 1)))

        guard case .failed(_, let reason) = snapshot.status else {
            return XCTFail("Expected failed status")
        }
        XCTAssertEqual(reason.source, .gbrainStatus)
    }

    func testGBrainTargetedCycleMapsToSaved() {
        let date = Date(timeIntervalSince1970: 1_800)
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: .success(report(cycle: .init(lastFullFinishedAt: nil, lastTargetedFinishedAt: date)))
        )

        XCTAssertEqual(snapshot.status, .saved(at: date))
    }

    func testGBrainFullCycleMapsToSavedWhenTargetedMissing() {
        let date = Date(timeIntervalSince1970: 1_200)
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: .success(report(cycle: .init(lastFullFinishedAt: date, lastTargetedFinishedAt: nil)))
        )

        XCTAssertEqual(snapshot.status, .saved(at: date))
    }

    func testGBrainFailureMapsToSaveFailed() {
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: .failure(BrainSaveFailure(source: .gbrainStatus, message: "invalid json"))
        )

        guard case .failed(_, let reason) = snapshot.status else {
            return XCTFail("Expected failed status")
        }
        XCTAssertEqual(reason.message, "invalid json")
    }

    func testGBrainUnavailableMapsToPendingNotFailure() {
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: .failure(BrainSaveFailure(source: .unavailable, message: "No database URL"))
        )

        XCTAssertEqual(snapshot.status, .unknown)
        XCTAssertEqual(snapshot.runtime, nil)
        XCTAssertEqual(snapshot.detail, "No database URL")
    }

    func testGBrainReportClassifiesMissingDatabaseAsUnavailable() async {
        let result = await BrainSaveStatusCollector.gbrainReport(
            runner: StubBrainSaveCommandRunner(result: .init(exitCode: 1, stdout: "", stderr: "No database URL"))
        )

        guard case .failure(let failure) = result else {
            return XCTFail("Expected unavailable failure")
        }
        XCTAssertEqual(failure.source, .unavailable)
        XCTAssertEqual(failure.message, "No database URL")
    }

    func testOpenClawRunningMapsToSavingWithoutGBrainSnapshot() {
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: nil,
            runtime: .openClaw(status: "running", finishedAt: nil, message: nil)
        )

        XCTAssertEqual(snapshot.status, .saving(startedAt: nil))
        XCTAssertEqual(snapshot.runtime, .openClaw)
    }

    func testOpenClawErrorMapsToSaveFailed() {
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: nil,
            runtime: .openClaw(status: "error", finishedAt: nil, message: "provider failed")
        )

        guard case .failed(_, let reason) = snapshot.status else {
            return XCTFail("Expected failed status")
        }
        XCTAssertEqual(reason.source, .openClawCron)
        XCTAssertEqual(reason.message, "provider failed")
    }

    func testOpenClawErrorOlderThanGBrainSavedDoesNotOverrideSaved() {
        let savedAt = Date(timeIntervalSince1970: 2_000)
        let failedAt = Date(timeIntervalSince1970: 1_000)
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: .success(report(cycle: .init(lastFullFinishedAt: nil, lastTargetedFinishedAt: savedAt))),
            runtime: .openClaw(status: "error", finishedAt: failedAt, message: "old failure")
        )

        XCTAssertEqual(snapshot.status, .saved(at: savedAt))
        XCTAssertEqual(snapshot.runtime, .gbrain)
    }

    func testOpenClawErrorNewerThanGBrainSavedOverridesSaved() {
        let savedAt = Date(timeIntervalSince1970: 1_000)
        let failedAt = Date(timeIntervalSince1970: 2_000)
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: .success(report(cycle: .init(lastFullFinishedAt: nil, lastTargetedFinishedAt: savedAt))),
            runtime: .openClaw(status: "error", finishedAt: failedAt, message: "new failure")
        )

        guard case .failed(let at, let reason) = snapshot.status else {
            return XCTFail("Expected failed status")
        }
        XCTAssertEqual(at, failedAt)
        XCTAssertEqual(reason.source, .openClawCron)
        XCTAssertEqual(reason.message, "new failure")
    }

    func testOpenClawSkippedMapsToSaveFailed() {
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: nil,
            runtime: .openClaw(status: "skipped", finishedAt: nil, message: "preflight failed")
        )

        guard case .failed(_, let reason) = snapshot.status else {
            return XCTFail("Expected failed status")
        }
        XCTAssertEqual(reason.source, .openClawCron)
        XCTAssertEqual(reason.message, "preflight failed")
    }

    func testOpenClawOkFallsThroughToGBrainSnapshot() {
        let date = Date(timeIntervalSince1970: 900)
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: .success(report(cycle: .init(lastFullFinishedAt: nil, lastTargetedFinishedAt: date))),
            runtime: .openClaw(status: "ok", finishedAt: nil, message: nil)
        )

        XCTAssertEqual(snapshot.status, .saved(at: date))
        XCTAssertEqual(snapshot.runtime, .gbrain)
    }

    func testHermesErrorMapsToSaveFailed() {
        let date = Date(timeIntervalSince1970: 500)
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: nil,
            runtime: .hermes(lastStatus: "error", lastRunAt: date, message: "agent failed")
        )

        guard case .failed(let at, let reason) = snapshot.status else {
            return XCTFail("Expected failed status")
        }
        XCTAssertEqual(at, date)
        XCTAssertEqual(reason.source, .hermesCron)
        XCTAssertEqual(reason.message, "agent failed")
    }

    func testHermesErrorOlderThanGBrainSavedDoesNotOverrideSaved() {
        let savedAt = Date(timeIntervalSince1970: 2_000)
        let failedAt = Date(timeIntervalSince1970: 1_000)
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: .success(report(cycle: .init(lastFullFinishedAt: nil, lastTargetedFinishedAt: savedAt))),
            runtime: .hermes(lastStatus: "error", lastRunAt: failedAt, message: "old agent failure")
        )

        XCTAssertEqual(snapshot.status, .saved(at: savedAt))
        XCTAssertEqual(snapshot.runtime, .gbrain)
    }

    func testHermesOkFallsThroughToGBrainSnapshot() {
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: .success(report(active: 1)),
            runtime: .hermes(lastStatus: "ok", lastRunAt: Date(timeIntervalSince1970: 1), message: nil)
        )

        XCTAssertEqual(snapshot.status, .saving(startedAt: nil))
        XCTAssertEqual(snapshot.runtime, .gbrain)
    }

    func testHermesScheduledWithoutGBrainSnapshotDoesNotMapToSaving() {
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: nil,
            runtime: .hermes(lastStatus: nil, lastRunAt: nil, message: nil)
        )

        XCTAssertEqual(snapshot.status, .unknown)
    }

    func testThinClientLocalOnlyQueueIsIgnoredByGBrainParser() {
        let parsed = BrainSaveStatusCollector.parseGBrainReport([
            "queue": ["local_only_remote": true],
            "locks": ["local_only_remote": true],
            "cycle": [:],
        ])

        XCTAssertNil(parsed.queue)
        XCTAssertEqual(parsed.activeLockCount, 0)
    }

    func testOpenClawRuntimeParserFindsGBrainJob() {
        let parsed = BrainSaveStatusCollector.parseOpenClawRuntime([
            "jobs": [
                ["name": "other", "status": "running"],
                ["name": "gbrain save", "status": "running"],
            ],
        ])

        XCTAssertEqual(parsed, .openClaw(status: "running", finishedAt: nil, message: nil))
    }

    func testOpenClawRuntimeParserPrefersNewestCompletedJobOverOlderError() {
        let parsed = BrainSaveStatusCollector.parseOpenClawRuntime([
            "jobs": [
                [
                    "name": "gbrain save",
                    "status": "error",
                    "finishedAt": "1970-01-01T00:00:01Z",
                    "error": "old failure",
                ],
                [
                    "name": "gbrain save",
                    "status": "ok",
                    "finishedAt": "1970-01-01T00:00:02Z",
                ],
            ],
        ])

        XCTAssertEqual(parsed, .openClaw(status: "ok", finishedAt: Date(timeIntervalSince1970: 2), message: nil))
    }

    func testOpenClawRuntimeParserPrefersRunningJobOverNewerCompletedJob() {
        let parsed = BrainSaveStatusCollector.parseOpenClawRuntime([
            "jobs": [
                [
                    "name": "gbrain save",
                    "status": "ok",
                    "finishedAt": "1970-01-01T00:00:02Z",
                ],
                [
                    "name": "gbrain save",
                    "status": "running",
                    "runningAtMs": 1_000,
                ],
            ],
        ])

        XCTAssertEqual(parsed, .openClaw(status: "running", finishedAt: nil, message: nil))
    }

    func testHermesRuntimeParserUsesLastStatus() {
        let parsed = BrainSaveStatusCollector.parseHermesRuntime([
            "jobs": [
                [
                    "name": "gbrain save",
                    "last_status": "error",
                    "last_error": "boom",
                    "last_run_at": "1970-01-01T00:00:01Z",
                ],
            ],
        ])

        XCTAssertEqual(
            parsed,
            .hermes(lastStatus: "error", lastRunAt: Date(timeIntervalSince1970: 1), message: "boom")
        )
    }

    private func report(
        activeLocks: Int = 0,
        active: Int = 0,
        failed: Int = 0,
        dead: Int = 0,
        cycle: BrainSaveGBrainReport.Cycle? = nil,
        warningCount: Int = 0
    ) -> BrainSaveGBrainReport {
        BrainSaveGBrainReport(
            activeLockCount: activeLocks,
            queue: .init(active: active, failed: failed, dead: dead),
            cycle: cycle,
            warningCount: warningCount
        )
    }
}

private struct StubBrainSaveCommandRunner: BrainSaveCommandRunning {
    let result: BrainSaveCommandResult

    func run(_ command: String, _ arguments: [String]) async -> BrainSaveCommandResult {
        result
    }
}
