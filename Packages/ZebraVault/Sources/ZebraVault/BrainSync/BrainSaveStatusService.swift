import Foundation

public enum BrainSaveFailureSource: String, Equatable, Sendable {
    case gbrainStatus
    case openClawCron
    case hermesCron
    case unavailable
}

public struct BrainSaveFailure: Error, Equatable, Sendable {
    public let source: BrainSaveFailureSource
    public let message: String

    public init(source: BrainSaveFailureSource, message: String) {
        self.source = source
        self.message = message
    }
}

public enum BrainSaveStatus: Equatable, Sendable {
    case unknown
    case saved(at: Date?)
    case saving(startedAt: Date?)
    case failed(at: Date?, reason: BrainSaveFailure)
}

public enum BrainSaveRuntime: String, Equatable, Sendable {
    case gbrain
    case openClaw
    case hermes
}

public struct BrainSaveStatusSnapshot: Equatable, Sendable {
    public let status: BrainSaveStatus
    public let runtime: BrainSaveRuntime?
    public let detail: String?

    public init(status: BrainSaveStatus, runtime: BrainSaveRuntime?, detail: String? = nil) {
        self.status = status
        self.runtime = runtime
        self.detail = detail
    }
}

public struct BrainSaveGBrainReport: Equatable, Sendable {
    public struct Cycle: Equatable, Sendable {
        public let lastFullFinishedAt: Date?
        public let lastTargetedFinishedAt: Date?

        public init(lastFullFinishedAt: Date?, lastTargetedFinishedAt: Date?) {
            self.lastFullFinishedAt = lastFullFinishedAt
            self.lastTargetedFinishedAt = lastTargetedFinishedAt
        }
    }

    public struct Queue: Equatable, Sendable {
        public let active: Int
        public let failed: Int
        public let dead: Int

        public init(active: Int, failed: Int, dead: Int) {
            self.active = active
            self.failed = failed
            self.dead = dead
        }
    }

    public let activeLockCount: Int
    public let queue: Queue?
    public let cycle: Cycle?
    public let warningCount: Int

    public init(activeLockCount: Int, queue: Queue?, cycle: Cycle?, warningCount: Int) {
        self.activeLockCount = activeLockCount
        self.queue = queue
        self.cycle = cycle
        self.warningCount = warningCount
    }
}

public enum BrainSaveRuntimeStatus: Equatable, Sendable {
    case none
    case openClaw(status: String, finishedAt: Date?, message: String?)
    case hermes(lastStatus: String?, lastRunAt: Date?, message: String?)
}

public enum BrainSaveStatusMapper {
    public static func map(
        gbrain: Result<BrainSaveGBrainReport, BrainSaveFailure>?,
        runtime: BrainSaveRuntimeStatus = .none
    ) -> BrainSaveStatusSnapshot {
        if case .openClaw(let status, _, let message) = runtime, status == "running" {
            return BrainSaveStatusSnapshot(
                status: .saving(startedAt: nil),
                runtime: .openClaw,
                detail: message
            )
        }

        let gbrainSnapshot = mapGBrain(gbrain)
        if case .saving = gbrainSnapshot?.status {
            return gbrainSnapshot!
        }
        if isGBrainHardFailure(gbrainSnapshot?.status) {
            return gbrainSnapshot!
        }

        switch runtime {
        case .openClaw(let status, let finishedAt, let message):
            switch status {
            case "error", "skipped":
                if runtimeFailureShouldWin(failedAt: finishedAt, gbrainSnapshot: gbrainSnapshot) {
                    return BrainSaveStatusSnapshot(
                        status: .failed(
                            at: finishedAt,
                            reason: BrainSaveFailure(
                                source: .openClawCron,
                                message: message ?? "OpenClaw cron \(status)"
                            )
                        ),
                        runtime: .openClaw,
                        detail: message
                    )
                }
            default:
                break
            }
        case .hermes(let lastStatus, let lastRunAt, let message):
            if lastStatus == "error", runtimeFailureShouldWin(failedAt: lastRunAt, gbrainSnapshot: gbrainSnapshot) {
                return BrainSaveStatusSnapshot(
                    status: .failed(
                        at: lastRunAt,
                        reason: BrainSaveFailure(
                            source: .hermesCron,
                            message: message ?? "Hermes cron failed"
                        )
                    ),
                    runtime: .hermes,
                    detail: message
                )
            }
        case .none:
            break
        }

        if let gbrainSnapshot {
            return gbrainSnapshot
        }
        return BrainSaveStatusSnapshot(status: .unknown, runtime: nil)
    }

    private static func mapGBrain(_ gbrain: Result<BrainSaveGBrainReport, BrainSaveFailure>?) -> BrainSaveStatusSnapshot? {
        guard let gbrain else {
            return nil
        }
        switch gbrain {
        case .failure(let failure):
            if failure.source == .unavailable {
                return BrainSaveStatusSnapshot(
                    status: .unknown,
                    runtime: nil,
                    detail: failure.message
                )
            }
            return BrainSaveStatusSnapshot(
                status: .failed(at: nil, reason: failure),
                runtime: .gbrain,
                detail: failure.message
            )
        case .success(let report):
            if report.activeLockCount > 0 || (report.queue?.active ?? 0) > 0 {
                return BrainSaveStatusSnapshot(status: .saving(startedAt: nil), runtime: .gbrain)
            }
            if (report.queue?.failed ?? 0) > 0 || (report.queue?.dead ?? 0) > 0 {
                return BrainSaveStatusSnapshot(
                    status: .failed(
                        at: nil,
                        reason: BrainSaveFailure(source: .gbrainStatus, message: "GBrain queue has failed or dead jobs")
                    ),
                    runtime: .gbrain
                )
            }
            if report.warningCount > 0 {
                return BrainSaveStatusSnapshot(
                    status: .failed(
                        at: nil,
                        reason: BrainSaveFailure(source: .gbrainStatus, message: "GBrain status returned warnings")
                    ),
                    runtime: .gbrain
                )
            }
            if let last = report.cycle?.lastTargetedFinishedAt ?? report.cycle?.lastFullFinishedAt {
                return BrainSaveStatusSnapshot(status: .saved(at: last), runtime: .gbrain)
            }
            return BrainSaveStatusSnapshot(status: .unknown, runtime: .gbrain)
        }
    }

    private static func isGBrainHardFailure(_ status: BrainSaveStatus?) -> Bool {
        guard case .failed(_, let reason) = status else { return false }
        return reason.source == .gbrainStatus
    }

    private static func runtimeFailureShouldWin(failedAt: Date?, gbrainSnapshot: BrainSaveStatusSnapshot?) -> Bool {
        guard let gbrainSnapshot else { return true }
        switch gbrainSnapshot.status {
        case .saved(let savedAt):
            guard let failedAt, let savedAt else { return false }
            return failedAt > savedAt
        case .unknown:
            return true
        case .saving, .failed:
            return false
        }
    }
}

@MainActor
public final class BrainSaveStatusService: ObservableObject {
    @Published public private(set) var snapshot = BrainSaveStatusSnapshot(status: .unknown, runtime: nil)
    @Published public private(set) var isRefreshing = false

    private let runner: BrainSaveCommandRunning
    private var refreshTask: Task<Void, Never>?

    public init(runner: BrainSaveCommandRunning = BrainSaveProcessRunner()) {
        self.runner = runner
    }

    deinit {
        refreshTask?.cancel()
    }

    public func start() {
        refresh()
    }

    public func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let runner = runner
        refreshTask = Task.detached(priority: .utility) {
            let snapshot = await BrainSaveStatusCollector.collect(runner: runner)
            await MainActor.run {
                self.snapshot = snapshot
                self.isRefreshing = false
            }
        }
    }
}

public protocol BrainSaveCommandRunning: Sendable {
    func run(_ command: String, _ arguments: [String]) async -> BrainSaveCommandResult
}

public struct BrainSaveCommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct BrainSaveProcessRunner: BrainSaveCommandRunning {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    public func run(_ command: String, _ arguments: [String]) async -> BrainSaveCommandResult {
        await withCheckedContinuation { continuation in
            let timeout = timeout
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.runSync(command, arguments, timeout: timeout))
            }
        }
    }

    private static func runSync(_ command: String, _ arguments: [String], timeout: TimeInterval) -> BrainSaveCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.bun/bin:\(NSHomeDirectory())/.local/bin"
        env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin") + ":" + extraPaths
        process.environment = env

        do {
            try process.run()
        } catch {
            return BrainSaveCommandResult(exitCode: 127, stdout: "", stderr: error.localizedDescription)
        }

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.zebra.brain-save-status.process-drain", attributes: .concurrent)
        nonisolated(unsafe) var stdoutData = Data()
        nonisolated(unsafe) var stderrData = Data()
        queue.async(group: group) {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        queue.async(group: group) {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            timedOut = true
            process.terminate()
        }
        process.waitUntilExit()
        group.wait()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        if timedOut {
            let detail = "\(command) \(arguments.joined(separator: " ")) timed out after \(Int(timeout))s"
            return BrainSaveCommandResult(exitCode: 124, stdout: stdout, stderr: stderr.isEmpty ? detail : "\(stderr)\n\(detail)")
        }
        return BrainSaveCommandResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}

public enum BrainSaveStatusCollector {
    public static func collect(runner: BrainSaveCommandRunning) async -> BrainSaveStatusSnapshot {
        let openClaw = await openClawStatus(runner: runner)
        if case .openClaw(let status, _, _) = openClaw, status == "running" {
            return BrainSaveStatusMapper.map(gbrain: nil, runtime: openClaw)
        }

        let hermes = hermesStatus()
        let gbrain = await gbrainReport(runner: runner)
        if case .openClaw = openClaw {
            return BrainSaveStatusMapper.map(gbrain: gbrain, runtime: openClaw)
        }
        if case .hermes = hermes {
            return BrainSaveStatusMapper.map(gbrain: gbrain, runtime: hermes)
        }
        return BrainSaveStatusMapper.map(gbrain: gbrain)
    }

    public static func gbrainReport(runner: BrainSaveCommandRunning) async -> Result<BrainSaveGBrainReport, BrainSaveFailure> {
        let result = await runner.run("gbrain", ["status", "--json"])
        guard result.exitCode == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = detail.isEmpty ? "gbrain status failed" : detail
            if result.exitCode == 127 || message.localizedCaseInsensitiveContains("No database URL") || message.localizedCaseInsensitiveContains("database_url is missing") {
                return .failure(BrainSaveFailure(source: .unavailable, message: message))
            }
            return .failure(BrainSaveFailure(source: .gbrainStatus, message: message))
        }
        guard let data = result.stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(BrainSaveFailure(source: .gbrainStatus, message: "gbrain status returned invalid JSON"))
        }
        return .success(parseGBrainReport(object))
    }

    public static func parseGBrainReport(_ object: [String: Any]) -> BrainSaveGBrainReport {
        let locks: Int = {
            if let rows = object["locks"] as? [[String: Any]] {
                return rows.count
            }
            return 0
        }()
        let queue: BrainSaveGBrainReport.Queue? = {
            guard let raw = object["queue"] as? [String: Any],
                  raw["local_only_remote"] == nil else { return nil }
            return BrainSaveGBrainReport.Queue(
                active: intValue(raw["active"]),
                failed: intValue(raw["failed"]),
                dead: intValue(raw["dead"])
            )
        }()
        let cycle: BrainSaveGBrainReport.Cycle? = {
            guard let raw = object["cycle"] as? [String: Any] else { return nil }
            let full = raw["last_full"] as? [String: Any]
            let targeted = raw["last_targeted"] as? [String: Any]
            return BrainSaveGBrainReport.Cycle(
                lastFullFinishedAt: dateValue(full?["finished_at"]),
                lastTargetedFinishedAt: dateValue(targeted?["finished_at"])
            )
        }()
        let warnings = (object["warnings"] as? [Any])?.count ?? 0
        return BrainSaveGBrainReport(activeLockCount: locks, queue: queue, cycle: cycle, warningCount: warnings)
    }

    public static func parseOpenClawRuntime(_ object: Any) -> BrainSaveRuntimeStatus {
        let jobs: [[String: Any]]
        if let array = object as? [[String: Any]] {
            jobs = array
        } else if let dict = object as? [String: Any],
                  let array = dict["jobs"] as? [[String: Any]] {
            jobs = array
        } else if let dict = object as? [String: Any],
                  looksLikeGBrainJob(dict) {
            jobs = [dict]
        } else {
            return .none
        }
        let candidates = jobs.filter(looksLikeGBrainJob)
        guard let job = preferredOpenClawJob(candidates) else { return .none }
        let status = stringValue(job["status"]) ?? stringValue((job["state"] as? [String: Any])?["lastRunStatus"]) ?? "idle"
        let state = job["state"] as? [String: Any]
        let finishedAt = dateValue(state?["lastFinishedAt"] ?? job["lastFinishedAt"] ?? job["finishedAt"])
        let message = stringValue(state?["lastError"] ?? job["lastError"] ?? job["error"])
        return .openClaw(status: status, finishedAt: finishedAt, message: message)
    }

    public static func parseHermesRuntime(_ object: [String: Any]) -> BrainSaveRuntimeStatus {
        guard let jobs = object["jobs"] as? [[String: Any]] else { return .none }
        let candidates = jobs.filter(looksLikeGBrainJob)
        guard let job = preferredHermesJob(candidates) else { return .none }
        return .hermes(
            lastStatus: stringValue(job["last_status"]),
            lastRunAt: dateValue(job["last_run_at"]),
            message: stringValue(job["last_error"]) ?? stringValue(job["last_delivery_error"])
        )
    }

    private static func openClawStatus(runner: BrainSaveCommandRunning) async -> BrainSaveRuntimeStatus {
        let result = await runner.run("openclaw", ["cron", "list", "--json"])
        guard result.exitCode == 0,
              let data = result.stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .none
        }
        return parseOpenClawRuntime(object)
    }

    private static func hermesStatus() -> BrainSaveRuntimeStatus {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".hermes/cron/jobs.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .none
        }
        return parseHermesRuntime(object)
    }

    private static func preferredOpenClawJob(_ jobs: [[String: Any]]) -> [String: Any]? {
        jobs.sorted { lhs, rhs in
            if openClawIsRunning(lhs) != openClawIsRunning(rhs) {
                return openClawIsRunning(lhs)
            }
            let lhsDate = openClawObservedAt(lhs) ?? .distantPast
            let rhsDate = openClawObservedAt(rhs) ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return openClawStatusRank(lhs) > openClawStatusRank(rhs)
        }.first
    }

    private static func openClawIsRunning(_ job: [String: Any]) -> Bool {
        let state = job["state"] as? [String: Any]
        return (stringValue(job["status"]) ?? stringValue(state?["lastRunStatus"])) == "running"
    }

    private static func openClawStatusRank(_ job: [String: Any]) -> Int {
        let state = job["state"] as? [String: Any]
        switch stringValue(job["status"]) ?? stringValue(state?["lastRunStatus"]) {
        case "running": return 400
        case "error", "skipped": return 300
        case "ok": return 200
        default: return 100
        }
    }

    private static func openClawObservedAt(_ job: [String: Any]) -> Date? {
        let state = job["state"] as? [String: Any]
        let candidates: [Any?] = [
            state?["runningAtMs"],
            state?["lastRunFinishedAt"],
            state?["lastFinishedAt"],
            state?["lastRunAt"],
            job["runningAtMs"],
            job["lastRunFinishedAt"],
            job["lastFinishedAt"],
            job["finishedAt"],
            job["lastRunAt"],
            job["updatedAt"],
            job["createdAt"],
        ]
        return candidates.compactMap(dateValue).first
    }

    private static func preferredHermesJob(_ jobs: [[String: Any]]) -> [String: Any]? {
        jobs.sorted { lhs, rhs in
            (dateValue(lhs["last_run_at"]) ?? .distantPast) > (dateValue(rhs["last_run_at"]) ?? .distantPast)
        }.first
    }

    private static func looksLikeGBrainJob(_ job: [String: Any]) -> Bool {
        let fields = ["name", "prompt", "script", "command", "workdir", "description"]
        return fields.contains { key in
            stringValue(job[key])?.localizedCaseInsensitiveContains("gbrain") == true
        }
    }

    private static func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            if raw > 10_000_000_000 {
                return Date(timeIntervalSince1970: raw / 1000)
            }
            if raw > 0 {
                return Date(timeIntervalSince1970: raw)
            }
        }
        guard let string = stringValue(value) else { return nil }
        if let raw = Double(string) {
            if raw > 10_000_000_000 {
                return Date(timeIntervalSince1970: raw / 1000)
            }
            if raw > 0 {
                return Date(timeIntervalSince1970: raw)
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
