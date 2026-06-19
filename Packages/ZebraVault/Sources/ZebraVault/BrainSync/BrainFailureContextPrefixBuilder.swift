import Foundation

public struct BrainFailureContextPrefixRequest: Sendable {
    public let title: String
    public let vaultPath: String
    public let reason: String
    public let rawReason: String?
    public let detail: String
    public let failedAt: Date?
    public let guidance: String
    public let extraSections: [String]
    public let inspectCommands: [String]

    public init(
        title: String,
        vaultPath: String,
        reason: String,
        rawReason: String?,
        detail: String,
        failedAt: Date?,
        guidance: String,
        extraSections: [String] = [],
        inspectCommands: [String]
    ) {
        self.title = title
        self.vaultPath = vaultPath
        self.reason = reason
        self.rawReason = rawReason
        self.detail = detail
        self.failedAt = failedAt
        self.guidance = guidance
        self.extraSections = extraSections
        self.inspectCommands = inspectCommands
    }
}

public enum BrainFailureContextPrefixBuilder {
    public static let totalByteBudget = 24_000

    public static func build(_ request: BrainFailureContextPrefixRequest) -> String {
        var sections: [String] = []
        sections.append(failureBlock(request))
        sections.append(repoSnapshotBlock(vaultPath: request.vaultPath))
        sections.append("""
        === Suggested path ===
        \(request.guidance)
        """)
        sections.append(contentsOf: request.extraSections)
        sections.append(inspectBlock(commands: request.inspectCommands))
        sections.append(safetyBlock)

        return cappedPrefix(
            sections.joined(separator: "\n\n"),
            byteBudget: totalByteBudget,
            truncationMarker: "\n\n*** truncated to stay under argv limit ***"
        )
    }

    public static func inlineSafe(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }
        for scalar in trimmed.unicodeScalars {
            if scalar.value < 0x20 || scalar.value > 0x7e {
                return "(contains non-ASCII; inspect existing files/logs for exact text)"
            }
        }
        return trimmed
    }

    public static func inlineSafeDetail(_ value: String) -> String {
        let safe = inlineSafe(value)
        guard safe == value.trimmingCharacters(in: .whitespacesAndNewlines) else { return safe }
        return utf8Prefix(safe, byteBudget: 2_000)
    }

    public static func runGit(_ args: [String], cwd: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)

        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin") + ":" + extraPaths
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return nil
        }

        let group = DispatchGroup()
        let drainQueue = DispatchQueue(label: "com.zebra.brain.failure-context.git-drain", attributes: .concurrent)
        nonisolated(unsafe) var stdoutData = Data()
        nonisolated(unsafe) var stderrData = Data()
        drainQueue.async(group: group) {
            stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        }
        drainQueue.async(group: group) {
            stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        }
        process.waitUntilExit()
        group.wait()
        _ = stderrData
        guard process.terminationStatus == 0 else { return nil }
        let raw = String(data: stdoutData, encoding: .utf8) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func failureBlock(_ request: BrainFailureContextPrefixRequest) -> String {
        var lines = [
            "=== \(request.title) ===",
            "Vault: \(inlineSafe(request.vaultPath))",
            "Reason: \(inlineSafe(request.reason))",
        ]
        if let rawReason = request.rawReason, !rawReason.isEmpty {
            lines.append("Raw reason: \(inlineSafe(rawReason))")
        }
        if let failedAt = request.failedAt {
            lines.append("Failed at: \(ISO8601DateFormatter().string(from: failedAt))")
        }
        if !request.detail.isEmpty {
            lines.append("Detail: \(inlineSafeDetail(request.detail))")
        }
        return lines.joined(separator: "\n")
    }

    private static func repoSnapshotBlock(vaultPath: String) -> String {
        let branch = runGit(["symbolic-ref", "--short", "HEAD"], cwd: vaultPath) ?? "(unknown)"
        let remote = sanitizedRemoteForDisplay(
            runGit(["remote", "get-url", "origin"], cwd: vaultPath) ?? "(missing origin)"
        )
        let localHead = runGit(["rev-parse", "--short", "HEAD"], cwd: vaultPath) ?? "(unknown)"
        let remoteRef = branch == "(unknown)" ? "origin/main" : "origin/\(branch)"
        let remoteHead = runGit(["rev-parse", "--short", remoteRef], cwd: vaultPath) ?? "(unknown)"
        let aheadBehind = formatAheadBehind(
            runGit(["rev-list", "--left-right", "--count", "HEAD...\(remoteRef)"], cwd: vaultPath)
        )

        return """
        === Repo snapshot ===
        Branch: \(inlineSafe(branch))
        Origin: \(inlineSafe(remote))
        Local HEAD: \(inlineSafe(localHead))
        Remote \(inlineSafe(remoteRef)): \(inlineSafe(remoteHead))
        Ahead/behind (`HEAD...\(inlineSafe(remoteRef))`): \(aheadBehind)
        """
    }

    private static func inspectBlock(commands: [String]) -> String {
        """
        === Inspect commands ===
        \(commands.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    private static let safetyBlock = """
    === Safety rules ===
    - Explain the likely cause before changing files or git state.
    - Ask before force-push, rebase, deleting locks/files, or choosing ours/theirs.
    """

    private static func formatAheadBehind(_ raw: String?) -> String {
        guard let raw else { return "(unknown)" }
        let parts = raw.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2 else { return raw }
        return "\(parts[0]) ahead, \(parts[1]) behind"
    }

    private static func cappedPrefix(_ value: String, byteBudget: Int, truncationMarker: String) -> String {
        guard value.utf8.count > byteBudget else { return value }
        guard byteBudget > 0 else { return "" }
        let marker = utf8Prefix(truncationMarker, byteBudget: byteBudget)
        let contentBudget = max(0, byteBudget - marker.utf8.count)
        return utf8Prefix(value, byteBudget: contentBudget) + marker
    }

    private static func utf8Prefix(_ value: String, byteBudget: Int) -> String {
        guard byteBudget > 0 else { return "" }
        var used = 0
        var result = ""
        result.reserveCapacity(min(value.count, byteBudget))
        for character in value {
            let bytes = String(character).utf8.count
            guard used + bytes <= byteBudget else { break }
            result.append(character)
            used += bytes
        }
        return result
    }

    private static func sanitizedRemoteForDisplay(_ remote: String) -> String {
        guard var components = URLComponents(string: remote),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              components.host != nil,
              (components.user != nil || components.password != nil) else {
            return remote
        }
        components.user = nil
        components.password = nil
        return components.string ?? remote
    }
}
