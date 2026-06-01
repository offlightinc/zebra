import Foundation

public enum ZebraAgentLaunchCommand {
    public static func shellStartupLine(
        agent: ZebraAgentKind,
        cwd: String,
        systemPrompt: String,
        userPrompt: String
    ) -> String {
        switch agent {
        case .claude:
            return "cd \(shellQuote(cwd)) && claude\r"
        case .codex:
            return "cd \(shellQuote(cwd)) && codex\r"
        case .antigravity:
            return "cd \(shellQuote(cwd)) && agy\r"
        }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

}
