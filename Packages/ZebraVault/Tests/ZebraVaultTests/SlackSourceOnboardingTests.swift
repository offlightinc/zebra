import Foundation
import Testing
@testable import ZebraVault

@Suite(.serialized)
struct SlackSourceOnboardingTests {
    @Test func catalogNormalizesEnglishAndKoreanAliases() {
        let english = ZebraSourceOnboardingCatalog.normalize(rawSourceInput: "Slack")
        let korean = ZebraSourceOnboardingCatalog.normalize(rawSourceInput: "슬랙")
        #expect(english.normalizedSourceList == ["slack"])
        #expect(korean.normalizedSourceList == ["slack"])
        #expect(english.sourceRows["slack"]?.playbookID == "slack.captured-polling")
        #expect(english.sourceRows["slack"]?.playbookVersion == "v1")
    }

    @MainActor
    @Test func nativeRunnerRequiresConfirmationAndActiveSlackSource() throws {
        let fixture = try Fixture(sourceIDs: ["gmail", "slack"])
        let coordinator = SlackSourceOnboardingCoordinator(
            stateURL: fixture.stateURL,
            applicationSupport: fixture.root,
            credentialStore: MemoryCredentialStore(),
            transport: FailingIfCalledTransport()
        )
        #expect(!coordinator.isSlackConfirmedAndActive())

        var state = try fixture.readState()
        state.progress.sourceConfirmation?.status = .confirmed
        state.progress.executionOrder = ["gmail", "slack"]
        state.progress.activeSourceID = "gmail"
        try fixture.writeState(state)
        #expect(!coordinator.isSlackConfirmedAndActive())

        state.progress.activeSourceID = "slack"
        try fixture.writeState(state)
        #expect(coordinator.isSlackConfirmedAndActive())
    }

    @MainActor
    @Test func rejectedBotTokenNeverReachesCredentialStore() async throws {
        let credentials = MemoryCredentialStore()
        let fixture = try Fixture(sourceIDs: ["slack"], confirmedActive: true)
        let coordinator = SlackSourceOnboardingCoordinator(
            stateURL: fixture.stateURL,
            applicationSupport: fixture.root,
            credentialStore: credentials,
            transport: FailingIfCalledTransport()
        )
        coordinator.begin(token: "xoxb-bot-token", startDate: Date(timeIntervalSince1970: 100))
        await waitUntilSettled(coordinator)
        #expect(coordinator.presentationState == .attention("user_oauth_token_required"))
        #expect(credentials.savedTokens.isEmpty)
        let encoded = try Data(contentsOf: fixture.stateURL)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("xoxb-bot-token"))
    }

    @MainActor
    @Test func validatedIdentityPollsDurablyChecksRowAndAdvancesToNextSource() async throws {
        let credentials = MemoryCredentialStore()
        let transport = SuccessfulPollTransport()
        let fixture = try Fixture(sourceIDs: ["slack", "gmail"], confirmedActive: true)
        let coordinator = SlackSourceOnboardingCoordinator(
            stateURL: fixture.stateURL,
            applicationSupport: fixture.root,
            credentialStore: credentials,
            transport: transport
        )
        let startDate = Date(timeIntervalSince1970: 100)
        coordinator.begin(token: "xoxp-user-secret", startDate: startDate)
        await waitUntilSettled(coordinator)

        #expect(coordinator.presentationState == .checked)
        let state = try fixture.readState()
        #expect(state.sourceReadiness.slack?.workspaceID == "T1")
        #expect(state.sourceReadiness.slack?.authorizedUserID == "U1")
        #expect(state.sourceReadiness.slack?.startDate == startDate)
        #expect(state.sourceReadiness.slack?.checkpointExists == true)
        #expect(state.progress.sourceRows["slack"]?.status == "checked")
        #expect(state.progress.activeSourceID == "gmail")
        #expect(credentials.savedTokens == ["xoxp-user-secret"])

        let captured = fixture.root.appendingPathComponent("outer-brain/slack/T1/captured")
        #expect(FileManager.default.fileExists(atPath: captured.appendingPathComponent("state/collector-checkpoint.json").path))
        let rawFiles = try FileManager.default.contentsOfDirectory(at: captured.appendingPathComponent("raw"), includingPropertiesForKeys: nil)
        let threadFiles = try FileManager.default.contentsOfDirectory(at: captured.appendingPathComponent("threads"), includingPropertiesForKeys: nil)
        #expect(!rawFiles.isEmpty)
        #expect(!threadFiles.isEmpty)
        for url in [fixture.stateURL] + rawFiles + threadFiles {
            #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("xoxp-user-secret"))
        }
        #expect(await transport.requestedOldest() == "100.0")
    }

    @MainActor
    @Test func pollFailureKeepsCapturedDataAndCredentialThenResumeRetriesSamePath() async throws {
        let credentials = MemoryCredentialStore()
        let fixture = try Fixture(sourceIDs: ["slack"], confirmedActive: true)
        var preexistingStore: SlackCapturedStore? = try SlackCapturedStore(applicationSupport: fixture.root, workspaceID: "T1")
        let preexistingCapture = try SlackRawCapture.make(
            workspaceID: "T1", authorizedUserID: "U1", conversationID: "C0",
            observedAt: Date(timeIntervalSince1970: 90), pollRunID: "existing",
            payload: .object(["ts": .string("90.0"), "user": .string("U1"), "text": .string("existing")])
        )
        _ = try preexistingStore?.appendRaw(preexistingCapture)
        let existing = preexistingStore!.rawDirectory.appendingPathComponent("1970-01-01.jsonl")
        preexistingStore = nil

        let failing = SlackSourceOnboardingCoordinator(
            stateURL: fixture.stateURL, applicationSupport: fixture.root,
            credentialStore: credentials, transport: PollFailureTransport()
        )
        failing.begin(token: "xoxp-retry-secret", startDate: Date(timeIntervalSince1970: 100))
        await waitUntilSettled(failing)
        #expect(failing.presentationState == .attention("slack_poll_failed"))
        #expect(FileManager.default.fileExists(atPath: existing.path))
        #expect(credentials.savedTokens == ["xoxp-retry-secret"])

        let retry = SlackSourceOnboardingCoordinator(
            stateURL: fixture.stateURL, applicationSupport: fixture.root,
            credentialStore: credentials, transport: SuccessfulPollTransport()
        )
        retry.resume(startDate: Date(timeIntervalSince1970: 100))
        await waitUntilSettled(retry)
        #expect(retry.presentationState == .checked)
        #expect(FileManager.default.fileExists(atPath: existing.path))
        #expect(try fixture.readState().progress.sourceRows["slack"]?.status == "checked")
    }

    @Test func helperSlackCLIRejectsBotTokenWithoutPersistingIt() throws {
        let fixture = try Fixture(sourceIDs: ["slack"], confirmedActive: true)
        let helper = ZebraSourceOnboardingHelper(
            stateURL: fixture.stateURL,
            gbrainOnboardingStateURL: fixture.root.appendingPathComponent("gbrain.json"),
            gbrainAdapterOnboardingStateURL: fixture.root.appendingPathComponent("adapter.json"),
            homeDirectoryPath: fixture.root.path
        )
        let launch = try #require(helper.prepareLaunch(selectedVaultPath: nil))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.helperPath)
        process.arguments = ["slack", "connect", "--slack-token", "xoxb-do-not-store", "--start-date", "2026-07-01"]
        var environment = ProcessInfo.processInfo.environment
        environment["ZEBRA_SOURCE_ONBOARDING_STATE"] = fixture.stateURL.path
        environment["ZEBRA_SOURCE_ONBOARDING_HOME"] = fixture.root.path
        process.environment = environment
        let output = Pipe(); process.standardOutput = output; process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 1)
        #expect(text.contains("user_oauth_token_required"))
        #expect(!String(decoding: try Data(contentsOf: fixture.stateURL), as: UTF8.self).contains("xoxb-do-not-store"))
    }

    @Test func helperSlackStartPromptGuidesAppSetupScopesInstallAndInclusiveDate() throws {
        let fixture = try Fixture(sourceIDs: ["slack"], confirmedActive: true)
        let helper = ZebraSourceOnboardingHelper(
            stateURL: fixture.stateURL,
            gbrainOnboardingStateURL: fixture.root.appendingPathComponent("gbrain.json"),
            gbrainAdapterOnboardingStateURL: fixture.root.appendingPathComponent("adapter.json"),
            homeDirectoryPath: fixture.root.path
        )
        let launch = try #require(helper.prepareLaunch(selectedVaultPath: nil))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.helperPath)
        process.arguments = ["next"]
        var environment = ProcessInfo.processInfo.environment
        environment["ZEBRA_SOURCE_ONBOARDING_STATE"] = fixture.stateURL.path
        environment["ZEBRA_SOURCE_ONBOARDING_HOME"] = fixture.root.path
        environment["ZEBRA_ONBOARDING_LANGUAGE"] = "ko"
        process.environment = environment
        let output = Pipe(); process.standardOutput = output; process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let prompt = try #require(payload["nextPrompt"] as? String)

        #expect(process.terminationStatus == 0)
        #expect(prompt.contains("https://api.slack.com/apps"))
        #expect(prompt.contains("Create New App"))
        #expect(prompt.contains("From scratch"))
        #expect(prompt.contains("App Manifest"))
        #expect(prompt.contains("JSON"))
        #expect(prompt.contains("Save Changes"))
        #expect(prompt.contains("search:read"))
        #expect(prompt.contains("reactions:read"))
        #expect(prompt.contains("im:read"))
        #expect(prompt.contains("mpim:history"))
        #expect(prompt.contains("Install to Workspace"))
        #expect(prompt.contains("Reinstall to Workspace"))
        #expect(prompt.contains("왼쪽 메뉴에서 **OAuth & Permissions**를 클릭"))
        #expect(prompt.contains("Slack 권한 승인 화면에서 **Allow**"))
        #expect(prompt.contains("승인이 끝나면 다시 **OAuth & Permissions** 페이지로 돌아옵니다"))
        #expect(prompt.contains("xoxp-"))
        #expect(prompt.contains("선택한 날짜 당일부터 포함"))
        let manifest = try #require(prompt.split(separator: "```json\n").last?.split(separator: "\n```").first)
        #expect(manifest.contains("\n"))
        #expect(manifest.hasPrefix("{"))
        #expect(manifest.split(separator: "\n").allSatisfy { !$0.hasPrefix("                ") })
        let manifestObject = try #require(
            JSONSerialization.jsonObject(with: Data(manifest.utf8)) as? [String: Any]
        )
        let oauth = try #require(manifestObject["oauth_config"] as? [String: Any])
        let scopes = try #require(oauth["scopes"] as? [String: Any])
        #expect((scopes["user"] as? [String])?.count == 10)
    }

    @Test func helperSlackCLIValidatesIdentityAndWritesOnlyKeychainReferenceState() throws {
        let fixture = try Fixture(sourceIDs: ["slack"], confirmedActive: true)
        let authResponse = fixture.root.appendingPathComponent("auth-test.json")
        try Data(#"{"ok":true,"team_id":"TCLI","user_id":"UCLI"}"#.utf8).write(to: authResponse)
        let fakeSecurity = fixture.root.appendingPathComponent("security")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: fakeSecurity)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeSecurity.path)
        let helper = ZebraSourceOnboardingHelper(
            stateURL: fixture.stateURL,
            gbrainOnboardingStateURL: fixture.root.appendingPathComponent("gbrain.json"),
            gbrainAdapterOnboardingStateURL: fixture.root.appendingPathComponent("adapter.json"),
            homeDirectoryPath: fixture.root.path
        )
        let launch = try #require(helper.prepareLaunch(selectedVaultPath: nil))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.helperPath)
        process.arguments = ["slack", "connect", "--slack-token", "xoxp-cli-secret", "--start-date", "2026-07-01"]
        var environment = ProcessInfo.processInfo.environment
        environment["ZEBRA_SOURCE_ONBOARDING_STATE"] = fixture.stateURL.path
        environment["ZEBRA_SOURCE_ONBOARDING_HOME"] = fixture.root.path
        environment["ZEBRA_SLACK_AUTH_TEST_URL"] = authResponse.absoluteString
        environment["ZEBRA_SLACK_SECURITY_BIN"] = fakeSecurity.path
        process.environment = environment
        let output = Pipe(); process.standardOutput = output; process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0)
        #expect(text.contains("polling_in_zebra"))
        let state = try fixture.readState()
        #expect(state.sourceReadiness.slack?.status == .readyToPoll)
        #expect(state.sourceReadiness.slack?.workspaceID == "TCLI")
        #expect(state.sourceReadiness.slack?.authorizedUserID == "UCLI")
        #expect(state.sourceReadiness.slack?.startDate == ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z"))
        #expect(!String(decoding: try Data(contentsOf: fixture.stateURL), as: UTF8.self).contains("xoxp-cli-secret"))
    }

    @MainActor
    private func waitUntilSettled(_ coordinator: SlackSourceOnboardingCoordinator) async {
        for _ in 0..<100 where coordinator.presentationState == .polling {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct Fixture {
        let root: URL
        let stateURL: URL

        init(sourceIDs: [String], confirmedActive: Bool = false) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            stateURL = root.appendingPathComponent("source-onboarding-state.json")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let normalized = ZebraSourceOnboardingCatalog.normalize(rawSourceInput: sourceIDs.joined(separator: ","))
            let now = Date(timeIntervalSince1970: 100)
            let state = ZebraSourceOnboardingState(
                status: .running,
                entryContext: .init(onboardingLanguageCode: "en", gbrainWriteTargetPath: nil,
                                    gbrainTargetPath: nil, gbrainTargetKey: nil, gbrainReceiptPath: nil,
                                    gbrainTargetStatus: nil, gbrainTargetMissingReason: nil, gbrainWarnings: [],
                                    liveProbe: .init(ran: false, status: nil, reason: nil),
                                    adapterReady: true, adapterReadinessReasons: []),
                sourceReadiness: .init(gmail: .init(status: .missingEnv, connectionPath: nil,
                                                   envPath: "", localArtifact: nil, repairKind: nil, reasons: []),
                                       slack: .init(status: .credentialMissing, workspaceID: nil,
                                                    authorizedUserID: nil, startDate: nil,
                                                    checkpointExists: false, reason: "credential_missing")),
                progress: .init(rawSourceInput: sourceIDs.joined(separator: ","),
                                normalizedSourceList: sourceIDs,
                                sourceConfirmation: .init(sourceIDs: sourceIDs, prompt: "confirm",
                                                          status: confirmedActive ? .confirmed : .pending,
                                                          confirmedAt: confirmedActive ? now : nil, updatedAt: now),
                                executionOrder: sourceIDs,
                                activeSourceID: confirmedActive ? sourceIDs.first : nil,
                                sourceRows: normalized.sourceRows),
                updatedAt: now
            )
            try writeState(state)
        }

        func readState() throws -> ZebraSourceOnboardingState {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ZebraSourceOnboardingState.self, from: Data(contentsOf: stateURL))
        }

        func writeState(_ state: ZebraSourceOnboardingState) throws {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: stateURL, options: .atomic)
        }
    }
}

private final class MemoryCredentialStore: SlackCredentialStoring, @unchecked Sendable {
    private(set) var savedTokens: [String] = []
    func saveUserToken(_ token: String, workspaceID: String, userID: String) throws { savedTokens.append(token) }
    func userToken(workspaceID: String, userID: String) throws -> String {
        guard let token = savedTokens.last else { throw SlackCapturedError.missingCredential }
        return token
    }
    func removeUserToken(workspaceID: String, userID: String) throws { savedTokens.removeAll() }
}

private struct FailingIfCalledTransport: SlackHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        Issue.record("Transport must not be called")
        throw SlackCapturedError.invalidResponse
    }
}

private actor SuccessfulPollTransport: SlackHTTPTransport {
    private var oldest: String?

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let method = request.url?.lastPathComponent ?? ""
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let body: String
        switch method {
        case "auth.test":
            body = #"{"ok":true,"team_id":"T1","user_id":"U1"}"#
        case "search.messages":
            if let search = query.first(where: { $0.name == "query" })?.value,
               search.contains("after:1969-12-31") { oldest = "100.0" }
            body = #"{"ok":true,"messages":{"matches":[{"channel":{"id":"C1"},"type":"message","ts":"200.0","user":"U1","text":"authored"}],"paging":{"pages":1}}}"#
        case "reactions.list":
            body = #"{"ok":true,"items":[],"response_metadata":{"next_cursor":""}}"#
        case "users.conversations":
            body = #"{"ok":true,"channels":[],"response_metadata":{"next_cursor":""}}"#
        case "conversations.replies":
            body = #"{"ok":true,"messages":[{"type":"message","ts":"200.0","user":"U1","text":"authored"}],"response_metadata":{"next_cursor":""}}"#
        default:
            body = #"{"ok":false,"error":"unexpected_method"}"#
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func requestedOldest() -> String? { oldest }
}

private actor PollFailureTransport: SlackHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = request.url?.lastPathComponent == "auth.test"
            ? #"{"ok":true,"team_id":"T1","user_id":"U1"}"#
            : #"{"ok":false,"error":"internal_error"}"#
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
