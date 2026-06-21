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

    func testOpenClawOkMapsToSavedFromRuntime() {
        let finishedAt = Date(timeIntervalSince1970: 1_100)
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: .success(report(cycle: .init(lastFullFinishedAt: nil, lastTargetedFinishedAt: Date(timeIntervalSince1970: 900)))),
            runtime: .openClaw(status: "ok", finishedAt: finishedAt, message: nil)
        )

        XCTAssertEqual(snapshot.status, .saved(at: finishedAt))
        XCTAssertEqual(snapshot.runtime, .openClaw)
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

    func testHermesOkMapsToSavedWithoutInferringSaving() {
        let snapshot = BrainSaveStatusMapper.map(
            gbrain: nil,
            runtime: .hermes(lastStatus: "ok", lastRunAt: Date(timeIntervalSince1970: 1), message: nil)
        )

        XCTAssertEqual(snapshot.status, .saved(at: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(snapshot.runtime, .hermes)
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

    func testGBrainParserUsesOnlySelectedVaultSourceRow() {
        let selected = "/tmp/zebra-selected"
        let otherDate = "1970-01-01T00:00:10Z"
        let selectedDate = "1970-01-01T00:00:20Z"
        let parsed = BrainSaveStatusCollector.parseGBrainReport(
            [
                "cycle": ["last_targeted": ["finished_at": otherDate]],
                "sync": [
                    "sources": [
                        ["local_path": "/tmp/other", "last_sync_at": otherDate],
                        ["local_path": selected, "last_sync_at": selectedDate],
                    ],
                ],
            ],
            selectedVaultPath: selected
        )

        XCTAssertTrue(parsed.selectedSourceMatched)
        XCTAssertEqual(parsed.cycle?.lastTargetedFinishedAt, Date(timeIntervalSince1970: 20))
    }

    func testGBrainParserDoesNotUseGlobalCycleWhenSelectedVaultSourceMissing() {
        let parsed = BrainSaveStatusCollector.parseGBrainReport(
            [
                "cycle": ["last_targeted": ["finished_at": "1970-01-01T00:00:10Z"]],
                "sync": ["sources": [["local_path": "/tmp/other", "last_sync_at": "1970-01-01T00:00:10Z"]]],
            ],
            selectedVaultPath: "/tmp/selected"
        )

        XCTAssertFalse(parsed.selectedSourceMatched)
        XCTAssertNil(parsed.cycle?.lastTargetedFinishedAt)
        XCTAssertEqual(BrainSaveStatusMapper.map(gbrain: .success(parsed)).status, .unknown)
    }

    func testOpenClawRuntimeParserFindsGBrainLiveSyncJob() {
        let parsed = BrainSaveStatusCollector.parseOpenClawRuntime([
            "jobs": [
                ["name": "other", "status": "running"],
                [
                    "name": "GBrain live sync",
                    "status": "running",
                    "message": "Run: gbrain sync --repo /tmp/selected --yes && gbrain embed --stale",
                ],
            ],
        ])

        XCTAssertEqual(parsed, .openClaw(status: "running", finishedAt: nil, message: nil))
    }

    func testOpenClawRuntimeParserFindsLiveSyncJobInPayloadMessage() {
        let parsed = BrainSaveStatusCollector.parseOpenClawRuntime(
            [
                "jobs": [
                    [
                        "name": "GBrain live sync",
                        "status": "idle",
                        "payload": [
                            "kind": "agentTurn",
                            "message": "Run: gbrain sync --repo '/tmp/selected' --yes && gbrain embed --stale, then run: gbrain status.",
                        ],
                    ],
                ],
            ],
            selectedVaultPath: "/tmp/selected"
        )

        XCTAssertEqual(parsed, .openClaw(status: "idle", finishedAt: nil, message: nil))
    }

    func testOpenClawRuntimeParserRequiresSelectedVaultPathWhenProvided() {
        let parsed = BrainSaveStatusCollector.parseOpenClawRuntime(
            [
                "jobs": [
                    [
                        "name": "GBrain live sync",
                        "status": "running",
                        "workdir": "/tmp/other",
                        "message": "Run: gbrain sync --repo /tmp/other --yes && gbrain embed --stale",
                    ],
                    [
                        "name": "GBrain live sync",
                        "status": "ok",
                        "workdir": "/tmp/selected",
                        "message": "Run: gbrain sync --repo /tmp/selected --yes && gbrain embed --stale",
                        "finishedAt": "1970-01-01T00:00:02Z",
                    ],
                ],
            ],
            selectedVaultPath: "/tmp/selected"
        )

        XCTAssertEqual(parsed, .openClaw(status: "ok", finishedAt: Date(timeIntervalSince1970: 2), message: nil))
    }

    func testOpenClawRuntimeParserIgnoresGBrainJobWithoutSelectedVaultPath() {
        let parsed = BrainSaveStatusCollector.parseOpenClawRuntime(
            [
                "jobs": [
                    [
                        "name": "GBrain live sync",
                        "status": "running",
                        "workdir": "/tmp/other",
                        "message": "Run: gbrain sync --repo /tmp/other --yes && gbrain embed --stale",
                    ],
                ],
            ],
            selectedVaultPath: "/tmp/selected"
        )

        XCTAssertEqual(parsed, .none)
    }

    func testOpenClawRuntimeParserPrefersNewestCompletedJobOverOlderError() {
        let parsed = BrainSaveStatusCollector.parseOpenClawRuntime([
            "jobs": [
                [
                    "name": "GBrain live sync",
                    "status": "error",
                    "message": "Run: gbrain sync --repo /tmp/selected --yes && gbrain embed --stale",
                    "finishedAt": "1970-01-01T00:00:01Z",
                    "error": "old failure",
                ],
                [
                    "name": "GBrain live sync",
                    "status": "ok",
                    "message": "Run: gbrain sync --repo /tmp/selected --yes && gbrain embed --stale",
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
                    "name": "GBrain live sync",
                    "status": "ok",
                    "message": "Run: gbrain sync --repo /tmp/selected --yes && gbrain embed --stale",
                    "finishedAt": "1970-01-01T00:00:02Z",
                ],
                [
                    "name": "GBrain live sync",
                    "status": "running",
                    "message": "Run: gbrain sync --repo /tmp/selected --yes && gbrain embed --stale",
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
                    "name": "GBrain live sync",
                    "prompt": "Run: gbrain sync --repo /tmp/selected --yes && gbrain embed --stale",
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

    func testHermesRuntimeParserRequiresSelectedVaultPathWhenProvided() {
        let parsed = BrainSaveStatusCollector.parseHermesRuntime(
            [
                "jobs": [
                    [
                        "name": "GBrain live sync",
                        "workdir": "/tmp/other",
                        "prompt": "Run: gbrain sync --repo /tmp/other --yes && gbrain embed --stale",
                        "last_status": "error",
                        "last_run_at": "1970-01-01T00:00:01Z",
                    ],
                    [
                        "name": "GBrain live sync",
                        "workdir": "/tmp/selected",
                        "prompt": "Run: gbrain sync --repo /tmp/selected --yes && gbrain embed --stale",
                        "last_status": "ok",
                        "last_run_at": "1970-01-01T00:00:02Z",
                    ],
                ],
            ],
            selectedVaultPath: "/tmp/selected"
        )

        XCTAssertEqual(
            parsed,
            .hermes(lastStatus: "ok", lastRunAt: Date(timeIntervalSince1970: 2), message: nil)
        )
    }

    func testOpenClawRuntimeParserIgnoresNonLiveSyncGBrainJobsForSaveStatus() {
        let parsed = BrainSaveStatusCollector.parseOpenClawRuntime(
            [
                "jobs": [
                    [
                        "name": "GBrain dream cycle",
                        "status": "running",
                        "message": "Run: gbrain dream --dir /tmp/selected",
                    ],
                    [
                        "name": "GBrain weekly health",
                        "status": "error",
                        "message": "Run: gbrain doctor --json && gbrain embed --stale",
                        "workdir": "/tmp/selected",
                    ],
                ],
            ],
            selectedVaultPath: "/tmp/selected"
        )

        XCTAssertEqual(parsed, .none)
    }

    func testCollectMapsOpenClawProviderFailureToPendingFallback() async {
        let snapshot = await BrainSaveStatusCollector.collect(
            runner: StubBrainSaveCommandRunner(results: [
                "openclaw": .init(exitCode: 1, stdout: "", stderr: "GatewayCredentialsRequiredError"),
                "gbrain": .init(exitCode: 0, stdout: #"{"sync":{"sources":[]}}"#, stderr: ""),
            ]),
            selectedVaultPath: "/tmp/selected",
            runtimeSelection: .openClaw
        )

        XCTAssertEqual(snapshot.status, .unknown)
        XCTAssertEqual(snapshot.detail, "GatewayCredentialsRequiredError")
    }

    func testCollectMapsMissingSelectedVaultCronJobToSaveFailed() async {
        let gbrainJSON = #"{"sync":{"sources":[{"local_path":"/tmp/selected"}]}}"#
        let openClawJSON = #"{"jobs":[{"name":"GBrain live sync","status":"ok","workdir":"/tmp/other","message":"Run: gbrain sync --repo /tmp/other --yes && gbrain embed --stale"}]}"#
        let snapshot = await BrainSaveStatusCollector.collect(
            runner: StubBrainSaveCommandRunner(results: [
                "openclaw": .init(exitCode: 0, stdout: openClawJSON, stderr: ""),
                "gbrain": .init(exitCode: 0, stdout: gbrainJSON, stderr: ""),
            ]),
            selectedVaultPath: "/tmp/selected",
            runtimeSelection: .openClaw
        )

        guard case .failed(_, let reason) = snapshot.status else {
            return XCTFail("Expected failed status")
        }
        XCTAssertEqual(reason.source, .missingCronJob)
        XCTAssertTrue(reason.message.contains("No GBrain live sync cron job"))
    }

    func testCollectMapsOpenClawGatewayDownToSaveFailedWhenLiveSyncJobExists() async {
        let gbrainJSON = #"{"sync":{"sources":[{"local_path":"/tmp/selected"}]}}"#
        let openClawJSON = #"{"jobs":[{"name":"GBrain live sync","status":"ok","workdir":"/tmp/selected","message":"Run: gbrain sync --repo /tmp/selected --yes && gbrain embed --stale","finishedAt":"1970-01-01T00:00:02Z"}]}"#
        let snapshot = await BrainSaveStatusCollector.collect(
            runner: StubBrainSaveCommandRunner(results: [
                StubBrainSaveCommandRunner.key("openclaw", ["cron", "list", "--json"]): .init(exitCode: 0, stdout: openClawJSON, stderr: ""),
                StubBrainSaveCommandRunner.key("openclaw", ["gateway", "status", "--json", "--require-rpc", "--timeout", "5000"]): .init(exitCode: 1, stdout: "", stderr: "gateway rpc unavailable"),
                "gbrain": .init(exitCode: 0, stdout: gbrainJSON, stderr: ""),
            ]),
            selectedVaultPath: "/tmp/selected",
            runtimeSelection: .openClaw
        )

        guard case .failed(_, let reason) = snapshot.status else {
            return XCTFail("Expected gateway failure")
        }
        XCTAssertEqual(reason.source, .openClawGateway)
        XCTAssertEqual(reason.message, "gateway rpc unavailable")
        XCTAssertEqual(snapshot.runtime, .openClaw)
    }

    func testCollectMapsOpenClawLiveSyncJobToSavedWhenGatewayIsRunning() async {
        let gbrainJSON = #"{"sync":{"sources":[{"local_path":"/tmp/selected"}]}}"#
        let openClawJSON = #"{"jobs":[{"name":"GBrain live sync","status":"ok","workdir":"/tmp/selected","message":"Run: gbrain sync --repo /tmp/selected --yes && gbrain embed --stale","finishedAt":"1970-01-01T00:00:02Z"}]}"#
        let snapshot = await BrainSaveStatusCollector.collect(
            runner: StubBrainSaveCommandRunner(results: [
                StubBrainSaveCommandRunner.key("openclaw", ["cron", "list", "--json"]): .init(exitCode: 0, stdout: openClawJSON, stderr: ""),
                StubBrainSaveCommandRunner.key("openclaw", ["gateway", "status", "--json", "--require-rpc", "--timeout", "5000"]): .init(exitCode: 0, stdout: #"{"running":true}"#, stderr: ""),
                "gbrain": .init(exitCode: 0, stdout: gbrainJSON, stderr: ""),
            ]),
            selectedVaultPath: "/tmp/selected",
            runtimeSelection: .openClaw
        )

        XCTAssertEqual(snapshot.status, .saved(at: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(snapshot.runtime, .openClaw)
    }

    func testCollectDoesNotReportMissingOpenClawCronWhenLiveSyncJobUsesPayloadMessage() async {
        let gbrainJSON = #"{"sync":{"sources":[{"local_path":"/tmp/selected"}]}}"#
        let openClawJSON = #"{"jobs":[{"name":"GBrain live sync","status":"ok","payload":{"kind":"agentTurn","message":"Run: gbrain sync --repo '/tmp/selected' --yes && gbrain embed --stale, then run: gbrain status."},"finishedAt":"1970-01-01T00:00:02Z"}]}"#
        let snapshot = await BrainSaveStatusCollector.collect(
            runner: StubBrainSaveCommandRunner(results: [
                StubBrainSaveCommandRunner.key("openclaw", ["cron", "list", "--json"]): .init(exitCode: 0, stdout: openClawJSON, stderr: ""),
                StubBrainSaveCommandRunner.key("openclaw", ["gateway", "status", "--json", "--require-rpc", "--timeout", "5000"]): .init(exitCode: 0, stdout: #"{"running":true}"#, stderr: ""),
                "gbrain": .init(exitCode: 0, stdout: gbrainJSON, stderr: ""),
            ]),
            selectedVaultPath: "/tmp/selected",
            runtimeSelection: .openClaw
        )

        XCTAssertEqual(snapshot.status, .saved(at: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(snapshot.runtime, .openClaw)
    }

    func testCollectMapsHermesGatewayDownToSaveFailedWhenLiveSyncJobExists() async throws {
        let jobsPath = try writeHermesJobsJSON(
            #"{"jobs":[{"name":"GBrain live sync","workdir":"/tmp/selected","prompt":"Run: gbrain sync --repo /tmp/selected --yes && gbrain embed --stale","last_status":null,"last_run_at":null}]}"#
        )
        let executablePath = (jobsPath.deletingLastPathComponent().path as NSString).appendingPathComponent("hermes")
        let pythonPath = (jobsPath.deletingLastPathComponent().path as NSString).appendingPathComponent("python")
        let gbrainJSON = #"{"sync":{"sources":[{"local_path":"/tmp/selected"}]}}"#
        let snapshot = await BrainSaveStatusCollector.collect(
            runner: StubBrainSaveCommandRunner(results: [
                pythonPath: .init(exitCode: 0, stdout: #"{"running":false,"pid":null}"#, stderr: ""),
                "gbrain": .init(exitCode: 0, stdout: gbrainJSON, stderr: ""),
            ]),
            selectedVaultPath: "/tmp/selected",
            runtimeSelection: .hermes,
            runtimeExecutablePath: executablePath,
            hermesCronJobsPath: jobsPath.path
        )

        guard case .failed(_, let reason) = snapshot.status else {
            return XCTFail("Expected Hermes gateway failure")
        }
        XCTAssertEqual(reason.source, .hermesGateway)
        XCTAssertEqual(reason.message, "Hermes gateway is not running.")
        XCTAssertEqual(snapshot.runtime, .hermes)
    }

    func testCollectMapsHermesLiveSyncJobThroughExistingStatusWhenGatewayIsRunning() async throws {
        let jobsPath = try writeHermesJobsJSON(
            #"{"jobs":[{"name":"GBrain live sync","workdir":"/tmp/selected","prompt":"Run: gbrain sync --repo /tmp/selected --yes && gbrain embed --stale","last_status":"ok","last_run_at":"1970-01-01T00:00:02Z"}]}"#
        )
        let executablePath = (jobsPath.deletingLastPathComponent().path as NSString).appendingPathComponent("hermes")
        let pythonPath = (jobsPath.deletingLastPathComponent().path as NSString).appendingPathComponent("python")
        let gbrainJSON = #"{"sync":{"sources":[{"local_path":"/tmp/selected"}]}}"#
        let snapshot = await BrainSaveStatusCollector.collect(
            runner: StubBrainSaveCommandRunner(results: [
                pythonPath: .init(exitCode: 0, stdout: #"{"running":true,"pid":123}"#, stderr: ""),
                "gbrain": .init(exitCode: 0, stdout: gbrainJSON, stderr: ""),
            ]),
            selectedVaultPath: "/tmp/selected",
            runtimeSelection: .hermes,
            runtimeExecutablePath: executablePath,
            hermesCronJobsPath: jobsPath.path
        )

        XCTAssertEqual(snapshot.status, .saved(at: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(snapshot.runtime, .hermes)
    }

    func testCollectResolvesHermesExecutableSymlinkBeforeGatewayProbe() async throws {
        let jobsPath = try writeHermesJobsJSON(
            #"{"jobs":[{"name":"GBrain live sync","workdir":"/tmp/selected","prompt":"Run: gbrain sync --repo /tmp/selected --yes && gbrain embed --stale","last_status":"ok","last_run_at":"1970-01-01T00:00:02Z"}]}"#
        )
        let realBin = jobsPath.deletingLastPathComponent()
        let realExecutable = realBin.appendingPathComponent("hermes")
        try Data().write(to: realExecutable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: realExecutable.path)
        let shimBin = realBin.appendingPathComponent("shim", isDirectory: true)
        try FileManager.default.createDirectory(at: shimBin, withIntermediateDirectories: true)
        let shimExecutable = shimBin.appendingPathComponent("hermes")
        try FileManager.default.createSymbolicLink(at: shimExecutable, withDestinationURL: realExecutable)
        let pythonPath = realBin.appendingPathComponent("python").path
        let gbrainJSON = #"{"sync":{"sources":[{"local_path":"/tmp/selected"}]}}"#
        let snapshot = await BrainSaveStatusCollector.collect(
            runner: StubBrainSaveCommandRunner(results: [
                pythonPath: .init(exitCode: 0, stdout: #"{"running":true,"pid":123}"#, stderr: ""),
                "gbrain": .init(exitCode: 0, stdout: gbrainJSON, stderr: ""),
            ]),
            selectedVaultPath: "/tmp/selected",
            runtimeSelection: .hermes,
            runtimeExecutablePath: shimExecutable.path,
            hermesCronJobsPath: jobsPath.path
        )

        XCTAssertEqual(snapshot.status, .saved(at: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(snapshot.runtime, .hermes)
    }

    @MainActor
    func testServiceRefreshUsesLatestSelectedVaultPath() async {
        let gbrainJSON = #"{"sync":{"sources":[{"local_path":"/tmp/vault-a"},{"local_path":"/tmp/vault-b"}]}}"#
        let openClawJSON = #"{"jobs":[{"name":"GBrain live sync","status":"ok","workdir":"/tmp/vault-a","message":"Run: gbrain sync --repo /tmp/vault-a --yes && gbrain embed --stale","finishedAt":"1970-01-01T00:00:02Z"}]}"#
        let service = BrainSaveStatusService(
            runner: StubBrainSaveCommandRunner(results: [
                "openclaw": .init(exitCode: 0, stdout: openClawJSON, stderr: ""),
                "gbrain": .init(exitCode: 0, stdout: gbrainJSON, stderr: ""),
            ]),
            runtimeSelectionProvider: { .openClaw }
        )

        service.refresh(selectedVaultPath: "/tmp/vault-a")
        await waitForRefresh(service)
        XCTAssertEqual(service.snapshot.status, .saved(at: Date(timeIntervalSince1970: 2)))

        service.refresh(selectedVaultPath: "/tmp/vault-b")
        await waitForRefresh(service)
        guard case .failed(_, let reason) = service.snapshot.status else {
            return XCTFail("Expected missing cron failure after switching vault")
        }
        XCTAssertEqual(reason.source, .missingCronJob)
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

    private func writeHermesJobsJSON(_ json: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrainSaveStatusServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let python = directory.appendingPathComponent("python")
        try Data().write(to: python)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        let jobs = directory.appendingPathComponent("jobs.json")
        try XCTUnwrap(json.data(using: .utf8)).write(to: jobs)
        return jobs
    }

    @MainActor
    private func waitForRefresh(_ service: BrainSaveStatusService) async {
        for _ in 0..<100 where service.isRefreshing {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private struct StubBrainSaveCommandRunner: BrainSaveCommandRunning {
    let results: [String: BrainSaveCommandResult]

    init(result: BrainSaveCommandResult) {
        self.results = ["default": result]
    }

    init(results: [String: BrainSaveCommandResult]) {
        self.results = results
    }

    static func key(_ command: String, _ arguments: [String]) -> String {
        ([command] + arguments).joined(separator: "\u{1f}")
    }

    func run(_ command: String, _ arguments: [String]) async -> BrainSaveCommandResult {
        results[Self.key(command, arguments)]
            ?? results[command]
            ?? results["default"]
            ?? BrainSaveCommandResult(exitCode: 127, stdout: "", stderr: "missing stub")
    }
}
