import Foundation
import SQLite3

public struct ZebraEmailStatus: Equatable, Sendable {
    public let connected: Bool
    public let email: String?
    public let lastSyncedAt: Date?

    public init(connected: Bool, email: String?, lastSyncedAt: Date?) {
        self.connected = connected
        self.email = email
        self.lastSyncedAt = lastSyncedAt
    }
}

public struct ZebraClawvisorStandingTaskProvisioningResult: Equatable, Sendable {
    public let taskId: String

    public init(taskId: String) {
        self.taskId = taskId
    }
}

public enum ZebraClawvisorEmailClientError: LocalizedError, Sendable {
    case notConfigured(String)
    case gateway(String)
    case sqlite(String)
    case malformedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let detail):
            return "Clawvisor Gmail is not configured: \(detail)"
        case .gateway(let detail):
            return "Clawvisor Gmail request failed: \(detail)"
        case .sqlite(let detail):
            return "Local Gmail cache failed: \(detail)"
        case .malformedResponse(let detail):
            return "Clawvisor Gmail response was malformed: \(detail)"
        }
    }

    public var connectionRepairState: ZebraEmailConnectionRepairState? {
        switch self {
        case .notConfigured(let detail):
            return ZebraEmailConnectionRepairState(
                kind: .configurationMissing,
                detail: detail
            )
        case .gateway(let detail):
            return Self.gatewayRepairState(detail: detail)
        case .sqlite, .malformedResponse:
            return nil
        }
    }

    private static func gatewayRepairState(detail: String) -> ZebraEmailConnectionRepairState? {
        let lowercased = detail.lowercased()
        if lowercased.contains("pending_task_approval") ||
            lowercased.contains("pending_approval") ||
            lowercased.contains("pending approval") ||
            lowercased.contains("task is pending") ||
            lowercased.contains("request status=pending") {
            return ZebraEmailConnectionRepairState(
                kind: .taskPendingApproval,
                detail: detail
            )
        }
        if lowercased.contains("unauthorized") ||
            lowercased.contains("forbidden") ||
            lowercased.contains("token_expired") ||
            lowercased.contains("agent token has expired") ||
            lowercased.contains("invalid agent token") ||
            lowercased.contains("401") ||
            lowercased.contains("403") {
            return ZebraEmailConnectionRepairState(
                kind: .authorizationFailed,
                detail: detail
            )
        }
        if lowercased.contains("task_not_found") ||
            lowercased.contains("invalid_task") ||
            lowercased.contains("missing_task") ||
            lowercased.contains("task not found") ||
            (lowercased.contains("task \"") && lowercased.contains("\" not found")) ||
            lowercased.contains("task is revoked") ||
            lowercased.contains("task is denied") ||
            lowercased.contains("denied, not active") ||
            lowercased.contains("task revoked") ||
            lowercased.contains("task_revoked") {
            return ZebraEmailConnectionRepairState(
                kind: .taskUnavailable,
                detail: detail
            )
        }
        if lowercased.contains("task_expired") ||
            (lowercased.contains("task") && lowercased.contains("expired")) {
            return ZebraEmailConnectionRepairState(
                kind: .taskExpired,
                detail: detail
            )
        }
        return nil
    }
}

public actor ZebraClawvisorEmailClient {
    public static let shared = ZebraClawvisorEmailClient()
    private static let initialSyncLookbackDays = 30
    private static let incrementalSyncOverlapDays = 1
    private static let initialSyncMaxResults = 100
    private static let incrementalSyncMaxResults = 50
    private static let missingDateBackfillDelayNanoseconds: UInt64 = 2 * 1_000_000_000

    private let session: URLSession
    private let fileManager: FileManager
    private var database: OpaquePointer?
    private var databaseInitialized = false
    private var cachedConfig: ClawvisorConfig?

    public init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    /// Forces the next config-dependent call to re-read `~/.gbrain/.env`.
    /// Triggered when `ZebraEmailListStore`'s file watcher sees the env
    /// file change — without this the actor keeps using the snapshot it
    /// loaded on the previous call.
    public func invalidateConfig() {
        cachedConfig = nil
    }

    @discardableResult
    public func provisionStandingGmailTask() async throws -> ZebraClawvisorStandingTaskProvisioningResult {
        let config = try loadProvisioningConfig()
        let service = "google.gmail:\(config.accountEmail)"
        let body: [String: Any] = [
            "purpose": "Zebra desktop email client: continuous inbox sync, read message bodies on user open, draft and send replies on user submit, and archive messages on user action.",
            "lifetime": "standing",
            "authorized_actions": [
                [
                    "service": service,
                    "action": "list_messages",
                    "auto_execute": true,
                    "expected_use": "List recent Gmail messages to keep Zebra's inbox sidebar in sync.",
                ],
                [
                    "service": service,
                    "action": "get_message",
                    "auto_execute": true,
                    "expected_use": "Read message bodies when the user opens an email in Zebra.",
                ],
                [
                    "service": service,
                    "action": "get_thread",
                    "auto_execute": true,
                    "expected_use": "Read Gmail thread messages when the user opens a conversation in Zebra.",
                ],
                [
                    "service": service,
                    "action": "get_attachment",
                    "auto_execute": true,
                    "expected_use": "Fetch Gmail attachments when the user opens an attached file in Zebra.",
                ],
                [
                    "service": service,
                    "action": "create_draft",
                    "auto_execute": true,
                    "expected_use": "Create Gmail reply drafts from explicit user actions in Zebra.",
                ],
                [
                    "service": service,
                    "action": "send_message",
                    "auto_execute": true,
                    "expected_use": "Send Gmail messages only after the user explicitly submits them in Zebra.",
                ],
                [
                    "service": service,
                    "action": "archive_message",
                    "auto_execute": true,
                    "expected_use": "Archive Gmail messages when the user triggers archive in Zebra.",
                ],
            ],
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        guard let url = URL(string: config.url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/tasks") else {
            throw ZebraClawvisorEmailClientError.notConfigured("bad CLAWVISOR_URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.agentToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ZebraClawvisorEmailClientError.gateway(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ZebraClawvisorEmailClientError.gateway("non-HTTP response")
        }
        let json = try decodeJSONObject(data)
        guard (200..<300).contains(http.statusCode) else {
            throw ZebraClawvisorEmailClientError.gateway(Self.errorSummary(json, status: http.statusCode))
        }
        guard let taskId = Self.taskId(from: json) else {
            throw ZebraClawvisorEmailClientError.malformedResponse("no task id in task creation response")
        }
        try Self.upsertDotEnv(values: ["CLAWVISOR_GMAIL_TASK_ID": taskId])
        cachedConfig = nil
        return ZebraClawvisorStandingTaskProvisioningResult(taskId: taskId)
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    public func status() async throws -> ZebraEmailStatus {
        let config = try loadConfig()
        return ZebraEmailStatus(
            connected: true,
            email: config.accountEmail,
            lastSyncedAt: try lastSyncedAt()
        )
    }

    @discardableResult
    public func syncRecentInbox() async throws -> Int {
        let config = try loadConfig()
        let previousSync = try lastSyncedAt()
        let afterDate = Self.syncQueryStartDate(lastSyncedAt: previousSync)
        let queryDate = Self.formatGmailQueryDate(afterDate)
        let maxResults = previousSync == nil ? Self.initialSyncMaxResults : Self.incrementalSyncMaxResults
        let response = try await invoke(
            config: config,
            action: "list_messages",
            params: [
                "query": "after:\(queryDate) (in:inbox OR is:important)",
                "max_results": maxResults,
            ],
            reason: "Incrementally pull recent inbox messages from the last Zebra sync window to keep the local email triage view current."
        )
        let messages = try normalizedListMessages(from: response, accountEmail: config.accountEmail)
        try upsertThreads(messages)
        try updateLastSyncedAt(Date())
        startMissingDateBackfill(messages: messages, config: config)
        return messages.count
    }

    public func threads() async throws -> [EmailThreadItem] {
        try openDatabaseIfNeeded()
        return try loadThreads(limit: 200)
    }

    @discardableResult
    public func prefetchRecentMessageBodies(limit: Int = 8) async throws -> Int {
        try openDatabaseIfNeeded()
        let candidates = try loadThreads(limit: limit)
        guard !candidates.isEmpty else { return 0 }

        let config = try loadConfig()
        var fetched = 0
        for thread in candidates {
            let cached = try loadMessages(threadId: thread.id)
            if cached.contains(where: { ($0.bodyText?.isEmpty == false) || ($0.bodyHtml?.isEmpty == false) }) {
                continue
            }
            let rows = try await fetchThreadMessages(config: config, threadId: thread.id)
            guard !rows.isEmpty else { continue }
            try upsertMessages(rows, threadId: thread.id)
            fetched += rows.count
        }
        return fetched
    }

    public func threadMessages(threadId: String, forceRefresh: Bool = false) async throws -> EmailThreadDetail {
        try openDatabaseIfNeeded()
        if !forceRefresh {
            let cached = try loadMessages(threadId: threadId)
            if cached.contains(where: { ($0.bodyText?.isEmpty == false) || ($0.bodyHtml?.isEmpty == false) }) {
                return EmailThreadDetail(
                    threadId: threadId,
                    providerThreadId: try? loadStoredThreadId(forLookupId: threadId),
                    accountEmail: (try? loadConfig().accountEmail).flatMap { $0.isEmpty ? nil : $0 },
                    cached: true,
                    messages: cached
                )
            }
        }

        let config = try loadConfig()
        let rows = try await fetchThreadMessages(config: config, threadId: threadId)
        try upsertMessages(rows, threadId: threadId)
        let saved = try loadMessages(threadId: threadId)
        let providerThreadId: String? = {
            if let candidate = rows.first?.threadId, !candidate.isEmpty {
                return candidate
            }
            return try? loadStoredThreadId(forLookupId: threadId)
        }()
        return EmailThreadDetail(
            threadId: threadId,
            providerThreadId: providerThreadId,
            accountEmail: config.accountEmail.isEmpty ? nil : config.accountEmail,
            cached: false,
            messages: saved
        )
    }

    public func archiveThread(
        threadId: String,
        providerThreadId: String?,
        messageIds: [String]
    ) async throws {
        let config = try loadConfig()
        let normalizedProviderThreadId = providerThreadId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerThreadId = normalizedProviderThreadId?.isEmpty == false ? normalizedProviderThreadId : nil

        // clawvisor 의 archive_message 는 단일 메시지에서 INBOX 라벨만 떼는 멱등
        // 연산이라(thread_id 는 받지 않는다) 스레드 전체를 아카이브하려면 메시지를
        // 하나씩 돌려야 한다. 하나라도 실패하면 즉시 throw 해서 로컬 캐시는 그대로
        // 둔다 — Gmail 은 진짜 롤백이 안 되지만, "전부 성공했을 때만 로컬 캐시 커밋"
        // + 멱등 재시도(이미 아카이브된 메시지는 no-op)로 원격/로컬 상태가 수렴한다.
        let targets = messageIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedPreservingOrder()
        guard !targets.isEmpty else {
            throw ZebraClawvisorEmailClientError.malformedResponse("no messages to archive in thread")
        }

        for messageId in targets {
            _ = try await invoke(
                config: config,
                action: "archive_message",
                params: ["message_id": messageId],
                reason: "Archive the selected Gmail thread after the user pressed Zebra's archive button in the email detail view."
            )
        }

        try removeThreadFromCache(threadId: threadId, providerThreadId: providerThreadId)
    }

    public func emailDrafts(threadId: String) throws -> [EmailDraftSnapshot] {
        try openDatabaseIfNeeded()
        return try loadEmailDrafts(threadId: threadId)
    }

    public func createEmailDraft(_ request: EmailDraftCreateRequest) throws -> EmailDraftSnapshot {
        try openDatabaseIfNeeded()
        return try createEmailDraftRow(request)
    }

    public func updateEmailDraft(
        localDraftId: String,
        baseVersion: Int?,
        patch: EmailDraftPatch,
        origin: EmailDraftOrigin
    ) throws -> EmailDraftSnapshot {
        try openDatabaseIfNeeded()
        return try updateEmailDraftRow(
            localDraftId: localDraftId,
            baseVersion: baseVersion,
            patch: patch,
            origin: origin
        )
    }

    public func discardEmailDraft(localDraftId: String) throws {
        try openDatabaseIfNeeded()
        try execute(
            """
            UPDATE email_drafts
            SET status = ?, sync_state = ?, updated_at = ?
            WHERE local_draft_id = ?
            """,
            [
                EmailDraftStatus.discarded.rawValue,
                EmailDraftSyncState.dirty.rawValue,
                Date().timeIntervalSince1970,
                localDraftId,
            ]
        )
    }

    private func fetchThreadMessages(config: ClawvisorConfig, threadId: String) async throws -> [NormalizedMessage] {
        var lastError: Error?

        do {
            let response = try await invoke(
                config: config,
                action: "get_message",
                params: ["message_id": threadId],
                reason: "Open one selected inbox message from the local email triage list so its contents can be reviewed for the daily digest."
            )
            let messages = normalizedDetailMessages(
                from: response,
                fallbackThreadId: threadId,
                accountEmail: config.accountEmail
            )
            if let providerThreadId = messages.first?.threadId,
               !providerThreadId.isEmpty,
               providerThreadId != threadId,
               let threadMessages = try await fetchWholeThread(
                    config: config,
                    providerThreadId: providerThreadId
               ),
               !threadMessages.isEmpty {
                return threadMessages
            }
            if !messages.isEmpty {
                return messages
            }
        } catch {
            lastError = error
        }

        if let threadMessages = try await fetchWholeThread(config: config, providerThreadId: threadId),
           !threadMessages.isEmpty {
            return threadMessages
        }
        if let lastError {
            throw lastError
        }
        throw ZebraClawvisorEmailClientError.malformedResponse("no messages in thread response")
    }

    private func fetchWholeThread(config: ClawvisorConfig, providerThreadId: String) async throws -> [NormalizedMessage]? {
        do {
            let response = try await invoke(
                config: config,
                action: "get_thread",
                params: ["thread_id": providerThreadId],
                reason: "Open one selected inbox message from the local email triage list so its contents can be reviewed for the daily digest."
            )
            let messages = normalizedDetailMessages(
                from: response,
                fallbackThreadId: providerThreadId,
                accountEmail: config.accountEmail
            )
            return messages.isEmpty ? nil : messages
        } catch {
            return nil
        }
    }

    private func backfillMissingReceivedDates(
        in messages: [NormalizedMessage],
        config: ClawvisorConfig,
        limit: Int = 24
    ) async {
        var fetched = 0
        for message in messages where message.receivedAt == nil {
            guard fetched < limit else { return }
            do {
                if try latestCachedMessageReceivedAt(threadId: message.threadId) != nil {
                    continue
                }
                let rows = try await fetchThreadMessages(config: config, threadId: message.threadId)
                guard !rows.isEmpty else { continue }
                try upsertMessages(rows, threadId: message.threadId)
                fetched += 1
            } catch {
                continue
            }
        }
    }

    private func startMissingDateBackfill(messages: [NormalizedMessage], config: ClawvisorConfig) {
        Task {
            try? await Task.sleep(nanoseconds: Self.missingDateBackfillDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await backfillMissingReceivedDates(in: messages, config: config)
        }
    }

    private func invoke(
        config: ClawvisorConfig,
        action: String,
        params: [String: Any],
        reason: String
    ) async throws -> Any {
        let body: [String: Any] = [
            "task_id": config.taskId,
            "session_id": UUID().uuidString,
            "service": "google.gmail:\(config.accountEmail)",
            "action": action,
            "params": params,
            "reason": reason,
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        guard let url = URL(string: config.url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/gateway/request?wait=true") else {
            throw ZebraClawvisorEmailClientError.notConfigured("bad CLAWVISOR_URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.agentToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ZebraClawvisorEmailClientError.gateway(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ZebraClawvisorEmailClientError.gateway("non-HTTP response")
        }
        let json = try decodeJSONObject(data)
        guard (200..<300).contains(http.statusCode) else {
            throw ZebraClawvisorEmailClientError.gateway(Self.errorSummary(json, status: http.statusCode))
        }
        if let dict = json as? [String: Any],
           let status = dict["status"] as? String,
           status != "executed" {
            throw ZebraClawvisorEmailClientError.gateway("request status=\(status)")
        }
        if let dict = json as? [String: Any],
           let result = dict["result"] {
            return result
        }
        return json
    }

    private func loadConfig() throws -> ClawvisorConfig {
        if let cachedConfig {
            return cachedConfig
        }
        var env = ProcessInfo.processInfo.environment
        for (key, value) in Self.readDotEnv() where env[key]?.isEmpty ?? true {
            env[key] = value
        }
        let url = env["CLAWVISOR_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = env["CLAWVISOR_AGENT_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let taskId = env["CLAWVISOR_GMAIL_TASK_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let accountEmail = env["ZEBRA_CLAWVISOR_GMAIL_ACCOUNT"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "dan@offlight.work"
        guard !url.isEmpty else { throw ZebraClawvisorEmailClientError.notConfigured("missing CLAWVISOR_URL") }
        guard !token.isEmpty else { throw ZebraClawvisorEmailClientError.notConfigured("missing CLAWVISOR_AGENT_TOKEN") }
        guard !taskId.isEmpty else { throw ZebraClawvisorEmailClientError.notConfigured("missing CLAWVISOR_GMAIL_TASK_ID") }
        let config = ClawvisorConfig(url: url, agentToken: token, taskId: taskId, accountEmail: accountEmail)
        cachedConfig = config
        return config
    }

    private func loadProvisioningConfig() throws -> ClawvisorProvisioningConfig {
        var env = ProcessInfo.processInfo.environment
        for (key, value) in Self.readDotEnv() where env[key]?.isEmpty ?? true {
            env[key] = value
        }
        let url = env["CLAWVISOR_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = env["CLAWVISOR_AGENT_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let accountEmail = env["ZEBRA_CLAWVISOR_GMAIL_ACCOUNT"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty else { throw ZebraClawvisorEmailClientError.notConfigured("missing CLAWVISOR_URL") }
        guard !token.isEmpty else { throw ZebraClawvisorEmailClientError.notConfigured("missing CLAWVISOR_AGENT_TOKEN") }
        guard !accountEmail.isEmpty else { throw ZebraClawvisorEmailClientError.notConfigured("missing ZEBRA_CLAWVISOR_GMAIL_ACCOUNT") }
        return ClawvisorProvisioningConfig(url: url, agentToken: token, accountEmail: accountEmail)
    }
}

private extension ZebraClawvisorEmailClient {
    struct ClawvisorConfig: Sendable {
        let url: String
        let agentToken: String
        let taskId: String
        let accountEmail: String
    }

    struct ClawvisorProvisioningConfig: Sendable {
        let url: String
        let agentToken: String
        let accountEmail: String
    }

    struct NormalizedMessage: Sendable {
        let id: String
        let threadId: String
        let internetMessageId: String?
        let subject: String
        let fromName: String?
        let fromEmail: String?
        let to: String?
        let cc: String?
        let receivedAt: Date?
        let snippet: String?
        let labelIds: [String]
        let isUnread: Bool
        let isSent: Bool
        let hasAttachment: Bool
        let bodyText: String?
        let bodyHtml: String?
    }

    static func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    static func formatGmailQueryDate(_ date: Date) -> String {
        makeDateFormatter("yyyy/MM/dd").string(from: date)
    }

    static func syncQueryStartDate(lastSyncedAt: Date?, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        if let lastSyncedAt,
           let overlapped = calendar.date(
                byAdding: .day,
                value: -incrementalSyncOverlapDays,
                to: lastSyncedAt
           ) {
            return overlapped
        }
        return calendar.date(byAdding: .day, value: -initialSyncLookbackDays, to: now) ?? now
    }

    static func parseRFC2822Date(_ value: String) -> Date? {
        makeDateFormatter("EEE, d MMM yyyy HH:mm:ss Z").date(from: value)
    }

    static func emailFallbackFormatters() -> [DateFormatter] {
        [
            "EEE, d MMM yyyy HH:mm:ss ZZZZ",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
        ].map(makeDateFormatter)
    }

    static func readDotEnv() -> [String: String] {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".gbrain/.env")
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || text.hasPrefix("#") { continue }
            if text.hasPrefix("export ") {
                text = String(text.dropFirst("export ".count))
            }
            guard let equals = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(text[text.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    static func upsertDotEnv(values: [String: String]) throws {
        let directory = (NSHomeDirectory() as NSString).appendingPathComponent(".gbrain")
        let path = (directory as NSString).appendingPathComponent(".env")
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let raw = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var remaining = values
        for index in lines.indices {
            guard let key = dotEnvKey(in: lines[index]),
                  let value = remaining[key] else {
                continue
            }
            lines[index] = "\(key)=\(dotEnvValue(value))"
            remaining.removeValue(forKey: key)
        }
        if !remaining.isEmpty, !lines.isEmpty, lines.last?.isEmpty == false {
            lines.append("")
        }
        for key in remaining.keys.sorted() {
            lines.append("\(key)=\(dotEnvValue(remaining[key] ?? ""))")
        }
        let output = lines.joined(separator: "\n") + "\n"
        try output.write(toFile: path, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    static func dotEnvKey(in line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.hasPrefix("#") else { return nil }
        if text.hasPrefix("export ") {
            text = String(text.dropFirst("export ".count))
        }
        guard let equals = text.firstIndex(of: "=") else { return nil }
        let key = String(text[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    static func dotEnvValue(_ value: String) -> String {
        let safeCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.@:/")
        if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        return "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    func decodeJSONObject(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            let sample = String(String(data: data, encoding: .utf8)?.prefix(200) ?? "")
            throw ZebraClawvisorEmailClientError.malformedResponse("invalid JSON: \(sample)")
        }
    }

    static func errorSummary(_ json: Any, status: Int) -> String {
        if let dict = json as? [String: Any] {
            let code = dict["code"] as? String ?? ""
            let error = dict["error"] as? String ?? ""
            let message = dict["message"] as? String ?? ""
            return "HTTP \(status) \(code) \(error) \(message)".trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "HTTP \(status)"
    }

    static func taskId(from json: Any) -> String? {
        guard let dict = json as? [String: Any] else { return nil }
        for key in ["task_id", "id"] {
            if let value = dict[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        for key in ["task", "data", "result"] {
            if let nested = dict[key] as? [String: Any],
               let value = taskId(from: nested) {
                return value
            }
        }
        return nil
    }

    func normalizedListMessages(from response: Any, accountEmail: String) throws -> [NormalizedMessage] {
        let items = messageArrayCandidates(from: response)
        return items.compactMap { normalizedMessage(from: $0, fallbackThreadId: nil, accountEmail: accountEmail) }
    }

    func normalizedDetailMessages(from response: Any, fallbackThreadId: String, accountEmail: String) -> [NormalizedMessage] {
        let items = messageArrayCandidates(from: response)
        if !items.isEmpty {
            return items.compactMap { normalizedMessage(from: $0, fallbackThreadId: fallbackThreadId, accountEmail: accountEmail) }
        }
        if let dict = response as? [String: Any],
           let message = normalizedMessage(from: dict, fallbackThreadId: fallbackThreadId, accountEmail: accountEmail) {
            return [message]
        }
        return []
    }

    func messageArrayCandidates(from response: Any) -> [[String: Any]] {
        if let array = response as? [[String: Any]] { return array }
        guard let dict = response as? [String: Any] else { return [] }
        if let messages = dict["messages"] as? [[String: Any]] { return messages }
        if let items = dict["items"] as? [[String: Any]] { return items }
        if let message = dict["message"] as? [String: Any] { return [message] }
        if let data = dict["data"] {
            if let messages = messageArrayCandidates(from: data).nilIfEmpty { return messages }
            if let dataDict = data as? [String: Any] {
                if let message = dataDict["message"] as? [String: Any] { return [message] }
                if stringValue(dataDict["id"]) != nil || stringValue(dataDict["message_id"]) != nil {
                    return [dataDict]
                }
            }
        }
        return []
    }

    func normalizedMessage(
        from raw: [String: Any],
        fallbackThreadId: String?,
        accountEmail: String
    ) -> NormalizedMessage? {
        let headers = headerMap(raw["payload"].flatMap { ($0 as? [String: Any])?["headers"] } ?? raw["headers"])
        let id = stringValue(raw["id"])
            ?? stringValue(raw["message_id"])
            ?? stringValue(raw["messageId"])
            ?? stringValue(headers["message-id"])
        guard let messageId = id, !messageId.isEmpty else { return nil }
        let threadId = stringValue(raw["threadId"])
            ?? stringValue(raw["thread_id"])
            ?? fallbackThreadId
            ?? messageId
        let fromRaw = stringValue(raw["from"]) ?? headers["from"] ?? ""
        let sender = parseSender(fromRaw)
        let labelIds = stringArray(raw["labels"]) ?? stringArray(raw["labelIds"]) ?? []
        let dateValue = stringValue(raw["timestamp"])
            ?? stringValue(raw["date"])
            ?? headers["date"]
            ?? stringValue(raw["internalDate"])
        let bodies = extractBodies(from: raw)
        return NormalizedMessage(
            id: messageId,
            threadId: threadId,
            internetMessageId: headers["message-id"],
            subject: stringValue(raw["subject"]) ?? headers["subject"] ?? "(no subject)",
            fromName: sender.name.nilIfEmpty,
            fromEmail: sender.email,
            to: stringValue(raw["to"]) ?? headers["to"],
            cc: stringValue(raw["cc"]) ?? headers["cc"],
            receivedAt: parseDate(dateValue),
            snippet: stringValue(raw["snippet"])?.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression),
            labelIds: labelIds,
            isUnread: boolValue(raw["is_unread"]) ?? boolValue(raw["isUnread"]) ?? labelIds.contains("UNREAD"),
            isSent: boolValue(raw["is_sent"]) ?? boolValue(raw["isSent"]) ?? labelIds.contains("SENT"),
            hasAttachment: boolValue(raw["has_attachment"]) ?? boolValue(raw["hasAttachment"]) ?? payloadHasAttachment(raw["payload"]),
            bodyText: bodies.text,
            bodyHtml: bodies.html
        )
    }

    func headerMap(_ value: Any?) -> [String: String] {
        guard let array = value as? [[String: Any]] else { return [:] }
        var result: [String: String] = [:]
        for header in array {
            guard let name = stringValue(header["name"])?.lowercased(),
                  let value = stringValue(header["value"]) else { continue }
            result[name] = value
        }
        return result
    }

    func extractBodies(from raw: [String: Any]) -> (text: String?, html: String?) {
        let directText = stringValue(raw["bodyText"])
            ?? stringValue(raw["body_text"])
            ?? stringValue(raw["body"])
            ?? stringValue(raw["text"])
            ?? stringValue(raw["plain"])
        let directHtml = stringValue(raw["bodyHtml"])
            ?? stringValue(raw["body_html"])
            ?? stringValue(raw["html"])
        if directText?.isEmpty == false || directHtml?.isEmpty == false {
            return (directText, directHtml)
        }
        return extractBodiesFromPayload(raw["payload"])
    }

    func extractBodiesFromPayload(_ payload: Any?) -> (text: String?, html: String?) {
        var textParts: [String] = []
        var htmlParts: [String] = []
        func visit(_ part: Any?) {
            guard let dict = part as? [String: Any] else { return }
            let mimeType = stringValue(dict["mimeType"])?.lowercased() ?? ""
            if let body = dict["body"] as? [String: Any],
               let data = stringValue(body["data"]),
               let decoded = Self.decodeBase64URL(data),
               !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if mimeType == "text/plain" {
                    textParts.append(decoded)
                } else if mimeType == "text/html" {
                    htmlParts.append(decoded)
                }
            }
            if let parts = dict["parts"] as? [Any] {
                for child in parts { visit(child) }
            }
        }
        visit(payload)
        let html = htmlParts.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        let text = textParts.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? html.map(Self.htmlToPlainText)
        return (text, html)
    }

    func payloadHasAttachment(_ payload: Any?) -> Bool {
        guard let dict = payload as? [String: Any] else { return false }
        if let filename = stringValue(dict["filename"]), !filename.isEmpty { return true }
        if let body = dict["body"] as? [String: Any],
           stringValue(body["attachmentId"]) != nil,
           !(stringValue(dict["mimeType"])?.lowercased().hasPrefix("text/") ?? false) {
            return true
        }
        if let parts = dict["parts"] as? [Any] {
            return parts.contains { payloadHasAttachment($0) }
        }
        return false
    }

    static func decodeBase64URL(_ value: String) -> String? {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: normalized) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func htmlToPlainText(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<script\b[\s\S]*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<style\b[\s\S]*?</style>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"</(p|div|li|tr|h[1-6])>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    func parseSender(_ value: String) -> (name: String, email: String?) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.lastIndex(of: "<"),
              let end = trimmed.lastIndex(of: ">"),
              start < end else {
            return (trimmed.contains("@") ? String(trimmed.split(separator: "@").first ?? "") : trimmed, trimmed.contains("@") ? trimmed : nil)
        }
        let name = String(trimmed[..<start]).trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        let email = String(trimmed[trimmed.index(after: start)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, email.isEmpty ? nil : email)
    }

    func parseDate(_ value: String?) -> Date? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let candidates = [
            raw,
            raw.replacingOccurrences(
                of: #"\s+\([^)]*\)$"#,
                with: "",
                options: .regularExpression
            ),
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        for candidate in candidates {
            if let date = parseDateCandidate(candidate) {
                return date
            }
        }
        return nil
    }

    func parseDateCandidate(_ raw: String) -> Date? {
        if let millis = Double(raw), millis > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: millis / 1000)
        }
        if let seconds = Double(raw), seconds > 1_000_000_000 {
            return Date(timeIntervalSince1970: seconds)
        }
        if let date = ISO8601DateFormatter().date(from: raw) {
            return date
        }
        if let date = Self.parseRFC2822Date(raw) {
            return date
        }
        return Self.emailFallbackFormatters().lazy.compactMap { $0.date(from: raw) }.first
    }

    func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            let normalized = value.lowercased()
            if ["1", "true", "yes"].contains(normalized) { return true }
            if ["0", "false", "no"].contains(normalized) { return false }
            return nil
        default:
            return nil
        }
    }

    func stringArray(_ value: Any?) -> [String]? {
        if let array = value as? [String] {
            return array
        }
        if let array = value as? [Any] {
            return array.compactMap(stringValue)
        }
        return nil
    }
}

private extension ZebraClawvisorEmailClient {
    func databaseURL() throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Zebra", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("email.sqlite")
    }

    func openDatabaseIfNeeded() throws {
        if database != nil, databaseInitialized { return }
        if database == nil {
            let url = try databaseURL()
            var db: OpaquePointer?
            let result = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
            guard result == SQLITE_OK, let opened = db else {
                let message = sqliteMessage(db) ?? "open failed with code \(result)"
                sqlite3_close(db)
                throw ZebraClawvisorEmailClientError.sqlite(message)
            }
            database = opened
        }
        do {
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA foreign_keys=ON")
            try execute("""
            CREATE TABLE IF NOT EXISTS email_threads (
              thread_id TEXT PRIMARY KEY,
              latest_message_id TEXT NOT NULL,
              subject TEXT NOT NULL,
              sender_name TEXT NOT NULL,
              sender_email TEXT,
              received_at REAL NOT NULL,
              snippet TEXT,
              label_ids_json TEXT NOT NULL,
              has_attachment INTEGER NOT NULL DEFAULT 0,
              updated_at REAL NOT NULL
            )
            """)
            try execute("""
            CREATE TABLE IF NOT EXISTS email_messages (
              message_id TEXT PRIMARY KEY,
              thread_id TEXT NOT NULL,
              internet_message_id TEXT,
              subject TEXT,
              from_name TEXT,
              from_email TEXT,
              to_recipients TEXT,
              cc_recipients TEXT,
              received_at REAL,
              snippet TEXT,
              label_ids_json TEXT NOT NULL,
              is_unread INTEGER NOT NULL DEFAULT 0,
              is_sent INTEGER NOT NULL DEFAULT 0,
              has_attachment INTEGER NOT NULL DEFAULT 0,
              body_text TEXT,
              body_html TEXT,
              body_fetched_at REAL NOT NULL,
              updated_at REAL NOT NULL
            )
            """)
            try execute("""
            CREATE TABLE IF NOT EXISTS email_sync_state (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL,
              updated_at REAL NOT NULL
            )
            """)
            try execute("""
            CREATE TABLE IF NOT EXISTS email_drafts (
              local_draft_id TEXT PRIMARY KEY,
              thread_id TEXT NOT NULL,
              provider_thread_id TEXT,
              target_message_id TEXT,
              provider_draft_id TEXT,
              provider_message_id TEXT,
              account_email TEXT,
              mode TEXT NOT NULL,
              display_name TEXT NOT NULL,
              origin TEXT NOT NULL,
              status TEXT NOT NULL,
              sync_state TEXT NOT NULL,
              version INTEGER NOT NULL,
              to_recipients_json TEXT NOT NULL,
              cc_recipients_json TEXT NOT NULL,
              bcc_recipients_json TEXT NOT NULL,
              subject TEXT NOT NULL,
              body_html TEXT NOT NULL,
              body_text TEXT NOT NULL,
              in_reply_to_header TEXT,
              references_header TEXT,
              last_error TEXT,
              created_at REAL NOT NULL,
              updated_at REAL NOT NULL,
              synced_at REAL,
              sent_at REAL
            )
            """)
            try execute("CREATE INDEX IF NOT EXISTS email_threads_received_idx ON email_threads(received_at DESC)")
            try execute("CREATE INDEX IF NOT EXISTS email_messages_thread_received_idx ON email_messages(thread_id, received_at)")
            try execute("CREATE INDEX IF NOT EXISTS email_drafts_thread_updated_idx ON email_drafts(thread_id, updated_at DESC)")
            try execute("CREATE INDEX IF NOT EXISTS email_drafts_provider_draft_idx ON email_drafts(provider_draft_id)")
            try execute("CREATE INDEX IF NOT EXISTS email_drafts_target_message_idx ON email_drafts(target_message_id)")
            try execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS email_drafts_one_active_per_target_idx
            ON email_drafts(thread_id, target_message_id)
            WHERE status = 'active' AND target_message_id IS NOT NULL
            """)
            try repairThreadSummaryDatesFromMessages()
            databaseInitialized = true
        } catch {
            if let database {
                sqlite3_close(database)
            }
            database = nil
            databaseInitialized = false
            throw error
        }
    }

    func lastSyncedAt() throws -> Date? {
        try openDatabaseIfNeeded()
        return try queryDouble("SELECT CAST(value AS REAL) FROM email_sync_state WHERE key = 'last_synced_at' LIMIT 1")
            .map(Date.init(timeIntervalSince1970:))
    }

    func updateLastSyncedAt(_ date: Date) throws {
        try openDatabaseIfNeeded()
        try execute(
            "INSERT INTO email_sync_state(key, value, updated_at) VALUES('last_synced_at', ?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
            [date.timeIntervalSince1970, Date().timeIntervalSince1970]
        )
    }

    func upsertThreads(_ messages: [NormalizedMessage]) throws {
        try openDatabaseIfNeeded()
        try execute("BEGIN IMMEDIATE")
        do {
            for message in messages {
                try execute(
                    """
                    INSERT INTO email_threads(
                      thread_id, latest_message_id, subject, sender_name, sender_email,
                      received_at, snippet, label_ids_json, has_attachment, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(thread_id) DO UPDATE SET
                      latest_message_id=excluded.latest_message_id,
                      subject=excluded.subject,
                      sender_name=excluded.sender_name,
                      sender_email=excluded.sender_email,
                      received_at=excluded.received_at,
                      snippet=excluded.snippet,
                      label_ids_json=excluded.label_ids_json,
                      has_attachment=excluded.has_attachment,
                      updated_at=excluded.updated_at
                    """,
                    [
                        message.threadId,
                        message.id,
                        message.subject,
                        message.fromName ?? message.fromEmail ?? "",
                        message.fromEmail as Any,
                        try threadSummaryReceivedAt(for: message).timeIntervalSince1970,
                        message.snippet as Any,
                        jsonString(message.labelIds),
                        message.hasAttachment ? 1 : 0,
                        Date().timeIntervalSince1970,
                    ]
                )
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func upsertMessages(_ messages: [NormalizedMessage], threadId: String) throws {
        try openDatabaseIfNeeded()
        try execute("BEGIN IMMEDIATE")
        do {
            try upsertThreadSummary(messages, storageThreadId: threadId)
            for message in messages {
                try execute(
                    """
                    INSERT INTO email_messages(
                      message_id, thread_id, internet_message_id, subject, from_name, from_email,
                      to_recipients, cc_recipients, received_at, snippet, label_ids_json,
                      is_unread, is_sent, has_attachment, body_text, body_html, body_fetched_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(message_id) DO UPDATE SET
                      thread_id=excluded.thread_id,
                      internet_message_id=excluded.internet_message_id,
                      subject=excluded.subject,
                      from_name=excluded.from_name,
                      from_email=excluded.from_email,
                      to_recipients=excluded.to_recipients,
                      cc_recipients=excluded.cc_recipients,
                      received_at=excluded.received_at,
                      snippet=excluded.snippet,
                      label_ids_json=excluded.label_ids_json,
                      is_unread=excluded.is_unread,
                      is_sent=excluded.is_sent,
                      has_attachment=excluded.has_attachment,
                      body_text=excluded.body_text,
                      body_html=excluded.body_html,
                      body_fetched_at=excluded.body_fetched_at,
                      updated_at=excluded.updated_at
                    """,
                    [
                        message.id,
                        message.threadId,
                        message.internetMessageId as Any,
                        message.subject,
                        message.fromName as Any,
                        message.fromEmail as Any,
                        message.to as Any,
                        message.cc as Any,
                        message.receivedAt?.timeIntervalSince1970 as Any,
                        message.snippet as Any,
                        jsonString(message.labelIds),
                        message.isUnread ? 1 : 0,
                        message.isSent ? 1 : 0,
                        message.hasAttachment ? 1 : 0,
                        message.bodyText as Any,
                        message.bodyHtml as Any,
                        Date().timeIntervalSince1970,
                        Date().timeIntervalSince1970,
                    ]
                )
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
        if messages.isEmpty {
            _ = threadId
        }
    }

    func upsertThreadSummary(_ messages: [NormalizedMessage], storageThreadId: String) throws {
        guard let latest = messages.max(by: { ($0.receivedAt ?? .distantPast) < ($1.receivedAt ?? .distantPast) }) else { return }
        let labelIds = Array(Set(messages.flatMap(\.labelIds))).sorted()
        try execute(
            """
            INSERT INTO email_threads(
              thread_id, latest_message_id, subject, sender_name, sender_email,
              received_at, snippet, label_ids_json, has_attachment, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(thread_id) DO UPDATE SET
              latest_message_id=excluded.latest_message_id,
              subject=excluded.subject,
              sender_name=excluded.sender_name,
              sender_email=excluded.sender_email,
              received_at=excluded.received_at,
              snippet=excluded.snippet,
              label_ids_json=excluded.label_ids_json,
              has_attachment=excluded.has_attachment,
              updated_at=excluded.updated_at
            """,
            [
                storageThreadId,
                latest.id,
                latest.subject,
                latest.fromName ?? latest.fromEmail ?? "",
                latest.fromEmail as Any,
                try threadSummaryReceivedAt(for: latest, storageThreadId: storageThreadId).timeIntervalSince1970,
                latest.snippet as Any,
                jsonString(labelIds),
                messages.contains(where: \.hasAttachment) ? 1 : 0,
                Date().timeIntervalSince1970,
            ]
        )
    }

    func loadThreads(limit: Int) throws -> [EmailThreadItem] {
        try openDatabaseIfNeeded()
        var rows: [EmailThreadItem] = []
        try query("""
        SELECT thread_id, subject, sender_name, received_at, label_ids_json, has_attachment
        FROM email_threads
        ORDER BY received_at DESC
        LIMIT ?
        """, [limit]) { stmt in
            let labelIds = jsonStringArray(sqliteText(stmt, 4) ?? "[]")
            rows.append(EmailThreadItem(
                id: sqliteText(stmt, 0) ?? "",
                subject: sqliteText(stmt, 1) ?? "(no subject)",
                senderName: sqliteText(stmt, 2) ?? "",
                receivedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                unread: labelIds.contains("UNREAD"),
                starred: labelIds.contains("STARRED"),
                hasAttachment: sqlite3_column_int(stmt, 5) != 0,
                labelIds: labelIds,
                category: category(from: labelIds)
            ))
        }
        return rows
    }

    func removeThreadFromCache(threadId: String, providerThreadId: String?) throws {
        try openDatabaseIfNeeded()
        let lookupIds = ([threadId, providerThreadId].compactMap { $0 })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedPreservingOrder()
        guard !lookupIds.isEmpty else { return }

        var storageThreadIds = Set(lookupIds)
        for lookupId in lookupIds {
            try query("""
            SELECT thread_id
            FROM email_messages
            WHERE thread_id = ? OR message_id = ?
            """, [lookupId, lookupId]) { stmt in
                if let value = sqliteText(stmt, 0), !value.isEmpty {
                    storageThreadIds.insert(value)
                }
            }
        }

        try execute("BEGIN IMMEDIATE")
        do {
            for id in storageThreadIds {
                try execute("DELETE FROM email_threads WHERE thread_id = ?", [id])
                try execute("DELETE FROM email_messages WHERE thread_id = ? OR message_id = ?", [id, id])
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func threadSummaryReceivedAt(for message: NormalizedMessage, storageThreadId: String? = nil) throws -> Date {
        if let receivedAt = message.receivedAt {
            return receivedAt
        }

        let threadIds = Array(Set([storageThreadId, message.threadId].compactMap { $0 }))
        for threadId in threadIds {
            if let cachedMessageDate = try latestCachedMessageReceivedAt(threadId: threadId) {
                return cachedMessageDate
            }
            if let existingThreadDate = try existingThreadReceivedAt(threadId: threadId) {
                return existingThreadDate
            }
        }

        return Date()
    }

    func latestCachedMessageReceivedAt(threadId: String) throws -> Date? {
        try queryDouble(
            """
            SELECT MAX(received_at)
            FROM email_messages
            WHERE thread_id = ?
              AND received_at IS NOT NULL
            """,
            [threadId]
        )
        .map(Date.init(timeIntervalSince1970:))
    }

    func existingThreadReceivedAt(threadId: String) throws -> Date? {
        try queryDouble(
            """
            SELECT received_at
            FROM email_threads
            WHERE thread_id = ?
            LIMIT 1
            """,
            [threadId]
        )
        .map(Date.init(timeIntervalSince1970:))
    }

    func repairThreadSummaryDatesFromMessages() throws {
        try execute(
            """
            UPDATE email_threads
            SET received_at = (
              SELECT MAX(email_messages.received_at)
              FROM email_messages
              WHERE email_messages.thread_id = email_threads.thread_id
                AND email_messages.received_at IS NOT NULL
            )
            WHERE ABS(received_at - updated_at) < 2
              AND EXISTS (
                SELECT 1
                FROM email_messages
                WHERE email_messages.thread_id = email_threads.thread_id
                  AND email_messages.received_at IS NOT NULL
              )
              AND ABS(received_at - (
                SELECT MAX(email_messages.received_at)
                FROM email_messages
                WHERE email_messages.thread_id = email_threads.thread_id
                  AND email_messages.received_at IS NOT NULL
              )) > 60
            """
        )
    }

    func loadStoredThreadId(forLookupId lookupId: String) throws -> String? {
        try openDatabaseIfNeeded()
        var found: String?
        try query("""
        SELECT thread_id FROM email_messages
        WHERE thread_id = ? OR message_id = ?
        LIMIT 1
        """, [lookupId, lookupId]) { stmt in
            if found == nil {
                found = sqliteText(stmt, 0)
            }
        }
        if let value = found, !value.isEmpty {
            return value
        }
        return nil
    }

    func loadMessages(threadId: String) throws -> [EmailThreadMessage] {
        try openDatabaseIfNeeded()
        var rows: [EmailThreadMessage] = []
        try query("""
        SELECT message_id, internet_message_id, subject, from_name, from_email,
               to_recipients, cc_recipients, received_at, snippet, label_ids_json,
               is_unread, is_sent, has_attachment, body_text, body_html
        FROM email_messages
        WHERE thread_id = ?
           OR thread_id IN (SELECT thread_id FROM email_messages WHERE message_id = ?)
        ORDER BY received_at ASC, message_id ASC
        """, [threadId, threadId]) { stmt in
            rows.append(EmailThreadMessage(
                id: sqliteText(stmt, 0) ?? "",
                internetMessageId: sqliteText(stmt, 1),
                subject: sqliteText(stmt, 2),
                fromName: sqliteText(stmt, 3),
                fromEmail: sqliteText(stmt, 4),
                to: sqliteText(stmt, 5),
                cc: sqliteText(stmt, 6),
                receivedAt: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                snippet: sqliteText(stmt, 8),
                labelIds: jsonStringArray(sqliteText(stmt, 9) ?? "[]"),
                isUnread: sqlite3_column_int(stmt, 10) != 0,
                isSent: sqlite3_column_int(stmt, 11) != 0,
                hasAttachment: sqlite3_column_int(stmt, 12) != 0,
                bodyText: sqliteText(stmt, 13),
                bodyHtml: sqliteText(stmt, 14)
            ))
        }
        return rows
    }

    func loadEmailDrafts(threadId: String) throws -> [EmailDraftSnapshot] {
        var rows: [EmailDraftSnapshot] = []
        try query("""
        SELECT local_draft_id, thread_id, provider_thread_id, target_message_id,
               provider_draft_id, provider_message_id, account_email, mode,
               display_name, origin, status, sync_state, version,
               to_recipients_json, cc_recipients_json, bcc_recipients_json,
               subject, body_html, body_text, in_reply_to_header,
               references_header, last_error, created_at, updated_at, synced_at, sent_at
        FROM email_drafts
        WHERE thread_id = ? AND status = ?
        ORDER BY created_at ASC, local_draft_id ASC
        """, [threadId, EmailDraftStatus.active.rawValue]) { stmt in
            rows.append(emailDraftSnapshot(from: stmt))
        }
        return rows
    }

    func createEmailDraftRow(_ request: EmailDraftCreateRequest) throws -> EmailDraftSnapshot {
        if let targetMessageId = request.targetMessageId, !targetMessageId.isEmpty,
           let existing = try loadActiveEmailDraft(threadId: request.threadId, targetMessageId: targetMessageId) {
            return existing
        }

        let existingCount = try queryDouble(
            "SELECT COUNT(*) FROM email_drafts WHERE thread_id = ?",
            [request.threadId]
        ) ?? 0
        let localDraftId = "draft_\(UUID().uuidString.lowercased())"
        let displayName = "Draft \(Int(existingCount) + 1)"
        let now = Date().timeIntervalSince1970
        let bodyHtml = htmlFromPlainText(request.bodyText)

        try execute(
            """
            INSERT INTO email_drafts(
              local_draft_id, thread_id, provider_thread_id, target_message_id,
              provider_draft_id, provider_message_id, account_email, mode,
              display_name, origin, status, sync_state, version,
              to_recipients_json, cc_recipients_json, bcc_recipients_json,
              subject, body_html, body_text, in_reply_to_header,
              references_header, last_error, created_at, updated_at, synced_at, sent_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                localDraftId,
                request.threadId,
                sqliteNullable(request.providerThreadId),
                sqliteNullable(request.targetMessageId),
                NSNull(),
                NSNull(),
                sqliteNullable(request.accountEmail),
                request.mode.rawValue,
                displayName,
                request.origin.rawValue,
                EmailDraftStatus.active.rawValue,
                EmailDraftSyncState.localOnly.rawValue,
                1,
                jsonString(request.toRecipients),
                jsonString(request.ccRecipients),
                jsonString(request.bccRecipients),
                request.subject,
                bodyHtml,
                request.bodyText,
                sqliteNullable(request.inReplyToHeader),
                sqliteNullable(request.referencesHeader),
                NSNull(),
                now,
                now,
                NSNull(),
                NSNull(),
            ]
        )

        guard let created = try loadEmailDraft(localDraftId: localDraftId) else {
            throw ZebraClawvisorEmailClientError.sqlite("email draft insert did not return a row")
        }
        return created
    }

    func updateEmailDraftRow(
        localDraftId: String,
        baseVersion: Int?,
        patch: EmailDraftPatch,
        origin: EmailDraftOrigin
    ) throws -> EmailDraftSnapshot {
        guard let current = try loadEmailDraft(localDraftId: localDraftId) else {
            throw ZebraClawvisorEmailClientError.sqlite("email draft not found")
        }
        guard current.status == .active else {
            throw ZebraClawvisorEmailClientError.sqlite("email draft is not active")
        }
        if let baseVersion, baseVersion != current.version {
            throw ZebraClawvisorEmailClientError.sqlite("email draft version conflict")
        }
        guard let bodyText = patch.bodyText else {
            return current
        }

        try execute(
            """
            UPDATE email_drafts
            SET origin = ?,
                sync_state = ?,
                version = version + 1,
                body_html = ?,
                body_text = ?,
                last_error = NULL,
                updated_at = ?
            WHERE local_draft_id = ? AND status = ?
            """,
            [
                origin.rawValue,
                EmailDraftSyncState.dirty.rawValue,
                htmlFromPlainText(bodyText),
                bodyText,
                Date().timeIntervalSince1970,
                localDraftId,
                EmailDraftStatus.active.rawValue,
            ]
        )

        guard let updated = try loadEmailDraft(localDraftId: localDraftId) else {
            throw ZebraClawvisorEmailClientError.sqlite("email draft update did not return a row")
        }
        return updated
    }

    func loadActiveEmailDraft(threadId: String, targetMessageId: String) throws -> EmailDraftSnapshot? {
        var row: EmailDraftSnapshot?
        try query("""
        SELECT local_draft_id, thread_id, provider_thread_id, target_message_id,
               provider_draft_id, provider_message_id, account_email, mode,
               display_name, origin, status, sync_state, version,
               to_recipients_json, cc_recipients_json, bcc_recipients_json,
               subject, body_html, body_text, in_reply_to_header,
               references_header, last_error, created_at, updated_at, synced_at, sent_at
        FROM email_drafts
        WHERE thread_id = ? AND target_message_id = ? AND status = ?
        LIMIT 1
        """, [threadId, targetMessageId, EmailDraftStatus.active.rawValue]) { stmt in
            if row == nil {
                row = emailDraftSnapshot(from: stmt)
            }
        }
        return row
    }

    func loadEmailDraft(localDraftId: String) throws -> EmailDraftSnapshot? {
        var row: EmailDraftSnapshot?
        try query("""
        SELECT local_draft_id, thread_id, provider_thread_id, target_message_id,
               provider_draft_id, provider_message_id, account_email, mode,
               display_name, origin, status, sync_state, version,
               to_recipients_json, cc_recipients_json, bcc_recipients_json,
               subject, body_html, body_text, in_reply_to_header,
               references_header, last_error, created_at, updated_at, synced_at, sent_at
        FROM email_drafts
        WHERE local_draft_id = ?
        LIMIT 1
        """, [localDraftId]) { stmt in
            if row == nil {
                row = emailDraftSnapshot(from: stmt)
            }
        }
        return row
    }

    func emailDraftSnapshot(from stmt: OpaquePointer) -> EmailDraftSnapshot {
        EmailDraftSnapshot(
            localDraftId: sqliteText(stmt, 0) ?? "",
            threadId: sqliteText(stmt, 1) ?? "",
            providerThreadId: sqliteText(stmt, 2),
            targetMessageId: sqliteText(stmt, 3),
            providerDraftId: sqliteText(stmt, 4),
            providerMessageId: sqliteText(stmt, 5),
            accountEmail: sqliteText(stmt, 6),
            mode: EmailDraftMode(rawValue: sqliteText(stmt, 7) ?? "") ?? .reply,
            displayName: sqliteText(stmt, 8) ?? "",
            origin: EmailDraftOrigin(rawValue: sqliteText(stmt, 9) ?? "") ?? .user,
            status: EmailDraftStatus(rawValue: sqliteText(stmt, 10) ?? "") ?? .active,
            syncState: EmailDraftSyncState(rawValue: sqliteText(stmt, 11) ?? "") ?? .localOnly,
            version: Int(sqlite3_column_int64(stmt, 12)),
            toRecipients: jsonStringArray(sqliteText(stmt, 13) ?? "[]"),
            ccRecipients: jsonStringArray(sqliteText(stmt, 14) ?? "[]"),
            bccRecipients: jsonStringArray(sqliteText(stmt, 15) ?? "[]"),
            subject: sqliteText(stmt, 16) ?? "",
            bodyHtml: sqliteText(stmt, 17) ?? "",
            bodyText: sqliteText(stmt, 18) ?? "",
            inReplyToHeader: sqliteText(stmt, 19),
            referencesHeader: sqliteText(stmt, 20),
            lastError: sqliteText(stmt, 21),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 22)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 23)),
            syncedAt: sqlite3_column_type(stmt, 24) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 24)),
            sentAt: sqlite3_column_type(stmt, 25) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 25))
        )
    }

    func category(from labels: [String]) -> EmailCategory? {
        if labels.contains("CATEGORY_UPDATES") { return .updates }
        if labels.contains("CATEGORY_PROMOTIONS") { return .promotions }
        if labels.contains("CATEGORY_SOCIAL") { return .social }
        if labels.contains("CATEGORY_FORUMS") { return .forums }
        if labels.contains("CATEGORY_PURCHASES") { return .purchases }
        if labels.contains("INBOX") { return .primary }
        return nil
    }

    func execute(_ sql: String, _ bindings: [Any] = []) throws {
        guard let database else { throw ZebraClawvisorEmailClientError.sqlite("database not open") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            sqlite3_finalize(stmt)
            throw ZebraClawvisorEmailClientError.sqlite(sqliteMessage(database) ?? "prepare failed")
        }
        defer { sqlite3_finalize(stmt) }
        try bind(bindings, to: stmt)
        while true {
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE {
                return
            }
            if result != SQLITE_ROW {
                throw ZebraClawvisorEmailClientError.sqlite(sqliteMessage(database) ?? "execute failed")
            }
        }
    }

    func query(_ sql: String, _ bindings: [Any] = [], row: (OpaquePointer) throws -> Void) throws {
        guard let database else { throw ZebraClawvisorEmailClientError.sqlite("database not open") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            sqlite3_finalize(stmt)
            throw ZebraClawvisorEmailClientError.sqlite(sqliteMessage(database) ?? "prepare failed")
        }
        defer { sqlite3_finalize(stmt) }
        try bind(bindings, to: stmt)
        while true {
            let result = sqlite3_step(stmt)
            if result == SQLITE_ROW {
                try row(stmt)
            } else if result == SQLITE_DONE {
                break
            } else {
                throw ZebraClawvisorEmailClientError.sqlite(sqliteMessage(database) ?? "query failed")
            }
        }
    }

    func queryDouble(_ sql: String, _ bindings: [Any] = []) throws -> Double? {
        var value: Double?
        try query(sql, bindings) { stmt in
            if sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                value = sqlite3_column_double(stmt, 0)
            }
        }
        return value
    }

    func bind(_ values: [Any], to stmt: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            if value is NSNull {
                sqlite3_bind_null(stmt, index)
            } else if let optional = value as? OptionalStringConvertible, optional.isNil {
                sqlite3_bind_null(stmt, index)
            } else if let text = value as? String {
                sqlite3_bind_text(stmt, index, text, -1, Self.sqliteTransient)
            } else if let int = value as? Int {
                sqlite3_bind_int64(stmt, index, sqlite3_int64(int))
            } else if let double = value as? Double {
                sqlite3_bind_double(stmt, index, double)
            } else if let bool = value as? Bool {
                sqlite3_bind_int(stmt, index, bool ? 1 : 0)
            } else {
                sqlite3_bind_null(stmt, index)
            }
        }
    }

    func sqliteText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let bytes = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: bytes)
    }

    func sqliteMessage(_ database: OpaquePointer?) -> String? {
        guard let database, let cString = sqlite3_errmsg(database) else { return nil }
        return String(cString: cString)
    }

    func jsonString(_ values: [String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: values, options: [])) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    func jsonStringArray(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return array
    }

    func sqliteNullable(_ value: String?) -> Any {
        value ?? NSNull()
    }

    func htmlFromPlainText(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
        return escaped
            .components(separatedBy: .newlines)
            .map { line in line.isEmpty ? "<br>" : "<p>\(line)</p>" }
            .joined()
    }

    static let sqliteTransient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
}

private protocol OptionalStringConvertible {
    var isNil: Bool { get }
}

extension Optional: OptionalStringConvertible {
    fileprivate var isNil: Bool {
        switch self {
        case .none:
            return true
        case .some:
            return false
        }
    }
}

private extension Array {
    var nilIfEmpty: [Element]? {
        isEmpty ? nil : self
    }
}

private extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
