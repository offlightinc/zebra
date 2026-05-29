import Foundation

public enum ZebraAgentOnboardingStartup {
    public static func shouldRunAutomaticWelcome(
        preferencesURL: URL = ZebraAgentPreferenceStore.defaultPreferencesURL(),
        stateURL: URL = defaultStateURL()
    ) -> Bool {
        !(hasCompletedState(at: stateURL) && hasValidPrimaryAgent(at: preferencesURL))
    }

    public static func appResourceShellStartupLine(cwd: String = NSHomeDirectory()) -> String? {
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

    public static func defaultStateURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("zebra", isDirectory: true)
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("agent-cli-state.json", isDirectory: false)
    }

    private static func hasCompletedState(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let phase = object["phase"] as? String else {
            return false
        }
        return phase == "complete"
    }

    private static func hasValidPrimaryAgent(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawPrimaryAgent = object["primaryAgent"] as? String else {
            return false
        }
        return ZebraAgentKind(rawValue: rawPrimaryAgent) != nil
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
