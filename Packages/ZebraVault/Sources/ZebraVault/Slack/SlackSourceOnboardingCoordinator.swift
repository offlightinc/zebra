import Foundation
import SwiftUI

@MainActor
final class SlackSourceOnboardingCoordinator: ObservableObject {
    enum PresentationState: Equatable {
        case idle
        case polling
        case attention(String)
        case checked
    }

    @Published private(set) var presentationState: PresentationState = .idle

    private let stateURL: URL
    private let applicationSupport: URL
    private let credentialStore: any SlackCredentialStoring
    private let transport: any SlackHTTPTransport
    private let fileManager: FileManager
    private var pollTask: Task<Void, Never>?

    init(
        stateURL: URL = ZebraSourceOnboardingState.defaultStateURL(),
        applicationSupport: URL? = nil,
        credentialStore: any SlackCredentialStoring = SlackKeychainCredentialStore(),
        transport: any SlackHTTPTransport = SlackURLSessionTransport(),
        fileManager: FileManager = .default
    ) {
        self.stateURL = stateURL
        self.applicationSupport = applicationSupport ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("zebra", isDirectory: true)
        self.credentialStore = credentialStore
        self.transport = transport
        self.fileManager = fileManager
    }

    deinit { pollTask?.cancel() }

    func begin(token: String, startDate: Date) {
        guard pollTask == nil else {
            presentationState = .attention("poll_already_running")
            return
        }
        guard isSlackConfirmedAndActive() else {
            presentationState = .attention("slack_source_not_active")
            return
        }
        presentationState = .polling
        updateReadiness(status: .polling, startDate: startDate, reason: nil)
        let credentialStore = credentialStore
        let transport = transport
        let stateURL = stateURL
        let applicationSupport = applicationSupport
        let fileManager = fileManager
        pollTask = Task { [weak self] in
            do {
                let client = SlackWebAPIClient(token: token, transport: transport)
                let identity = try await client.authenticatedIdentity()
                let store = try SlackCapturedStore(applicationSupport: applicationSupport, workspaceID: identity.workspaceID, fileManager: fileManager)
                try credentialStore.saveUserToken(token, workspaceID: identity.workspaceID, userID: identity.userID)
                try Self.markReady(stateURL: stateURL, identity: identity, startDate: startDate)
                try await SlackCapturedPoller(
                    workspaceID: identity.workspaceID,
                    authorizedUserID: identity.userID,
                    startDate: startDate,
                    api: client,
                    store: store
                ).poll()
                guard try store.readCheckpoint() != nil else { throw SlackCapturedError.invalidResponse }
                try Self.markChecked(stateURL: stateURL, identity: identity, startDate: startDate)
                self?.presentationState = .checked
            } catch {
                let reason = Self.sanitizedReason(error)
                try? Self.markAttention(stateURL: stateURL, startDate: startDate, reason: reason)
                self?.presentationState = .attention(reason)
            }
            self?.pollTask = nil
        }
    }

    func resume(startDate: Date) {
        guard let readiness = loadState()?.sourceReadiness.slack,
              let workspaceID = readiness.workspaceID,
              let userID = readiness.authorizedUserID,
              let token = try? credentialStore.userToken(workspaceID: workspaceID, userID: userID) else {
            presentationState = .attention("credential_missing")
            updateReadiness(status: .credentialMissing, startDate: startDate, reason: "credential_missing")
            return
        }
        begin(token: token, startDate: startDate)
    }

    func isSlackConfirmedAndActive() -> Bool {
        guard let state = loadState() else { return false }
        return state.progress.sourceConfirmation?.status == .confirmed
            && state.progress.activeSourceID == "slack"
            && state.progress.sourceRows["slack"].map { $0.status != "checked" && $0.status != "skipped" } == true
    }

    private func loadState() -> ZebraSourceOnboardingState? {
        try? Self.readState(at: stateURL)
    }

    private func updateReadiness(status: ZebraSourceOnboardingState.SlackStatus, startDate: Date, reason: String?) {
        guard var state = loadState() else { return }
        state.sourceReadiness.slack = .init(status: status, workspaceID: state.sourceReadiness.slack?.workspaceID,
                                           authorizedUserID: state.sourceReadiness.slack?.authorizedUserID,
                                           startDate: startDate, checkpointExists: state.sourceReadiness.slack?.checkpointExists ?? false,
                                           reason: reason)
        try? Self.writeState(state, to: stateURL)
    }

    private static func markChecked(at date: Date = Date(), stateURL: URL, identity: SlackWebAPIClient.Identity, startDate: Date) throws {
        var state = try readState(at: stateURL)
        state.sourceReadiness.slack = .init(status: .checked, workspaceID: identity.workspaceID,
                                           authorizedUserID: identity.userID, startDate: startDate,
                                           checkpointExists: true, reason: nil)
        var row = state.progress.sourceRows["slack"] ?? .init(id: "slack", displayName: "Slack", type: "messages", status: "unchecked")
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
        try writeState(state, to: stateURL)
    }

    private static func markReady(stateURL: URL, identity: SlackWebAPIClient.Identity, startDate: Date) throws {
        var state = try readState(at: stateURL)
        state.sourceReadiness.slack = .init(status: .readyToPoll, workspaceID: identity.workspaceID,
                                           authorizedUserID: identity.userID, startDate: startDate,
                                           checkpointExists: state.sourceReadiness.slack?.checkpointExists ?? false,
                                           reason: nil)
        try writeState(state, to: stateURL)
    }

    private static func markAttention(stateURL: URL, startDate: Date, reason: String) throws {
        var state = try readState(at: stateURL)
        let previous = state.sourceReadiness.slack
        state.sourceReadiness.slack = .init(status: .attention, workspaceID: previous?.workspaceID,
                                           authorizedUserID: previous?.authorizedUserID, startDate: startDate,
                                           checkpointExists: previous?.checkpointExists ?? false, reason: reason)
        if var row = state.progress.sourceRows["slack"] {
            row.phase = "poll"; row.status = "attention"; row.playbookStepID = "poll"
            row.attentionReason = reason; row.updatedAt = Date(); state.progress.sourceRows["slack"] = row
        }
        state.status = .attention; state.updatedAt = Date()
        try writeState(state, to: stateURL)
    }

    private static func sanitizedReason(_ error: Error) -> String {
        switch error {
        case SlackCapturedError.invalidUserToken: return "user_oauth_token_required"
        case SlackCapturedError.tokenRevoked: return "token_revoked"
        case SlackCapturedError.workspaceMismatch: return "workspace_identity_mismatch"
        case SlackCapturedError.partialScope: return "missing_required_scope"
        case SlackCapturedError.writerAlreadyActive: return "poll_already_running"
        case SlackCapturedError.rateLimited: return "slack_rate_limited"
        default: return "slack_poll_failed"
        }
    }

    private static func readState(at url: URL) throws -> ZebraSourceOnboardingState {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ZebraSourceOnboardingState.self, from: Data(contentsOf: url))
    }

    private static func writeState(_ state: ZebraSourceOnboardingState, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try encoder.encode(state).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
