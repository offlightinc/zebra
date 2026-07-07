import Foundation

struct ZebraSourceOnboardingRuntimeLaunchPlan: Equatable {
    enum Runtime: String, Equatable {
        case openclaw
        case hermes
        case unsupported
    }

    let runtime: Runtime
    let runtimeID: String
    let executablePath: String
    let launchDirectory: String
    let helperPath: String
    let promptPath: String
    let prompt: String
    let shellEnvironmentPrefix: String
    let startMessage: String
    let openClawAgentID: String?
    let openClawAgentWorkspace: String?
    let openClawSessionKey: String?
    let hermesSessionID: String?

    var terminalStartupLine: String {
        let executable = ZebraAgentLaunchCommand.shellQuote(executablePath)
        let helper = ZebraAgentLaunchCommand.shellQuote(helperPath)
        let promptPathArgument = ZebraAgentLaunchCommand.shellQuote(promptPath)
        let launchDirectoryArgument = ZebraAgentLaunchCommand.shellQuote(launchDirectory)
        let command: String
        switch runtime {
        case .openclaw:
            let launchStartingEvent = ZebraAgentLaunchCommand.shellQuote("openclaw.source_onboarding.launch.starting")
            let launchFinishedEvent = ZebraAgentLaunchCommand.shellQuote("openclaw.source_onboarding.launch.finished")
            command = "ZEBRA_SOURCE_ONBOARDING_PROMPT=$(cat \(promptPathArgument)) && { \(helper) audit-openclaw-config --event \(launchStartingEvent) --executable \(executable) >/dev/null 2>&1 || true; } && \(startMessage) && cd \(launchDirectoryArgument) && \(executable) tui --message \"$ZEBRA_SOURCE_ONBOARDING_PROMPT\"; _ZEBRA_SOURCE_ONBOARDING_OPENCLAW_STATUS=$?; \(helper) audit-openclaw-config --event \(launchFinishedEvent) --executable \(executable) >/dev/null 2>&1 || true; exit $_ZEBRA_SOURCE_ONBOARDING_OPENCLAW_STATUS\r"
        case .hermes:
            command = "ZEBRA_SOURCE_ONBOARDING_PROMPT=$(cat \(promptPathArgument)) && \(startMessage) && cd \(launchDirectoryArgument) && exec \(executable) chat --tui --source zebra-source-onboarding --query \"$ZEBRA_SOURCE_ONBOARDING_PROMPT\"\r"
        case .unsupported:
            command = "echo 'Unsupported OpenClaw/Hermes runtime for Source Onboarding: \(runtimeID)' >&2 && exit 1\r"
        }
        return "\(shellEnvironmentPrefix)\(command)"
    }

    static func make(
        launch: ZebraSourceOnboardingHelper.LaunchContext,
        runtime selectedRuntime: ZebraGBrainRuntimeOnboardingStore.SelectedRuntime,
        prompt rawPrompt: String,
        language: ZebraOnboardingLanguage = ZebraOnboardingLanguage.current(),
        runID: String = UUID().uuidString
    ) -> ZebraSourceOnboardingRuntimeLaunchPlan? {
        let prompt = "\(language.promptPolicy)\n\n\(rawPrompt)"
        guard let promptPath = writePromptFile(
            directoryPath: launch.runtimePromptDirectory,
            prompt: prompt
        ) else {
            return nil
        }
        let runtime = Runtime(rawValue: selectedRuntime.runtime) ?? .unsupported
        let displayName = displayName(for: selectedRuntime.runtime)
        let startMessage = "printf '%s\\n' \(ZebraAgentLaunchCommand.shellQuote("Starting \(displayName) for Zebra Source Onboarding..."))"
        let openClawAgentID: String?
        let openClawSessionKey: String?
        if runtime == .openclaw {
            let agentID = sourceReplayOpenClawAgentID(runID: runID)
            openClawAgentID = agentID
            openClawSessionKey = "agent:\(agentID):\(runID)"
        } else {
            openClawAgentID = nil
            openClawSessionKey = nil
        }
        return ZebraSourceOnboardingRuntimeLaunchPlan(
            runtime: runtime,
            runtimeID: selectedRuntime.runtime,
            executablePath: selectedRuntime.executablePath,
            launchDirectory: launch.launchDirectory,
            helperPath: launch.helperPath,
            promptPath: promptPath,
            prompt: prompt,
            shellEnvironmentPrefix: launch.shellEnvironmentPrefix,
            startMessage: startMessage,
            openClawAgentID: openClawAgentID,
            openClawAgentWorkspace: runtime == .openclaw ? launch.launchDirectory : nil,
            openClawSessionKey: openClawSessionKey,
            hermesSessionID: nil
        )
    }

    private static func writePromptFile(directoryPath: String, prompt: String) -> String? {
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let url = directory.appendingPathComponent(
            "source-onboarding-\(UUID().uuidString).prompt.txt",
            isDirectory: false
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url.path
        } catch {
            return nil
        }
    }

    private static func displayName(for runtime: String) -> String {
        switch runtime {
        case "openclaw":
            return "OpenClaw"
        case "hermes":
            return "Hermes"
        default:
            return runtime
        }
    }

    private static func sourceReplayOpenClawAgentID(runID: String) -> String {
        let safeRunID = runID
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "-" {
                    return character
                }
                return "-"
            }
        let suffix = String(String(safeRunID).suffix(32)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "zebra-source-replay-\(suffix.isEmpty ? "run" : suffix)"
    }
}
