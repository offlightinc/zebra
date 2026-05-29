import Foundation

/// Short context passed to an agent when any brain-sync failure needs
/// intervention. Keep this inline prefix compact: large logs, git status output,
/// and file bodies stay in their existing locations and are referenced by path or
/// command instead of being copied into the agent argv.
public enum BrainSyncFailureContextPrefix {
    private static let totalByteBudget = 24_000

    public static func build(
        vaultPath: String,
        reason: BrainSyncService.FailureReason,
        rawReasonId: String?,
        detail: String,
        failedAt: Date?
    ) -> String {
        var sections: [String] = []
        sections.append(failureBlock(vaultPath: vaultPath, reason: reason, rawReasonId: rawReasonId, detail: detail, failedAt: failedAt))
        sections.append(repoSnapshotBlock(vaultPath: vaultPath))
        sections.append(reasonGuidanceBlock(reason: reason, rawReasonId: rawReasonId))

        if reason == .conflict {
            sections.append(BrainSyncConflictContextPrefix.build(vaultPath: vaultPath))
        }
        sections.append(inspectBlock(reason: reason, vaultPath: vaultPath))
        sections.append(safetyBlock)

        let combined = sections.joined(separator: "\n\n")
        return cappedPrefix(
            combined,
            byteBudget: totalByteBudget,
            truncationMarker: "\n\n*** truncated to stay under argv limit ***"
        )
    }

    private static func failureBlock(
        vaultPath: String,
        reason: BrainSyncService.FailureReason,
        rawReasonId: String?,
        detail: String,
        failedAt: Date?
    ) -> String {
        var lines = [
            "=== Zebra brain sync failure ===",
            "Vault: \(inlineSafe(vaultPath))",
            "Reason: \(reason.rawValue)"
        ]
        if let rawReasonId, !rawReasonId.isEmpty {
            lines.append("Raw reason: \(inlineSafe(rawReasonId))")
        }
        if let failedAt {
            lines.append("Failed at: \(ISO8601DateFormatter().string(from: failedAt))")
        }
        if !detail.isEmpty {
            lines.append("Detail: \(inlineSafeDetail(detail))")
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

    private static func reasonGuidanceBlock(
        reason: BrainSyncService.FailureReason,
        rawReasonId: String?
    ) -> String {
        let heading = "=== Suggested path ==="
        let body: String
        switch reason {
        case .authExpired:
            body = """
            Authentication failed. Inspect the remote URL, credential helper state, and current GitHub/auth CLI status before retrying. Do not rewrite repo history for an auth failure.
            """
        case .offline:
            body = """
            Network access failed. Confirm whether this is transient connectivity/DNS before changing files. If the repo state is clean, a later retry may be enough.
            """
        case .pushRejected:
            body = """
            Push was rejected, usually because remote moved or policy blocked the push. Inspect ahead/behind and recent remote commits. Prefer fetch/rebase/merge. Do not force-push unless the user explicitly chooses that path.
            """
        case .permissionDenied:
            body = """
            Repository permission failed. Check remote URL, selected account, and write access. Avoid local file edits unless the logs show a separate validation problem.
            """
        case .diskFull:
            body = """
            The local machine is out of disk space. Help the user identify safe cleanup options, but do not delete user data without explicit confirmation.
            """
        case .hookFailed:
            body = """
            Zebra validation or a local git hook failed. Use the detail line plus `git status --porcelain` to find the offending file. Common causes: non-markdown files, hidden files, symlinks, possible secrets, detached HEAD, wrong branch, or invalid sync commit message.
            """
        case .rateLimit:
            body = """
            The remote service rate-limited the sync. Inspect logs for retry timing. Avoid repeated manual retries if the remote asks for backoff.
            """
        case .conflict:
            body = """
            Conflict markers or an active merge/rebase conflict are present. Identify whether this is marker residue or an active git operation, then inspect the listed files.
            """
        case .notGbrainRepo:
            body = """
            The selected vault is not recognized as a GBrain repo because `.gbrain-mount` or `.gbrain-source` is missing at the repo root. Confirm the user selected the intended vault before adding markers or changing remotes.
            """
        case .alreadyRunning:
            body = """
            Another sync lock is present. Use the lock detail in the failure message to determine whether the process is still alive or stale. Do not remove a live lock; if stale, explain the cleanup before acting.
            """
        case .unknown:
            let raw = rawReasonId.map { " The script emitted unrecognized reason `\(inlineSafe($0))`." } ?? ""
            body = """
            The failure was not classified by the app.\(raw) Start from the recent sync log and git status, classify the likely root cause, then propose a recovery path.
            """
        }
        return "\(heading)\n\(body)"
    }

    private static func inspectBlock(
        reason: BrainSyncService.FailureReason,
        vaultPath: String
    ) -> String {
        let branch = runGit(["symbolic-ref", "--short", "HEAD"], cwd: vaultPath) ?? "main"
        var commands = [
            "git status --porcelain"
        ]
        switch reason {
        case .authExpired, .permissionDenied:
            commands.append("tail -80 ~/Library/Logs/zebra/brainsync.log")
            commands.append("git remote -v")
            commands.append("gh auth status")
        case .pushRejected:
            commands.append("tail -80 ~/Library/Logs/zebra/brainsync.log")
            commands.append("git log --oneline --left-right HEAD...origin/\(inlineSafe(branch)) -20")
        case .conflict:
            commands.append("tail -80 ~/Library/Logs/zebra/brainsync.log")
            commands.append("rg -n '^(<<<<<<<|=======|>>>>>>>)' -- '*.md'")
        case .alreadyRunning:
            commands.append("tail -120 ~/Library/Logs/zebra/brainsync.log")
        case .hookFailed, .unknown:
            commands.append("tail -80 ~/Library/Logs/zebra/brainsync.log")
            commands.append("git diff --name-only")
        case .offline, .diskFull, .rateLimit, .notGbrainRepo:
            commands.append("tail -80 ~/Library/Logs/zebra/brainsync.log")
        }

        return """
        === Inspect commands ===
        \(commands.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    private static func inlineSafe(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }
        for scalar in trimmed.unicodeScalars {
            if scalar.value < 0x20 || scalar.value > 0x7e {
                return "(contains non-ASCII; inspect existing files/logs for exact text)"
            }
        }
        return trimmed
    }

    private static func inlineSafeDetail(_ value: String) -> String {
        let safe = inlineSafe(value)
        guard safe == value.trimmingCharacters(in: .whitespacesAndNewlines) else { return safe }
        return utf8Prefix(safe, byteBudget: 2_000)
    }

    private static let safetyBlock = """
    === Safety rules ===
    - Explain the likely cause before changing files or git state.
    - Ask before force-push, rebase, deleting locks/files, or choosing ours/theirs.
    """

    private static func runGit(_ args: [String], cwd: String) -> String? {
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
        let drainQueue = DispatchQueue(label: "com.zebra.brainsync.failure-context.git-drain", attributes: .concurrent)
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
