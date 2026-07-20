import XCTest
@testable import ZebraVault

@MainActor
final class ZebraRemindersEventKitTests: XCTestCase {
    func testHelperRunsEventKitPermissionSmokeScopeIngestReadbackWithoutRemindctl() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ZebraRemindersHelperTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let brain = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: brain, withIntermediateDirectories: true)
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root.appendingPathComponent("gbrain-state.json")
        let adapterStateURL = root.appendingPathComponent("adapter-state.json")
        try writeCompletedGBrainState(to: gbrainStateURL, vaultPath: brain.path)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: brain.path)
        )
        let requestDirectory = root.appendingPathComponent("reminders-eventkit", isDirectory: true)
        let fileStore = ZebraRemindersRequestFileStore(directoryURL: requestDirectory)
        let eventStore = FakeRemindersEventStore(
            authorizationStatus: .notDetermined,
            requestedAuthorizationStatus: .authorized,
            lists: [ZebraRemindersListSnapshot(id: "work", title: "Work")],
            reminders: [
                ZebraReminderSnapshot(
                    id: "r1",
                    title: "Investor update",
                    notes: "Send the revised deck",
                    listID: "work",
                    listTitle: "Work",
                    isCompleted: false,
                    priority: 1,
                    dueDate: nil
                )
            ]
        )
        let broker = ZebraRemindersRequestBroker(
            fileStore: fileStore,
            processor: ZebraRemindersRequestProcessor(eventStore: eventStore)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "PATH": "/usr/bin:/bin",
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_GBRAIN_WRITE_TARGET_PATH": brain.path,
            "ZEBRA_REMINDERS_EVENTKIT_DIR": requestDirectory.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]

        XCTAssertEqual(try runHelper(
            helperURL,
            ["intake", "--raw", "Apple Reminders", "--candidate", "apple-reminders=Apple Reminders"],
            environment
        ).status, 0)
        XCTAssertEqual(try runHelper(helperURL, ["confirm", "--answer", "yes"], environment).status, 0)
        let next = try runHelper(helperURL, ["next"], environment)
        XCTAssertEqual(next.status, 0)
        XCTAssertEqual(try jsonObject(next.stdout)["nextPlaybookID"] as? String, "apple-reminders.eventkit")
        XCTAssertEqual(try jsonObject(next.stdout)["nextPlaybookStepID"] as? String, "check_reminders_permission")

        let consent = try await runHelper(helperURL, ["apple-reminders", "check-access"], environment, broker)
        XCTAssertEqual(consent.status, 1)
        XCTAssertEqual(try jsonObject(consent.stdout)["reason"] as? String, "reminders_permission_consent_required")
        XCTAssertEqual(eventStore.authorizationRequestCount, 0)

        let permission = try await runHelper(
            helperURL,
            ["apple-reminders", "check-access", "--permission-answer", "yes"],
            environment,
            broker
        )
        XCTAssertEqual(permission.status, 0, permission.stderr)
        XCTAssertEqual(try jsonObject(permission.stdout)["authorizationStatus"] as? String, "authorized")
        XCTAssertEqual(eventStore.authorizationRequestCount, 1)

        let smoke = try await runHelper(helperURL, ["apple-reminders", "smoke-list"], environment, broker)
        XCTAssertEqual(smoke.status, 0, smoke.stderr)
        XCTAssertEqual(try jsonObject(smoke.stdout)["openReminderCount"] as? Int, 1)
        XCTAssertEqual(try runHelper(
            helperURL,
            ["apple-reminders", "choose-scope", "--scope", "one-list", "--list", "Work"],
            environment
        ).status, 0)
        XCTAssertEqual(try runHelper(
            helperURL,
            ["apple-reminders", "confirm-plan", "--answer", "yes"],
            environment
        ).status, 0)

        let ingest = try await runHelper(helperURL, ["apple-reminders", "ingest"], environment, broker)
        XCTAssertEqual(ingest.status, 0, ingest.stderr)
        let artifactPath = try XCTUnwrap(jsonObject(ingest.stdout)["artifactPath"] as? String)
        let artifact = try String(contentsOfFile: artifactPath, encoding: .utf8)
        XCTAssertTrue(artifact.contains("source: apple-reminders"), artifact)
        XCTAssertTrue(artifact.contains("playbook: apple-reminders.eventkit.v1"), artifact)
        XCTAssertTrue(artifact.contains("Investor update"), artifact)
        XCTAssertTrue(artifact.contains("Send the revised deck"), artifact)

        let readback = try runHelper(helperURL, ["apple-reminders", "verify-readback"], environment)
        XCTAssertEqual(readback.status, 0, readback.stderr)
        XCTAssertEqual(try jsonObject(readback.stdout)["readbackStatus"] as? String, "passed")
        XCTAssertEqual(try jsonObject(readback.stdout)["nextPlaybookStepID"] as? String, "complete")
    }

    func testAuthorizationStatusDoesNotRequestAndExplicitRequestRunsOnce() async throws {
        let store = FakeRemindersEventStore(authorizationStatus: .notDetermined)
        let processor = ZebraRemindersRequestProcessor(eventStore: store)

        let statusReceipt = await processor.process(
            ZebraRemindersRequest(
                requestID: "status-1",
                sourceRunID: "run-1",
                operation: .authorizationStatus
            )
        )

        XCTAssertEqual(statusReceipt.state, .succeeded)
        XCTAssertEqual(statusReceipt.executionOwner, .zebraApp)
        XCTAssertEqual(statusReceipt.authorizationStatus, .notDetermined)
        XCTAssertEqual(store.authorizationRequestCount, 0)

        store.authorizationStatusValue = .authorized
        let requestReceipt = await processor.process(
            ZebraRemindersRequest(
                requestID: "authorize-1",
                sourceRunID: "run-1",
                operation: .requestAuthorization
            )
        )

        XCTAssertEqual(requestReceipt.state, .succeeded)
        XCTAssertEqual(requestReceipt.authorizationStatus, .authorized)
        XCTAssertEqual(store.authorizationRequestCount, 1)
    }

    func testPermissionOutcomesHaveDistinctMachineReadableReasons() async {
        let expectations: [(ZebraRemindersAuthorizationStatus, String, Bool)] = [
            (.denied, "reminders_permission_denied", true),
            (.restricted, "reminders_permission_restricted", false),
            (.unavailable, "reminders_permission_unavailable", false),
        ]

        for (status, reason, retryable) in expectations {
            let store = FakeRemindersEventStore(authorizationStatus: status)
            let processor = ZebraRemindersRequestProcessor(eventStore: store)
            let receipt = await processor.process(
                ZebraRemindersRequest(
                    requestID: "smoke-\(status.rawValue)",
                    sourceRunID: "run-1",
                    operation: .smokeRead
                )
            )

            XCTAssertEqual(receipt.state, .failed)
            XCTAssertEqual(receipt.authorizationStatus, status)
            XCTAssertEqual(receipt.failureReason, reason)
            XCTAssertEqual(receipt.retryable, retryable)
            XCTAssertEqual(store.fetchCount, 0)
        }
    }

    func testEmptyAuthorizedSmokePassesWithoutReminderBodies() async throws {
        let store = FakeRemindersEventStore(
            authorizationStatus: .authorized,
            lists: [],
            reminders: []
        )
        let processor = ZebraRemindersRequestProcessor(eventStore: store)

        let receipt = await processor.process(
            ZebraRemindersRequest(
                requestID: "smoke-empty",
                sourceRunID: "run-1",
                operation: .smokeRead
            )
        )

        XCTAssertEqual(receipt.state, .succeeded)
        XCTAssertEqual(receipt.result?.listCount, 0)
        XCTAssertEqual(receipt.result?.openReminderCount, 0)
        XCTAssertEqual(receipt.result?.reminders, nil)
        XCTAssertEqual(store.fetchCount, 1)

        let encoded = try JSONEncoder().encode(receipt)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(json.contains("private smoke body"))
    }

    func testScopeReadFiltersAllOpenListTodayWeekCustomAndSkip() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )))
        let work = ZebraRemindersListSnapshot(id: "work", title: "Work")
        let home = ZebraRemindersListSnapshot(id: "home", title: "Home")
        let reminders = [
            ZebraReminderSnapshot(
                id: "today-work",
                title: "Investor update",
                notes: "private smoke body",
                listID: work.id,
                listTitle: work.title,
                isCompleted: false,
                priority: 1,
                dueDate: calendar.date(byAdding: .hour, value: 2, to: now)
            ),
            ZebraReminderSnapshot(
                id: "week-home",
                title: "Buy milk",
                notes: nil,
                listID: home.id,
                listTitle: home.title,
                isCompleted: false,
                priority: 0,
                dueDate: calendar.date(byAdding: .day, value: 3, to: now)
            ),
            ZebraReminderSnapshot(
                id: "overdue-work",
                title: "Review metrics",
                notes: nil,
                listID: work.id,
                listTitle: work.title,
                isCompleted: false,
                priority: 5,
                dueDate: calendar.date(byAdding: .day, value: -1, to: now)
            ),
            ZebraReminderSnapshot(
                id: "done-work",
                title: "Completed task",
                notes: nil,
                listID: work.id,
                listTitle: work.title,
                isCompleted: true,
                priority: 0,
                dueDate: nil
            ),
        ]
        let store = FakeRemindersEventStore(
            authorizationStatus: .authorized,
            lists: [work, home],
            reminders: reminders
        )
        let processor = ZebraRemindersRequestProcessor(
            eventStore: store,
            calendar: calendar,
            now: { now }
        )

        let cases: [(ZebraRemindersScope, [String])] = [
            (.allOpen, ["today-work", "week-home", "overdue-work"]),
            (.oneList("Work"), ["today-work", "overdue-work"]),
            (.today, ["today-work"]),
            (.week, ["today-work", "week-home"]),
            (
                .custom(
                    listTitles: ["Work"],
                    status: .all,
                    dueWindow: .all,
                    itemCap: 2
                ),
                ["today-work", "overdue-work"]
            ),
            (.skip, []),
        ]

        for (index, item) in cases.enumerated() {
            let receipt = await processor.process(
                ZebraRemindersRequest(
                    requestID: "scope-\(index)",
                    sourceRunID: "run-1",
                    operation: .scopeRead,
                    scope: item.0
                )
            )
            XCTAssertEqual(receipt.state, .succeeded)
            XCTAssertEqual(receipt.result?.reminders?.map(\.id), item.1)
        }
    }

    func testFetchFailureAndCancellationStayDistinct() async {
        let failedStore = FakeRemindersEventStore(
            authorizationStatus: .authorized,
            fetchError: FakeError.fetchFailed
        )
        let failed = await ZebraRemindersRequestProcessor(eventStore: failedStore).process(
            ZebraRemindersRequest(
                requestID: "fetch-failed",
                sourceRunID: "run-1",
                operation: .smokeRead
            )
        )
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.failureReason, "reminders_fetch_failed")
        XCTAssertTrue(failed.retryable)

        let cancelledStore = FakeRemindersEventStore(
            authorizationStatus: .authorized,
            fetchError: CancellationError()
        )
        let cancelled = await ZebraRemindersRequestProcessor(eventStore: cancelledStore).process(
            ZebraRemindersRequest(
                requestID: "fetch-cancelled",
                sourceRunID: "run-1",
                operation: .smokeRead
            )
        )
        XCTAssertEqual(cancelled.state, .cancelled)
        XCTAssertEqual(cancelled.failureReason, "reminders_request_cancelled")
        XCTAssertTrue(cancelled.retryable)
    }

    func testFileBrokerProcessesStableRequestExactlyOnceAndWritesPrivateReceipt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ZebraRemindersEventKitTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let fileStore = ZebraRemindersRequestFileStore(directoryURL: root)
        let fake = FakeRemindersEventStore(authorizationStatus: .authorized)
        let processor = ZebraRemindersRequestProcessor(eventStore: fake)
        let broker = ZebraRemindersRequestBroker(fileStore: fileStore, processor: processor)
        let request = ZebraRemindersRequest(
            requestID: "stable-request",
            sourceRunID: "run-1",
            operation: .smokeRead
        )

        try fileStore.writeRequest(request)
        try await broker.processPendingRequestsOnce()
        try await broker.processPendingRequestsOnce()

        XCTAssertEqual(fake.fetchCount, 1)
        let receipt = try XCTUnwrap(fileStore.readReceipt(requestID: request.requestID))
        XCTAssertEqual(receipt.requestID, request.requestID)
        XCTAssertEqual(receipt.executionOwner, .zebraApp)
        XCTAssertEqual(receipt.state, .succeeded)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: fileStore.receiptURL(requestID: request.requestID).path
        )
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testZebraOverlayProducesLocalizedRemindersUsageDescriptionInAppArtifact() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ZebraRemindersOverlayTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let app = root.appendingPathComponent("Zebra.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let infoPlist = app.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try writePlist(["CFBundleName": "Zebra"], to: infoPlist)
        for language in ["en", "ja"] {
            let lproj = resources.appendingPathComponent("\(language).lproj", isDirectory: true)
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            try writePlist(
                ["about.appName": "cmux"],
                to: lproj.appendingPathComponent("Localizable.strings")
            )
        }

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let result = try runHelper(
            URL(fileURLWithPath: "/usr/bin/python3"),
            [
                repositoryRoot.appendingPathComponent("scripts/apply-zebra-localization-overlay.py").path,
                app.path,
                "--overlay",
                repositoryRoot.appendingPathComponent("scripts/zebra-localization-overlay.json").path,
            ],
            [:]
        )
        XCTAssertEqual(result.status, 0, result.stderr)

        let info = try readPlist(infoPlist)
        XCTAssertEqual(
            info["NSRemindersFullAccessUsageDescription"] as? String,
            "Zebra reads the Apple Reminders scope you approve during Source Onboarding."
        )
        let japanese = try readPlist(
            resources.appendingPathComponent("ja.lproj/InfoPlist.strings")
        )
        XCTAssertEqual(
            japanese["NSRemindersFullAccessUsageDescription"] as? String,
            "ZebraはSource Onboardingで承認した範囲のAppleリマインダーを読み取ります。"
        )
    }
}

@MainActor
private final class FakeRemindersEventStore: ZebraRemindersEventStore {
    var authorizationStatusValue: ZebraRemindersAuthorizationStatus
    var requestedAuthorizationStatus: ZebraRemindersAuthorizationStatus
    var lists: [ZebraRemindersListSnapshot]
    var reminders: [ZebraReminderSnapshot]
    var fetchError: Error?
    private(set) var authorizationRequestCount = 0
    private(set) var fetchCount = 0

    init(
        authorizationStatus: ZebraRemindersAuthorizationStatus,
        requestedAuthorizationStatus: ZebraRemindersAuthorizationStatus? = nil,
        lists: [ZebraRemindersListSnapshot] = [],
        reminders: [ZebraReminderSnapshot] = [],
        fetchError: Error? = nil
    ) {
        self.authorizationStatusValue = authorizationStatus
        self.requestedAuthorizationStatus = requestedAuthorizationStatus ?? authorizationStatus
        self.lists = lists
        self.reminders = reminders
        self.fetchError = fetchError
    }

    func authorizationStatus() -> ZebraRemindersAuthorizationStatus {
        authorizationStatusValue
    }

    func requestAuthorization() async throws -> ZebraRemindersAuthorizationStatus {
        authorizationRequestCount += 1
        authorizationStatusValue = requestedAuthorizationStatus
        return requestedAuthorizationStatus
    }

    func fetchSnapshot() async throws -> ZebraRemindersStoreSnapshot {
        fetchCount += 1
        if let fetchError { throw fetchError }
        return ZebraRemindersStoreSnapshot(lists: lists, reminders: reminders)
    }
}

private enum FakeError: Error {
    case fetchFailed
}

private extension ZebraRemindersEventKitTests {
    func runHelper(
        _ executableURL: URL,
        _ arguments: [String],
        _ environment: [String: String]
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = configuredProcess(executableURL, arguments, environment)
        let stdout = try XCTUnwrap(process.standardOutput as? Pipe)
        let stderr = try XCTUnwrap(process.standardError as? Pipe)
        try process.run()
        process.waitUntilExit()
        return processResult(process, stdout, stderr)
    }

    func runHelper(
        _ executableURL: URL,
        _ arguments: [String],
        _ environment: [String: String],
        _ broker: ZebraRemindersRequestBroker
    ) async throws -> (status: Int32, stdout: String, stderr: String) {
        let process = configuredProcess(executableURL, arguments, environment)
        let stdout = try XCTUnwrap(process.standardOutput as? Pipe)
        let stderr = try XCTUnwrap(process.standardError as? Pipe)
        try process.run()
        while process.isRunning {
            try await broker.processPendingRequestsOnce()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return processResult(process, stdout, stderr)
    }

    func configuredProcess(
        _ executableURL: URL,
        _ arguments: [String],
        _ environment: [String: String]
    ) -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        return process
    }

    func processResult(
        _ process: Process,
        _ stdout: Pipe,
        _ stderr: Pipe
    ) -> (status: Int32, stdout: String, stderr: String) {
        (
            process.terminationStatus,
            String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    func jsonObject(_ stdout: String) throws -> [String: Any] {
        let data = try XCTUnwrap(stdout.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func writeCompletedGBrainState(to url: URL, vaultPath: String) throws {
        let key = "vault:\(vaultPath)"
        let timestamp = "2026-07-20T00:00:00Z"
        let target: [String: Any] = [
            "vaultPath": vaultPath,
            "sourceId": "brain",
            "gbrainExecutablePath": "/usr/bin/true",
            "doctorStatus": ["ok": true, "status": "ok"],
            "sourcesCurrentResult": ["ok": true, "sourceId": "brain", "localPath": vaultPath],
            "searchProbeResult": ["ok": true, "status": "not_run"],
            "verifiedAt": timestamp,
            "complete": true,
            "targetResolution": ["method": "user_created_repo", "confirmedAt": timestamp],
            "reasons": [],
        ]
        let state: [String: Any] = [
            "schemaVersion": 1,
            "progress": [
                "resolvedTargetKey": key,
                "targetResolution": [
                    "status": "verified",
                    "method": "user_created_repo",
                    "confirmedAt": timestamp,
                ],
            ],
            "receipt": [
                "globalReadiness": [
                    "complete": true,
                    "gbrainExecutablePath": "/usr/bin/true",
                    "doctorOk": true,
                    "verifiedAt": timestamp,
                ],
                "primaryTargetKey": key,
                "targets": [key: target],
            ],
        ]
        try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }

    func writePlist(_ value: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)
    }

    func readPlist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any]
        )
    }
}
