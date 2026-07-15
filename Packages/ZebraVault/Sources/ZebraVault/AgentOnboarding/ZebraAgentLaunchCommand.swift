import Foundation

public enum ZebraAgentLaunchCommand {
    public static func shellStartupLine(
        agent: ZebraAgentKind,
        cwd: String,
        systemPrompt: String,
        userPrompt: String,
        executablePath: String? = nil
    ) -> String {
        let executable = executablePath.map(shellQuote) ?? agent.binaryName
        switch agent {
        case .claude:
            return "cd \(shellQuote(cwd)) && \(executable)\r"
        case .codex:
            return "cd \(shellQuote(cwd)) && \(executable)\r"
        case .antigravity:
            return "cd \(shellQuote(cwd)) && \(executable)\r"
        }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

}
