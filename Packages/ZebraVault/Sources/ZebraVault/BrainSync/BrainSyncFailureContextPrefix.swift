import Foundation

/// Short context passed to an agent when any brain-sync failure needs
/// intervention. Keep this inline prefix compact: large logs, git status output,
/// and file bodies stay in their existing locations and are referenced by path or
/// command instead of being copied into the agent argv.
public enum BrainSyncFailureContextPrefix {
    public static func build(
        vaultPath: String,
        reason: BrainSyncService.FailureReason,
        rawReasonId: String?,
        detail: String,
        failedAt: Date?
    ) -> String {
        var extraSections: [String] = []
        if reason == .conflict {
            extraSections.append(BrainSyncConflictContextPrefix.build(vaultPath: vaultPath))
        }
        return BrainFailureContextPrefixBuilder.build(
            BrainFailureContextPrefixRequest(
                title: "Zebra brain sync failure",
                vaultPath: vaultPath,
                reason: reason.rawValue,
                rawReason: rawReasonId,
                detail: detail,
                failedAt: failedAt,
                guidance: reasonGuidance(reason: reason, rawReasonId: rawReasonId),
                extraSections: extraSections,
                inspectCommands: inspectCommands(reason: reason, vaultPath: vaultPath)
            )
        )
    }

    private static func reasonGuidance(
        reason: BrainSyncService.FailureReason,
        rawReasonId: String?
    ) -> String {
        switch reason {
        case .authExpired:
            return """
            Authentication failed. Inspect the remote URL, credential helper state, and current GitHub/auth CLI status before retrying. Do not rewrite repo history for an auth failure.
            """
        case .offline:
            return """
            Network access failed. Confirm whether this is transient connectivity/DNS before changing files. If the repo state is clean, a later retry may be enough.
            """
        case .pushRejected:
            return """
            Push was rejected, usually because remote moved or policy blocked the push. Inspect ahead/behind and recent remote commits. Prefer fetch/rebase/merge. Do not force-push unless the user explicitly chooses that path.
            """
        case .permissionDenied:
            return """
            Repository permission failed. Check remote URL, selected account, and write access. Avoid local file edits unless the logs show a separate validation problem.
            """
        case .diskFull:
            return """
            The local machine is out of disk space. Help the user identify safe cleanup options, but do not delete user data without explicit confirmation.
            """
        case .hookFailed:
            return """
            Zebra validation or a local git hook failed. Use the detail line plus `git status --porcelain` to find the offending file. Common causes: non-markdown files, hidden files, symlinks, possible secrets, detached HEAD, wrong branch, or invalid sync commit message.
            """
        case .rateLimit:
            return """
            The remote service rate-limited the sync. Inspect logs for retry timing. Avoid repeated manual retries if the remote asks for backoff.
            """
        case .conflict:
            return """
            Conflict markers or an active merge/rebase conflict are present. Identify whether this is marker residue or an active git operation, then inspect the listed files.
            """
        case .notGbrainRepo:
            return """
            The selected vault is not recognized as a GBrain repo because `.gbrain-mount` or `.gbrain-source` is missing at the repo root. Confirm the user selected the intended vault before adding markers or changing remotes.
            """
        case .alreadyRunning:
            return """
            Another sync lock is present. Use the lock detail in the failure message to determine whether the process is still alive or stale. Do not remove a live lock; if stale, explain the cleanup before acting.
            """
        case .unknown:
            let raw = rawReasonId.map { " The script emitted unrecognized reason `\(BrainFailureContextPrefixBuilder.inlineSafe($0))`." } ?? ""
            return """
            The failure was not classified by the app.\(raw) Start from the recent sync log and git status, classify the likely root cause, then propose a recovery path.
            """
        }
    }

    private static func inspectCommands(
        reason: BrainSyncService.FailureReason,
        vaultPath: String
    ) -> [String] {
        let branch = BrainFailureContextPrefixBuilder.runGit(["symbolic-ref", "--short", "HEAD"], cwd: vaultPath) ?? "main"
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
            commands.append("git log --oneline --left-right HEAD...origin/\(BrainFailureContextPrefixBuilder.inlineSafe(branch)) -20")
        case .conflict:
            commands.append("tail -80 ~/Library/Logs/zebra/brainsync.log")
            commands.append("rg -n '^(<<<<<<<|=======|>>>>>>>)' -g '*.md' .")
        case .alreadyRunning:
            commands.append("tail -120 ~/Library/Logs/zebra/brainsync.log")
        case .hookFailed, .unknown:
            commands.append("tail -80 ~/Library/Logs/zebra/brainsync.log")
            commands.append("git diff --name-only")
        case .offline, .diskFull, .rateLimit, .notGbrainRepo:
            commands.append("tail -80 ~/Library/Logs/zebra/brainsync.log")
        }
        return commands
    }
}
