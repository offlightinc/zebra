import AppKit
import SwiftUI
import ZebraVault

/// Container for Zebra-only app-wide stores.
///
/// Why this exists: cmux is upstream, Zebra is a fork. We want upstream files
/// (AppDelegate, ContentView, tests) to mention Zebra in as few places as
/// possible so `git rebase upstream/main` stays cheap.
///
/// This is NOT an `ObservableObject` on purpose. Wrapping all 7 stores into a
/// single Observable would re-invalidate every consumer whenever any one of
/// them changes (or, if the wrapper does not forward `objectWillChange`,
/// `onChange(of: store.foo)` stops firing). Keep each store as its own
/// `ObservableObject`; the container just gives them a shared identity for
/// dependency injection.
///
/// See `/Users/han/.claude/plans/cmux-zbrown-cmux-wise-treasure.md` Phase 1.1
/// for the rationale and rollout plan.
@MainActor
struct ZebraServices {
    let sidebarMode: VerticalTabsSidebarModeState
    let vault: VerticalTabsSidebarVaultState
    let markdownFiles: MarkdownFileListStore
    let goals: GoalFileListStore
    let tasks: TaskFileListStore
    let people: PersonFileListStore
    let goalsViewState: GoalsViewState
    let email: ZebraEmailListStore
    let emailDetail: ZebraEmailDetailStore

    /// Per-panel side-car controllers for markdown panels. Owner of all
    /// `MarkdownPanelController` instances — views may only `@ObservedObject`
    /// them. Lifecycle is driven by `MarkdownPanel.didCloseNotification`
    /// so the registry survives view churn (split reparent, tab switch).
    let panelControllers: MarkdownPanelControllerRegistry

    /// Build a fresh container with default-initialized stores. Call this once
    /// per main window in `AppDelegate.createMainWindow(...)`.
    static func makeDefault() -> ZebraServices {
        // Idempotent: the cmux metric reads this static at layout time, so
        // setting it before the first window builds is enough. Same value
        // every call so racing main-window creation is harmless.
        MinimalModeSidebarTitlebarControlsMetrics.extraLeadingInset =
            VerticalTabsSidebarModeRail.fixedWidth
        return ZebraServices(
            sidebarMode: VerticalTabsSidebarModeState(),
            vault: VerticalTabsSidebarVaultState(),
            markdownFiles: MarkdownFileListStore(),
            goals: GoalFileListStore(),
            tasks: TaskFileListStore(),
            people: PersonFileListStore(),
            goalsViewState: GoalsViewState(),
            email: ZebraEmailListStore(),
            emailDetail: ZebraEmailDetailStore(),
            panelControllers: MarkdownPanelControllerRegistry()
        )
    }

    /// Inject every Zebra store into the view's environment in one call.
    ///
    /// Each store is still exposed as its own `@EnvironmentObject` so existing
    /// Zebra views don't need to change. `@Environment(\.zebra)` also returns
    /// the container for cases where a view needs to read multiple stores
    /// without subscribing to any of them.
    func injectIntoEnvironment<V: View>(_ view: V) -> some View {
        // NOTE: caller must attach `.zebraStoreBindings()` to the innermost
        // view (e.g., `ContentView()`) BEFORE handing it here. The modifier
        // reads cmux `@EnvironmentObject` values (TabManager, etc.) plus the
        // Zebra ones below, so every env provider has to sit above it in
        // the SwiftUI tree.
        view
            .environment(\.zebra, self)
            .environment(\.sidebarComposer, ZebraSidebarComposer.composer)
            .environment(\.sidebarExtraLeadingInset, VerticalTabsSidebarModeRail.fixedWidth)
            .environment(\.markdownPanelViewFactory, ZebraMarkdownPanelViewFactory.make(services: self))
            .environment(\.customPanelViewFactory, ZebraCustomPanelViewFactoryProvider.make(services: self))
            .environmentObject(sidebarMode)
            .environmentObject(vault)
            .environmentObject(markdownFiles)
            .environmentObject(goals)
            .environmentObject(tasks)
            .environmentObject(people)
            .environmentObject(goalsViewState)
            .environmentObject(email)
            .environmentObject(emailDetail)
    }
}

private struct ZebraServicesKey: EnvironmentKey {
    static let defaultValue: ZebraServices? = nil
}

extension EnvironmentValues {
    /// Optional Zebra service container. Returns `nil` when cmux is running
    /// without Zebra wiring (e.g., upstream-only test targets), which is the
    /// safety net the adapter pattern relies on.
    var zebra: ZebraServices? {
        get { self[ZebraServicesKey.self] }
        set { self[ZebraServicesKey.self] = newValue }
    }
}

@MainActor
final class ZebraEmailListStore: ObservableObject {
    @Published private(set) var threads: [EmailThreadItem] = [] {
        didSet { persistThreads(threads) }
    }
    // Seed from the last persisted state so the first frame after relaunch
    // doesn't flash the "Gmail 연결" CTA while waiting for status to come back.
    @Published private(set) var isConnected: Bool
    // isLoading = 모든 in-flight 작업 (DB read, connect, manual sync) 의 합집합.
    // 빈 list placeholder ("불러오는 중") 분기 같은 곳에 쓰임.
    @Published private(set) var isLoading = false
    // isSyncing = 사용자 명시 sync (refresh 버튼) 만 true. 자동 DB read 동안은 false.
    // sidebar 의 sync 버튼 spinner 가 이걸로 판정.
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?

    private let client: ZebraGmailAPIClient
    private static let lastConnectedKey = "ZebraEmailListStore.lastKnownConnected"
    private static let lastThreadsKey = "ZebraEmailListStore.lastThreadsSnapshot"

    init() {
        self.client = .shared
        self.isConnected = UserDefaults.standard.bool(forKey: Self.lastConnectedKey)
        // Seed threads from persisted snapshot so the first frame after relaunch
        // shows the user's last seen inbox while we re-fetch in the background.
        if let data = UserDefaults.standard.data(forKey: Self.lastThreadsKey),
           let restored = try? JSONDecoder().decode([EmailThreadItem].self, from: data) {
            self.threads = restored
        }
        Self.perfLog("init isConnected=\(self.isConnected) cachedThreads=\(self.threads.count)")
        // Warm the auth token in the background so the first sidebar visit
        // doesn't pay the ~2s first-token cost on top of the network round trip.
        // Failures are logged (not swallowed) — the next currentTokens() call
        // retries, but the silent failure used to mask token-store regressions.
        Task.detached {
            do {
                _ = try await AuthManager.shared.currentTokens()
            } catch {
                NSLog("%@", "[ZebraEmail] auth token preheat failed: \(error)")
            }
        }
    }

    private func persistThreads(_ value: [EmailThreadItem]) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: Self.lastThreadsKey)
        }
    }

    /// Diagnostic perf logging. Active only in Debug builds — the body is
    /// compiled out in Release so production has no NSLog noise or file IO.
    /// Kept around (rather than deleted) so future investigations can flip
    /// it back on without redoing the plumbing.
    nonisolated static func perfLog(_ message: String) {
        #if DEBUG
        let full = "[ZebraEmailPerf] \(message)"
        NSLog("%@", full)
        let line = "\(Date().timeIntervalSince1970) \(full)\n"
        let path = "/tmp/zebra-email-perf-direct.log"
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        if let data = line.data(using: .utf8),
           let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        }
        #endif
    }

    private func recordConnected(_ value: Bool) {
        isConnected = value
        UserDefaults.standard.set(value, forKey: Self.lastConnectedKey)
    }

    var userLabels: [EmailUserLabel] {
        let ids = Set(threads.flatMap { $0.labelIds })
            .subtracting(Self.gmailSystemLabelIDs)
        return ids
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { id in
                EmailUserLabel(id: id, name: readableLabelName(id), color: labelColor(for: id))
            }
    }

    /// Read-only path used when the email sidebar becomes visible. Loads the
    /// backend's cached threads without touching Gmail outbound. Manual sync
    /// only fires when the user taps refresh or completes OAuth.
    ///
    /// Status and threads are fetched in parallel — they have no dependency
    /// (a disconnected account returns an empty thread list anyway), so a
    /// single round trip's worth of latency is enough.
    func refreshIfNeeded() async {
        let tStart = Date()
        Self.perfLog("refreshIfNeeded entry isLoading=\(isLoading)")
        if isLoading { return }
        isLoading = true
        defer {
            isLoading = false
            Self.perfLog("refreshIfNeeded end total=\(Int(Date().timeIntervalSince(tStart) * 1000))ms")
        }
        do {
            async let statusTask = client.status()
            async let threadsTask = client.threads()
            let status = try await statusTask
            Self.perfLog("status awaited at \(Int(Date().timeIntervalSince(tStart) * 1000))ms")
            let loadedThreads = try await threadsTask
            Self.perfLog("threads awaited at \(Int(Date().timeIntervalSince(tStart) * 1000))ms")
            recordConnected(status.connected)
            threads = status.connected ? loadedThreads : []
            lastError = nil
        } catch ZebraGmailAPIClientError.notSignedIn {
            recordConnected(false)
            threads = []
            lastError = nil
        } catch ZebraGmailAPIClientError.backendUnreachable {
            // Network blip — keep the cached snapshot and connected state so
            // the UI doesn't lose its first-frame inbox just because the user
            // is briefly offline. Persisted threads stay untouched; the next
            // successful read replaces them.
            lastError = nil
        } catch {
            lastError = displayError(error)
        }
    }

    func refresh() async {
        if isLoading { return }
        isLoading = true
        isSyncing = true
        defer {
            isLoading = false
            isSyncing = false
        }
        do {
            let status = try await client.status()
            recordConnected(status.connected)
            guard status.connected else {
                threads = []
                lastError = nil
                return
            }
            var syncError: String?
            do {
                try await client.sync()
            } catch {
                syncError = displayError(error)
            }
            let loadedThreads = try await client.threads()
            threads = loadedThreads
            lastError = loadedThreads.isEmpty ? syncError : nil
        } catch ZebraGmailAPIClientError.notSignedIn {
            recordConnected(false)
            threads = []
            lastError = nil
        } catch ZebraGmailAPIClientError.backendUnreachable {
            // Same as refreshIfNeeded: don't blow away the cached snapshot
            // on a transient network failure.
            lastError = nil
        } catch {
            lastError = displayError(error)
        }
    }

    func connect() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let authURL = try await client.startOAuth()
            NSWorkspace.shared.open(authURL)
            lastError = nil
            pollAfterOAuthLaunch()
        } catch ZebraGmailAPIClientError.notSignedIn {
            lastError = nil
            beginSignInThenConnectGmail()
        } catch {
            lastError = displayError(error)
        }
    }

    func localLabel(named name: String) -> EmailUserLabel {
        EmailUserLabel(id: "local-\(UUID().uuidString)", name: name, color: labelColor(for: name))
    }

    private func readableLabelName(_ id: String) -> String {
        id
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func labelColor(for value: String) -> Color {
        let palette: [Color] = [
            Color(nsColor: NSColor.systemTeal),
            Color(nsColor: NSColor.systemGreen),
            Color(nsColor: NSColor.systemOrange),
            Color(nsColor: NSColor.systemPink),
            Color(nsColor: NSColor.systemPurple),
            Color(nsColor: NSColor.systemBlue),
        ]
        let hash = value.unicodeScalars.reduce(0) { (($0 &* 31) &+ Int($1.value)) & 0x7fffffff }
        return palette[hash % palette.count]
    }

    private func displayError(_ error: Error) -> String {
        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count > 240 else { return raw }
        let index = raw.index(raw.startIndex, offsetBy: 240)
        return String(raw[..<index]) + "..."
    }

    private func pollAfterOAuthLaunch() {
        // Backend's OAuth callback already backfills inbox. Polling here only
        // needs to detect when status flips to connected and load the cached
        // threads — no extra Gmail outbound from the desktop side.
        Task { [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                await self.refreshIfNeeded()
                if self.isConnected { return }
            }
        }
    }

    private func beginSignInThenConnectGmail() {
        Task { @MainActor [weak self] in
            let signedIn = await AuthManager.shared.beginSignInAndAwait(timeout: 90)
            guard let self else { return }
            if signedIn {
                await self.connect()
            } else {
                self.lastError = String(localized: "email.error.signInRequired", defaultValue: "먼저 Zebra에 로그인해 주세요")
            }
        }
    }

    private static let gmailSystemLabelIDs: Set<String> = [
        "CHAT",
        "DRAFT",
        "IMPORTANT",
        "INBOX",
        "SENT",
        "SPAM",
        "STARRED",
        "TRASH",
        "UNREAD",
        "CATEGORY_FORUMS",
        "CATEGORY_PERSONAL",
        "CATEGORY_PROMOTIONS",
        "CATEGORY_PURCHASES",
        "CATEGORY_SOCIAL",
        "CATEGORY_UPDATES",
    ]
}

@MainActor
final class ZebraEmailDetailStore: ObservableObject {
    @Published private(set) var selectedThreadId: String?
    @Published private var threadStates: [String: ZebraEmailThreadUIState] = [:]

    private let client = ZebraGmailAPIClient.shared

    func selectThread(_ thread: EmailThreadItem) {
        selectedThreadId = thread.id
        Task { await loadThreadIfNeeded(threadId: thread.id) }
    }

    func loadThreadIfNeeded(threadId: String) async {
        if threadStates[threadId]?.detail != nil { return }
        await reloadThread(threadId: threadId, forceRefresh: false)
    }

    func reloadThread(threadId: String, forceRefresh: Bool = true) async {
        var loadingState = threadStates[threadId] ?? ZebraEmailThreadUIState()
        if loadingState.isLoading { return }
        loadingState.isLoading = true
        loadingState.errorMessage = nil
        threadStates[threadId] = loadingState

        do {
            let detail = try await client.threadMessages(threadId: threadId, forceRefresh: forceRefresh)
            var loadedState = threadStates[threadId] ?? ZebraEmailThreadUIState()
            loadedState.detail = detail
            loadedState.isLoading = false
            loadedState.errorMessage = nil
            if loadedState.expandedMessageIds == nil {
                loadedState.expandedMessageIds = defaultExpandedMessageIds(detail)
            }
            threadStates[threadId] = loadedState
        } catch {
            var failedState = threadStates[threadId] ?? ZebraEmailThreadUIState()
            failedState.isLoading = false
            failedState.errorMessage = displayError(error)
            threadStates[threadId] = failedState
        }
    }

    func toggleMessage(threadId: String, messageId: String) {
        var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
        var ids = state.expandedMessageIds ?? []
        if ids.contains(messageId) {
            ids.remove(messageId)
        } else {
            ids.insert(messageId)
        }
        state.expandedMessageIds = ids
        threadStates[threadId] = state
    }

    func detail(threadId: String) -> EmailThreadDetail? {
        threadStates[threadId]?.detail
    }

    func isLoading(threadId: String) -> Bool {
        threadStates[threadId]?.isLoading ?? false
    }

    func errorMessage(threadId: String) -> String? {
        threadStates[threadId]?.errorMessage
    }

    func expandedMessageIds(threadId: String) -> Set<String> {
        threadStates[threadId]?.expandedMessageIds ?? []
    }

    private func defaultExpandedMessageIds(_ detail: EmailThreadDetail) -> Set<String> {
        var expanded = Set(detail.messages.filter(\.isUnread).map(\.id))
        if let latest = detail.messages.last {
            expanded.insert(latest.id)
        }
        if expanded.isEmpty, let first = detail.messages.first {
            expanded.insert(first.id)
        }
        return expanded
    }

    private func displayError(_ error: Error) -> String {
        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count > 240 else { return raw }
        let index = raw.index(raw.startIndex, offsetBy: 240)
        return String(raw[..<index]) + "..."
    }
}

private struct ZebraEmailThreadUIState {
    var detail: EmailThreadDetail?
    var isLoading = false
    var errorMessage: String?
    var expandedMessageIds: Set<String>?
}

private actor ZebraGmailAPIClient {
    static let shared = ZebraGmailAPIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let iso8601: ISO8601DateFormatter

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        self.decoder = decoder
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.iso8601 = formatter
    }

    func status() async throws -> GmailStatusResponse {
        let (data, http) = try await request("GET", path: "/api/gmail/status")
        try ensureOK(http, data: data)
        return try decoder.decode(GmailStatusResponse.self, from: data)
    }

    func sync() async throws {
        let (data, http) = try await request("POST", path: "/api/gmail/sync", jsonBody: [:])
        try ensureOK(http, data: data)
    }

    func startOAuth() async throws -> URL {
        let (data, http) = try await request("POST", path: "/api/gmail/oauth/start", jsonBody: [:])
        try ensureOK(http, data: data)
        let response = try decoder.decode(GmailOAuthStartResponse.self, from: data)
        guard let url = URL(string: response.authUrl) else {
            throw ZebraGmailAPIClientError.malformedResponse("bad Gmail OAuth URL")
        }
        return url
    }

    func threads() async throws -> [EmailThreadItem] {
        let (data, http) = try await request("GET", path: "/api/gmail/threads")
        try ensureOK(http, data: data)
        let response = try decoder.decode(GmailThreadsResponse.self, from: data)
        return response.threads.compactMap { dto in
            guard let receivedAt = parseDate(dto.receivedAt) else { return nil }
            return EmailThreadItem(
                id: dto.id,
                subject: dto.subject,
                senderName: dto.senderName,
                receivedAt: receivedAt,
                unread: dto.unread,
                starred: dto.starred,
                hasAttachment: dto.hasAttachment,
                labelIds: dto.labelIds,
                category: dto.category.flatMap(EmailCategory.init(rawValue:))
            )
        }
    }

    func threadMessages(threadId: String, forceRefresh: Bool = false) async throws -> EmailThreadDetail {
        let encodedThreadId = threadId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? threadId
        let queryItems = forceRefresh ? [URLQueryItem(name: "refresh", value: "1")] : []
        let (data, http) = try await request(
            "GET",
            path: "/api/gmail/threads/\(encodedThreadId)/messages",
            queryItems: queryItems
        )
        try ensureOK(http, data: data)
        let response = try decoder.decode(GmailThreadMessagesResponse.self, from: data)
        return EmailThreadDetail(
            threadId: response.threadId,
            cached: response.cached,
            messages: response.messages.map { dto in
                EmailThreadMessage(
                    id: dto.messageId,
                    internetMessageId: dto.internetMessageId,
                    subject: dto.subject,
                    fromName: dto.fromName,
                    fromEmail: dto.fromEmail,
                    to: dto.to,
                    cc: dto.cc,
                    receivedAt: dto.receivedAt.flatMap(parseDate),
                    snippet: dto.snippet,
                    labelIds: dto.labelIds,
                    isUnread: dto.isUnread,
                    isSent: dto.isSent,
                    hasAttachment: dto.hasAttachment,
                    bodyText: dto.bodyText,
                    bodyHtml: dto.bodyHtml
                )
            }
        )
    }

    private func request(
        _ method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        jsonBody: [String: Any]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let tStart = Date()
        let tokens: (accessToken: String, refreshToken: String)
        do {
            tokens = try await AuthManager.shared.currentTokens()
        } catch {
            throw ZebraGmailAPIClientError.notSignedIn
        }
        let tAfterTokens = Date()

        guard var components = URLComponents(url: AuthEnvironment.vmAPIBaseURL, resolvingAgainstBaseURL: false) else {
            throw ZebraGmailAPIClientError.malformedResponse("bad Gmail API base URL")
        }
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path) + path
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }
        guard let url = components.url else {
            throw ZebraGmailAPIClientError.malformedResponse("could not build Gmail API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(tokens.refreshToken, forHTTPHeaderField: "X-Stack-Refresh-Token")
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [])
        }

        let data: Data
        let response: URLResponse
        do {
            let tBeforeNet = Date()
            (data, response) = try await session.data(for: request)
            let now = Date()
            let tokensMs = Int(tAfterTokens.timeIntervalSince(tStart) * 1000)
            let netMs = Int(now.timeIntervalSince(tBeforeNet) * 1000)
            let totalMs = Int(now.timeIntervalSince(tStart) * 1000)
            ZebraEmailListStore.perfLog("\(method) \(path) tokens=\(tokensMs)ms net=\(netMs)ms total=\(totalMs)ms")
        } catch let error as URLError {
            throw ZebraGmailAPIClientError.backendUnreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ZebraGmailAPIClientError.malformedResponse("non-HTTP Gmail API response")
        }
        return (data, http)
    }

    private func ensureOK(_ response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ZebraGmailAPIClientError.httpStatus(response.statusCode, body)
        }
    }

    private func parseDate(_ value: String) -> Date? {
        if let date = iso8601.date(from: value) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }
}

private struct GmailStatusResponse: Decodable {
    let connected: Bool
    let email: String?
    let lastSyncedAt: String?
}

private struct GmailThreadsResponse: Decodable {
    let threads: [GmailThreadDTO]
}

private struct GmailOAuthStartResponse: Decodable {
    let authUrl: String
}

private struct GmailThreadDTO: Decodable {
    let id: String
    let subject: String
    let senderName: String
    let receivedAt: String
    let unread: Bool
    let starred: Bool
    let hasAttachment: Bool
    let labelIds: [String]
    let category: String?
}

private struct GmailThreadMessagesResponse: Decodable {
    let threadId: String
    let cached: Bool
    let messages: [GmailThreadMessageDTO]
}

private struct GmailThreadMessageDTO: Decodable {
    let messageId: String
    let threadId: String
    let internetMessageId: String?
    let subject: String?
    let fromName: String?
    let fromEmail: String?
    let to: String?
    let cc: String?
    let receivedAt: String?
    let snippet: String?
    let labelIds: [String]
    let isUnread: Bool
    let isSent: Bool
    let hasAttachment: Bool
    let bodyText: String?
    let bodyHtml: String?
}

private enum ZebraGmailAPIClientError: LocalizedError {
    case notSignedIn
    case backendUnreachable(String)
    case httpStatus(Int, String)
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in."
        case .backendUnreachable(let detail):
            return "Gmail API backend is unreachable: \(detail)"
        case .httpStatus(let status, let body):
            return "Gmail API request failed (\(status)): \(body)"
        case .malformedResponse(let detail):
            return "Gmail API response was malformed: \(detail)"
        }
    }
}
