import Foundation

public enum ZebraAgentLaunchCommand {
    public static func shellStartupLine(
        agent: ZebraAgentKind,
        cwd: String,
        systemPrompt: String,
        userPrompt: String
    ) -> String {
        let visiblePrompt = systemPrompt.isEmpty ? userPrompt : "\(systemPrompt)\n\n\(userPrompt)"
        switch agent {
        case .claude:
            return "cd \(shellQuote(cwd)) && claude --append-system-prompt \(shellQuote(systemPrompt)) \(shellQuote(singleLineShellArgument(userPrompt)))\r"
        case .codex:
            return "cd \(shellQuote(cwd)) && codex -C \(shellQuote(cwd)) \(shellQuote(visiblePrompt))\r"
        case .antigravity:
            return "cd \(shellQuote(cwd)) && agy -p \(shellQuote(visiblePrompt)) --cwd \(shellQuote(cwd))\r"
        }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func singleLineShellArgument(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
