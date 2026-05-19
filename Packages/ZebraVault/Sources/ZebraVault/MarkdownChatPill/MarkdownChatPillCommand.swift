import Foundation

/// Builds the shell command that drives a chat-pill session.
///
/// Split out of `MarkdownChatPill.swift` because the pill view itself was
/// trending past a thousand lines. Keeping the agent invocation contract
/// in its own file makes the per-agent CLI conventions (codex `-c` trust
/// override, claude `--append-system-prompt`, gemini `--skip-trust`)
/// auditable without scrolling past hundreds of lines of view code.
public enum MarkdownChatPillCommand {
    private static let codexTargetRepoEnvKey = "CMUX_MARKDOWN_CHAT_CODEX_TARGET_REPO"

    /// Prepare any agent-specific launch state that cannot be expressed as a
    /// safe session-scoped CLI flag. Returns false when preparation failed and
    /// the agent should fall back to its own first-run prompt.
    public static func prepareLaunchEnvironment(agent: MarkdownPillAgent, markdownFilePath: String) -> Bool {
        let parent = (markdownFilePath as NSString).deletingLastPathComponent
        let cwd = parent.isEmpty ? "/" : parent
        switch agent {
        case .codex:
            return true
        case .claude:
            return markClaudeProjectTrusted(cwd: cwd)
        case .gemini:
            return true
        }
    }

    public static func shellStartupLine(
        agent: MarkdownPillAgent,
        markdownFilePath: String,
        surface: MarkdownChatPillContextSurface,
        userPrompt: String
    ) -> String {
        let parent = (markdownFilePath as NSString).deletingLastPathComponent
        let cwd = parent.isEmpty ? "/" : parent
        let contextPrefix = MarkdownChatPillContextPrefix.build(
            markdownFilePath: markdownFilePath,
            surface: surface
        )
        return "\(invocation(agent: agent, cwd: cwd, contextPrefix: contextPrefix, prompt: userPrompt))\r"
    }

    /// Per-agent CLI invocation tuned to keep the initial prompt on the agent
    /// path instead of a first-run trust dialog. Codex uses a per-process
    /// config override, Gemini uses its official session-scoped `--skip-trust`
    /// flag, and Claude relies on `prepareLaunchEnvironment` to pre-accept the
    /// current cwd in Claude's project state when that file is writable.
    private static func invocation(
        agent: MarkdownPillAgent,
        cwd: String,
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
            let codexLaunch = codexLaunchContext(markdownCwd: cwd)
            let trustOverride = "projects.\"\(codexLaunch.cwd)\".trust_level=\"trusted\""
            var parts = [
                "cd \(shellQuote(codexLaunch.cwd)) && codex",
                "-C \(shellQuote(codexLaunch.cwd))"
            ]
            if let addDir = codexLaunch.addDir {
                parts.append("--add-dir \(shellQuote(addDir))")
            }
            parts.append("-c \(shellQuote(trustOverride))")
            parts.append(shellQuote(visibleContextPrompt))
            return parts.joined(separator: " ")
        case .claude:
            return "cd \(shellQuote(cwd)) && claude --append-system-prompt \(shellQuote(contextPrefix)) \(shellQuote(promptArgument))"
        case .gemini:
            return "cd \(shellQuote(cwd)) && gemini --skip-trust --prompt-interactive \(shellQuote(visibleContextPrompt))"
        }
    }

    private struct CodexLaunchContext {
        let cwd: String
        let addDir: String?
    }

    private static func codexLaunchContext(markdownCwd: String) -> CodexLaunchContext {
        let markdownCwd = standardizedPath(markdownCwd)
        guard let targetRepo = codexTargetRepoPath(),
              targetRepo != markdownCwd else {
            return CodexLaunchContext(cwd: markdownCwd, addDir: nil)
        }

        return CodexLaunchContext(
            cwd: targetRepo,
            addDir: isPath(markdownCwd, inside: targetRepo) ? nil : markdownCwd
        )
    }

    private static func codexTargetRepoPath() -> String? {
        guard let raw = ProcessInfo.processInfo.environment[codexTargetRepoEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        let path = standardizedPath((raw as NSString).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return path
    }

    private static func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private static func isPath(_ path: String, inside root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
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
