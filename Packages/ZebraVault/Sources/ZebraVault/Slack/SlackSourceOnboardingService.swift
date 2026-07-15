import Foundation

public struct SlackSourceOnboardingResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case checked, attention }

    public let ok: Bool
    public let sourceID: String
    public let status: Status
    public let reason: String?
    public let retryable: Bool
    public let workspaceID: String?
    public let authorizedUserID: String?
    public let startDate: String
    public let nextActiveSourceID: String?
}

struct SlackSourceOnboardingService: @unchecked Sendable {
    enum Credential: Sendable {
        case token(String)
        case storedIdentity(workspaceID: String, userID: String)
    }

    private let stateURL: URL
    private let applicationSupport: URL
    private let credentialStore: any SlackCredentialStoring
    private let transport: any SlackHTTPTransport
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    init(
        stateURL: URL = ZebraSourceOnboardingState.defaultStateURL(),
        applicationSupport: URL? = nil,
        credentialStore: any SlackCredentialStoring = SlackKeychainCredentialStore(),
        transport: any SlackHTTPTransport = SlackURLSessionTransport(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.stateURL = stateURL
        self.applicationSupport = applicationSupport ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("zebra", isDirectory: true)
        self.credentialStore = credentialStore
        self.transport = transport
        self.fileManager = fileManager
        self.now = now
    }

    func run(credential: Credential, startDate: Date) async -> SlackSourceOnboardingResult {
        do {
            var state = try readState()
            guard isConfirmedAndActive(state) else {
                return attention(reason: "slack_source_not_active", startDate: startDate, state: state)
            }

            let token: String
            let expectedIdentity: SlackWebAPIClient.Identity?
            switch credential {
            case .token(let supplied):
                token = supplied
                expectedIdentity = nil
            case .storedIdentity(let workspaceID, let userID):
                token = try credentialStore.userToken(workspaceID: workspaceID, userID: userID)
                expectedIdentity = .init(workspaceID: workspaceID, userID: userID)
            }

            let client = SlackWebAPIClient(token: token, transport: transport)
            let identity = try await client.authenticatedIdentity()
            if let expectedIdentity, expectedIdentity != identity { throw SlackCapturedError.workspaceMismatch }

            if case .token = credential {
                try credentialStore.saveUserToken(token, workspaceID: identity.workspaceID, userID: identity.userID)
            }
            try markPolling(identity: identity, startDate: startDate, state: &state)
            let store = try SlackCapturedStore(
                applicationSupport: applicationSupport,
                workspaceID: identity.workspaceID,
                fileManager: fileManager
            )
            try await poll(client: client, identity: identity, startDate: startDate, store: store)
            guard try store.readCheckpoint() != nil else { throw SlackCapturedError.invalidResponse }
            try markChecked(identity: identity, startDate: startDate, state: &state)
            return result(status: .checked, reason: nil, retryable: false, identity: identity,
                          startDate: startDate, nextActiveSourceID: state.progress.activeSourceID)
        } catch {
            let reason = Self.sanitizedReason(error)
            let state = try? readState()
            try? markAttention(startDate: startDate, reason: reason)
            return attention(reason: reason, startDate: startDate, state: state)
        }
    }

    func resumeFromState() async -> SlackSourceOnboardingResult {
        do {
            let state = try readState()
            guard let readiness = state.sourceReadiness.slack,
                  let workspaceID = readiness.workspaceID,
                  let userID = readiness.authorizedUserID,
                  let startDate = readiness.startDate else {
                return attention(reason: "credential_missing", startDate: Date(timeIntervalSince1970: 0), state: state)
            }
            return await run(credential: .storedIdentity(workspaceID: workspaceID, userID: userID), startDate: startDate)
        } catch {
            return result(status: .attention, reason: "slack_state_unavailable", retryable: true,
                          identity: nil, startDate: Date(timeIntervalSince1970: 0), nextActiveSourceID: nil)
        }
    }

    func isConfirmedAndActive() -> Bool {
        (try? readState()).map(isConfirmedAndActive) ?? false
    }

    func scheduledWorkspaces() -> [SlackScheduledWorkspace] {
        guard let state = try? readState(),
              let readiness = state.sourceReadiness.slack,
              readiness.status == .checked,
              let workspaceID = readiness.workspaceID,
              let userID = readiness.authorizedUserID,
              let startDate = readiness.startDate,
              let store = try? SlackCapturedStore(applicationSupport: applicationSupport,
                                                   workspaceID: workspaceID,
                                                   fileManager: fileManager) else { return [] }
        let checkpoint = try? store.readCheckpoint()
        return [.init(workspaceID: workspaceID, authorizedUserID: userID, startDate: startDate,
                      lastSuccessfulPollAt: checkpoint?.lastSuccessfulPollAt)]
    }

    func pollScheduled(_ workspace: SlackScheduledWorkspace) async -> SlackScheduledPollResult {
        do {
            let token = try credentialStore.userToken(workspaceID: workspace.workspaceID,
                                                      userID: workspace.authorizedUserID)
            let client = SlackWebAPIClient(token: token, transport: transport)
            let identity = SlackWebAPIClient.Identity(workspaceID: workspace.workspaceID,
                                                      userID: workspace.authorizedUserID)
            let store = try SlackCapturedStore(applicationSupport: applicationSupport,
                                               workspaceID: workspace.workspaceID,
                                               fileManager: fileManager)
            try await poll(client: client, identity: identity, startDate: workspace.startDate, store: store)
            return .success(completedAt: now())
        } catch {
            return .failure(.init(reason: Self.sanitizedReason(error)))
        }
    }

    private func poll(client: SlackWebAPIClient, identity: SlackWebAPIClient.Identity,
                      startDate: Date, store: SlackCapturedStore) async throws {
        try await SlackCapturedPoller(
            workspaceID: identity.workspaceID,
            authorizedUserID: identity.userID,
            startDate: startDate,
            api: client,
            store: store,
            now: now
        ).poll()
    }

    private func isConfirmedAndActive(_ state: ZebraSourceOnboardingState) -> Bool {
        state.progress.sourceConfirmation?.status == .confirmed
            && state.progress.activeSourceID == "slack"
            && state.progress.sourceRows["slack"].map { $0.status != "checked" && $0.status != "skipped" } == true
    }

    private func markPolling(identity: SlackWebAPIClient.Identity, startDate: Date,
                             state: inout ZebraSourceOnboardingState) throws {
        state.sourceReadiness.slack = .init(status: .polling, workspaceID: identity.workspaceID,
                                           authorizedUserID: identity.userID, startDate: startDate,
                                           checkpointExists: state.sourceReadiness.slack?.checkpointExists ?? false,
                                           reason: nil)
        try writeState(state)
    }

    private func markChecked(identity: SlackWebAPIClient.Identity, startDate: Date,
                             state: inout ZebraSourceOnboardingState) throws {
        let date = now()
        state.sourceReadiness.slack = .init(status: .checked, workspaceID: identity.workspaceID,
                                           authorizedUserID: identity.userID, startDate: startDate,
                                           checkpointExists: true, reason: nil)
        var row = state.progress.sourceRows["slack"]
            ?? .init(id: "slack", displayName: "Slack", type: "messages", status: "unchecked")
        row.phase = "complete"; row.status = "checked"; row.selectionState = "confirmed"
        row.playbookID = "slack.captured-polling"; row.playbookVersion = "v1"; row.playbookStepID = "complete"
        row.attentionReason = nil; row.resultSummary = "slack_initial_captured_poll_completed"; row.updatedAt = date
        state.progress.sourceRows["slack"] = row
        let order = state.progress.executionOrder ?? state.progress.normalizedSourceList
        state.progress.activeSourceID = order.drop { $0 != "slack" }.dropFirst().first { id in
            guard let candidate = state.progress.sourceRows[id] else { return false }
            return candidate.status != "checked" && candidate.status != "skipped"
        }
        state.status = state.progress.activeSourceID == nil ? .completed : .ready
        state.updatedAt = date
        try writeState(state)
    }

    private func markAttention(startDate: Date, reason: String) throws {
        var state = try readState()
        let previous = state.sourceReadiness.slack
        state.sourceReadiness.slack = .init(status: .attention, workspaceID: previous?.workspaceID,
                                           authorizedUserID: previous?.authorizedUserID, startDate: startDate,
                                           checkpointExists: previous?.checkpointExists ?? false, reason: reason)
        if var row = state.progress.sourceRows["slack"] {
            row.phase = "poll"; row.status = "attention"; row.playbookStepID = "poll"
            row.attentionReason = reason; row.updatedAt = now(); state.progress.sourceRows["slack"] = row
        }
        state.status = .attention; state.updatedAt = now()
        try writeState(state)
    }

    private func attention(reason: String, startDate: Date, state: ZebraSourceOnboardingState?) -> SlackSourceOnboardingResult {
        result(status: .attention, reason: reason, retryable: Self.isRetryable(reason), identity: state.flatMap {
            guard let workspaceID = $0.sourceReadiness.slack?.workspaceID,
                  let userID = $0.sourceReadiness.slack?.authorizedUserID else { return nil }
            return .init(workspaceID: workspaceID, userID: userID)
        }, startDate: startDate, nextActiveSourceID: state?.progress.activeSourceID)
    }

    private func result(status: SlackSourceOnboardingResult.Status, reason: String?, retryable: Bool,
                        identity: SlackWebAPIClient.Identity?, startDate: Date,
                        nextActiveSourceID: String?) -> SlackSourceOnboardingResult {
        SlackSourceOnboardingResult(ok: status == .checked, sourceID: "slack", status: status,
                                    reason: reason, retryable: retryable,
                                    workspaceID: identity?.workspaceID, authorizedUserID: identity?.userID,
                                    startDate: Self.dateString(startDate), nextActiveSourceID: nextActiveSourceID)
    }

    private func readState() throws -> ZebraSourceOnboardingState {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ZebraSourceOnboardingState.self, from: Data(contentsOf: stateURL))
    }

    private func writeState(_ state: ZebraSourceOnboardingState) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileManager.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        try encoder.encode(state).write(to: stateURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    static func sanitizedReason(_ error: Error) -> String {
        switch error {
        case SlackCapturedError.invalidUserToken: return "user_oauth_token_required"
        case SlackCapturedError.tokenRevoked: return "token_revoked"
        case SlackCapturedError.missingCredential: return "credential_missing"
        case SlackCapturedError.workspaceMismatch: return "workspace_identity_mismatch"
        case SlackCapturedError.partialScope: return "missing_required_scope"
        case SlackCapturedError.writerAlreadyActive: return "poll_already_running"
        case SlackCapturedError.rateLimited: return "slack_rate_limited"
        default: return "slack_poll_failed"
        }
    }

    private static func isRetryable(_ reason: String) -> Bool {
        !["slack_source_not_active", "user_oauth_token_required", "token_revoked",
          "workspace_identity_mismatch"].contains(reason)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
}
