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

    private let client: ZebraClawvisorEmailClient
    private var prefetchTask: Task<Void, Never>?
    private static let lastConnectedKey = "ZebraEmailListStore.lastKnownConnected"
    private static let lastThreadsKey = "ZebraEmailListStore.lastThreadsSnapshot"

    // ~/.gbrain/.env watcher state. `fileWatchSource` watches the .env file
    // itself; `directoryWatchSource` watches `~/.gbrain` for the .env's
    // creation (atomic writes show up as a new inode here). One of the two
    // is active at any given time. See `startDotEnvWatching()`.
    private nonisolated(unsafe) var fileWatchSource: DispatchSourceFileSystemObject?
    private nonisolated(unsafe) var directoryWatchSource: DispatchSourceFileSystemObject?
    private let dotEnvWatcherQueue = DispatchQueue(
        label: "com.cmux.zebra.dotenv-watcher", qos: .utility
    )

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
        // Auto-reload whenever ~/.gbrain/.env is created or rewritten — that's
        // the file Clawvisor onboarding (via the chat-pill agent) ends with,
        // so this catches the moment without a manual sidebar refresh.
        startDotEnvWatching()
    }

    deinit {
        fileWatchSource?.cancel()
        directoryWatchSource?.cancel()
    }

    // MARK: - ~/.gbrain/.env file watcher

    private var dotEnvPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".gbrain/.env")
    }

    private var gbrainDirectoryPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".gbrain")
    }

    /// Bootstrap whichever watcher matches the current state of
    /// `~/.gbrain/.env`. If the file already exists, watch it directly; if
    /// it doesn't, watch the parent directory so we can pick up its first
    /// creation. The two paths self-correct each other on every event.
    private func startDotEnvWatching() {
        if FileManager.default.fileExists(atPath: dotEnvPath) {
            startFileWatcher()
        } else {
            startDirectoryWatcher()
        }
    }

    private func startFileWatcher() {
        stopFileWatcher()
        let fd = open(dotEnvPath, O_EVTONLY)
        guard fd >= 0 else {
            startDirectoryWatcher()
            return
        }
        stopDirectoryWatcher()
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: dotEnvWatcherQueue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            DispatchQueue.main.async {
                if flags.contains(.delete) || flags.contains(.rename) {
                    // Atomic writes look like "old inode renamed/deleted,
                    // new file created" — re-attach via the directory
                    // watcher so we land on the replacement.
                    self.stopFileWatcher()
                    self.startDirectoryWatcher()
                }
                self.scheduleConfigReload()
            }
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        fileWatchSource = source
    }

    private func startDirectoryWatcher() {
        stopDirectoryWatcher()
        // Make sure `~/.gbrain/` exists so the watcher has something to
        // attach to. Idempotent — the directory may already be there from
        // earlier gbrain tooling.
        try? FileManager.default.createDirectory(
            atPath: gbrainDirectoryPath,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let fd = open(gbrainDirectoryPath, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: dotEnvWatcherQueue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                // The directory just changed — check whether `.env` exists
                // now and graduate to the file watcher if so.
                if FileManager.default.fileExists(atPath: self.dotEnvPath) {
                    self.startFileWatcher()
                    self.scheduleConfigReload()
                }
            }
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        directoryWatchSource = source
    }

    private func stopFileWatcher() {
        if let source = fileWatchSource {
            source.cancel()
            fileWatchSource = nil
        }
    }

    private func stopDirectoryWatcher() {
        if let source = directoryWatchSource {
            source.cancel()
            directoryWatchSource = nil
        }
    }

    /// Invalidate the actor's cached config so the next call picks up the
    /// new env values, then trigger a sidebar refresh.
    private func scheduleConfigReload() {
        Task { [weak self] in
            await ZebraClawvisorEmailClient.shared.invalidateConfig()
            await self?.refresh()
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
    /// local SQLite cache without touching Gmail outbound. Manual sync only
    /// fires when the user taps refresh.
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
            if status.connected {
                startBodyPrefetchIfNeeded(for: loadedThreads)
            }
            lastError = nil
        } catch ZebraClawvisorEmailClientError.notConfigured(_) {
            recordConnected(false)
            threads = []
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
                _ = try await client.syncRecentInbox()
            } catch {
                syncError = displayError(error)
            }
            let loadedThreads = try await client.threads()
            threads = loadedThreads
            lastError = loadedThreads.isEmpty ? syncError : nil
            startBodyPrefetchIfNeeded(for: loadedThreads)
        } catch ZebraClawvisorEmailClientError.notConfigured(_) {
            recordConnected(false)
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
            let status = try await client.status()
            recordConnected(status.connected)
            if status.connected {
                _ = try await client.syncRecentInbox()
                threads = try await client.threads()
                startBodyPrefetchIfNeeded(for: threads)
            }
            lastError = nil
        } catch ZebraClawvisorEmailClientError.notConfigured(_) {
            recordConnected(false)
            lastError = String(localized: "email.error.clawvisorRequired", defaultValue: "Clawvisor Gmail 설정이 필요합니다")
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

    private func startBodyPrefetchIfNeeded(for threads: [EmailThreadItem]) {
        guard !threads.isEmpty else { return }
        if prefetchTask?.isCancelled == false { return }
        let client = self.client
        prefetchTask = Task(priority: .utility) { [weak self] in
            defer { self?.prefetchTask = nil }
            do {
                let fetched = try await client.prefetchRecentMessageBodies(limit: 8)
                Self.perfLog("prefetchRecentMessageBodies fetched=\(fetched)")
            } catch {
                Self.perfLog("prefetchRecentMessageBodies failed=\(error.localizedDescription)")
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

    private let client = ZebraClawvisorEmailClient.shared

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
