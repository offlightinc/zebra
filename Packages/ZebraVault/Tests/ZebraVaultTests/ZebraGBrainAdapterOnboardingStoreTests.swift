import XCTest
@testable import ZebraVault

final class ZebraGBrainAdapterOnboardingStoreTests: XCTestCase {
    func testPrepareLaunchRunsAdapterHelperDirectly() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)

        let launch = ZebraGBrainAdapterOnboardingStore(
            stateURL: stateURL,
            gbrainOnboardingStateURL: gbrainStateURL,
            homeDirectoryPath: root.path
        ).prepareLaunch(selectedVaultPath: vault.path)

        let line = try XCTUnwrap(launch?.startupLine)
        XCTAssertTrue(line.contains("zebra-gbrain-adapter-onboarding"), line)
        XCTAssertTrue(line.contains(" run"), line)
        XCTAssertTrue(line.contains("ZEBRA_GBRAIN_SETUP_STATE"), line)
        XCTAssertTrue(line.contains("ZEBRA_GBRAIN_ADAPTER_SELECTED_VAULT"), line)
        XCTAssertFalse(line.contains("Help me install"), line)
    }

    func testHelperRunClonesSiblingInstallsAndWritesReceipt() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = root
            .appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent("gbrain", isDirectory: true)
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        let adapterRemote = root.appendingPathComponent("adapter-remote", isDirectory: true)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try createFakeAdapterRepo(at: adapterRemote)
        try writeCompletedGBrainState(
            stateURL: gbrainStateURL,
            vaultPath: vault.path,
            sourceRepoPath: sourceRepo.path
        )

        let store = ZebraGBrainAdapterOnboardingStore(
            stateURL: adapterStateURL,
            gbrainOnboardingStateURL: gbrainStateURL,
            homeDirectoryPath: root.path
        )
        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: vault.path))
        let helperURL = adapterStateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-adapter-onboarding", isDirectory: false)

        let result = try runProcess(
            executableURL: helperURL,
            arguments: ["run"],
            environment: [
                "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
                "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
                "ZEBRA_GBRAIN_ADAPTER_REMOTE": adapterRemote.path,
                "ZEBRA_GBRAIN_ADAPTER_REF": "main",
                "ZEBRA_GBRAIN_ADAPTER_HOME": root.path,
                "ZEBRA_GBRAIN_ADAPTER_SELECTED_VAULT": vault.path,
            ]
        )

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let expectedAdapterRepo = sourceRepo
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-adapter", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedAdapterRepo.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".gbrain-adapter/skills/router/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".gbrain-adapter/skills/source-to-tasks/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".gbrain-adapter/skills/zebra-daily-planner/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("goals/README.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("tasks/README.md").path))

        let state = try stateObject(in: adapterStateURL)
        let binding = try XCTUnwrap(state["adapterSourceBinding"] as? [String: Any])
        XCTAssertEqual(binding["repoPath"] as? String, canonicalPath(expectedAdapterRepo))
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["complete"] as? Bool, true)
        XCTAssertEqual(receipt["targetVaultPath"] as? String, canonicalPath(vault))
        XCTAssertEqual(receipt["adapterRepoPath"] as? String, canonicalPath(expectedAdapterRepo))
        XCTAssertTrue(store.cachedCompletionResult(selectedVaultPath: vault.path).isComplete)
    }

    func testCachedCompletionRequiresSelectedVaultToMatchAdapterReceipt() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = root
            .appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent("gbrain", isDirectory: true)
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        let otherVault = root.appendingPathComponent("other-brain", isDirectory: true)
        let adapterRepo = sourceRepo
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-adapter", isDirectory: true)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherVault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: adapterRepo, withIntermediateDirectories: true)
        try writeCompletedGBrainState(
            stateURL: gbrainStateURL,
            vaultPath: vault.path,
            sourceRepoPath: sourceRepo.path
        )
        try writeInstalledAdapterFiles(vault)
        try writeCompletedAdapterState(
            stateURL: adapterStateURL,
            targetVaultPath: vault.path,
            adapterRepoPath: adapterRepo.path
        )

        let store = ZebraGBrainAdapterOnboardingStore(
            stateURL: adapterStateURL,
            gbrainOnboardingStateURL: gbrainStateURL,
            homeDirectoryPath: root.path
        )

        XCTAssertTrue(store.cachedCompletionResult(selectedVaultPath: vault.path).isComplete)
        XCTAssertFalse(store.cachedCompletionResult(selectedVaultPath: otherVault.path).isComplete)
    }

    func testHelperRunStopsBeforeInstallWhenTargetIsDirty() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = root
            .appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent("gbrain", isDirectory: true)
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        let adapterRemote = root.appendingPathComponent("adapter-remote", isDirectory: true)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try createFakeAdapterRepo(at: adapterRemote)
        try writeCompletedGBrainState(
            stateURL: gbrainStateURL,
            vaultPath: vault.path,
            sourceRepoPath: sourceRepo.path
        )
        try "# RESOLVER\n".write(to: vault.appendingPathComponent("RESOLVER.md"), atomically: true, encoding: .utf8)
        try runGit(["init", "-b", "main"], cwd: vault)
        try runGit(["add", "RESOLVER.md"], cwd: vault)
        try runGit(["commit", "-m", "seed"], cwd: vault)
        try "# RESOLVER\n\nlocal dirty edit\n".write(
            to: vault.appendingPathComponent("RESOLVER.md"),
            atomically: true,
            encoding: .utf8
        )
        let store = ZebraGBrainAdapterOnboardingStore(
            stateURL: adapterStateURL,
            gbrainOnboardingStateURL: gbrainStateURL,
            homeDirectoryPath: root.path
        )
        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: vault.path))
        let helperURL = adapterStateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-adapter-onboarding", isDirectory: false)

        let result = try runProcess(
            executableURL: helperURL,
            arguments: ["run"],
            environment: [
                "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
                "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
                "ZEBRA_GBRAIN_ADAPTER_REMOTE": adapterRemote.path,
                "ZEBRA_GBRAIN_ADAPTER_REF": "main",
                "ZEBRA_GBRAIN_ADAPTER_HOME": root.path,
                "ZEBRA_GBRAIN_ADAPTER_SELECTED_VAULT": vault.path,
            ]
        )

        XCTAssertNotEqual(result.status, 0)
        let state = try stateObject(in: adapterStateURL)
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        XCTAssertEqual(progress["lastFailure"] as? String, "target_dirty")
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".gbrain-adapter").path))
    }

    private func writeCompletedGBrainState(
        stateURL: URL,
        vaultPath: String,
        sourceRepoPath: String
    ) throws {
        let targetKey = "vault:\((vaultPath as NSString).standardizingPath)"
        let timestamp = "2026-06-04T00:00:00Z"
        let state: [String: Any] = [
            "schemaVersion": 1,
            "activeGBrainBinding": [
                "sourceRepoPath": sourceRepoPath,
                "sourceRepoStatus": "existing",
                "gbrainHomePath": sourceRepoPath,
                "confirmedAt": timestamp,
            ],
            "receipt": [
                "globalReadiness": [
                    "complete": true,
                    "verifiedAt": timestamp,
                ],
                "primaryTargetKey": targetKey,
                "targets": [
                    targetKey: [
                        "vaultPath": vaultPath,
                        "sourceId": "brain",
                        "complete": true,
                        "verifiedAt": timestamp,
                    ],
                ],
            ],
        ]
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateURL, options: .atomic)
    }

    private func writeCompletedAdapterState(
        stateURL: URL,
        targetVaultPath: String,
        adapterRepoPath: String
    ) throws {
        let targetKey = "vault:\((targetVaultPath as NSString).standardizingPath)"
        let timestamp = "2026-06-04T00:00:00Z"
        let state: [String: Any] = [
            "schemaVersion": 1,
            "adapterSourceBinding": [
                "repoPath": adapterRepoPath,
                "remote": "test",
                "ref": "main",
                "commit": "test",
                "status": "cloned",
            ],
            "receipt": [
                "complete": true,
                "targetKey": targetKey,
                "targetVaultPath": targetVaultPath,
                "adapterRepoPath": adapterRepoPath,
                "adapterRemote": "test",
                "adapterRef": "main",
                "adapterCommit": "test",
                "installerPath": "\(adapterRepoPath)/scripts/install.sh",
                "installedAt": timestamp,
                "verifiedAt": timestamp,
                "checks": [
                    "adapterSkillRouter": true,
                    "adapterSkillDailyTaskManager": true,
                    "adapterSkillDailyTaskPrep": true,
                    "adapterSkillSourceToTasks": true,
                    "adapterSkillZebraDailyPlanner": true,
                    "goalsReadme": true,
                    "tasksReadme": true,
                    "resolverBlock": true,
                    "schemaBlock": true,
                    "agentsBlock": true,
                ],
                "reasons": [],
            ],
        ]
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateURL, options: .atomic)
    }

    private func createFakeAdapterRepo(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let paths = [
            "scripts",
            "skills/router",
            "skills/daily-task-manager",
            "skills/daily-task-prep",
            "skills/source-to-tasks",
            "skills/zebra-daily-planner",
            "templates/blocks",
            "templates/goals",
            "templates/tasks",
        ]
        for path in paths {
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        let script = """
        #!/bin/sh
        set -eu
        BRAIN=""
        DRY_RUN=0
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --brain)
              BRAIN="$2"
              shift 2
              ;;
            --dry-run)
              DRY_RUN=1
              shift
              ;;
            *)
              exit 2
              ;;
          esac
        done
        if [ -z "$BRAIN" ]; then
          exit 2
        fi
        if [ "$DRY_RUN" = "1" ]; then
          exit 0
        fi
        mkdir -p "$BRAIN/.gbrain-adapter/skills/router" "$BRAIN/.gbrain-adapter/skills/daily-task-manager" "$BRAIN/.gbrain-adapter/skills/daily-task-prep" "$BRAIN/.gbrain-adapter/skills/source-to-tasks" "$BRAIN/.gbrain-adapter/skills/zebra-daily-planner" "$BRAIN/goals" "$BRAIN/tasks"
        printf 'router\\n' > "$BRAIN/.gbrain-adapter/skills/router/SKILL.md"
        printf 'daily-task-manager\\n' > "$BRAIN/.gbrain-adapter/skills/daily-task-manager/SKILL.md"
        printf 'daily-task-prep\\n' > "$BRAIN/.gbrain-adapter/skills/daily-task-prep/SKILL.md"
        printf 'source-to-tasks\\n' > "$BRAIN/.gbrain-adapter/skills/source-to-tasks/SKILL.md"
        printf 'zebra-daily-planner\\n' > "$BRAIN/.gbrain-adapter/skills/zebra-daily-planner/SKILL.md"
        printf 'goals\\n' > "$BRAIN/goals/README.md"
        printf 'tasks\\n' > "$BRAIN/tasks/README.md"
        for file in RESOLVER.md schema.md AGENTS.md; do
          {
            printf '# %s\\n\\n' "$file"
            printf '<!-- gbrain-adapter:begin goals-tasks -->\\n'
            printf 'installed\\n'
            printf '<!-- gbrain-adapter:end goals-tasks -->\\n'
          } > "$BRAIN/$file"
        done
        """
        let scriptURL = url.appendingPathComponent("scripts/install.sh", isDirectory: false)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try "router\n".write(to: url.appendingPathComponent("skills/router/SKILL.md"), atomically: true, encoding: .utf8)
        try "daily-task-manager\n".write(to: url.appendingPathComponent("skills/daily-task-manager/SKILL.md"), atomically: true, encoding: .utf8)
        try "daily-task-prep\n".write(to: url.appendingPathComponent("skills/daily-task-prep/SKILL.md"), atomically: true, encoding: .utf8)
        try "source-to-tasks\n".write(to: url.appendingPathComponent("skills/source-to-tasks/SKILL.md"), atomically: true, encoding: .utf8)
        try "zebra-daily-planner\n".write(to: url.appendingPathComponent("skills/zebra-daily-planner/SKILL.md"), atomically: true, encoding: .utf8)
        try "<!-- gbrain-adapter:begin goals-tasks -->\nresolver\n<!-- gbrain-adapter:end goals-tasks -->\n".write(
            to: url.appendingPathComponent("templates/blocks/RESOLVER.goals-tasks.md"),
            atomically: true,
            encoding: .utf8
        )
        try "<!-- gbrain-adapter:begin goals-tasks -->\nschema\n<!-- gbrain-adapter:end goals-tasks -->\n".write(
            to: url.appendingPathComponent("templates/blocks/schema.goals-tasks.md"),
            atomically: true,
            encoding: .utf8
        )
        try "<!-- gbrain-adapter:begin goals-tasks -->\nagents\n<!-- gbrain-adapter:end goals-tasks -->\n".write(
            to: url.appendingPathComponent("templates/blocks/AGENTS.goals-tasks.md"),
            atomically: true,
            encoding: .utf8
        )
        try "goals\n".write(to: url.appendingPathComponent("templates/goals/README.md"), atomically: true, encoding: .utf8)
        try "tasks\n".write(to: url.appendingPathComponent("templates/tasks/README.md"), atomically: true, encoding: .utf8)
        try runGit(["init", "-b", "main"], cwd: url)
        try runGit(["add", "."], cwd: url)
        try runGit(["commit", "-m", "seed"], cwd: url)
    }

    private func writeInstalledAdapterFiles(_ vault: URL) throws {
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".gbrain-adapter/skills/router", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".gbrain-adapter/skills/daily-task-manager", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".gbrain-adapter/skills/daily-task-prep", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".gbrain-adapter/skills/source-to-tasks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".gbrain-adapter/skills/zebra-daily-planner", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("goals", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("tasks", isDirectory: true), withIntermediateDirectories: true)
        try "router\n".write(to: vault.appendingPathComponent(".gbrain-adapter/skills/router/SKILL.md"), atomically: true, encoding: .utf8)
        try "manager\n".write(to: vault.appendingPathComponent(".gbrain-adapter/skills/daily-task-manager/SKILL.md"), atomically: true, encoding: .utf8)
        try "prep\n".write(to: vault.appendingPathComponent(".gbrain-adapter/skills/daily-task-prep/SKILL.md"), atomically: true, encoding: .utf8)
        try "source-to-tasks\n".write(to: vault.appendingPathComponent(".gbrain-adapter/skills/source-to-tasks/SKILL.md"), atomically: true, encoding: .utf8)
        try "zebra-daily-planner\n".write(to: vault.appendingPathComponent(".gbrain-adapter/skills/zebra-daily-planner/SKILL.md"), atomically: true, encoding: .utf8)
        try "goals\n".write(to: vault.appendingPathComponent("goals/README.md"), atomically: true, encoding: .utf8)
        try "tasks\n".write(to: vault.appendingPathComponent("tasks/README.md"), atomically: true, encoding: .utf8)
        for file in ["RESOLVER.md", "schema.md", "AGENTS.md"] {
            try """
            # \(file)

            <!-- gbrain-adapter:begin goals-tasks -->
            installed
            <!-- gbrain-adapter:end goals-tasks -->
            """.write(to: vault.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
    }

    private func runGit(_ arguments: [String], cwd: URL) throws {
        let result = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: [
                "-c", "user.name=Zebra Test",
                "-c", "user.email=zebra-test@example.com",
            ] + arguments,
            environment: [:],
            currentDirectoryURL: cwd
        )
        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL? = nil
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdoutText, stderrText)
    }

    private func stateObject(in stateURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: stateURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func canonicalPath(_ url: URL) -> String {
        let path = url.path
        if path.hasPrefix("/var/") {
            return "/private\(path)"
        }
        return path
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZebraGBrainAdapterOnboardingStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
