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
            .environmentObject(sidebarMode)
            .environmentObject(vault)
            .environmentObject(markdownFiles)
            .environmentObject(goals)
            .environmentObject(tasks)
            .environmentObject(people)
            .environmentObject(goalsViewState)
            .environmentObject(email)
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
    @Published private(set) var threads: [EmailThreadItem] = []
    @Published private(set) var isConnected = false
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let client: ZebraGmailAPIClient
    private var lastRefreshAt: Date?

    init() {
        self.client = .shared
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

    func refreshIfNeeded() async {
        if let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < 300 {
            return
        }
        await refresh()
    }

    func refresh() async {
        if isLoading { return }
        isLoading = true
        defer {
            isLoading = false
            lastRefreshAt = Date()
        }
        do {
            let status = try await client.status()
            isConnected = status.connected
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
            isConnected = false
            threads = []
            lastError = nil
        } catch ZebraGmailAPIClientError.backendUnreachable {
            isConnected = false
            threads = []
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
        Task { [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                await self.refresh()
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

    private func request(
        _ method: String,
        path: String,
        jsonBody: [String: Any]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let tokens: (accessToken: String, refreshToken: String)
        do {
            tokens = try await AuthManager.shared.currentTokens()
        } catch {
            throw ZebraGmailAPIClientError.notSignedIn
        }

        guard var components = URLComponents(url: AuthEnvironment.vmAPIBaseURL, resolvingAgainstBaseURL: false) else {
            throw ZebraGmailAPIClientError.malformedResponse("bad Gmail API base URL")
        }
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path) + path
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
            (data, response) = try await session.data(for: request)
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
