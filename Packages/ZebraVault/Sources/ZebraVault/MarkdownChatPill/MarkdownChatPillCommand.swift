import Foundation

/// Builds the shell command that drives a chat-pill session.
///
/// Split out of `MarkdownChatPill.swift` because the pill view itself was
/// trending past a thousand lines. Keeping the agent invocation contract
/// in its own file makes the per-agent CLI conventions (codex `-c` trust
/// override, claude `--append-system-prompt`, gemini `--skip-trust`)
/// auditable without scrolling past hundreds of lines of view code.
public enum MarkdownChatPillCommand {
    public struct LaunchPlan {
        public let requestedWorktree: String?
        public let launchDirectory: String?
        public let launchEnvironmentReady: Bool
        public let startupLine: String?
    }

    /// Resolve the cwd for a chat-pill agent launch. A markdown document may
    /// store the creator's local directory in top-level frontmatter:
    ///
    ///     worktree: /Users/dan/zebra
    ///
    /// On another Mac, Zebra first tries the same path under the current user's
    /// home directory (`/Users/han/zebra`). If that deterministic candidate is
    /// missing, the caller can ask the user to choose a folder.
    public static func resolvedLaunchDirectory(
        markdownContent: String?,
        fallbackDirectory: String?,
        chooseDirectory: ((_ requestedPath: String, _ suggestedPath: String?) -> String?)? = nil
    ) -> String? {
        if let worktree = worktreeFrontmatterPath(markdownContent) {
            let candidate = deterministicWorktreeCandidate(worktree, fallbackDirectory: fallbackDirectory)
            if let cwd = validLaunchDirectoryCwd(candidate) {
                return cwd
            }
            if let chosen = chooseDirectory?(worktree, candidate),
               let cwd = validLaunchDirectoryCwd(chosen) {
                return cwd
            }
            return nil
        }
        return validLaunchDirectoryCwd(fallbackDirectory)
    }

    /// Shared launch contract for every ChatPill surface. Callers provide the
    /// surface-specific context and fallback directory, and this returns the
    /// agent prep result plus the exact startup command that uses the same cwd.
    public static func launchPlan(
        agent: MarkdownPillAgent,
        markdownContent: String?,
        markdownFilePath: String?,
        fallbackDirectory: String?,
        surface: MarkdownChatPillContextSurface,
        userPrompt: String,
        chooseDirectory: ((_ requestedPath: String, _ suggestedPath: String?) -> String?)? = nil
    ) -> LaunchPlan {
        let requestedWorktree = worktreeFrontmatterPath(markdownContent)
        let launchDirectory = resolvedLaunchDirectory(
            markdownContent: markdownContent,
            fallbackDirectory: fallbackDirectory,
            chooseDirectory: chooseDirectory
        )

        guard requestedWorktree == nil || launchDirectory != nil else {
            return LaunchPlan(
                requestedWorktree: requestedWorktree,
                launchDirectory: nil,
                launchEnvironmentReady: true,
                startupLine: nil
            )
        }

        let launchEnvironmentReady = prepareLaunchEnvironment(
            agent: agent,
            markdownFilePath: markdownFilePath,
            launchDirectory: launchDirectory
        )
        let startupLine = shellStartupLine(
            agent: agent,
            markdownFilePath: markdownFilePath,
            surface: surface,
            userPrompt: userPrompt,
            launchDirectory: launchDirectory
        )
        return LaunchPlan(
            requestedWorktree: requestedWorktree,
            launchDirectory: launchDirectory,
            launchEnvironmentReady: launchEnvironmentReady,
            startupLine: startupLine
        )
    }

    /// Prepare any agent-specific launch state that cannot be expressed as a
    /// safe session-scoped CLI flag. Returns false when preparation failed and
    /// the agent should fall back to its own first-run prompt.
    ///
    /// `launchDirectory` 는 호출부가 frontmatter `worktree:` 또는 selected Vault
    /// 기준으로 이미 resolve 한 cwd 이다. 없고 markdownFilePath 도 nil 인 surface
    /// (email panel 등)는 path-bound prep 없이 성공 처리한다.
    public static func prepareLaunchEnvironment(
        agent: MarkdownPillAgent,
        markdownFilePath: String?,
        launchDirectory: String? = nil
    ) -> Bool {
        switch agent {
        case .codex:
            return true
        case .claude:
            if let cwd = validLaunchDirectoryCwd(launchDirectory) {
                guard let trustedCwd = safeTrustCwd(cwd) else {
                    return false
                }
                return markClaudeProjectTrusted(cwd: trustedCwd)
            }
            guard let markdownFilePath, !markdownFilePath.isEmpty else {
                return true
            }
            let parent = (markdownFilePath as NSString).deletingLastPathComponent
            guard let cwd = safeTrustCwd(parent) else {
                return false
            }
            return markClaudeProjectTrusted(cwd: cwd)
        case .gemini:
            return true
        }
    }

    /// Brain-sync failure 전용 prep. cwd = vaultPath. Claude 분기는 vault path 를
    /// `~/.claude.json` 에 trusted 로 박는다.
    public static func prepareLaunchEnvironmentForBrainSyncFailure(
        agent: MarkdownPillAgent,
        vaultPath: String
    ) -> Bool {
        switch agent {
        case .codex:
            return true
        case .claude:
            guard let cwd = safeTrustCwd(vaultPath) else { return false }
            return markClaudeProjectTrusted(cwd: cwd)
        case .gemini:
            return true
        }
    }

    public static func prepareLaunchEnvironmentForBrainSyncConflict(
        agent: MarkdownPillAgent,
        vaultPath: String
    ) -> Bool {
        prepareLaunchEnvironmentForBrainSyncFailure(agent: agent, vaultPath: vaultPath)
    }

    /// Brain-sync failure 전용 entry. ChatPill 의 `invocation` 을 재사용해 agent
    /// CLI 명령을 만들되 prefix 는 짧은 failure summary + inspect commands 만
    /// 포함한다. 로그/파일 본문은 prefix 에 inline 하지 않고 agent 가 기존 파일을
    /// 직접 확인하게 한다.
    public static func shellStartupLineForBrainSyncFailure(
        agent: MarkdownPillAgent,
        vaultPath: String,
        reason: BrainSyncService.FailureReason,
        rawReasonId: String?,
        detail: String,
        failedAt: Date?,
        userPrompt: String = ""
    ) -> String {
        let failurePrefix = BrainSyncFailureContextPrefix.build(
            vaultPath: vaultPath,
            reason: reason,
            rawReasonId: rawReasonId,
            detail: detail,
            failedAt: failedAt
        )
        return "\(invocation(agent: agent, cwd: vaultPath, trustEligible: true, contextPrefix: failurePrefix, prompt: userPrompt))\r"
    }

    public static func shellStartupLineForBrainSyncConflict(
        agent: MarkdownPillAgent,
        vaultPath: String,
        userPrompt: String = ""
    ) -> String {
        shellStartupLineForBrainSyncFailure(
            agent: agent,
            vaultPath: vaultPath,
            reason: .conflict,
            rawReasonId: nil,
            detail: "",
            failedAt: nil,
            userPrompt: userPrompt
        )
    }

    public static func shellStartupLine(
        agent: MarkdownPillAgent,
        markdownFilePath: String?,
        surface: MarkdownChatPillContextSurface,
        userPrompt: String,
        launchDirectory: String? = nil
    ) -> String {
        // Zebra ChatPill 호출부는 frontmatter `worktree:` 또는 selected Vault
        // 기준으로 resolve 한 cwd 를 launchDirectory 로 넘긴다. 없으면 markdown
        // file parent, 그것도 없으면 home 으로 fallback 한다.
        let cwd: String
        let trustEligible: Bool
        if let launchDirectoryCwd = validLaunchDirectoryCwd(launchDirectory) {
            cwd = launchDirectoryCwd
            trustEligible = true
        } else if let markdownFilePath, !markdownFilePath.isEmpty {
            let parent = (markdownFilePath as NSString).deletingLastPathComponent
            cwd = parent.isEmpty ? "/" : parent
            trustEligible = true
        } else {
            cwd = NSHomeDirectory()
            trustEligible = false
        }
        let contextPrefix = MarkdownChatPillContextPrefix.build(
            markdownFilePath: markdownFilePath,
            surface: surface
        )
        return "\(invocation(agent: agent, cwd: cwd, trustEligible: trustEligible, contextPrefix: contextPrefix, prompt: userPrompt))\r"
    }

    public static func worktreeFrontmatterPath(_ markdownContent: String?) -> String? {
        guard let markdownContent,
              let block = FrontmatterUtils.extractFrontmatterBlock(from: markdownContent) else {
            return nil
        }
        let kv = FrontmatterUtils.parseFlatKeyValues(block)
        guard let raw = kv["worktree"]?.trimmedUnquoted,
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private static func deterministicWorktreeCandidate(_ rawPath: String, fallbackDirectory: String?) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("~/") || trimmed == "~" {
            return standardizedPath((trimmed as NSString).expandingTildeInPath)
        }
        let expanded = standardizedPath((trimmed as NSString).expandingTildeInPath)
        if let translated = currentHomeTranslatedUsersPath(expanded) {
            return translated
        }
        if expanded.hasPrefix("/") {
            return expanded
        }
        guard let fallback = validLaunchDirectoryCwd(fallbackDirectory) else {
            return nil
        }
        return standardizedPath((fallback as NSString).appendingPathComponent(trimmed))
    }

    private static func currentHomeTranslatedUsersPath(_ path: String) -> String? {
        let components = URL(fileURLWithPath: path).pathComponents
        guard components.count >= 3,
              components[0] == "/",
              components[1] == "Users" else {
            return nil
        }
        let home = standardizedPath(NSHomeDirectory())
        let tail = components.dropFirst(3).joined(separator: "/")
        guard !tail.isEmpty else { return home }
        return standardizedPath((home as NSString).appendingPathComponent(tail))
    }

    private static func validLaunchDirectoryCwd(_ launchDirectory: String?) -> String? {
        guard let launchDirectory else { return nil }
        let trimmed = launchDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cwd = standardizedPath((trimmed as NSString).expandingTildeInPath)
        guard cwd.hasPrefix("/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return cwd
    }

    /// Per-agent CLI invocation tuned to keep the initial prompt on the agent
    /// path instead of a first-run trust dialog. Codex uses a per-process
    /// config override, Gemini uses its official session-scoped `--skip-trust`
    /// flag, and Claude relies on `prepareLaunchEnvironment` to pre-accept the
    /// current cwd in Claude's project state when that file is writable.
    private static func invocation(
        agent: MarkdownPillAgent,
        cwd: String,
        trustEligible: Bool,
        contextPrefix: String,
        prompt: String
    ) -> String {
        let promptArgument = singleLineShellArgument(prompt)
        // Visible context = surface advisory + gbrain advisory + blank line + user prompt
        // (서로 다른 두 메시지 줄이라 빈 줄로 끊어둔다). 단일 따옴표 안의 embedded newline 은
        // bash/zsh 모두 그대로 argv 한 인자로 들고가니까 quoting 만 정직하게 하면 된다.
        // claude 분기는 `contextPrefix` 자체를 system prompt 로 보내고 user prompt 는 별도 argv.
        let visibleContextPrompt = "\(contextPrefix)\n\n\(promptArgument)"
        switch agent {
        case .codex:
            var parts = [
                "cd \(shellQuote(cwd)) && codex",
                "-C \(shellQuote(cwd))"
            ]
            // trust 우회는 (a) surface 가 file-bound 이고 (b) cwd 가 안전한
            // 사용자-소유 디렉터리일 때만. `/` 나 home 직속을 silent trusted 처리 금지.
            if trustEligible, let trustCwd = safeTrustCwd(cwd) {
                let trustOverride = "projects.\"\(trustCwd)\".trust_level=\"trusted\""
                parts.append("-c \(shellQuote(trustOverride))")
            }
            parts.append(shellQuote(visibleContextPrompt))
            return parts.joined(separator: " ")
        case .claude:
            return "cd \(shellQuote(cwd)) && claude --append-system-prompt \(shellQuote(contextPrefix)) \(shellQuote(promptArgument))"
        case .gemini:
            let skipTrust = (trustEligible && safeTrustCwd(cwd) != nil) ? "--skip-trust " : ""
            return "cd \(shellQuote(cwd)) && gemini \(skipTrust)--prompt-interactive \(shellQuote(visibleContextPrompt))"
        }
    }

    private static func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    /// 자동 trust 처리를 허용할지 판단. 빈 string / 상대경로 / filesystem root `/` /
    /// `"` 나 제어문자 포함 경로 / 실제로 존재하지 않는 경로는 모두 거절. 통과하면
    /// standardized absolute path 반환. Claude 의 `.claude.json` 영구 쓰기, codex
    /// `-c trust_level=trusted` override, gemini `--skip-trust` 모두 이 게이트를
    /// 통과한 cwd 에서만 적용. tilde-prefixed 입력도 expand 후 검증해서 콜러가
    /// `~/...` 를 넘겨도 silent 거절되지 않게 한다.
    private static func safeTrustCwd(_ cwd: String) -> String? {
        guard !cwd.isEmpty else { return nil }
        let expanded = (cwd as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        let standardized = standardizedPath(expanded)
        guard standardized != "/" else { return nil }
        // codex `-c projects."<path>"` 의 TOML override key 와 .claude.json JSON key 에
        // embed 되므로 `"` / control char 포함된 경로는 silent 우회 대상에서 제외.
        // shell 측은 single-quote 로 안전하나 상위 파서가 깨질 수 있음.
        for scalar in standardized.unicodeScalars {
            if scalar == "\"" || scalar.value < 0x20 { return nil }
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return standardized
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func singleLineShellArgument(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func markClaudeProjectTrusted(cwd: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard var root = readJSONObjectIfPresent(at: url) else {
            return false
        }
        var projects = root["projects"] as? [String: Any] ?? [:]
        var project = projects[cwd] as? [String: Any] ?? [:]
        project["hasTrustDialogAccepted"] = true
        projects[cwd] = project
        root["projects"] = projects
        return writeJSONObject(root, to: url)
    }

    private static func readJSONObjectIfPresent(at url: URL) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func writeJSONObject(_ object: [String: Any], to url: URL) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
