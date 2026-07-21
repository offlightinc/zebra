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
            lists: [
                ZebraRemindersListSnapshot(id: "work-primary", title: "Work"),
                ZebraRemindersListSnapshot(id: "work-secondary", title: "Work"),
            ],
            reminders: [
                ZebraReminderSnapshot(
                    id: "r1",
                    title: "Investor update",
                    notes: "Send the revised deck",
                    listID: "work-primary",
                    listTitle: "Work",
                    isCompleted: false,
                    priority: 1,
                    dueDate: nil
                ),
                ZebraReminderSnapshot(
                    id: "r2",
                    title: "Unapproved duplicate-list reminder",
                    notes: nil,
                    listID: "work-secondary",
                    listTitle: "Work",
                    isCompleted: false,
                    priority: 0,
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

        let declined = try await runHelper(
            helperURL,
            ["apple-reminders", "check-access", "--permission-answer", "no"],
            environment,
            broker
        )
        XCTAssertEqual(declined.status, 1)
        XCTAssertEqual(try jsonObject(declined.stdout)["reason"] as? String, "reminders_permission_declined")
        XCTAssertEqual(try jsonObject(declined.stdout)["authorizationStatus"] as? String, "notDetermined")
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
        XCTAssertEqual(try jsonObject(smoke.stdout)["openReminderCount"] as? Int, 2)
        let smokeLists = try XCTUnwrap(try jsonObject(smoke.stdout)["lists"] as? [[String: Any]])
        XCTAssertEqual(smokeLists.compactMap { $0["id"] as? String }, ["work-primary", "work-secondary"])
        XCTAssertEqual(try runHelper(
            helperURL,
            [
                "apple-reminders", "choose-scope", "--scope", "custom",
                "--list-id", "work-primary", "--status", "open",
            ],
            environment
        ).status, 0)
        XCTAssertEqual(try runHelper(
            helperURL,
            ["apple-reminders", "confirm-plan", "--answer", "yes"],
            environment
        ).status, 0)

        let ingest = try await runHelper(helperURL, ["apple-reminders", "ingest"], environment, broker)
        XCTAssertEqual(ingest.status, 0, ingest.stderr)
        let ingestPayload = try jsonObject(ingest.stdout)
        XCTAssertEqual(ingestPayload["ingestedReminderCount"] as? Int, 1)
        XCTAssertNil(ingestPayload["artifactPath"])

        let readback = try runHelper(helperURL, ["apple-reminders", "verify-readback"], environment)
        XCTAssertEqual(readback.status, 0, readback.stderr)
        XCTAssertEqual(try jsonObject(readback.stdout)["readbackStatus"] as? String, "passed")
        XCTAssertEqual(try jsonObject(readback.stdout)["verifiedRecordCount"] as? Int, 1)
        XCTAssertEqual(try jsonObject(readback.stdout)["nextPlaybookStepID"] as? String, "complete")
        let pageStore = root.appendingPathComponent("fake-gbrain-pages", isDirectory: true)
        let pageURLs = try FileManager.default.contentsOfDirectory(at: pageStore, includingPropertiesForKeys: nil)
        let persisted = try pageURLs.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        XCTAssertTrue(persisted.contains("Investor update"), persisted)
        XCTAssertTrue(persisted.contains("Send the revised deck"), persisted)
        XCTAssertFalse(persisted.contains("Unapproved duplicate-list reminder"), persisted)
        let completion = try runHelper(
            helperURL,
            ["report", "--status", "completed", "--source", "apple-reminders"],
            environment
        )
        XCTAssertEqual(completion.status, 0, completion.stderr)
        XCTAssertEqual(try jsonObject(completion.stdout)["completedSourceID"] as? String, "apple-reminders")
        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let rows = try XCTUnwrap(progress["sourceRows"] as? [String: Any])
        let row = try XCTUnwrap(rows["apple-reminders"] as? [String: Any])
        XCTAssertEqual(row["status"] as? String, "checked")
        let runStatePath = try XCTUnwrap(row["runStatePath"] as? String)
        let runState = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: runStatePath))) as? [String: Any]
        )
        XCTAssertEqual(runState["workflowStatus"] as? String, "completed")
        XCTAssertEqual(runState["ingestStatus"] as? String, "succeeded")
        XCTAssertEqual(runState["readbackStatus"] as? String, "passed")
    }

    func testAuthorizationStatusDoesNotRequestAndExplicitRequestRunsOnce() async throws {
        let store = FakeRemindersEventStore(
            authorizationStatus: .notDetermined,
            requestedAuthorizationStatus: .authorized
        )
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
            (.oneList(id: "work", title: "Work"), ["today-work", "overdue-work"]),
            (.today, ["today-work"]),
            (.week, ["today-work", "week-home"]),
            (
                .custom(
                    listIDs: ["work"],
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

    func testScopeReadFailsWhenApprovedCalendarCannotBeResolved() async {
        let store = FakeRemindersEventStore(
            authorizationStatus: .authorized,
            lists: [ZebraRemindersListSnapshot(id: "available", title: "Available")]
        )

        let receipt = await ZebraRemindersRequestProcessor(eventStore: store).process(
            ZebraRemindersRequest(
                requestID: "missing-approved-calendar",
                sourceRunID: "run-1",
                operation: .scopeRead,
                scope: .oneList(id: "missing", title: "Display only")
            )
        )

        XCTAssertEqual(receipt.state, .failed)
        XCTAssertEqual(receipt.failureReason, "approved_calendar_unavailable")
        XCTAssertNil(receipt.result)
        XCTAssertEqual(store.lastRequestedCalendarIDs, ["missing"])
        XCTAssertEqual(receipt.requestedCalendarCount, 1)
        XCTAssertEqual(receipt.resolvedCalendarCount, 0)
        XCTAssertEqual(receipt.fetchedReminderCount, 0)
        XCTAssertEqual(receipt.resultReminderCount, 0)
        XCTAssertEqual(receipt.outcome, "failed")
        XCTAssertEqual(receipt.reason, "approved_calendar_unavailable")
        XCTAssertEqual(receipt.schemaProvenance, "zebra-reminders-eventkit.v1")
        XCTAssertFalse(receipt.buildProvenance.isEmpty)
        XCTAssertEqual(store.reminderFetchCount, 0)
    }

    func testNonEmptyDiscoveryFollowedByZeroIngestBlocksArtifactAndReadback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ZebraRemindersMismatchTests-\(UUID().uuidString)",
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
        let eventStore = FakeRemindersEventStore(
            authorizationStatus: .authorized,
            lists: [ZebraRemindersListSnapshot(id: "selected", title: "Selected")],
            reminders: [ZebraReminderSnapshot(
                id: "present-at-discovery",
                title: "Private title",
                notes: "Private notes",
                listID: "selected",
                listTitle: "Selected",
                isCompleted: false,
                priority: 0,
                dueDate: nil
            )]
        )
        let broker = ZebraRemindersRequestBroker(
            fileStore: ZebraRemindersRequestFileStore(directoryURL: requestDirectory),
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

        XCTAssertEqual(try runHelper(helperURL, ["intake", "--raw", "Apple Reminders", "--candidate", "apple-reminders=Apple Reminders"], environment).status, 0)
        XCTAssertEqual(try runHelper(helperURL, ["confirm", "--answer", "yes"], environment).status, 0)
        _ = try runHelper(helperURL, ["next"], environment)
        let access = try await runHelper(helperURL, ["apple-reminders", "check-access"], environment, broker)
        XCTAssertEqual(access.status, 0)
        let smoke = try await runHelper(helperURL, ["apple-reminders", "smoke-list"], environment, broker)
        XCTAssertEqual(smoke.status, 0)
        XCTAssertEqual(try runHelper(helperURL, ["apple-reminders", "choose-scope", "--scope", "one-list", "--list-id", "selected"], environment).status, 0)
        XCTAssertEqual(try runHelper(helperURL, ["apple-reminders", "confirm-plan", "--answer", "yes"], environment).status, 0)

        eventStore.reminders = []
        let ingest = try await runHelper(helperURL, ["apple-reminders", "ingest"], environment, broker)
        let payload = try jsonObject(ingest.stdout)

        XCTAssertNotEqual(ingest.status, 0)
        XCTAssertEqual(payload["reason"] as? String, "scope_changed_or_result_mismatch")
        XCTAssertNil(payload["artifactPath"])
        XCTAssertEqual(payload["workflowStatus"] as? String, "reconciliationRequired")
        XCTAssertEqual(payload["ingestStatus"] as? String, "mismatch")
        XCTAssertEqual(payload["readbackStatus"] as? String, "pending")
        XCTAssertFalse(FileManager.default.fileExists(atPath: brain.appendingPathComponent("sources/apple-reminders-eventkit.md").path))
        let blockedCompletion = try runHelper(
            helperURL,
            ["report", "--status", "completed", "--source", "apple-reminders"],
            environment
        )
        XCTAssertNotEqual(blockedCompletion.status, 0)
        let blockedState = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        XCTAssertNotEqual(blockedState["status"] as? String, "completed")
        let blockedProgress = try XCTUnwrap(blockedState["progress"] as? [String: Any])
        let blockedRows = try XCTUnwrap(blockedProgress["sourceRows"] as? [String: Any])
        let blockedRow = try XCTUnwrap(blockedRows["apple-reminders"] as? [String: Any])
        XCTAssertEqual(blockedRow["status"] as? String, "attention")

        let acceptedEmpty = try await runHelper(
            helperURL,
            ["apple-reminders", "ingest", "--accept-empty", "yes"],
            environment,
            broker
        )
        let acceptedPayload = try jsonObject(acceptedEmpty.stdout)
        XCTAssertEqual(acceptedEmpty.status, 0, acceptedEmpty.stderr)
        XCTAssertEqual(acceptedPayload["ingestedReminderCount"] as? Int, 0)
        XCTAssertEqual(acceptedPayload["outcome"] as? String, "confirmed-empty")
        XCTAssertEqual(acceptedPayload["reason"] as? String, "explicit_empty_approval")
        XCTAssertFalse(FileManager.default.fileExists(atPath: brain.appendingPathComponent("sources/apple-reminders-eventkit.md").path))
    }

    func testDiscoveryConfirmedEmptyListHasDistinctSuccessfulOutcome() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ZebraRemindersConfirmedEmptyTests-\(UUID().uuidString)",
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
        let broker = ZebraRemindersRequestBroker(
            fileStore: ZebraRemindersRequestFileStore(directoryURL: requestDirectory),
            processor: ZebraRemindersRequestProcessor(eventStore: FakeRemindersEventStore(
                authorizationStatus: .authorized,
                lists: [ZebraRemindersListSnapshot(id: "empty", title: "Empty")],
                reminders: []
            ))
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

        XCTAssertEqual(try runHelper(helperURL, ["intake", "--raw", "Apple Reminders", "--candidate", "apple-reminders=Apple Reminders"], environment).status, 0)
        XCTAssertEqual(try runHelper(helperURL, ["confirm", "--answer", "yes"], environment).status, 0)
        _ = try runHelper(helperURL, ["next"], environment)
        let access = try await runHelper(helperURL, ["apple-reminders", "check-access"], environment, broker)
        XCTAssertEqual(access.status, 0)
        let smoke = try await runHelper(helperURL, ["apple-reminders", "smoke-list"], environment, broker)
        XCTAssertEqual(smoke.status, 0)
        let smokeLists = try XCTUnwrap(try jsonObject(smoke.stdout)["lists"] as? [[String: Any]])
        XCTAssertEqual(smokeLists.first?["openReminderCount"] as? Int, 0)
        XCTAssertEqual(try runHelper(helperURL, ["apple-reminders", "choose-scope", "--scope", "one-list", "--list-id", "empty"], environment).status, 0)
        XCTAssertEqual(try runHelper(helperURL, ["apple-reminders", "confirm-plan", "--answer", "yes"], environment).status, 0)

        let ingest = try await runHelper(helperURL, ["apple-reminders", "ingest"], environment, broker)
        let payload = try jsonObject(ingest.stdout)
        XCTAssertEqual(ingest.status, 0, ingest.stderr)
        XCTAssertEqual(payload["ingestedReminderCount"] as? Int, 0)
        XCTAssertEqual(payload["outcome"] as? String, "confirmed-empty")
        XCTAssertEqual(payload["reason"] as? String, "discovery_confirmed_empty")
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
        let fake = FakeRemindersEventStore(
            authorizationStatus: .authorized,
            lists: [ZebraRemindersListSnapshot(id: "stable-list", title: "Display")]
        )
        let processor = ZebraRemindersRequestProcessor(eventStore: fake)
        let broker = ZebraRemindersRequestBroker(fileStore: fileStore, processor: processor)
        let request = ZebraRemindersRequest(
            requestID: "stable-request",
            sourceRunID: "run-1",
            operation: .scopeRead,
            scope: .oneList(id: "stable-list", title: "Display"),
            helperBuildProvenance: "helper-test-build"
        )

        try fileStore.writeRequest(request)
        let decodedRequest = try XCTUnwrap(fileStore.pendingRequests().first)
        XCTAssertEqual(decodedRequest.scope?.listIDs, ["stable-list"])
        XCTAssertEqual(decodedRequest.schemaProvenance, "zebra-reminders-eventkit.v1")
        XCTAssertEqual(decodedRequest.helperBuildProvenance, "helper-test-build")
        try await broker.processPendingRequestsOnce()
        try await broker.processPendingRequestsOnce()

        XCTAssertEqual(fake.fetchCount, 1)
        let receipt = try XCTUnwrap(fileStore.readReceipt(requestID: request.requestID))
        XCTAssertEqual(receipt.requestID, request.requestID)
        XCTAssertEqual(receipt.executionOwner, .zebraApp)
        XCTAssertEqual(receipt.state, .succeeded)
        XCTAssertEqual(fake.lastRequestedCalendarIDs, ["stable-list"])

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

    func testZebraOverlayStillFailsWhenLocalizationTablesAreMissing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ZebraRemindersOverlayGuardTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let app = root.appendingPathComponent("Zebra.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let infoPlist = app.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(
            at: resources.appendingPathComponent("en.lproj", isDirectory: true),
            withIntermediateDirectories: true
        )
        try writePlist(["CFBundleName": "Zebra"], to: infoPlist)

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
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

        XCTAssertNotEqual(result.status, 0, result.stdout)
        XCTAssertTrue(result.stderr.contains("no localization tables were changed"), result.stderr)
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
    private(set) var reminderFetchCount = 0
    private(set) var lastRequestedCalendarIDs: [String]?

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

    func fetchSnapshot(calendarIDs: [String]?) async throws -> ZebraRemindersStoreSnapshot {
        fetchCount += 1
        lastRequestedCalendarIDs = calendarIDs
        if let fetchError { throw fetchError }
        let requested = calendarIDs.map(Set.init)
        let openCounts = Dictionary(grouping: reminders.filter { !$0.isCompleted }, by: \.listID).mapValues(\.count)
        let countedLists = lists.map {
            ZebraRemindersListSnapshot(id: $0.id, title: $0.title, openReminderCount: openCounts[$0.id, default: 0])
        }
        let resolvedLists = requested.map { ids in countedLists.filter { ids.contains($0.id) } } ?? countedLists
        if let calendarIDs, resolvedLists.count != calendarIDs.count {
            return ZebraRemindersStoreSnapshot(
                lists: resolvedLists,
                reminders: [],
                requestedCalendarCount: calendarIDs.count,
                resolvedCalendarCount: resolvedLists.count,
                fetchedReminderCount: 0
            )
        }
        reminderFetchCount += 1
        let resolvedIDs = Set(resolvedLists.map(\.id))
        let fetched = calendarIDs == nil ? reminders : reminders.filter { resolvedIDs.contains($0.listID) }
        return ZebraRemindersStoreSnapshot(
            lists: resolvedLists,
            reminders: fetched,
            requestedCalendarCount: calendarIDs?.count ?? resolvedLists.count,
            resolvedCalendarCount: resolvedLists.count,
            fetchedReminderCount: fetched.count
        )
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
        let root = url.deletingLastPathComponent()
        let home = root.appendingPathComponent("gbrain-home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let executable = try SourceOnboardingFakeGBrain.install(
            root: root,
            sourcePath: vaultPath,
            log: root.appendingPathComponent("gbrain.log", isDirectory: false)
        )
        try SourceOnboardingFakeGBrain.writeCompletedState(
            to: url,
            vaultPath: vaultPath,
            executablePath: executable.path,
            sourceRepoPath: home.path
        )
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
