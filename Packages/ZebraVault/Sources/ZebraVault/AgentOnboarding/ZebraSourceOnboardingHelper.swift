import Foundation

struct ZebraSourceOnboardingHelper {
    struct LaunchContext {
        var helperPath: String
        var launchDirectory: String
        var runtimePromptDirectory: String
        var shellEnvironmentPrefix: String
    }

    private let stateURL: URL
    private let gbrainOnboardingStateURL: URL
    private let gbrainAdapterOnboardingStateURL: URL
    private let fileManager: FileManager
    private let homeDirectoryPath: String

    init(
        stateURL: URL = ZebraSourceOnboardingState.defaultStateURL(),
        gbrainOnboardingStateURL: URL = ZebraGBrainOnboardingStore.defaultStateURL(),
        gbrainAdapterOnboardingStateURL: URL = ZebraGBrainAdapterOnboardingStore.defaultStateURL(),
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory()
    ) {
        self.stateURL = stateURL
        self.gbrainOnboardingStateURL = gbrainOnboardingStateURL
        self.gbrainAdapterOnboardingStateURL = gbrainAdapterOnboardingStateURL
        self.fileManager = fileManager
        self.homeDirectoryPath = Self.standardizedPath(homeDirectoryPath)
    }

    func prepareLaunch(selectedVaultPath: String?) -> LaunchContext? {
        guard let helperURL = installHelperScript() else { return nil }
        guard let playbookDirectory = installSourcePlaybooks() else { return nil }
        let helperDirectory = helperURL.deletingLastPathComponent().path
        let languageCode = ZebraOnboardingLanguage.current().code
        persistOnboardingLanguageCode(languageCode)
        var commands = [
            "export ZEBRA_SOURCE_ONBOARDING_STATE=\(ZebraAgentLaunchCommand.shellQuote(stateURL.path))",
            "export ZEBRA_GBRAIN_SETUP_STATE=\(ZebraAgentLaunchCommand.shellQuote(gbrainOnboardingStateURL.path))",
            "export ZEBRA_GBRAIN_ADAPTER_STATE=\(ZebraAgentLaunchCommand.shellQuote(gbrainAdapterOnboardingStateURL.path))",
            "export ZEBRA_SOURCE_ONBOARDING_HOME=\(ZebraAgentLaunchCommand.shellQuote(homeDirectoryPath))",
            "export ZEBRA_SOURCE_PLAYBOOK_DIR=\(ZebraAgentLaunchCommand.shellQuote(playbookDirectory.path))",
            "export ZEBRA_REMINDERS_EVENTKIT_DIR=\(ZebraAgentLaunchCommand.shellQuote(remindersEventKitDirectoryURL().path))",
            "export ZEBRA_ONBOARDING_LANGUAGE=\(ZebraAgentLaunchCommand.shellQuote(languageCode))",
            "export PATH=\(ZebraAgentLaunchCommand.shellQuote(helperDirectory)):\"$PATH\"",
        ]
        if let selectedVaultPath = standardizedExistingDirectoryPath(selectedVaultPath) {
            commands.append("export ZEBRA_GBRAIN_WRITE_TARGET_PATH=\(ZebraAgentLaunchCommand.shellQuote(selectedVaultPath))")
        }
        return LaunchContext(
            helperPath: helperURL.path,
            launchDirectory: onboardingWorkDirectoryPath(),
            runtimePromptDirectory: runtimePromptDirectoryPath(),
            shellEnvironmentPrefix: commands.joined(separator: " && ") + " && "
        )
    }

    private func persistOnboardingLanguageCode(_ languageCode: String) {
        let directory = stateURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let languageURL = directory.appendingPathComponent(
            "source-onboarding-language.json",
            isDirectory: false
        )
        let sidecar = ["onboardingLanguageCode": languageCode]
        if let data = try? JSONSerialization.data(
            withJSONObject: sidecar,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: languageURL, options: .atomic)
        }

        guard fileManager.fileExists(atPath: stateURL.path),
              let data = try? Data(contentsOf: stateURL),
              var state = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        var entry = state["entryContext"] as? [String: Any] ?? [:]
        entry["onboardingLanguageCode"] = languageCode
        state["entryContext"] = entry
        state["updatedAt"] = ISO8601DateFormatter().string(from: Date())
        if let updated = try? JSONSerialization.data(
            withJSONObject: state,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? updated.write(to: stateURL, options: .atomic)
        }
    }

    private func installHelperScript() -> URL? {
        let onboardingDirectory = stateURL.deletingLastPathComponent()
        let directory = onboardingDirectory.appendingPathComponent("bin", isDirectory: true)
        let runtimeDirectory = onboardingDirectory.appendingPathComponent(
            "source-onboarding-runtime",
            isDirectory: true
        )
        let url = directory.appendingPathComponent("zebra-source-onboarding", isDirectory: false)
        do {
            guard let bundledRuntime = Self.sourceOnboardingRuntimeResourceURL(),
                  Self.runtimeResourceIsComplete(at: bundledRuntime)
            else { return nil }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporaryRuntime = onboardingDirectory.appendingPathComponent(
                ".source-onboarding-runtime-\(UUID().uuidString)",
                isDirectory: true
            )
            defer { try? fileManager.removeItem(at: temporaryRuntime) }
            try fileManager.copyItem(at: bundledRuntime, to: temporaryRuntime)
            guard Self.runtimeResourceIsComplete(at: temporaryRuntime) else { return nil }
            if fileManager.fileExists(atPath: runtimeDirectory.path) {
                try fileManager.removeItem(at: runtimeDirectory)
            }
            try fileManager.moveItem(at: temporaryRuntime, to: runtimeDirectory)
            let bundledEntrypoint = runtimeDirectory.appendingPathComponent(
                "zebra-source-onboarding",
                isDirectory: false
            )
            guard fileManager.fileExists(atPath: bundledEntrypoint.path) else { return nil }
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.copyItem(at: bundledEntrypoint, to: url)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            guard ZebraInteractiveTerminalRunner.install(
                in: directory,
                fileManager: fileManager
            ) != nil else { return nil }
            return url
        } catch {
            return nil
        }
    }

    private static func sourceOnboardingRuntimeResourceURL() -> URL? {
        let direct = Bundle.module.resourceURL?.appendingPathComponent(
            "SourceOnboardingRuntime",
            isDirectory: true
        )
        if let direct, FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        return Bundle.module.url(
            forResource: "SourceOnboardingRuntime",
            withExtension: nil
        )
    }

    private static func runtimeResourceIsComplete(at directory: URL) -> Bool {
        let requiredFiles = ["manifest.json", "main.py", "zebra-source-onboarding"]
        return requiredFiles.allSatisfy {
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent($0, isDirectory: false).path
            )
        }
    }

    private func installSourcePlaybooks() -> URL? {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("source-playbooks", isDirectory: true)
        let playbooks: [(resource: String, filename: String)] = [
            (
                "obsidian.direct-markdown.v1",
                "obsidian.direct-markdown.v1.md"
            ),
            (
                "imessage.imsg-cli.v1",
                "imessage.imsg-cli.v1.md"
            ),
            (
                "notion.ntn-cli.v1",
                "notion.ntn-cli.v1.md"
            ),
            (
                "apple-notes.memo-cli.v1",
                "apple-notes.memo-cli.v1.md"
            ),
            (
                "apple-reminders.eventkit.v1",
                "apple-reminders.eventkit.v1.md"
            ),
        ]
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            for playbook in playbooks {
                let destination = directory.appendingPathComponent(
                    playbook.filename,
                    isDirectory: false
                )
                guard let resource = Self.sourcePlaybookResourceURL(named: playbook.resource) else {
                    return nil
                }
                let contents = try String(contentsOf: resource, encoding: .utf8)
                try contents.write(to: destination, atomically: true, encoding: .utf8)
            }
        } catch {
            return nil
        }
        return directory
    }

    private static func sourcePlaybookResourceURL(named resource: String) -> URL? {
        Bundle.module.url(
            forResource: resource,
            withExtension: "md",
            subdirectory: "SourcePlaybooks"
        ) ?? Bundle.module.url(
            forResource: resource,
            withExtension: "md"
        )
    }

    private func remindersEventKitDirectoryURL() -> URL {
        stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("reminders-eventkit", isDirectory: true)
    }

    private func onboardingWorkDirectoryPath() -> String {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("source-onboarding-work", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return Self.standardizedPath(directory.path)
    }

    private func runtimePromptDirectoryPath() -> String {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("source-runtime-prompts", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return Self.standardizedPath(directory.path)
    }

    private func standardizedExistingDirectoryPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let standardized = Self.standardizedPath((path as NSString).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return standardized
    }

    private static func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

}
