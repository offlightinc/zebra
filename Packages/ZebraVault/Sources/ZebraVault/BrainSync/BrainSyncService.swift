import AppKit
import Combine
import Foundation

/// Brain repo (e.g. `~/brain-offlight/`) 의 git sync 를 zebra 가 직접 owns 하는
/// runtime core. 기존 launchd plist (`ai.offlight.local-brain-sync`) 와는 완전
/// 분리 — 사용자 머신에 그게 살아있어도 zebra 는 모름. 단순히 같은 brain repo 를
/// 양쪽에서 동시에 sync 시도할 뿐 (git lock 으로 데이터는 안전).
///
/// 책임:
/// - 15분 간격 schedule (background queue `DispatchSourceTimer`)
/// - app launch 직후 1회, system wake 시 1회 즉시 sync
/// - bundled bash 스크립트 (`zebra-brain-sync`) 를 subprocess 로 호출
/// - stderr 의 `[REASON:<id>]` 태그 또는 패턴 매칭으로 `FailureReason` 분류
/// - state 를 sentinel JSON (`~/Library/Application Support/zebra/brainsync/last-sync.json`) 에 영구화
/// - 로그를 `~/Library/Logs/zebra/brainsync.log` 에 append
///
/// V1 = 단일 sync only. `bind(vaultRoot:)` 로 active sync target vault 가 동적으로
/// 바뀜. 동시 multi-vault sync 는 V2.
@MainActor
public final class BrainSyncService: ObservableObject {
    public enum SyncState: Equatable, Sendable {
        case synced(at: Date, commit: String)
        case failed(at: Date, reason: FailureReason, detail: String)
    }

    public enum FailureReason: String, Sendable, Codable {
        case authExpired
        case offline
        case pushRejected
        case permissionDenied
        case diskFull
        case hookFailed
        case rateLimit
        case conflict
        case unknown

        public var humanLabel: String {
            switch self {
            case .authExpired: return String(localized: "brainSync.reason.authExpired", defaultValue: "인증 토큰 만료")
            case .offline: return String(localized: "brainSync.reason.offline", defaultValue: "오프라인")
            case .pushRejected: return String(localized: "brainSync.reason.pushRejected", defaultValue: "Push 거절")
            case .permissionDenied: return String(localized: "brainSync.reason.permissionDenied", defaultValue: "권한 없음")
            case .diskFull: return String(localized: "brainSync.reason.diskFull", defaultValue: "디스크 공간 부족")
            case .hookFailed: return String(localized: "brainSync.reason.hookFailed", defaultValue: "Pre-commit hook 실패")
            case .rateLimit: return String(localized: "brainSync.reason.rateLimit", defaultValue: "Rate limit")
            case .conflict: return String(localized: "brainSync.reason.conflict", defaultValue: "동기화 충돌")
            case .unknown: return String(localized: "brainSync.reason.unknown", defaultValue: "기타 오류")
            }
        }
    }

    @Published public private(set) var state: SyncState?
    @Published public private(set) var isSyncing: Bool = false

    public var vaultRoot: String? { boundVault }

    private static let interval: TimeInterval = 15 * 60
    private static let timerQueueLabel = "com.zebra.brainsync.timer"
    private static let runQueueLabel = "com.zebra.brainsync.run"

    private let timerQueue = DispatchQueue(label: timerQueueLabel, qos: .utility)
    private let runQueue = DispatchQueue(label: runQueueLabel, qos: .utility)

    private var timerSource: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var currentTask: Task<Void, Never>?
    private var boundVault: String?
    private var started = false
    private var vaultCancellable: AnyCancellable?

    public init() {
        // Sentinel 로부터 마지막 sync state 복원 (앱 재시작 후에도 "X분 전" 유지).
        if let restored = Self.loadSentinel() {
            self.state = restored
        }
    }

    // MARK: - Lifecycle

    /// `applicationDidFinishLaunching` 에서 호출. Timer + wake observer 등록 +
    /// launch 직후 1회 즉시 sync. 이미 started 면 no-op (idempotent).
    public func start() {
        guard !started else { return }
        started = true
        registerWakeObserver()
        registerTerminateObserver()
        scheduleTimer()
        triggerSync()
    }

    /// `applicationWillTerminate` 에서 호출. Timer/observer 해제 + in-flight sync
    /// 가 있으면 최대 `graceful` 초 대기, 안 끝나면 강제 종료. default 5.
    public func stop(graceful: TimeInterval = 5) {
        guard started else { return }
        started = false
        timerSource?.cancel()
        timerSource = nil
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
        if let observer = terminateObserver {
            NotificationCenter.default.removeObserver(observer)
            terminateObserver = nil
        }
        waitForInFlightSync(timeout: graceful)
    }

    /// Vault 선택 변경 시 호출 (또는 처음 selection 결정 시). 같은 vault 면 no-op.
    public func bind(vaultRoot: String?) {
        let normalized = vaultRoot.flatMap { $0.isEmpty ? nil : $0 }
        guard normalized != boundVault else { return }
        boundVault = normalized
        if started, normalized != nil {
            triggerSync()
        }
    }

    /// `VerticalTabsSidebarVaultState` 의 `selectedVaultPath` 변경을 listen 해서
    /// 자동으로 `bind(vaultRoot:)` 호출. `ZebraServices.makeDefault()` 에서 한 번
    /// 호출하면 sync target 이 사용자의 vault 선택을 따라간다.
    public func attachVaultSource(_ vault: VerticalTabsSidebarVaultState) {
        vaultCancellable?.cancel()
        // 초기 bind
        bind(vaultRoot: vault.selectedVaultPath)
        vaultCancellable = vault.$selectedVaultPath
            .removeDuplicates()
            .sink { [weak self] newPath in
                Task { @MainActor in self?.bind(vaultRoot: newPath) }
            }
    }

    // MARK: - Trigger

    /// 사용자 클릭 / Timer tick / wake 모두 같은 entry. in-flight 면 no-op
    /// (스크립트 내부 lock 까지 갈 필요 없이 zebra 측에서 차단).
    public func triggerSync() {
        #if DEBUG
        NSLog("[BrainSync] triggerSync started=\(started) isSyncing=\(isSyncing) vault=\(boundVault ?? "nil")")
        #endif
        guard started, !isSyncing, let vault = boundVault else { return }
        isSyncing = true
        let startedAt = Date()
        let task = Task.detached(priority: .utility) { [weak self] in
            let outcome = await Self.run(vaultRoot: vault)
            // fail loop 인 vault 면 sync 가 1초 안에 끝나서 사용자가 transient
            // syncing 표시를 인지 못 함. 최소 0.45s 보장 — click 의 시각 feedback.
            let elapsed = Date().timeIntervalSince(startedAt)
            let minimum: TimeInterval = 0.45
            if elapsed < minimum {
                try? await Task.sleep(nanoseconds: UInt64((minimum - elapsed) * 1_000_000_000))
            }
            await MainActor.run {
                guard let self else { return }
                self.applyOutcome(outcome)
                self.isSyncing = false
                self.currentTask = nil
            }
        }
        currentTask = task
    }

    // MARK: - Schedule

    private func scheduleTimer() {
        let source = DispatchSource.makeTimerSource(queue: timerQueue)
        source.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .seconds(30))
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.triggerSync() }
        }
        source.resume()
        timerSource = source
    }

    private func registerWakeObserver() {
        let center = NSWorkspace.shared.notificationCenter
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.triggerSync() }
        }
    }

    /// `NSApplication.willTerminateNotification` 을 받아 자가 `stop()` 호출.
    /// AppDelegate 의 cmux upstream 파일을 안 만지고 lifecycle 종결.
    private func registerTerminateObserver() {
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    private func waitForInFlightSync(timeout: TimeInterval) {
        guard currentTask != nil else { return }
        let deadline = Date().addingTimeInterval(timeout)
        // graceful 동안 main run loop 를 spin 시키며 currentTask 완료를 기다림.
        // applicationWillTerminate 안에서 호출되므로 run loop spin 이 허용됨.
        while currentTask != nil, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        // 시간 초과 시 task 는 그대로 두고 진행 — 프로세스가 곧 종료되므로 자연
        // 정리됨. git 명령 중간에 끊겨도 다음 sync 가 git op-in-progress 를
        // detect 해서 자동 복구.
    }

    // MARK: - Outcome handling

    private func applyOutcome(_ outcome: SyncOutcome) {
        let now = Date()
        switch outcome {
        case .success(let commit):
            state = .synced(at: now, commit: commit)
        case .failure(let reason, let detail):
            state = .failed(at: now, reason: reason, detail: detail)
        }
        Self.writeSentinel(state)
    }

    // MARK: - Sentinel persistence

    private static func brainSyncDirectory() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("zebra", isDirectory: true)
            .appendingPathComponent("brainsync", isDirectory: true)
    }

    private static func sentinelURL() -> URL {
        brainSyncDirectory().appendingPathComponent("last-sync.json", isDirectory: false)
    }

    private struct SentinelPayload: Codable {
        let timestamp: Date
        let kind: String   // "synced" | "failed"
        let reason: FailureReason?
        let detail: String?
        let commit: String?
    }

    static func writeSentinel(_ state: SyncState?) {
        guard let state else { return }
        try? FileManager.default.createDirectory(
            at: brainSyncDirectory(),
            withIntermediateDirectories: true
        )
        let payload: SentinelPayload
        switch state {
        case .synced(let at, let commit):
            payload = SentinelPayload(timestamp: at, kind: "synced", reason: nil, detail: nil, commit: commit)
        case .failed(let at, let reason, let detail):
            payload = SentinelPayload(timestamp: at, kind: "failed", reason: reason, detail: detail, commit: nil)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: sentinelURL(), options: .atomic)
    }

    static func loadSentinel() -> SyncState? {
        let url = sentinelURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(SentinelPayload.self, from: data) else { return nil }
        switch payload.kind {
        case "synced":
            return .synced(at: payload.timestamp, commit: payload.commit ?? "")
        case "failed":
            return .failed(
                at: payload.timestamp,
                reason: payload.reason ?? .unknown,
                detail: payload.detail ?? ""
            )
        default:
            return nil
        }
    }

    // MARK: - Run

    private enum SyncOutcome: Sendable {
        case success(commit: String)
        case failure(reason: FailureReason, detail: String)
    }

    private static func run(vaultRoot: String) async -> SyncOutcome {
        guard let scriptURL = bundledScriptURL() else {
            return .failure(reason: .hookFailed, detail: "zebra-brain-sync script missing from app bundle")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, "--repo", vaultRoot]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // PATH 보강 — git, gbrain CLI 등은 user shell PATH 의 일부일 수 있음.
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.bun/bin:\(NSHomeDirectory())/.local/bin"
        env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin") + ":" + extraPaths
        process.environment = env

        do {
            try process.run()
        } catch {
            return .failure(reason: .hookFailed, detail: "failed to launch zebra-brain-sync: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let stdout = (try? stdoutPipe.fileHandleForReading.readToEnd()).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let stderr = (try? stderrPipe.fileHandleForReading.readToEnd()).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        appendLog(vaultRoot: vaultRoot, exit: process.terminationStatus, stdout: stdout, stderr: stderr)

        if process.terminationStatus == 0 {
            let commit = parseCommit(stdout: stdout)
            return .success(commit: commit)
        }
        let (reason, detail) = classifyFailure(stderr: stderr, stdout: stdout)
        return .failure(reason: reason, detail: detail)
    }

    private static func bundledScriptURL() -> URL? {
        Bundle.main.url(forResource: "zebra-brain-sync", withExtension: nil)
    }

    private static func parseCommit(stdout: String) -> String {
        // 스크립트가 `committed <sha>` 같은 라인 emit 시 거기서 추출. 없으면 빈 string.
        let lines = stdout.split(separator: "\n")
        for line in lines.reversed() {
            let parts = line.split(separator: " ", maxSplits: 2)
            if parts.first == "committed", parts.count >= 2 {
                return String(parts[1])
            }
        }
        return ""
    }

    // MARK: - Failure classification

    static func classifyFailure(stderr: String, stdout: String) -> (FailureReason, String) {
        // Source A — 스크립트가 `[REASON:<id>]` 태그를 emit 했으면 우선.
        if let (reason, detail) = parseReasonTag(stderr: stderr) {
            return (reason, detail)
        }
        // Source B — git 명령 stderr 패턴 매칭.
        let haystack = (stderr + "\n" + stdout).lowercased()
        let lastStderrLine = stderr
            .split(separator: "\n", omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? ""

        if haystack.contains("authentication failed")
            || haystack.contains("could not read username")
            || haystack.contains(" 401 ")
            || haystack.hasSuffix(" 401") {
            return (.authExpired, lastStderrLine)
        }
        if haystack.contains("could not resolve host")
            || haystack.contains("connection refused")
            || haystack.contains("network is unreachable")
            || haystack.contains("timeout") {
            return (.offline, lastStderrLine)
        }
        if haystack.contains("merge conflict") || haystack.contains("conflict marker") {
            return (.conflict, lastStderrLine)
        }
        if haystack.contains("non-fast-forward") || haystack.contains("rejected") {
            return (.pushRejected, lastStderrLine)
        }
        if haystack.contains(" 403 ")
            || haystack.hasSuffix(" 403")
            || haystack.contains("permission denied")
            || haystack.contains("repository not found")
            || haystack.contains("write access to repository not granted") {
            return (.permissionDenied, lastStderrLine)
        }
        if haystack.contains("no space left on device") || haystack.contains("enospc") {
            return (.diskFull, lastStderrLine)
        }
        if haystack.contains("api rate limit") || haystack.contains(" 429 ") || haystack.hasSuffix(" 429") {
            return (.rateLimit, lastStderrLine)
        }
        return (.unknown, lastStderrLine)
    }

    private static func parseReasonTag(stderr: String) -> (FailureReason, String)? {
        for raw in stderr.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[REASON:") else { continue }
            guard let end = line.firstIndex(of: "]") else { continue }
            let idStart = line.index(line.startIndex, offsetBy: "[REASON:".count)
            let id = String(line[idStart..<end])
            let detail = String(line[line.index(after: end)...]).trimmingCharacters(in: .whitespaces)
            if let reason = FailureReason(rawValue: id) {
                return (reason, detail)
            }
        }
        return nil
    }

    // MARK: - Log

    private static func logDirectory() -> URL {
        let library = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("zebra", isDirectory: true)
    }

    private static func logURL() -> URL {
        logDirectory().appendingPathComponent("brainsync.log", isDirectory: false)
    }

    private static func appendLog(vaultRoot: String, exit: Int32, stdout: String, stderr: String) {
        try? FileManager.default.createDirectory(at: logDirectory(), withIntermediateDirectories: true)
        let ts = ISO8601DateFormatter().string(from: Date())
        var body = "[\(ts)] zebra-brain-sync --repo \(vaultRoot) exit=\(exit)\n"
        if !stdout.isEmpty { body += "── stdout ──\n\(stdout)\n" }
        if !stderr.isEmpty { body += "── stderr ──\n\(stderr)\n" }
        body += "\n"
        guard let data = body.data(using: .utf8) else { return }
        let url = logURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        }
    }
}
