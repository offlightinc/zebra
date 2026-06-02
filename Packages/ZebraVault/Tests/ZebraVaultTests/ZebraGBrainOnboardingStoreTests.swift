import XCTest
@testable import ZebraVault

final class ZebraGBrainOnboardingStoreTests: XCTestCase {
    func testSelectedVaultReceiptCompletesGBrainStep() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "main\n".write(to: vault.appendingPathComponent(".gbrain-source"), atomically: true, encoding: .utf8)
        let bin = try installFakeGBrain(root: root, sourceId: "main", localPath: vault.path)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: vault.path,
            sourceId: "main",
            method: "selected_vault"
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": bin.path]
        )

        XCTAssertTrue(store.isSetupCompleted(selectedVaultPath: vault.path))
    }

    func testPrimaryTargetCompletesWhenNoVaultSelected() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "main\n".write(to: vault.appendingPathComponent(".gbrain-source"), atomically: true, encoding: .utf8)
        let bin = try installFakeGBrain(root: root, sourceId: "main", localPath: vault.path)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: vault.path,
            sourceId: "main",
            method: "user_existing_repo"
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": bin.path]
        )

        XCTAssertTrue(store.isSetupCompleted(selectedVaultPath: nil))
    }

    func testUnconfirmedDiscoveryCandidateDoesNotComplete() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "main\n".write(to: vault.appendingPathComponent(".gbrain-source"), atomically: true, encoding: .utf8)
        let bin = try installFakeGBrain(root: root, sourceId: "main", localPath: vault.path)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: vault.path,
            sourceId: "main",
            method: "auto_discovered_candidate"
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": bin.path]
        )

        XCTAssertFalse(store.isSetupCompleted(selectedVaultPath: vault.path))
    }

    func testStaleReceiptDoesNotCompleteWhenLiveSourcePathDiffers() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        let other = root.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try "main\n".write(to: vault.appendingPathComponent(".gbrain-source"), atomically: true, encoding: .utf8)
        let bin = try installFakeGBrain(root: root, sourceId: "main", localPath: other.path)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: vault.path,
            sourceId: "main",
            method: "selected_vault"
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": bin.path]
        )

        XCTAssertFalse(store.isSetupCompleted(selectedVaultPath: vault.path))
    }

    func testLiveVerifierFindsBunShimWhenAppPathIsEmpty() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "brain\n".write(to: vault.appendingPathComponent(".gbrain-source"), atomically: true, encoding: .utf8)
        try installFakeBunBackedGBrain(root: root, sourceId: "brain", localPath: vault.path)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: vault.path,
            sourceId: "brain",
            method: "user_created_repo"
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": ""]
        )

        XCTAssertTrue(store.isSetupCompleted(selectedVaultPath: nil))
    }

    func testLiveVerifierCanRecoverStaleIncompleteReceipt() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "brain\n".write(to: vault.appendingPathComponent(".gbrain-source"), atomically: true, encoding: .utf8)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: vault.path)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: vault.path,
            sourceId: "brain",
            method: "user_created_repo",
            complete: false
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": bin.path]
        )

        XCTAssertTrue(store.isSetupCompleted(selectedVaultPath: nil))
        let target = try receiptTarget(in: stateURL, targetPath: vault.path)
        XCTAssertEqual(target["complete"] as? Bool, true)
        XCTAssertEqual(target["reasons"] as? [String], [])
    }

    func testPrepareLaunchWithoutSelectedVaultRequiresTopologyResolutionFirst() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"]
        )

        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let expectedWorkDirectory = root.appendingPathComponent("gbrain-work", isDirectory: true)
        var isDirectory: ObjCBool = false

        XCTAssertEqual(launch.launchDirectory, expectedWorkDirectory.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedWorkDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertFalse(launch.allowTrustedAutomation)
        XCTAssertTrue(launch.allowLaunchDirectoryTrust)
        XCTAssertTrue(launch.startupPrompt.contains("Do not implicitly use the home directory"))
        XCTAssertTrue(launch.startupPrompt.contains("do not run `gbrain init`"))
        XCTAssertTrue(launch.startupPrompt.contains("waitingForUser: topology_resolution"))
        XCTAssertTrue(launch.startupPrompt.contains("Ask only for the Step 3 topology decision now"))
        XCTAssertTrue(launch.startupPrompt.contains("Do not ask for the brain repo target in this gate"))
        XCTAssertTrue(launch.startupPrompt.contains("Do not ask for Step 2 API keys in this gate"))
        XCTAssertTrue(launch.startupPrompt.contains("Target-resolution timing"))
        XCTAssertFalse(launch.startupPrompt.contains("User decisions you must stop and ask for"))
        XCTAssertTrue(launch.shellEnvironmentPrefix.contains("ZEBRA_GBRAIN_STATE"))
        let progress = try progressObject(in: stateURL)
        XCTAssertEqual(progress["waitingForUser"] as? String, "topology_resolution")
        XCTAssertEqual(progress["nextSection"] as? String, "Step 3: Create the Brain")
    }

    func testPrepareLaunchPreservesBrainRepoTargetResolutionGate() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        try """
        {
          "schemaVersion": 1,
          "progress": {
            "launchDirectory": "\(root.path)",
            "completedSections": [],
            "waitingForUser": "brain_repo_target_resolution",
            "nextSection": "Step 3: Create the Brain"
          }
        }
        """.write(to: stateURL, atomically: true, encoding: .utf8)

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"]
        )

        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let progress = try progressObject(in: stateURL)

        XCTAssertTrue(launch.startupPrompt.contains("waitingForUser: brain_repo_target_resolution"))
        XCTAssertTrue(launch.startupPrompt.contains("Ask only for the Step 3 brain repo target now"))
        XCTAssertFalse(launch.startupPrompt.contains("Ask only for the Step 3 topology decision now"))
        XCTAssertEqual(progress["waitingForUser"] as? String, "brain_repo_target_resolution")
        XCTAssertEqual(progress["nextSection"] as? String, "Step 3: Create the Brain")
    }

    func testPrepareLaunchAddsDocsSnapshotManifest() throws {
        let root = try makeTemporaryDirectory()
        let repo = root.appendingPathComponent("gbrain-docs-source", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        # Install

        ## Step 1: Install CLI
        Install the CLI.

        ## Step 3: Create the Brain
        Ask for the brain repo target.
        """
        .write(to: repo.appendingPathComponent("INSTALL_FOR_AGENTS.md"), atomically: true, encoding: .utf8)
        try "# GBrain\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo
        )

        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let state = try String(contentsOf: stateURL, encoding: .utf8)

        XCTAssertTrue(launch.startupPrompt.contains("GBrain docs snapshot:"))
        XCTAssertTrue(launch.startupPrompt.contains("Step 1: Install CLI"))
        XCTAssertTrue(launch.startupPrompt.contains("Step 3: Create the Brain"))
        XCTAssertTrue(state.contains("\"docsManifest\""))
        XCTAssertTrue(state.contains("\"docsSnapshotPath\""))
    }

    func testPrepareLaunchResetsCompletedSectionsWhenDocsChange() throws {
        let root = try makeTemporaryDirectory()
        let repo = root.appendingPathComponent("gbrain-docs-source", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let install = repo.appendingPathComponent("INSTALL_FOR_AGENTS.md")
        try """
        # Install

        ## Step 1: Install CLI
        First version.

        ## Step 2: Configure
        Configure.
        """
        .write(to: install, atomically: true, encoding: .utf8)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try markCompletedSection("Step 1: Install CLI", in: stateURL)
        try """
        # Install

        ## Step 1: Install CLI
        Changed version.

        ## Step 2: Configure
        Configure.
        """
        .write(to: install, atomically: true, encoding: .utf8)

        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let progress = try progressObject(in: stateURL)

        XCTAssertEqual(progress["completedSections"] as? [String], [])
        XCTAssertEqual(progress["nextSection"] as? String, "Step 1: Install CLI")
    }

    private func writeState(
        _ stateURL: URL,
        targetPath: String,
        sourceId: String,
        method: String,
        complete: Bool = true
    ) throws {
        let key = "vault:\((targetPath as NSString).standardizingPath)"
        let json = """
        {
          "schemaVersion": 1,
          "receipt": {
            "globalReadiness": {
              "complete": true
            },
            "primaryTargetKey": "\(key)",
            "targets": {
              "\(key)": {
                "vaultPath": "\(targetPath)",
                "sourceId": "\(sourceId)",
                "profileId": "default",
                "complete": \(complete ? "true" : "false"),
                "targetResolution": {
                  "method": "\(method)",
                  "confirmedAt": "2026-06-02T00:00:00Z"
                },
                "sourcesCurrentResult": {
                  "ok": true,
                  "sourceId": "\(sourceId)",
                  "localPath": "\(targetPath)"
                }
              }
            }
          }
        }
        """
        try json.write(to: stateURL, atomically: true, encoding: .utf8)
    }

    private func receiptTarget(in stateURL: URL, targetPath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: stateURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let receipt = try XCTUnwrap(object["receipt"] as? [String: Any])
        let targets = try XCTUnwrap(receipt["targets"] as? [String: Any])
        let key = "vault:\((targetPath as NSString).standardizingPath)"
        return try XCTUnwrap(targets[key] as? [String: Any])
    }

    private func installFakeGBrain(root: URL, sourceId: String, localPath: String) throws -> URL {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        try writeFakeGBrainScript(script, sourceId: sourceId, localPath: localPath, shebang: "#!/bin/sh")
        return bin
    }

    private func installFakeBunBackedGBrain(root: URL, sourceId: String, localPath: String) throws {
        let bin = root.appendingPathComponent(".bun/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let bun = bin.appendingPathComponent("fakebun", isDirectory: false)
        try """
        #!/bin/sh
        exec /bin/sh "$@"
        """
        .write(to: bun, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bun.path)

        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        try writeFakeGBrainScript(script, sourceId: sourceId, localPath: localPath, shebang: "#!/usr/bin/env fakebun")
    }

    private func writeFakeGBrainScript(
        _ script: URL,
        sourceId: String,
        localPath: String,
        shebang: String
    ) throws {
        let escapedPath = localPath.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let content = """
        \(shebang)
        if [ "$1" = "--version" ]; then
          echo "gbrain test"
          exit 0
        fi
        if [ "$1" = "doctor" ]; then
          echo '{"ok":true}'
          exit 0
        fi
        if [ "$1" = "sources" ] && [ "$2" = "current" ]; then
          echo '{"source_id":"\(sourceId)","tier":"dotfile","detail":".gbrain-source"}'
          exit 0
        fi
        if [ "$1" = "sources" ] && [ "$2" = "list" ]; then
          echo '{"sources":[{"id":"\(sourceId)","name":"Main","local_path":"\(escapedPath)","federated":false,"page_count":1,"last_sync_at":null}]}'
          exit 0
        fi
        exit 1
        """
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }

    private func markCompletedSection(_ section: String, in stateURL: URL) throws {
        let data = try Data(contentsOf: stateURL)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var progress = try XCTUnwrap(object["progress"] as? [String: Any])
        progress["completedSections"] = [section]
        object["progress"] = progress
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: stateURL, options: .atomic)
    }

    private func progressObject(in stateURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: stateURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["progress"] as? [String: Any])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZebraGBrainOnboardingStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url.standardizedFileURL
    }
}
