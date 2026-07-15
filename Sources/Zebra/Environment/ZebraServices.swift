import AppKit
import Bonsplit
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
    let brainSync: BrainSyncSelectionService
    let brainSaveStatus: BrainSaveStatusService
    let onboardingChecklist: ZebraOnboardingChecklistStore

    /// Per-panel side-car controllers for markdown panels. Owner of all
    /// `MarkdownPanelController` instances — views may only `@ObservedObject`
    /// them. Lifecycle is driven by `MarkdownPanel.didCloseNotification`
    /// so the registry survives view churn (split reparent, tab switch).
    let panelControllers: MarkdownPanelControllerRegistry

    /// Terminal-side marker registry for Zebra-owned agent panels.
    /// Marks terminal panel ids rather than pane ids so tab moves/reparents
    /// are reflected by live layout lookup instead of stale pane memory.
    let agentTerminals: ZebraAgentTerminalRegistry

    /// Build a fresh container with default-initialized stores. Call this once
    /// per main window in `AppDelegate.createMainWindow(...)`.
    static func makeDefault(tabManager: TabManager? = nil) -> ZebraServices {
        // Idempotent: the cmux metric reads this static at layout time, so
        // setting it before the first window builds is enough. Same value
        // every call so racing main-window creation is harmless.
        MinimalModeSidebarTitlebarControlsMetrics.extraLeadingInset =
            VerticalTabsSidebarModeRail.fixedWidth
        ZebraTelemetry.sink = ZebraTelemetryPostHogBridge.shared
        SlackCapturedPollingScheduler.shared.start()
        let vault = VerticalTabsSidebarVaultState()
        let brainSync = BrainSyncSelectionService()
        brainSync.attachVaultSource(vault)
        brainSync.setSyncEnabled(GBrainConfig.usesRemoteMCP())
        let brainSaveStatus = BrainSaveStatusService()
        let email = ZebraEmailListStore()
        let agentTerminals = ZebraAgentTerminalRegistry()
        let emailDetail = ZebraEmailDetailStore(
            onConnectionRepairRequired: { repairState in
                email.beginConnectionRepair(repairState)
            },
            onThreadSummariesChanged: {
                Task { await email.reloadCachedThreads() }
            }
        )
        ZebraEmailDraftSocketBridge.shared.configure(
            tabManager: tabManager,
            emailListStore: email,
            emailDetailStore: emailDetail,
            agentTerminals: agentTerminals
        )
        return ZebraServices(
            sidebarMode: VerticalTabsSidebarModeState(),
            vault: vault,
            markdownFiles: MarkdownFileListStore(),
            goals: GoalFileListStore(),
            tasks: TaskFileListStore(),
            people: PersonFileListStore(),
            goalsViewState: GoalsViewState(),
            email: email,
            emailDetail: emailDetail,
            brainSync: brainSync,
            brainSaveStatus: brainSaveStatus,
            onboardingChecklist: ZebraOnboardingChecklistStore(),
            panelControllers: MarkdownPanelControllerRegistry(),
            agentTerminals: agentTerminals
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
            .environmentObject(brainSync)
            .environmentObject(brainSaveStatus)
            .environmentObject(onboardingChecklist)
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
    @Published private(set) var hasVerifiedConnection = false
    // isLoading = 모든 in-flight 작업 (DB read, connect, manual sync) 의 합집합.
    // 빈 list placeholder ("불러오는 중") 분기 같은 곳에 쓰임.
    @Published private(set) var isLoading = false
    // isSyncing = 사용자 명시 sync (refresh 버튼) 만 true. 자동 DB read 동안은 false.
    // sidebar 의 sync 버튼 spinner 가 이걸로 판정.
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var connectionRepairState: ZebraEmailConnectionRepairState?

    private let client: ZebraClawvisorEmailClient
    private var prefetchTask: Task<Void, Never>?
    private var periodicSyncTask: Task<Void, Never>?
    private var provisioningTask: Task<Void, Never>?
    private static let lastConnectedKey = "ZebraEmailListStore.lastKnownConnected"
    private static let lastThreadsKey = "ZebraEmailListStore.lastThreadsSnapshot"
    private static let startupSyncDelayNanoseconds: UInt64 = 3 * 1_000_000_000
    private static let periodicSyncIntervalNanoseconds: UInt64 = 5 * 60 * 1_000_000_000

    // ~/.gbrain/.env watcher state. `fileWatchSource` watches the .env file
    // itself; `directoryWatchSource` watches `~/.gbrain` for the .env's
    // creation (atomic writes show up as a new inode here). One of the two
    // is active at any given time. See `startDotEnvWatching()`.
    private nonisolated(unsafe) var fileWatchSource: DispatchSourceFileSystemObject?
    private nonisolated(unsafe) var directoryWatchSource: DispatchSourceFileSystemObject?
    private let dotEnvWatcherQueue = DispatchQueue(
        label: "com.cmux.zebra.dotenv-watcher", qos: .utility
    )
    /// Pending coalesced reload — see `scheduleConfigReload()` for the
    /// debounce rationale. Cancelled and re-scheduled on each new event.
    private var configReloadWorkItem: DispatchWorkItem?

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
        if isConnected {
            startPeriodicSyncIfNeeded(initialDelay: Self.startupSyncDelayNanoseconds)
        }
    }

    deinit {
        fileWatchSource?.cancel()
        directoryWatchSource?.cancel()
        configReloadWorkItem?.cancel()
        periodicSyncTask?.cancel()
        provisioningTask?.cancel()
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
    ///
    /// Debounced — DispatchSource fires one event per write, and editors
    /// (or gbrain's own writer) can emit several writes within a few ms
    /// when rewriting `~/.gbrain/.env`. Without coalescing we'd queue N
    /// `invalidateConfig` + `refresh` Task chains and stampede the actor.
    /// 100ms is long enough to swallow a burst, short enough that the
    /// "Connect" screen still flips to the inbox before the user notices.
    private func scheduleConfigReload() {
        configReloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task {
                await ZebraClawvisorEmailClient.shared.invalidateConfig()
                await self.refresh()
            }
        }
        configReloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: item)
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
        hasVerifiedConnection = value
        UserDefaults.standard.set(value, forKey: Self.lastConnectedKey)
        if value {
            startPeriodicSyncIfNeeded()
        } else {
            stopPeriodicSync()
        }
    }

    func beginConnectionRepair(_ state: ZebraEmailConnectionRepairState) {
        recordConnected(false)
        threads = []
        lastError = nil
        connectionRepairState = state
        if shouldProvisionStandingTask(for: state) {
            provisionStandingTaskIfNeeded()
        }
    }

    private func clearConnectionRepair() {
        connectionRepairState = nil
    }

    private func handleConnectionFailure(_ error: Error) -> Bool {
        guard let state = Self.connectionRepairState(for: error) else {
            return false
        }
        beginConnectionRepair(state)
        return true
    }

    private static func connectionRepairState(for error: Error) -> ZebraEmailConnectionRepairState? {
        guard let clawvisorError = error as? ZebraClawvisorEmailClientError else {
            return nil
        }
        return clawvisorError.connectionRepairState
    }

    private func shouldProvisionStandingTask(for state: ZebraEmailConnectionRepairState) -> Bool {
        false
    }

    private func provisionStandingTaskIfNeeded() {
        guard provisioningTask == nil else { return }
        connectionRepairState = ZebraEmailConnectionRepairState(kind: .provisioning)
        provisioningTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.client.provisionStandingGmailTask()
                self.connectionRepairState = ZebraEmailConnectionRepairState(
                    kind: .taskPendingApproval,
                    taskId: result.taskId
                )
            } catch {
                let repairState = Self.connectionRepairState(for: error)
                self.connectionRepairState = ZebraEmailConnectionRepairState(
                    kind: .provisioningFailed,
                    detail: repairState?.detail ?? self.displayError(error)
                )
            }
            self.provisioningTask = nil
        }
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
        if !isConnected {
            await refresh()
            return
        }
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
            clearConnectionRepair()
            lastError = nil
        } catch let error as ZebraClawvisorEmailClientError {
            if !handleConnectionFailure(error) {
                lastError = displayError(error)
            }
        } catch {
            if handleConnectionFailure(error) { return }
            lastError = displayError(error)
        }
    }

    func refresh() async {
        await syncInboxAndReload(showSyncIndicator: true)
    }

    func reloadCachedThreads() async {
        do {
            threads = try await client.threads()
            lastError = nil
        } catch let error as ZebraClawvisorEmailClientError {
            if !handleConnectionFailure(error) {
                lastError = displayError(error)
            }
        } catch {
            if handleConnectionFailure(error) { return }
            lastError = displayError(error)
        }
    }

    func threadItem(threadId: String) -> EmailThreadItem? {
        threads.first { $0.id == threadId }
    }

    private func syncInboxAndReload(showSyncIndicator: Bool) async {
        if isLoading { return }
        isLoading = true
        if showSyncIndicator {
            isSyncing = true
        }
        defer {
            isLoading = false
            if showSyncIndicator {
                isSyncing = false
            }
        }
        do {
            let status = try await client.status()
            recordConnected(status.connected)
            guard status.connected else {
                threads = []
                clearConnectionRepair()
                lastError = nil
                return
            }
            var syncError: String?
            do {
                let syncedCount = try await client.syncRecentInbox()
                Self.perfLog("syncRecentInbox synced=\(syncedCount)")
            } catch {
                if handleConnectionFailure(error) { return }
                syncError = displayError(error)
            }
            let loadedThreads = try await client.threads()
            threads = loadedThreads
            clearConnectionRepair()
            lastError = loadedThreads.isEmpty ? syncError : nil
            startBodyPrefetchIfNeeded(for: loadedThreads)
        } catch let error as ZebraClawvisorEmailClientError {
            if !handleConnectionFailure(error) {
                lastError = displayError(error)
            }
        } catch {
            if handleConnectionFailure(error) { return }
            lastError = displayError(error)
        }
    }

    private func startPeriodicSyncIfNeeded(initialDelay: UInt64? = nil) {
        guard periodicSyncTask == nil else { return }
        periodicSyncTask = Task { [weak self] in
            var delay = initialDelay ?? Self.periodicSyncIntervalNanoseconds
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self?.syncInboxAndReload(showSyncIndicator: false)
                delay = Self.periodicSyncIntervalNanoseconds
            }
        }
    }

    private func stopPeriodicSync() {
        periodicSyncTask?.cancel()
        periodicSyncTask = nil
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
            clearConnectionRepair()
            lastError = nil
        } catch let error as ZebraClawvisorEmailClientError {
            if !handleConnectionFailure(error) {
                lastError = displayError(error)
            }
        } catch {
            if handleConnectionFailure(error) { return }
            lastError = displayError(error)
        }
    }

    func localLabel(named name: String) -> EmailUserLabel {
        EmailUserLabel(id: "local-\(UUID().uuidString)", name: name, color: labelColor(for: name))
    }

    func removeLocalThread(threadId: String) {
        threads.removeAll { $0.id == threadId }
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
                if let repairState = Self.connectionRepairState(for: error) {
                    self?.beginConnectionRepair(repairState)
                }
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
    private let onConnectionRepairRequired: (ZebraEmailConnectionRepairState) -> Void
    private let onThreadSummariesChanged: () -> Void
    private var draftUpdateQueues: [String: ZebraEmailDraftUpdateQueue] = [:]

    init(
        onConnectionRepairRequired: @escaping (ZebraEmailConnectionRepairState) -> Void = { _ in },
        onThreadSummariesChanged: @escaping () -> Void = {}
    ) {
        self.onConnectionRepairRequired = onConnectionRepairRequired
        self.onThreadSummariesChanged = onThreadSummariesChanged
    }

    func selectThread(_ thread: EmailThreadItem) {
        selectedThreadId = thread.id
        Task { await loadThreadIfNeeded(threadId: thread.id) }
    }

    func loadThreadIfNeeded(threadId: String) async {
        if threadStates[threadId]?.detail != nil {
            await loadDrafts(threadId: threadId)
            return
        }
        await reloadThread(threadId: threadId, forceRefresh: false)
    }

    func reloadThread(threadId: String, forceRefresh: Bool = true) async {
        var loadingState = threadStates[threadId] ?? ZebraEmailThreadUIState()
        if loadingState.isLoading { return }
        loadingState.isLoading = true
        loadingState.errorMessage = nil
        loadingState.archiveErrorMessage = nil
        threadStates[threadId] = loadingState

        do {
            let detail = try await client.threadMessages(threadId: threadId, forceRefresh: forceRefresh)
            let drafts = try await client.emailDrafts(threadId: detail.threadId)
            var loadedState = threadStates[threadId] ?? ZebraEmailThreadUIState()
            loadedState.detail = detail
            loadedState.drafts = drafts
            loadedState.isLoading = false
            loadedState.errorMessage = nil
            if loadedState.expandedMessageIds == nil {
                loadedState.expandedMessageIds = defaultExpandedMessageIds(detail)
            }
            threadStates[threadId] = loadedState
        } catch {
            if let repairState = Self.connectionRepairState(for: error) {
                onConnectionRepairRequired(repairState)
            }
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

    func archiveThread(threadId: String) async -> Bool {
        var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
        if state.isArchiving { return false }
        state.isArchiving = true
        state.archiveErrorMessage = nil
        threadStates[threadId] = state

        do {
            let detail: EmailThreadDetail
            if let cached = state.detail {
                detail = cached
            } else {
                detail = try await client.threadMessages(threadId: threadId, forceRefresh: false)
            }
            try await client.archiveThread(
                threadId: threadId,
                providerThreadId: detail.providerThreadId,
                messageIds: detail.messages.map(\.id)
            )
            var archivedState = threadStates[threadId] ?? ZebraEmailThreadUIState()
            archivedState.detail = nil
            archivedState.isLoading = false
            archivedState.isArchiving = false
            archivedState.errorMessage = nil
            archivedState.archiveErrorMessage = nil
            archivedState.expandedMessageIds = nil
            threadStates[threadId] = archivedState
            if selectedThreadId == threadId {
                selectedThreadId = nil
            }
            return true
        } catch {
            var failedState = threadStates[threadId] ?? ZebraEmailThreadUIState()
            failedState.isArchiving = false
            if let repairState = Self.connectionRepairState(for: error) {
                failedState.archiveErrorMessage = nil
                threadStates[threadId] = failedState
                onConnectionRepairRequired(repairState)
                return false
            }
            failedState.archiveErrorMessage = String.localizedStringWithFormat(
                String(localized: "email.detail.archiveFailed", defaultValue: "Archive failed: %@"),
                displayError(error)
            )
            threadStates[threadId] = failedState
            return false
        }
    }

    func clearArchiveError(threadId: String) {
        var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
        state.archiveErrorMessage = nil
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

    func isArchiving(threadId: String) -> Bool {
        threadStates[threadId]?.isArchiving ?? false
    }

    func archiveErrorMessage(threadId: String) -> String? {
        threadStates[threadId]?.archiveErrorMessage
    }

    func draftErrorMessage(threadId: String) -> String? {
        threadStates[threadId]?.draftErrorMessage
    }

    func draftErrorMessage(threadId: String, localDraftId: String) -> String? {
        threadStates[threadId]?.draftErrorMessages[localDraftId]
    }

    func sendingDraftIds(threadId: String) -> Set<String> {
        threadStates[threadId]?.sendingDraftIds ?? []
    }

    func clearDraftError(threadId: String) {
        var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
        state.draftErrorMessage = nil
        threadStates[threadId] = state
    }

    func expandedMessageIds(threadId: String) -> Set<String> {
        threadStates[threadId]?.expandedMessageIds ?? []
    }

    func drafts(threadId: String) -> [EmailDraftSnapshot] {
        threadStates[threadId]?.drafts ?? []
    }

    func threadIdForDraft(localDraftId: String) -> String? {
        for (threadId, state) in threadStates where state.drafts.contains(where: { $0.localDraftId == localDraftId }) {
            return threadId
        }
        return nil
    }

    func agentDrafts(threadId requestedThreadId: String?) async throws -> [EmailDraftSnapshot] {
        guard let threadId = resolveDraftThreadId(requestedThreadId) else {
            throw ZebraEmailDraftSocketError.invalidParams("thread_id is required")
        }
        let drafts = try await client.emailDrafts(threadId: threadId)
        var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
        state.drafts = drafts
        threadStates[threadId] = state
        return drafts
    }

    func createAgentReplyDraft(
        threadId requestedThreadId: String?,
        targetMessageId requestedTargetMessageId: String?,
        subject requestedSubject: String?,
        toRecipients requestedToRecipients: [String]?,
        ccRecipients requestedCcRecipients: [String]?,
        bccRecipients requestedBccRecipients: [String]?,
        bodyText requestedBodyText: String?
    ) async throws -> EmailDraftSnapshot {
        guard let threadId = resolveDraftThreadId(requestedThreadId) else {
            throw ZebraEmailDraftSocketError.invalidParams("thread_id is required")
        }
        let detail = try await loadDetailForAgentCommand(threadId: threadId)
        guard !detail.messages.isEmpty else {
            throw ZebraEmailDraftSocketError.notFound("thread has no messages")
        }
        let targetMessage: EmailThreadMessage
        if let requestedTargetMessageId {
            guard let found = detail.messages.first(where: { $0.id == requestedTargetMessageId }) else {
                throw ZebraEmailDraftSocketError.notFound("target_message_id not found")
            }
            targetMessage = found
        } else if let latestInbound = detail.messages.last(where: { !$0.isSent }) {
            targetMessage = latestInbound
        } else {
            targetMessage = detail.messages[detail.messages.index(before: detail.messages.endIndex)]
        }

        var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
        var expanded = state.expandedMessageIds ?? []
        expanded.insert(targetMessage.id)
        state.expandedMessageIds = expanded
        threadStates[threadId] = state

        let defaultSubject = replySubject(
            for: targetMessage,
            fallbackSubject: detail.messages.compactMap(\.subject).first
        )
        let defaultToRecipients = targetMessage.fromEmail.map { [$0] } ?? []
        let bodyText = requestedBodyText ?? ""
        var draft = try await client.createEmailDraft(EmailDraftCreateRequest(
            threadId: detail.threadId,
            providerThreadId: detail.providerThreadId,
            targetMessageId: targetMessage.id,
            accountEmail: detail.accountEmail,
            mode: .reply,
            origin: .agent,
            toRecipients: requestedToRecipients ?? defaultToRecipients,
            ccRecipients: requestedCcRecipients ?? [],
            bccRecipients: requestedBccRecipients ?? [],
            subject: requestedSubject ?? defaultSubject,
            bodyText: bodyText,
            inReplyToHeader: targetMessage.internetMessageId,
            referencesHeader: targetMessage.internetMessageId
        ))

        let patch = EmailDraftPatch(
            subject: requestedSubject,
            toRecipients: requestedToRecipients,
            ccRecipients: requestedCcRecipients,
            bccRecipients: requestedBccRecipients,
            bodyText: requestedBodyText
        )
        if !patch.isEmpty {
            draft = try await client.updateEmailDraft(
                localDraftId: draft.localDraftId,
                baseVersion: draft.version,
                patch: patch,
                origin: .agent
            )
        }
        upsertDraft(draft, threadId: threadId)
        return draft
    }

    func updateAgentDraft(
        threadId requestedThreadId: String?,
        localDraftId: String,
        baseVersion: Int?,
        patch: EmailDraftPatch
    ) async throws -> EmailDraftSnapshot {
        guard !localDraftId.isEmpty else {
            throw ZebraEmailDraftSocketError.invalidParams("local_draft_id is required")
        }
        guard !patch.isEmpty else {
            throw ZebraEmailDraftSocketError.invalidParams("at least one draft field is required")
        }
        guard let threadId = resolveDraftThreadId(requestedThreadId, localDraftId: localDraftId) else {
            throw ZebraEmailDraftSocketError.invalidParams("thread_id is required")
        }
        let draft = try await client.updateEmailDraft(
            localDraftId: localDraftId,
            baseVersion: baseVersion,
            patch: patch,
            origin: .agent
        )
        upsertDraft(draft, threadId: threadId)
        return draft
    }

    func createReplyDraft(threadId: String, targetMessageId: String) {
        guard let detail = threadStates[threadId]?.detail,
              let targetMessage = detail.messages.first(where: { $0.id == targetMessageId }) else { return }
        var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
        var expanded = state.expandedMessageIds ?? []
        expanded.insert(targetMessage.id)
        state.expandedMessageIds = expanded
        threadStates[threadId] = state

        Task {
            do {
                let draft = try await client.createEmailDraft(EmailDraftCreateRequest(
                    threadId: detail.threadId,
                    providerThreadId: detail.providerThreadId,
                    targetMessageId: targetMessage.id,
                    accountEmail: detail.accountEmail,
                    mode: .reply,
                    origin: .user,
                    toRecipients: targetMessage.fromEmail.map { [$0] } ?? [],
                    subject: replySubject(for: targetMessage, fallbackSubject: detail.messages.compactMap(\.subject).first),
                    bodyText: "",
                    inReplyToHeader: targetMessage.internetMessageId,
                    referencesHeader: targetMessage.internetMessageId
                ))
                upsertDraft(draft, threadId: threadId)
            } catch {
                setDraftError(error, threadId: threadId)
            }
        }
    }

    func updateDraftBody(threadId: String, localDraftId: String, baseVersion: Int, bodyText: String) {
        updateDraft(
            threadId: threadId,
            localDraftId: localDraftId,
            baseVersion: baseVersion,
            patch: EmailDraftPatch(bodyText: bodyText)
        )
    }

    func updateDraft(threadId: String, localDraftId: String, baseVersion: Int, patch: EmailDraftPatch) {
        enqueueDraftUpdate(
            threadId: threadId,
            localDraftId: localDraftId,
            baseVersion: baseVersion,
            patch: patch,
            sendAfterFlush: false
        )
    }

    func sendDraft(threadId: String, localDraftId: String, baseVersion: Int, patch: EmailDraftPatch) {
        enqueueDraftUpdate(
            threadId: threadId,
            localDraftId: localDraftId,
            baseVersion: baseVersion,
            patch: patch,
            sendAfterFlush: true
        )
    }

    private func enqueueDraftUpdate(
        threadId: String,
        localDraftId: String,
        baseVersion: Int,
        patch: EmailDraftPatch,
        sendAfterFlush: Bool
    ) {
        guard !patch.isEmpty || sendAfterFlush else { return }
        var queue = draftUpdateQueues[localDraftId] ?? ZebraEmailDraftUpdateQueue(threadId: threadId)
        queue.threadId = threadId
        if !patch.isEmpty {
            queue.merge(baseVersion: baseVersion, patch: patch)
        }
        queue.sendAfterFlush = queue.sendAfterFlush || sendAfterFlush
        draftUpdateQueues[localDraftId] = queue
        processNextDraftUpdate(localDraftId: localDraftId)
    }

    private func processNextDraftUpdate(localDraftId: String) {
        guard var queue = draftUpdateQueues[localDraftId],
              !queue.isProcessing else { return }

        if queue.patch.isEmpty {
            guard queue.sendAfterFlush else { return }
            queue.sendAfterFlush = false
            queue.isProcessing = true
            draftUpdateQueues[localDraftId] = queue
            sendQueuedDraft(localDraftId: localDraftId, threadId: queue.threadId)
            return
        }

        let threadId = queue.threadId
        let baseVersion = currentDraftVersion(threadId: threadId, localDraftId: localDraftId) ?? queue.fallbackBaseVersion
        let patch = queue.patch
        queue.patch = EmailDraftPatch()
        queue.fallbackBaseVersion = nil
        queue.isProcessing = true
        draftUpdateQueues[localDraftId] = queue

        Task {
            do {
                let draft = try await client.updateEmailDraft(
                    localDraftId: localDraftId,
                    baseVersion: baseVersion,
                    patch: patch,
                    origin: .user
                )
                upsertDraft(draft, threadId: threadId)
                completeDraftUpdate(localDraftId: localDraftId)
            } catch {
                retainFailedDraftUpdate(localDraftId: localDraftId, patch: patch)
                setDraftError(error, threadId: threadId, localDraftId: localDraftId)
            }
        }
    }

    private func completeDraftUpdate(localDraftId: String) {
        guard var queue = draftUpdateQueues[localDraftId] else { return }
        queue.isProcessing = false
        if queue.patch.isEmpty && !queue.sendAfterFlush {
            draftUpdateQueues[localDraftId] = nil
        } else {
            draftUpdateQueues[localDraftId] = queue
            processNextDraftUpdate(localDraftId: localDraftId)
        }
    }

    private func retainFailedDraftUpdate(localDraftId: String, patch: EmailDraftPatch) {
        guard var queue = draftUpdateQueues[localDraftId] else { return }
        let pendingPatch = queue.patch
        let pendingFallbackBaseVersion = queue.fallbackBaseVersion
        queue.isProcessing = false
        queue.patch = patch
        queue.fallbackBaseVersion = pendingFallbackBaseVersion
        queue.merge(baseVersion: pendingFallbackBaseVersion, patch: pendingPatch)
        draftUpdateQueues[localDraftId] = queue
    }

    private func sendQueuedDraft(localDraftId: String, threadId: String) {
        markDraftSending(threadId: threadId, localDraftId: localDraftId, isSending: true)
        Task {
            do {
                let sentDraft = try await client.sendEmailDraft(localDraftId: localDraftId)
                completeDraftSend(sentDraft, threadId: threadId)
                onThreadSummariesChanged()
                await reloadThread(threadId: threadId, forceRefresh: true)
                onThreadSummariesChanged()
            } catch {
                failDraftSend(localDraftId: localDraftId, threadId: threadId, error: error)
            }
        }
    }

    private func completeDraftSend(_ sentDraft: EmailDraftSnapshot, threadId: String) {
        let localDraftId = sentDraft.localDraftId
        draftUpdateQueues[localDraftId] = nil
        var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
        state.sendingDraftIds.remove(localDraftId)
        state.draftErrorMessages[localDraftId] = nil
        state.drafts.removeAll { $0.localDraftId == localDraftId }
        if let detail = state.detail {
            let sentMessage = sentThreadMessage(from: sentDraft)
            var messages = detail.messages.filter { $0.id != sentMessage.id }
            messages.append(sentMessage)
            messages.sort {
                ($0.receivedAt ?? .distantPast) == ($1.receivedAt ?? .distantPast)
                    ? $0.id < $1.id
                    : ($0.receivedAt ?? .distantPast) < ($1.receivedAt ?? .distantPast)
            }
            state.detail = EmailThreadDetail(
                threadId: detail.threadId,
                providerThreadId: detail.providerThreadId,
                accountEmail: detail.accountEmail,
                cached: detail.cached,
                messages: messages
            )
            var expanded = state.expandedMessageIds ?? []
            expanded.insert(sentMessage.id)
            state.expandedMessageIds = expanded
        }
        threadStates[threadId] = state
    }

    private func sentThreadMessage(from draft: EmailDraftSnapshot) -> EmailThreadMessage {
        let messageId = draft.providerMessageId?.nilIfEmpty ?? "local-sent-\(draft.localDraftId)"
        let bodyText = draft.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let snippet = bodyText?
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        return EmailThreadMessage(
            id: messageId,
            internetMessageId: nil,
            subject: draft.subject.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            fromName: nil,
            fromEmail: draft.accountEmail,
            to: draft.toRecipients.joined(separator: ", ").nilIfEmpty,
            cc: draft.ccRecipients.joined(separator: ", ").nilIfEmpty,
            receivedAt: draft.sentAt ?? Date(),
            snippet: snippet,
            labelIds: ["SENT"],
            isUnread: false,
            isSent: true,
            hasAttachment: false,
            bodyText: bodyText,
            bodyHtml: nil
        )
    }

    private func failDraftSend(localDraftId: String, threadId: String, error: Error) {
        if var queue = draftUpdateQueues[localDraftId] {
            queue.isProcessing = false
            draftUpdateQueues[localDraftId] = queue.patch.isEmpty && !queue.sendAfterFlush ? nil : queue
        }
        markDraftSending(threadId: threadId, localDraftId: localDraftId, isSending: false)
        setDraftError(error, threadId: threadId, localDraftId: localDraftId)
    }

    private func markDraftSending(threadId: String, localDraftId: String, isSending: Bool) {
        var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
        if isSending {
            state.sendingDraftIds.insert(localDraftId)
            state.draftErrorMessages[localDraftId] = nil
        } else {
            state.sendingDraftIds.remove(localDraftId)
        }
        threadStates[threadId] = state
    }

    private func currentDraftVersion(threadId: String, localDraftId: String) -> Int? {
        threadStates[threadId]?.drafts.first { $0.localDraftId == localDraftId }?.version
    }

    func discardDraft(threadId: String, localDraftId: String) {
        Task {
            do {
                try await client.discardEmailDraft(localDraftId: localDraftId)
                var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
                state.drafts.removeAll { $0.localDraftId == localDraftId }
                state.draftErrorMessages[localDraftId] = nil
                state.sendingDraftIds.remove(localDraftId)
                threadStates[threadId] = state
                draftUpdateQueues[localDraftId] = nil
            } catch {
                setDraftError(error, threadId: threadId, localDraftId: localDraftId)
            }
        }
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

    private func loadDrafts(threadId: String) async {
        do {
            let drafts = try await client.emailDrafts(threadId: threadId)
            var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
            state.drafts = drafts
            threadStates[threadId] = state
        } catch {
            setDraftError(error, threadId: threadId)
        }
    }

    private func upsertDraft(_ draft: EmailDraftSnapshot, threadId: String) {
        var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
        state.draftErrorMessage = nil
        state.draftErrorMessages[draft.localDraftId] = nil
        if let index = state.drafts.firstIndex(where: { $0.localDraftId == draft.localDraftId }) {
            state.drafts[index] = draft
        } else {
            state.drafts.append(draft)
            state.drafts.sort { $0.createdAt < $1.createdAt }
        }
        threadStates[threadId] = state
    }

    private func resolveDraftThreadId(_ requestedThreadId: String?, localDraftId: String? = nil) -> String? {
        if let requestedThreadId, !requestedThreadId.isEmpty {
            return requestedThreadId
        }
        if let localDraftId {
            for (threadId, state) in threadStates where state.drafts.contains(where: { $0.localDraftId == localDraftId }) {
                return threadId
            }
        }
        return selectedThreadId
    }

    private func loadDetailForAgentCommand(threadId: String) async throws -> EmailThreadDetail {
        if let detail = threadStates[threadId]?.detail {
            return detail
        }
        let detail = try await client.threadMessages(threadId: threadId, forceRefresh: false)
        let drafts = try await client.emailDrafts(threadId: detail.threadId)
        var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
        state.detail = detail
        state.drafts = drafts
        if state.expandedMessageIds == nil {
            state.expandedMessageIds = defaultExpandedMessageIds(detail)
        }
        threadStates[threadId] = state
        return detail
    }

    private func setDraftError(_ error: Error, threadId: String, localDraftId: String? = nil) {
        var state = threadStates[threadId] ?? ZebraEmailThreadUIState()
        if let localDraftId {
            state.draftErrorMessages[localDraftId] = displayError(error)
        } else {
            state.draftErrorMessage = displayError(error)
        }
        threadStates[threadId] = state
    }

    private func replySubject(for message: EmailThreadMessage, fallbackSubject: String?) -> String {
        let messageSubject = message.subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = fallbackSubject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let raw = messageSubject.isEmpty ? fallback : messageSubject
        guard raw.range(of: "re:", options: [.caseInsensitive, .anchored]) == nil else { return raw }
        return raw.isEmpty ? "Re:" : "Re: \(raw)"
    }

    private func displayError(_ error: Error) -> String {
        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count > 240 else { return raw }
        let index = raw.index(raw.startIndex, offsetBy: 240)
        return String(raw[..<index]) + "..."
    }

    private static func connectionRepairState(for error: Error) -> ZebraEmailConnectionRepairState? {
        guard let clawvisorError = error as? ZebraClawvisorEmailClientError else {
            return nil
        }
        return clawvisorError.connectionRepairState
    }
}

private struct ZebraEmailThreadUIState {
    var detail: EmailThreadDetail?
    var drafts: [EmailDraftSnapshot] = []
    var draftErrorMessage: String?
    var draftErrorMessages: [String: String] = [:]
    var sendingDraftIds: Set<String> = []
    var isLoading = false
    var isArchiving = false
    var errorMessage: String?
    var archiveErrorMessage: String?
    var expandedMessageIds: Set<String>?
}

private struct ZebraEmailDraftUpdateQueue {
    var threadId: String
    var patch = EmailDraftPatch()
    var fallbackBaseVersion: Int?
    var isProcessing = false
    var sendAfterFlush = false

    mutating func merge(baseVersion: Int?, patch nextPatch: EmailDraftPatch) {
        if fallbackBaseVersion == nil {
            fallbackBaseVersion = baseVersion
        }
        patch = EmailDraftPatch(
            subject: nextPatch.subject ?? patch.subject,
            toRecipients: nextPatch.toRecipients ?? patch.toRecipients,
            ccRecipients: nextPatch.ccRecipients ?? patch.ccRecipients,
            bccRecipients: nextPatch.bccRecipients ?? patch.bccRecipients,
            bodyText: nextPatch.bodyText ?? patch.bodyText
        )
    }
}

enum ZebraEmailDraftSocketError: LocalizedError {
    case unavailable(String)
    case invalidParams(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .invalidParams(let message), .notFound(let message):
            return message
        }
    }
}

@MainActor
final class ZebraEmailDraftSocketBridge {
    static let shared = ZebraEmailDraftSocketBridge()

    private final class Context {
        weak var tabManager: TabManager?
        weak var emailListStore: ZebraEmailListStore?
        weak var emailDetailStore: ZebraEmailDetailStore?
        weak var agentTerminals: ZebraAgentTerminalRegistry?

        init(
            tabManager: TabManager?,
            emailListStore: ZebraEmailListStore,
            emailDetailStore: ZebraEmailDetailStore,
            agentTerminals: ZebraAgentTerminalRegistry
        ) {
            self.tabManager = tabManager
            self.emailListStore = emailListStore
            self.emailDetailStore = emailDetailStore
            self.agentTerminals = agentTerminals
        }

        var isAlive: Bool {
            emailListStore != nil && emailDetailStore != nil && agentTerminals != nil
        }
    }

    private var contextsByTabManager: [ObjectIdentifier: Context] = [:]
    private var fallbackContext: Context?

    private init() {}

    func configure(
        tabManager: TabManager?,
        emailListStore: ZebraEmailListStore,
        emailDetailStore: ZebraEmailDetailStore,
        agentTerminals: ZebraAgentTerminalRegistry
    ) {
        let context = Context(
            tabManager: tabManager,
            emailListStore: emailListStore,
            emailDetailStore: emailDetailStore,
            agentTerminals: agentTerminals
        )
        if let tabManager {
            contextsByTabManager[ObjectIdentifier(tabManager)] = context
        }
        fallbackContext = context
    }

    func handleAsync(method: String, params: [String: Any], controller: TerminalController) async throws -> [String: Any] {
        let tabManager = controller.v2ResolveTabManager(params: params)
        guard let context = context(for: tabManager),
              let detailStore = context.emailDetailStore else {
            throw ZebraEmailDraftSocketError.unavailable("Zebra email draft store is unavailable")
        }
        switch method {
        case "zebra.email_draft.list":
            let drafts = try await detailStore.agentDrafts(threadId: Self.string(params, "thread_id", "threadId"))
            return ["drafts": drafts.map(Self.draftPayload)]
        case "zebra.email_draft.create":
            let draft = try await detailStore.createAgentReplyDraft(
                threadId: Self.string(params, "thread_id", "threadId"),
                targetMessageId: Self.string(params, "target_message_id", "targetMessageId"),
                subject: Self.string(params, "subject"),
                toRecipients: Self.recipients(params, "to", "to_recipients", "toRecipients"),
                ccRecipients: Self.recipients(params, "cc", "cc_recipients", "ccRecipients"),
                bccRecipients: Self.recipients(params, "bcc", "bcc_recipients", "bccRecipients"),
                bodyText: Self.rawString(params, "body_text", "bodyText", "body")
            )
            return ["draft": Self.draftPayload(draft)]
        case "zebra.email_draft.update":
            guard let localDraftId = Self.string(params, "local_draft_id", "localDraftId", "draft_id", "draftId") else {
                throw ZebraEmailDraftSocketError.invalidParams("local_draft_id is required")
            }
            let draft = try await detailStore.updateAgentDraft(
                threadId: Self.string(params, "thread_id", "threadId"),
                localDraftId: localDraftId,
                baseVersion: Self.int(params, "base_version", "baseVersion"),
                patch: EmailDraftPatch(
                    subject: Self.string(params, "subject"),
                    toRecipients: Self.recipients(params, "to", "to_recipients", "toRecipients"),
                    ccRecipients: Self.recipients(params, "cc", "cc_recipients", "ccRecipients"),
                    bccRecipients: Self.recipients(params, "bcc", "bcc_recipients", "bccRecipients"),
                    bodyText: Self.rawString(params, "body_text", "bodyText", "body")
                )
            )
            return ["draft": Self.draftPayload(draft)]
        default:
            throw ZebraEmailDraftSocketError.notFound("Unknown Zebra email draft method")
        }
    }

    func handleFocus(params: [String: Any], controller: TerminalController) -> TerminalController.V2CallResult {
        guard let tabManager = controller.v2ResolveTabManager(params: params) else {
            return .err(code: "unavailable", message: "TabManager not available", data: nil)
        }
        guard let context = context(for: tabManager),
              let detailStore = context.emailDetailStore,
              let agentTerminals = context.agentTerminals else {
            return .err(code: "unavailable", message: "Zebra email draft store is unavailable", data: nil)
        }
        let localDraftId = Self.string(params, "local_draft_id", "localDraftId", "draft_id", "draftId")
        guard let threadId = Self.string(params, "thread_id", "threadId") ?? threadIdForLoadedDraft(localDraftId, detailStore: detailStore) else {
            return .err(code: "invalid_params", message: "thread_id is required", data: nil)
        }
        guard let thread = context.emailListStore?.threadItem(threadId: threadId) ?? syntheticThreadItem(threadId: threadId, detailStore: detailStore) else {
            return .err(code: "not_found", message: "Email thread not found", data: ["thread_id": threadId])
        }
        guard let workspace = controller.v2ResolveWorkspace(params: params, tabManager: tabManager) else {
            return .err(code: "not_found", message: "Workspace not found", data: nil)
        }

        controller.v2MaybeFocusWindow(for: tabManager)
        controller.v2MaybeSelectWorkspace(tabManager, workspace: workspace)

        let excludedPaneIds = workspace.zebraAgentCompanionPaneIds(markedBy: agentTerminals)
        guard let panel = workspace.openOrFocusEmailThreadContent(
            thread: thread,
            excludedAgentCompanionPaneIds: excludedPaneIds,
            requestedPaneId: nil
        ) else {
            return .err(code: "internal_error", message: "Failed to focus email thread", data: ["thread_id": threadId])
        }
        detailStore.selectThread(thread)
        return .ok([
            "thread_id": threadId,
            "local_draft_id": localDraftId as Any? ?? NSNull(),
            "surface_id": panel.id.uuidString,
            "surface_ref": controller.v2Ref(kind: .surface, uuid: panel.id),
            "workspace_id": workspace.id.uuidString,
            "workspace_ref": controller.v2Ref(kind: .workspace, uuid: workspace.id),
        ])
    }

    private func threadIdForLoadedDraft(_ localDraftId: String?, detailStore: ZebraEmailDetailStore) -> String? {
        guard let localDraftId else { return nil }
        if let selectedThreadId = detailStore.selectedThreadId,
           detailStore.drafts(threadId: selectedThreadId).contains(where: { $0.localDraftId == localDraftId }) {
            return selectedThreadId
        }
        return detailStore.threadIdForDraft(localDraftId: localDraftId)
    }

    private func syntheticThreadItem(threadId: String, detailStore: ZebraEmailDetailStore) -> EmailThreadItem? {
        guard let detail = detailStore.detail(threadId: threadId),
              let latest = detail.messages.last else { return nil }
        return EmailThreadItem(
            id: threadId,
            subject: latest.subject ?? "(no subject)",
            senderName: latest.fromName ?? latest.fromEmail ?? "",
            receivedAt: latest.receivedAt ?? Date(),
            unread: detail.messages.contains(where: \.isUnread),
            starred: detail.messages.contains { $0.labelIds.contains("STARRED") },
            hasAttachment: detail.messages.contains(where: \.hasAttachment),
            labelIds: Array(Set(detail.messages.flatMap(\.labelIds))).sorted(),
            category: nil
        )
    }

    private static func draftPayload(_ draft: EmailDraftSnapshot) -> [String: Any] {
        [
            "local_draft_id": draft.localDraftId,
            "thread_id": draft.threadId,
            "provider_thread_id": draft.providerThreadId as Any? ?? NSNull(),
            "target_message_id": draft.targetMessageId as Any? ?? NSNull(),
            "provider_draft_id": draft.providerDraftId as Any? ?? NSNull(),
            "provider_message_id": draft.providerMessageId as Any? ?? NSNull(),
            "account_email": draft.accountEmail as Any? ?? NSNull(),
            "mode": draft.mode.rawValue,
            "display_name": draft.displayName,
            "origin": draft.origin.rawValue,
            "status": draft.status.rawValue,
            "sync_state": draft.syncState.rawValue,
            "version": draft.version,
            "to": draft.toRecipients,
            "cc": draft.ccRecipients,
            "bcc": draft.bccRecipients,
            "subject": draft.subject,
            "body_text": draft.bodyText,
            "in_reply_to_header": draft.inReplyToHeader as Any? ?? NSNull(),
            "references_header": draft.referencesHeader as Any? ?? NSNull(),
            "last_error": draft.lastError as Any? ?? NSNull(),
            "created_at": isoString(draft.createdAt),
            "updated_at": isoString(draft.updatedAt),
            "synced_at": draft.syncedAt.map(isoString) as Any? ?? NSNull(),
            "sent_at": draft.sentAt.map(isoString) as Any? ?? NSNull(),
        ]
    }

    private func context(for tabManager: TabManager?) -> Context? {
        if let tabManager {
            let key = ObjectIdentifier(tabManager)
            if let context = contextsByTabManager[key], context.isAlive {
                return context
            }
            contextsByTabManager[key] = nil
        }
        if let context = fallbackContext, context.isAlive {
            return context
        }
        fallbackContext = nil
        return nil
    }

    private static func string(_ params: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            guard let raw = params[key] else { continue }
            if raw is NSNull { continue }
            if let string = raw as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let number = raw as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func rawString(_ params: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            guard let raw = params[key] else { continue }
            if raw is NSNull { continue }
            if let string = raw as? String {
                return string
            } else if let number = raw as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func recipients(_ params: [String: Any], _ keys: String...) -> [String]? {
        for key in keys {
            guard let raw = params[key], !(raw is NSNull) else { continue }
            if let array = raw as? [String] {
                return normalizeRecipients(array)
            }
            if let array = raw as? [Any] {
                return normalizeRecipients(array.compactMap { $0 as? String })
            }
            if let string = raw as? String {
                return normalizeRecipients(string.split(separator: ",").map(String.init))
            }
        }
        return nil
    }

    private static func normalizeRecipients(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func int(_ params: [String: Any], _ keys: String...) -> Int? {
        for key in keys {
            guard let raw = params[key], !(raw is NSNull) else { continue }
            if let int = raw as? Int { return int }
            if let number = raw as? NSNumber { return number.intValue }
            if let string = raw as? String,
               let int = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return int
            }
        }
        return nil
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

extension TerminalController {
    nonisolated func socketWorkerZebraEmailDraftResponse(
        method: String,
        id: Any?,
        params: [String: Any]
    ) -> String {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<[String: Any], Error>?
        let task = Task {
            do {
                result = .success(try await ZebraEmailDraftSocketBridge.shared.handleAsync(method: method, params: params, controller: self))
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 30) == .timedOut {
            task.cancel()
            return v2Error(id: id, code: "timeout", message: "Zebra email draft request timed out")
        }
        switch result {
        case .success(let payload):
            return zebraEmailDraftSuccessResponse(id: id, payload: payload)
        case .failure(let error):
            return zebraEmailDraftErrorResponse(id: id, error: error)
        case nil:
            return v2Error(id: id, code: "internal_error", message: "Unknown Zebra email draft error")
        }
    }

    func v2ZebraEmailDraftFocus(params: [String: Any]) -> V2CallResult {
        ZebraEmailDraftSocketBridge.shared.handleFocus(params: params, controller: self)
    }

    private nonisolated func zebraEmailDraftErrorResponse(id: Any?, error: Error) -> String {
        if let error = error as? ZebraEmailDraftSocketError {
            switch error {
            case .unavailable(let message):
                return v2Error(id: id, code: "unavailable", message: message)
            case .invalidParams(let message):
                return v2Error(id: id, code: "invalid_params", message: message)
            case .notFound(let message):
                return v2Error(id: id, code: "not_found", message: message)
            }
        }
        return v2Error(id: id, code: "operation_failed", message: error.localizedDescription)
    }

    private nonisolated func zebraEmailDraftSuccessResponse(id: Any?, payload: [String: Any]) -> String {
        zebraEmailDraftEncode([
            "id": id ?? NSNull(),
            "ok": true,
            "result": payload
        ])
    }

    private nonisolated func zebraEmailDraftEncode(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8)
        else {
            return v2Error(id: nil, code: "encode_failed", message: "Failed to encode Zebra email draft response")
        }
        return json
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
