import Foundation

public enum ZebraAgentOnboardingScriptCommand {
    public enum Command: String, Sendable {
        case run
        case choosePrimary = "choose-primary"
    }

    public static func shellStartupLine(
        command: Command,
        cwd: String,
        agent: ZebraAgentKind? = nil,
        languageCode: String? = nil,
        continueWithCommandFile: String? = nil
    ) -> String? {
        guard let scriptURL = Bundle.main.url(
            forResource: "zebra-agent-onboarding",
            withExtension: nil
        ) else {
            return nil
        }

        return shellStartupLine(
            scriptPath: scriptURL.path,
            command: command,
            cwd: cwd,
            agent: agent,
            languageCode: languageCode,
            continueWithCommandFile: continueWithCommandFile
        )
    }

    public static func shellStartupLine(
        scriptPath: String,
        command: Command,
        cwd: String,
        agent: ZebraAgentKind? = nil,
        languageCode: String? = nil,
        continueWithCommandFile: String? = nil
    ) -> String {
        var arguments = [
            scriptPath,
            command.rawValue,
        ]
        let trimmedCWD = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCWD.isEmpty {
            arguments += ["--cwd", trimmedCWD]
        }
        if let agent {
            arguments += ["--agent", agent.rawValue]
        }
        let resolvedLanguageCode = languageCode
            .flatMap(ZebraOnboardingLanguage.resolve(_:))?
            .code ?? ZebraOnboardingLanguage.current().code
        arguments += ["--language", resolvedLanguageCode]
        if let continueWithCommandFile,
           !continueWithCommandFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--continue-with-command-file", continueWithCommandFile]
        }
        return arguments.map(ZebraAgentLaunchCommand.shellQuote).joined(separator: " ") + "\r"
    }
}
