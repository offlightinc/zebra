import Foundation

/// Builds the shell command that drives a chat-pill session.
///
/// Split out of `MarkdownChatPill.swift` because the pill view itself was
/// trending past a thousand lines. Keeping the agent invocation contract
/// in its own file makes the per-agent CLI conventions (codex `-c` trust
/// override, claude `--append-system-prompt`, gemini `--skip-trust`)
/// auditable without scrolling past hundreds of lines of view code.
enum MarkdownChatPillCommand {
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
        userPrompt: String,
        selection: MarkdownChatPillSelection? = nil
    ) -> String {
        let parent = (markdownFilePath as NSString).deletingLastPathComponent
        let cwd = parent.isEmpty ? "/" : parent
        return "\(invocation(agent: agent, cwd: cwd, markdownFilePath: markdownFilePath, prompt: userPrompt, selection: selection))\r"
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
        prompt: String,
        selection: MarkdownChatPillSelection?
    ) -> String {
        let promptArgument = singleLineShellArgument(prompt)
        let fileContext = "Use this markdown file as context: \(markdownFilePath)"
        let selectionContext = selection.map { selectionNote(for: $0) }
        // Visible context = what we want the agent to *see in the user message*
        // (file + optional selection + user's question). Compressed to one
        // line so shell single-quoting is straightforward.
        let visibleParts: [String] = [fileContext + ".", selectionContext.map { $0 + "." }, promptArgument]
            .compactMap { $0 }
        let visibleContextPrompt = visibleParts.joined(separator: " ")
        // Hidden system-prompt variant for claude's --append-system-prompt:
        // same file + selection note, but without the user message tacked on
        // (claude takes the user prompt separately).
        let hiddenParts: [String] = [fileContext, selectionContext].compactMap { $0 }
        let hiddenContextInstruction = hiddenParts.joined(separator: ". ")
        switch agent {
        case .codex:
            let override = "projects.\"\(cwd)\".trust_level=\"trusted\""
            return "cd \(shellQuote(cwd)) && codex -c \(shellQuote(override)) \(shellQuote(visibleContextPrompt))"
        case .claude:
            return "cd \(shellQuote(cwd)) && claude --append-system-prompt \(shellQuote(hiddenContextInstruction)) \(shellQuote(promptArgument))"
        case .gemini:
            return "cd \(shellQuote(cwd)) && gemini --skip-trust --prompt-interactive \(shellQuote(visibleContextPrompt))"
        }
    }

    /// One-line sentence describing the user's excerpt selection — used both
    /// as the visible context (codex/gemini) and the system-prompt note
    /// (claude). Heading is included when we managed to back-resolve it.
    private static func selectionNote(for selection: MarkdownChatPillSelection) -> String {
        let excerpt = selection.fullExcerpt
        if let heading = selection.heading {
            return "The user selected this excerpt from the section titled \u{201C}\(heading)\u{201D}: \u{201C}\(excerpt)\u{201D}"
        }
        return "The user selected this excerpt from the markdown: \u{201C}\(excerpt)\u{201D}"
    }

    /// Follow-up text for an already-running session. Do not append Return:
    /// agent TUIs disagree about whether synthetic Return submits or inserts a
    /// newline, so we only type the text and let the user press Enter.
    static func followUpPrompt(userPrompt: String) -> String {
        userPrompt
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
