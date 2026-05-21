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
    ///
    /// markdownFilePath nil 은 email panel 호출처럼 file-on-disk 가 없는 surface.
    /// 이 경우 claude trust 같은 path-bound prep 은 의미가 없어 no-op 으로 성공 처리.
    public static func prepareLaunchEnvironment(agent: MarkdownPillAgent, markdownFilePath: String?) -> Bool {
        switch agent {
        case .codex:
            return true
        case .claude:
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

    public static func shellStartupLine(
        agent: MarkdownPillAgent,
        markdownFilePath: String?,
        surface: MarkdownChatPillContextSurface,
        userPrompt: String
    ) -> String {
        // markdownFilePath 가 있는 surface 에서만 자동 trust 우회 자격. nil/empty 면
        // file-on-disk 가 없는 surface (예: email panel) 라 cd 는 home 으로 떨어뜨리되
        // codex/gemini 의 trust-bypass flag 는 붙이지 않는다 (claude prep 은 이미 skip).
        let cwd: String
        let trustEligible: Bool
        if let markdownFilePath, !markdownFilePath.isEmpty {
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
            let codexLaunch = codexLaunchContext(markdownCwd: cwd)
            var parts = [
                "cd \(shellQuote(codexLaunch.cwd)) && codex",
                "-C \(shellQuote(codexLaunch.cwd))"
            ]
            if let addDir = codexLaunch.addDir {
                parts.append("--add-dir \(shellQuote(addDir))")
            }
            // trust 우회는 (a) surface 가 file-bound 이고 (b) cwd 가 안전한
            // 사용자-소유 디렉터리일 때만. `/` 나 home 직속을 silent trusted 처리 금지.
            if trustEligible, let trustCwd = safeTrustCwd(codexLaunch.cwd) {
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

    /// 자동 trust 처리를 허용할지 판단. 빈 string / 상대경로 / filesystem root `/` /
    /// `"` 나 제어문자 포함 경로 / 실제로 존재하지 않는 경로는 모두 거절. 통과하면
    /// standardized absolute path 반환. Claude 의 `.claude.json` 영구 쓰기, codex
    /// `-c trust_level=trusted` override, gemini `--skip-trust` 모두 이 게이트를
    /// 통과한 cwd 에서만 적용. tilde-prefixed 입력도 expand 후 검증해서 콜러가
    /// `~/...` 를 넘겨도 silent 거절되지 않게 한다 (codexTargetRepoPath 와 대칭).
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
