import Foundation

/// Builds the shell command that drives a chat-pill session.
///
/// Split out of `MarkdownChatPill.swift` because the pill view itself was
/// trending past a thousand lines. Keeping the agent invocation contract
/// in its own file makes the per-agent CLI conventions (codex `-c` trust
/// override, claude `--append-system-prompt`, gemini `--skip-trust`)
/// auditable without scrolling past hundreds of lines of view code.
enum MarkdownChatPillCommand {
    private static let codexTargetRepoEnvKey = "CMUX_MARKDOWN_CHAT_CODEX_TARGET_REPO"

    /// Prepare any agent-specific launch state that cannot be expressed as a
    /// safe session-scoped CLI flag. Returns false when preparation failed and
    /// the agent should fall back to its own first-run prompt.
    static func prepareLaunchEnvironment(agent: MarkdownPillAgent, markdownFilePath: String) -> Bool {
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

    static func shellStartupLine(
        agent: MarkdownPillAgent,
        markdownFilePath: String,
        userPrompt: String
    ) -> String {
        let parent = (markdownFilePath as NSString).deletingLastPathComponent
        let cwd = parent.isEmpty ? "/" : parent
        return "\(invocation(agent: agent, cwd: cwd, markdownFilePath: markdownFilePath, prompt: userPrompt))\r"
    }

    /// Per-agent CLI invocation tuned to keep the initial prompt on the agent
    /// path instead of a first-run trust dialog. Codex uses a per-process
    /// config override, Gemini uses its official session-scoped `--skip-trust`
    /// flag, and Claude relies on `prepareLaunchEnvironment` to pre-accept the
    /// current cwd in Claude's project state when that file is writable.
    private static func invocation(
        agent: MarkdownPillAgent,
        cwd: String,
        markdownFilePath: String,
        prompt: String
    ) -> String {
        let promptArgument = singleLineShellArgument(prompt)
        let fileContext = "Use this markdown file as context: \(markdownFilePath)"
        // Visible context = what we want the agent to *see in the user
        // message* (file note + user's question). Compressed to one line so
        // shell single-quoting is straightforward.
        let visibleContextPrompt = "\(fileContext). \(promptArgument)"
        // Hidden system-prompt variant for claude's --append-system-prompt:
        // the file note alone (claude takes the user prompt separately).
        let hiddenContextInstruction = fileContext
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
            return "cd \(shellQuote(cwd)) && claude --append-system-prompt \(shellQuote(hiddenContextInstruction)) \(shellQuote(promptArgument))"
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
