import Foundation

public enum ZebraAgentOnboardingWelcomeCommand {
    public static func bundledShellStartupLine(cwd: String = NSHomeDirectory()) -> String? {
        guard let scriptURL = Bundle.main.url(
            forResource: "zebra-agent-onboarding",
            withExtension: nil
        ) else {
            return nil
        }
        return shellStartupLine(scriptPath: scriptURL.path, cwd: cwd)
    }

    public static func shellStartupLine(scriptPath: String, cwd: String) -> String {
        [
            scriptPath,
            "run",
            "--cwd",
            cwd
        ]
        .map(shellQuote)
        .joined(separator: " ") + "\n"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
