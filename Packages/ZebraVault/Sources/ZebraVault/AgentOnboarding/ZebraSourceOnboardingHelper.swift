import Foundation
import Darwin

struct ZebraSourceOnboardingHelper {
    enum InstallationError: Error, Equatable {
        case runtimeResourceMissing
        case runtimeResourceIncomplete
        case installedRuntimeIncomplete
        case runtimeEntrypointMissing
        case filesystemFailure(String)
    }

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
    private let runtimeResourceLocator: () -> URL?

    init(
        stateURL: URL = ZebraSourceOnboardingState.defaultStateURL(),
        gbrainOnboardingStateURL: URL = ZebraGBrainOnboardingStore.defaultStateURL(),
        gbrainAdapterOnboardingStateURL: URL = ZebraGBrainAdapterOnboardingStore.defaultStateURL(),
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory(),
        runtimeResourceLocator: @escaping () -> URL? = { Self.sourceOnboardingRuntimeResourceURL() }
    ) {
        self.stateURL = stateURL
        self.gbrainOnboardingStateURL = gbrainOnboardingStateURL
        self.gbrainAdapterOnboardingStateURL = gbrainAdapterOnboardingStateURL
        self.fileManager = fileManager
        self.homeDirectoryPath = Self.standardizedPath(homeDirectoryPath)
        self.runtimeResourceLocator = runtimeResourceLocator
    }

    func prepareLaunch(selectedVaultPath: String?) -> LaunchContext? {
        try? prepareLaunchResult(selectedVaultPath: selectedVaultPath).get()
    }

    func prepareLaunchResult(selectedVaultPath: String?) -> Result<LaunchContext, InstallationError> {
        let helperURL: URL
        do {
            helperURL = try installHelperScript()
        } catch let error as InstallationError {
            return .failure(error)
        } catch {
            return .failure(.filesystemFailure(String(describing: error)))
        }
        guard let playbookDirectory = installSourcePlaybooks() else {
            return .failure(.filesystemFailure("source_playbook_install_failed"))
        }
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
        return .success(LaunchContext(
            helperPath: helperURL.path,
            launchDirectory: onboardingWorkDirectoryPath(),
            runtimePromptDirectory: runtimePromptDirectoryPath(),
            shellEnvironmentPrefix: commands.joined(separator: " && ") + " && "
        ))
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

    private func installHelperScript() throws -> URL {
        let onboardingDirectory = stateURL.deletingLastPathComponent()
        let directory = onboardingDirectory.appendingPathComponent("bin", isDirectory: true)
        let runtimeDirectory = onboardingDirectory.appendingPathComponent(
            "source-onboarding-runtime",
            isDirectory: true
        )
        let runtimeGenerationsDirectory = onboardingDirectory.appendingPathComponent(
            "source-onboarding-runtimes",
            isDirectory: true
        )
        let url = directory.appendingPathComponent("zebra-source-onboarding", isDirectory: false)
        do {
            guard let bundledRuntime = runtimeResourceLocator() else {
                throw InstallationError.runtimeResourceMissing
            }
            guard Self.runtimeResourceIsComplete(at: bundledRuntime) else {
                throw InstallationError.runtimeResourceIncomplete
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let bundledVersion = Self.runtimeVersion(at: bundledRuntime) else {
                throw InstallationError.runtimeResourceIncomplete
            }
            let safeVersion = bundledVersion.map { character in
                character.isLetter || character.isNumber || character == "." || character == "-"
                    ? String(character)
                    : "-"
            }.joined()
            let generationDirectory = runtimeGenerationsDirectory.appendingPathComponent(
                "runtime-\(safeVersion)",
                isDirectory: true
            )
            try fileManager.createDirectory(at: runtimeGenerationsDirectory, withIntermediateDirectories: true)
            if !Self.runtimeResourceIsComplete(at: generationDirectory) {
                let temporaryRuntime = runtimeGenerationsDirectory.appendingPathComponent(
                    ".source-onboarding-runtime-\(UUID().uuidString)",
                    isDirectory: true
                )
                defer { try? fileManager.removeItem(at: temporaryRuntime) }
                try fileManager.copyItem(at: bundledRuntime, to: temporaryRuntime)
                guard Self.runtimeResourceIsComplete(at: temporaryRuntime) else {
                    throw InstallationError.installedRuntimeIncomplete
                }
                if Self.pathEntryExists(generationDirectory, fileManager: fileManager) {
                    _ = try fileManager.replaceItemAt(
                        generationDirectory,
                        withItemAt: temporaryRuntime,
                        backupItemName: nil,
                        options: []
                    )
                } else {
                    try fileManager.moveItem(at: temporaryRuntime, to: generationDirectory)
                }
            }
            let currentGeneration = runtimeDirectory.resolvingSymlinksInPath().standardizedFileURL
            let reuseInstalledRuntime = currentGeneration == generationDirectory.standardizedFileURL
                && Self.runtimeResourceIsComplete(at: runtimeDirectory)
            if !reuseInstalledRuntime {
                let temporaryLink = onboardingDirectory.appendingPathComponent(
                    ".source-onboarding-runtime-current-\(UUID().uuidString)",
                    isDirectory: false
                )
                defer { try? fileManager.removeItem(at: temporaryLink) }
                try fileManager.createSymbolicLink(at: temporaryLink, withDestinationURL: generationDirectory)
                if Self.pathEntryExists(runtimeDirectory, fileManager: fileManager) {
                    let attributes = try fileManager.attributesOfItem(atPath: runtimeDirectory.path)
                    let fileType = attributes[.type] as? FileAttributeType
                    let result: Int32
                    if fileType == .typeDirectory {
                        result = renamex_np(temporaryLink.path, runtimeDirectory.path, UInt32(RENAME_SWAP))
                    } else {
                        result = rename(temporaryLink.path, runtimeDirectory.path)
                    }
                    guard result == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                } else {
                    try fileManager.moveItem(at: temporaryLink, to: runtimeDirectory)
                }
            }
            let bundledEntrypoint = generationDirectory.appendingPathComponent(
                "zebra-source-onboarding",
                isDirectory: false
            )
            guard fileManager.fileExists(atPath: bundledEntrypoint.path) else {
                throw InstallationError.runtimeEntrypointMissing
            }
            if !reuseInstalledRuntime || !fileManager.isExecutableFile(atPath: url.path) {
                let temporaryEntrypoint = directory.appendingPathComponent(
                    ".zebra-source-onboarding-\(UUID().uuidString)",
                    isDirectory: false
                )
                defer { try? fileManager.removeItem(at: temporaryEntrypoint) }
                try fileManager.copyItem(at: bundledEntrypoint, to: temporaryEntrypoint)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporaryEntrypoint.path)
                if fileManager.fileExists(atPath: url.path) {
                    _ = try fileManager.replaceItemAt(
                        url,
                        withItemAt: temporaryEntrypoint,
                        backupItemName: nil,
                        options: []
                    )
                } else {
                    try fileManager.moveItem(at: temporaryEntrypoint, to: url)
                }
            }
            guard ZebraInteractiveTerminalRunner.install(
                in: directory,
                fileManager: fileManager
            ) != nil else {
                throw InstallationError.filesystemFailure("interactive_terminal_runner_install_failed")
            }
            return url
        } catch let error as InstallationError {
            throw error
        } catch {
            throw InstallationError.filesystemFailure(String(describing: error))
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
        let manifestURL = directory.appendingPathComponent("manifest.json", isDirectory: false)
        guard let data = try? Data(contentsOf: manifestURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schemaVersion"] as? Int == 1,
              let runtimeVersion = object["runtimeVersion"] as? String,
              !runtimeVersion.isEmpty,
              let entrypoint = object["entrypoint"] as? String,
              !entrypoint.isEmpty,
              let requiredFiles = object["requiredFiles"] as? [String],
              !requiredFiles.isEmpty
        else { return false }
        return requiredFiles.contains(entrypoint) && requiredFiles.allSatisfy {
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent($0, isDirectory: false).path
            )
        }
    }

    private static func runtimeVersion(at directory: URL) -> String? {
        let manifestURL = directory.appendingPathComponent("manifest.json", isDirectory: false)
        guard let data = try? Data(contentsOf: manifestURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["runtimeVersion"] as? String,
              !version.isEmpty
        else { return nil }
        return version
    }

    private static func pathEntryExists(_ url: URL, fileManager: FileManager) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
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
