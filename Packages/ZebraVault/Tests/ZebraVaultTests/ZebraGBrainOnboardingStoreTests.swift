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
        let doctorStatus = try XCTUnwrap(target["doctorStatus"] as? [String: Any])
        XCTAssertEqual(doctorStatus["status"] as? String, "ok")
    }

    func testLiveVerifierKeepsCycleFreshnessAsStrictDoctorFailure() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "brain\n".write(to: vault.appendingPathComponent(".gbrain-source"), atomically: true, encoding: .utf8)
        let bin = try installFakeGBrainWithOnlyCycleFreshnessFailure(root: root, localPath: vault.path)
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

        XCTAssertFalse(store.isSetupCompleted(selectedVaultPath: nil))
        let target = try receiptTarget(in: stateURL, targetPath: vault.path)
        XCTAssertEqual(target["complete"] as? Bool, false)
        XCTAssertEqual(target["reasons"] as? [String], ["doctor_failed"])
        let doctorStatus = try XCTUnwrap(target["doctorStatus"] as? [String: Any])
        XCTAssertEqual(doctorStatus["status"] as? String, "failed")
    }

    func testWaitingForUserSkipsLiveVerification() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "brain\n".write(to: vault.appendingPathComponent(".gbrain-source"), atomically: true, encoding: .utf8)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: vault.path,
            sourceId: "brain",
            method: "user_created_repo"
        )
        try writeActiveProgress(
            stateURL,
            targetPath: vault.path,
            completedSections: [],
            waitingForUser: "topology_resolution"
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": ""]
        )

        let result = store.completionResult(selectedVaultPath: nil)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.reasons, ["waiting_for_user:topology_resolution"])
    }

    func testLiveVerifierDoesNotRewriteReceiptWhenMaterialStateIsUnchanged() throws {
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
        try rewriteReceiptVerifiedAt(
            stateURL,
            targetPath: vault.path,
            value: "2000-01-01T00:00:00Z"
        )
        let timestampOnlyState = try String(contentsOf: stateURL, encoding: .utf8)
        XCTAssertTrue(store.isSetupCompleted(selectedVaultPath: nil))
        let afterSecondVerification = try String(contentsOf: stateURL, encoding: .utf8)
        XCTAssertEqual(afterSecondVerification, timestampOnlyState)
    }

    func testLiveVerifierPreservesCompleteReceiptWhenSourceProbeIsTransient() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "brain\n".write(to: vault.appendingPathComponent(".gbrain-source"), atomically: true, encoding: .utf8)
        let bin = try installFakeGBrainWithTransientSources(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: vault.path,
            sourceId: "brain",
            method: "user_created_repo",
            complete: true
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": bin.path]
        )

        XCTAssertTrue(store.isSetupCompleted(selectedVaultPath: nil))
        let target = try receiptTarget(in: stateURL, targetPath: vault.path)
        XCTAssertEqual(target["complete"] as? Bool, true)
    }

    func testLiveVerifierPreservesCompleteReceiptWhenDoctorProbeIsTransient() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "brain\n".write(to: vault.appendingPathComponent(".gbrain-source"), atomically: true, encoding: .utf8)
        let bin = try installFakeGBrainWithTransientDoctor(root: root, localPath: vault.path)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: vault.path,
            sourceId: "brain",
            method: "user_created_repo",
            complete: true
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": bin.path]
        )

        XCTAssertTrue(store.isSetupCompleted(selectedVaultPath: nil))
        let target = try receiptTarget(in: stateURL, targetPath: vault.path)
        XCTAssertEqual(target["complete"] as? Bool, true)
    }

    func testActiveRunDoesNotCompleteBeforeImportIndexReport() throws {
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
            method: "user_created_repo"
        )
        try writeActiveProgress(
            stateURL,
            targetPath: vault.path,
            completedSections: [
                "Step 3: Create the Brain",
                "Step 3.5: Confirm search mode with the user (DO NOT SKIP)",
            ]
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": bin.path]
        )

        let result = store.completionResult(selectedVaultPath: nil)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.reasons, ["import_index_not_completed"])
    }

    func testActiveRunCompletesAfterImportIndexReportAndLiveVerification() throws {
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
            method: "user_created_repo"
        )
        try writeActiveProgress(
            stateURL,
            targetPath: vault.path,
            completedSections: [
                "Step 3: Create the Brain",
                "Step 3.5: Confirm search mode with the user (DO NOT SKIP)",
                "Step 4: Import and Index",
            ]
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": bin.path]
        )

        XCTAssertTrue(store.isSetupCompleted(selectedVaultPath: nil))
    }

    func testPrepareLaunchWithoutSelectedVaultStartsAtInstallBeforeTopologyGate() throws {
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
        XCTAssertTrue(launch.startupPrompt.contains("Zebra GBrain setup is starting"))
        XCTAssertTrue(launch.startupPrompt.contains(launch.setupPacketPath))
        XCTAssertFalse(launch.startupPrompt.contains("Do not implicitly use the home directory"))
        let packet = try setupPacketContent(launch)
        XCTAssertTrue(packet.contains("Do not implicitly use the home directory"))
        XCTAssertTrue(packet.contains("When Step 3 is the current section"))
        XCTAssertTrue(packet.contains("waitingForUser: none"))
        XCTAssertFalse(packet.contains("waitingForUser: topology_resolution"))
        XCTAssertFalse(packet.contains("Ask only for the Step 3 topology decision now"))
        XCTAssertFalse(packet.contains("Do not ask for the brain repo target in this gate"))
        XCTAssertFalse(packet.contains("Do not ask for Step 2 API keys in the topology prompt"))
        XCTAssertTrue(packet.contains("Do not run `gbrain init --pglite --no-embedding`"))
        XCTAssertTrue(packet.contains("provider key provided: set one of `OPENAI_API_KEY`, `ZEROENTROPY_API_KEY`, or `VOYAGE_API_KEY`"))
        XCTAssertTrue(packet.contains("defer embeddings: initialize with `gbrain init --pglite --no-embedding` now"))
        XCTAssertFalse(packet.contains("Target-resolution timing"))
        XCTAssertFalse(packet.contains("User decisions you must stop and ask for"))
        XCTAssertTrue(launch.shellEnvironmentPrefix.contains("ZEBRA_GBRAIN_STATE"))
        let progress = try progressObject(in: stateURL)
        XCTAssertNil(waitingForUserReason(in: progress))
        XCTAssertEqual(progress["nextSection"] as? String, "Step 1: Install GBrain")
    }

    func testPrepareLaunchPreservesBrainRepoTargetResolutionGate() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeProgress(
            stateURL,
            completedSections: ["Step 1: Install GBrain", "Step 2: API Keys"],
            waitingForUser: "brain_repo_target_resolution",
            nextSection: "Step 3: Create the Brain"
        )

        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let progress = try progressObject(in: stateURL)
        let packet = try setupPacketContent(launch)
        let recommendedBrainPath = root.appendingPathComponent("brain", isDirectory: true).path

        XCTAssertTrue(launch.startupPrompt.contains("Zebra GBrain setup is starting"))
        XCTAssertTrue(packet.contains("waitingForUser: brain_repo_target_resolution"))
        XCTAssertTrue(packet.contains("Ask only for the Step 3 brain repo target now"))
        XCTAssertTrue(packet.contains("1. Create a new brain repo at \(recommendedBrainPath) (recommended)"))
        XCTAssertTrue(packet.contains("2. Use an existing markdown/brain repo path that the user provides"))
        XCTAssertTrue(packet.contains("3. Create a new brain repo at a custom path"))
        XCTAssertTrue(packet.contains("Do not present Zebra's onboarding work directory"))
        XCTAssertTrue(packet.contains("Do not ask only as an open-ended"))
        XCTAssertFalse(packet.contains("Ask only for the Step 3 topology decision now"))
        XCTAssertEqual(waitingForUserReason(in: progress), "brain_repo_target_resolution")
        XCTAssertEqual(progress["nextSection"] as? String, "Step 3: Create the Brain")
    }

    func testPrepareLaunchClearsStaleInitialTopologyGateFromPacketStatus() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeProgress(
            stateURL,
            completedSections: [],
            waitingForUser: "topology_resolution",
            nextSection: "Step 3: Create the Brain"
        )

        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let progress = try progressObject(in: stateURL)
        let packet = try setupPacketContent(launch)

        XCTAssertNil(waitingForUserReason(in: progress))
        XCTAssertEqual(progress["nextSection"] as? String, "Step 1: Install GBrain")
        XCTAssertTrue(packet.contains("waitingForUser: none"))
        XCTAssertFalse(packet.contains("waiting_for_user:topology_resolution"))
        XCTAssertFalse(packet.contains("waitingForUser: topology_resolution"))
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
        let packet = try setupPacketContent(launch)

        XCTAssertTrue(launch.startupPrompt.contains("Zebra GBrain setup is starting"))
        XCTAssertTrue(packet.contains("GBrain docs snapshot:"))
        XCTAssertTrue(packet.contains("Step 1: Install CLI"))
        XCTAssertTrue(packet.contains("Step 3: Create the Brain"))
        XCTAssertTrue(state.contains("\"docsManifest\""))
        XCTAssertTrue(state.contains("\"docsSnapshotPath\""))
    }

    func testPrepareLaunchUsesPrefetchedDocsSnapshotRecordWhenRemoteDisabled() throws {
        let root = try makeTemporaryDirectory()
        let snapshot = root
            .appendingPathComponent("gbrain-docs", isDirectory: true)
            .appendingPathComponent("cached-ref", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try """
        # Install

        ## Step 1: Cached Install

        Use the prefetched docs snapshot.

        ## Step 2: Cached API Keys

        Configure keys.
        """
        .write(to: snapshot.appendingPathComponent("INSTALL_FOR_AGENTS.md"), atomically: true, encoding: .utf8)

        let recordURL = root
            .appendingPathComponent("gbrain-docs", isDirectory: true)
            .appendingPathComponent("latest-snapshot.json", isDirectory: false)
        try """
        {
          "commit": "cached-ref",
          "manifest": {
            "files": [
              {
                "hash": "install-hash",
                "path": "INSTALL_FOR_AGENTS.md"
              }
            ],
            "generatedAt": "2026-06-03T00:00:00Z",
            "installForAgentsSections": [
              {
                "hash": "step-1-hash",
                "title": "Step 1: Cached Install"
              },
              {
                "hash": "step-2-hash",
                "title": "Step 2: Cached API Keys"
              }
            ],
            "sourceKind": "remote",
            "sourceRef": "cached-ref",
            "sourceRepoPath": "https://raw.githubusercontent.com/garrytan/gbrain"
          },
          "path": "\(snapshot.path)",
          "storedAt": "2026-06-03T00:00:00Z"
        }
        """.write(to: recordURL, atomically: true, encoding: .utf8)

        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"]
        )

        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let packet = try setupPacketContent(launch)
        let state = try String(contentsOf: stateURL, encoding: .utf8)

        XCTAssertTrue(packet.contains("path: \(snapshot.path)"))
        XCTAssertTrue(packet.contains("commit: cached-ref"))
        XCTAssertTrue(packet.contains("Step 1: Cached Install"))
        XCTAssertFalse(packet.contains("GBrain docs snapshot:\nunavailable"))
        XCTAssertTrue(state.contains("\"docsSnapshotPath\""))
        XCTAssertTrue(state.contains("\"cached-ref\""))
    }

    func testPrepareLaunchIgnoresPartialPrefetchedDocsSnapshotRecord() throws {
        let root = try makeTemporaryDirectory()
        let snapshot = root
            .appendingPathComponent("gbrain-docs", isDirectory: true)
            .appendingPathComponent("partial-ref", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try "# GBrain\n".write(to: snapshot.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let recordURL = root
            .appendingPathComponent("gbrain-docs", isDirectory: true)
            .appendingPathComponent("latest-snapshot.json", isDirectory: false)
        try """
        {
          "commit": "partial-ref",
          "manifest": {
            "files": [
              {
                "hash": "readme-hash",
                "path": "README.md"
              }
            ],
            "generatedAt": "2026-06-03T00:00:00Z",
            "installForAgentsSections": [],
            "sourceKind": "remote",
            "sourceRef": "partial-ref",
            "sourceRepoPath": "https://raw.githubusercontent.com/garrytan/gbrain"
          },
          "path": "\(snapshot.path)",
          "storedAt": "2026-06-03T00:00:00Z"
        }
        """.write(to: recordURL, atomically: true, encoding: .utf8)

        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"]
        )

        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let packet = try setupPacketContent(launch)

        XCTAssertTrue(packet.contains("GBrain docs snapshot:\nunavailable"))
        XCTAssertFalse(packet.contains("partial-ref"))
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

    func testReportGuardRejectsCreateBrainCompletionWithoutTarget() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: root.appendingPathComponent("brain").path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let progress = try progressObject(in: stateURL)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("brain_repo_target_unresolved"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertEqual(waitingForUserReason(in: progress), "brain_repo_target_resolution")
        XCTAssertEqual(payload["nextAction"] as? String, "ask_user_for_brain_repo_target")
        XCTAssertNotNil(payload["targetOptions"])
        XCTAssertEqual(progress["completedSections"] as? [String], [])
    }

    func testReportWaitingForBrainTargetRequiresExplicitReasonForOptions() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: root.appendingPathComponent("brain").path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let missingReason = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "waiting_for_user",
                "--section", "Step 3: Create the Brain",
                "--note", "Need brain repo target confirmation before import, sync, or source registration",
            ]
        )
        let missingReasonPayload = try helperPayload(missingReason.stdout)

        XCTAssertNotEqual(missingReason.exitCode, 0)
        XCTAssertEqual(missingReasonPayload["reason"] as? String, "missing_waiting_reason")
        XCTAssertEqual(missingReasonPayload["allowedReasons"] as? [String], ["topology_resolution", "brain_repo_target_resolution"])

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "waiting_for_user",
                "--section", "Step 3: Create the Brain",
                "--reason", "brain_repo_target_resolution",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let progress = try progressObject(in: stateURL)
        let options = try XCTUnwrap(payload["targetOptions"] as? [[String: Any]])

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertEqual(waitingForUserReason(in: progress), "brain_repo_target_resolution")
        XCTAssertEqual(payload["nextAction"] as? String, "ask_user_for_brain_repo_target")
        XCTAssertEqual(options.first?["path"] as? String, root.appendingPathComponent("brain", isDirectory: true).path)
        XCTAssertFalse(options.contains { ($0["path"] as? String) == root.path })
        XCTAssertFalse(options.contains { ($0["path"] as? String)?.contains("gbrain-work") == true })
        XCTAssertNil(payload["forbiddenTargets"])
    }

    func testReportGuardRejectsForbiddenBrainTargets() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let workBrain = root
            .appendingPathComponent("gbrain-work", isDirectory: true)
            .appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: workBrain, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: workBrain.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path)

        let workTargetResult = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--target", workBrain.path,
                "--method", "user_created_repo",
            ]
        )
        let homeTargetResult = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--target", root.path,
                "--method", "user_created_repo",
            ]
        )
        let confirmedHomeResult = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--target", root.path,
                "--method", "user_confirmed_home",
            ]
        )
        let progress = try progressObject(in: stateURL)

        XCTAssertNotEqual(workTargetResult.exitCode, 0)
        XCTAssertTrue(
            workTargetResult.stdout.contains("onboarding_work_directory_target"),
            "stdout: \(workTargetResult.stdout) stderr: \(workTargetResult.stderr)"
        )
        XCTAssertNotEqual(homeTargetResult.exitCode, 0)
        XCTAssertTrue(
            homeTargetResult.stdout.contains("implicit_home_target"),
            "stdout: \(homeTargetResult.stdout) stderr: \(homeTargetResult.stderr)"
        )
        XCTAssertEqual(confirmedHomeResult.exitCode, 0, "stdout: \(confirmedHomeResult.stdout) stderr: \(confirmedHomeResult.stderr)")
        XCTAssertEqual(progress["resolvedTargetKey"] as? String, "vault:\(root.path)")
    }

    func testReportGuardAllowsCreateBrainCompletionWithExplicitTarget() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path)

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        let progress = try progressObject(in: stateURL)
        let targetResolution = try XCTUnwrap(progress["targetResolution"] as? [String: Any])

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue((progress["completedSections"] as? [String] ?? []).contains("Step 3: Create the Brain"))
        XCTAssertEqual(targetResolution["method"] as? String, "user_created_repo")
        XCTAssertEqual(progress["resolvedTargetKey"] as? String, "vault:\(target.path)")
    }

    func testReportGuardIgnoresCycleFreshnessAsCreateBrainBlocker() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrainWithOnlyCycleFreshnessFailure(root: root, localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path)

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        let progress = try progressObject(in: stateURL)

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue((progress["completedSections"] as? [String] ?? []).contains("Step 3: Create the Brain"))
        XCTAssertFalse(result.stdout.contains("doctor_failed"), "stdout: \(result.stdout) stderr: \(result.stderr)")
    }

    func testReportGuardRejectsCreateBrainCompletionWithoutEmbeddingDecision() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("embedding_decision_required"), "stdout: \(result.stdout) stderr: \(result.stderr)")
    }

    func testReportRecordsEmbeddingDecisionWithoutSecretValue() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: root.appendingPathComponent("brain").path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path, decision: "provider_key")
        let progress = try progressObject(in: stateURL)
        let decision = try XCTUnwrap(progress["embeddingDecision"] as? [String: Any])

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertEqual(decision["decision"] as? String, "provider_key")
        XCTAssertNil(decision["apiKey"])
        XCTAssertNil(decision["key"])
        XCTAssertTrue((progress["completedSections"] as? [String] ?? []).contains("Step 2: API Keys"))
    }

    func testReportGuardRejectsImportBeforeSearchModeCompletion() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path)
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "started",
                "--section", "Step 4: Import and Index",
            ]
        )
        let progress = try progressObject(in: stateURL)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("search_mode_not_completed"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue((progress["completedSections"] as? [String] ?? []).contains("Step 3: Create the Brain"))
    }

    func testReportGuardRejectsImportCompletionWithoutSourceRegistration() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        let other = root.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: other.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path)
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--target", target.path,
                "--method", "user_created_repo",
                "--source-id", "brain",
            ]
        )
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3.5: Confirm search mode with the user (DO NOT SKIP)",
            ]
        )

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 4: Import and Index",
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("source_not_registered"), "stdout: \(result.stdout) stderr: \(result.stderr)")
    }

    func testImportCompletionRecordsVerifiedSourceId() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path)
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3.5: Confirm search mode with the user (DO NOT SKIP)",
            ]
        )

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 4: Import and Index",
                "--source-id", "brain",
            ]
        )

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        let targetReceipt = try receiptTarget(in: stateURL, targetPath: target.path)
        XCTAssertEqual(targetReceipt["sourceId"] as? String, "brain")
    }

    func testHelperVerifyPreservesCompleteReceiptWhenSourceProbeIsTransient() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrainWithTransientSources(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: target.path,
            sourceId: "brain",
            method: "user_created_repo",
            complete: true
        )
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "verify",
                "--target", target.path,
                "--source-id", "brain",
                "--method", "user_created_repo",
            ]
        )

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(#""complete": true"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        let receipt = try receiptTarget(in: stateURL, targetPath: target.path)
        XCTAssertEqual(receipt["complete"] as? Bool, true)
        let globalReadiness = try globalReadiness(in: stateURL)
        XCTAssertEqual(globalReadiness["complete"] as? Bool, true)
    }

    func testHelperVerifyReportsPGLiteBusyInsteadOfSourceNotRegistered() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrainWithTransientSources(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: target.path,
            sourceId: "brain",
            method: "user_created_repo",
            complete: false
        )
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "verify",
                "--target", target.path,
                "--source-id", "brain",
                "--method", "user_created_repo",
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("pglite_busy"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertFalse(result.stdout.contains("source_not_registered"), "stdout: \(result.stdout) stderr: \(result.stderr)")
    }

    func testHelperVerifyPreservesCompleteReceiptWhenDoctorProbeIsTransient() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrainWithTransientDoctor(root: root, localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: target.path,
            sourceId: "brain",
            method: "user_created_repo",
            complete: true
        )
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "verify",
                "--target", target.path,
                "--source-id", "brain",
                "--method", "user_created_repo",
            ]
        )

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(#""complete": true"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        let receipt = try receiptTarget(in: stateURL, targetPath: target.path)
        XCTAssertEqual(receipt["complete"] as? Bool, true)
        let globalReadiness = try globalReadiness(in: stateURL)
        XCTAssertEqual(globalReadiness["complete"] as? Bool, true)
    }

    func testHelperVerifyKeepsCycleFreshnessAsStrictDoctorFailure() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrainWithOnlyCycleFreshnessFailure(root: root, localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: target.path,
            sourceId: "brain",
            method: "user_created_repo",
            complete: false
        )
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "verify",
                "--target", target.path,
                "--source-id", "brain",
                "--method", "user_created_repo",
            ]
        )

        XCTAssertEqual(result.exitCode, 1, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(#""complete": false"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        let receipt = try receiptTarget(in: stateURL, targetPath: target.path)
        XCTAssertEqual(receipt["complete"] as? Bool, false)
        XCTAssertEqual(receipt["reasons"] as? [String], ["doctor_failed"])
        let doctorStatus = try XCTUnwrap(receipt["doctorStatus"] as? [String: Any])
        XCTAssertEqual(doctorStatus["status"] as? String, "failed")
    }

    func testReportGuardRejectsImportCompletionBeforeSearchModeCompletion() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path)
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--target", target.path,
                "--method", "user_created_repo",
                "--source-id", "brain",
            ]
        )

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 4: Import and Index",
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("search_mode_not_completed"), "stdout: \(result.stdout) stderr: \(result.stderr)")
    }

    func testReportPreservesWaitingForUserOnUnrelatedSuccessfulReport() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: root.appendingPathComponent("brain").path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeProgress(
            stateURL,
            completedSections: ["Step 1: Install GBrain", "Step 2: API Keys"],
            waitingForUser: "brain_repo_target_resolution",
            nextSection: "Step 3: Create the Brain"
        )

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        let progress = try progressObject(in: stateURL)

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertEqual(waitingForUserReason(in: progress), "brain_repo_target_resolution")
    }

    func testReportClearsWaitingForUserWhenSameSectionIsResolved() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: root.appendingPathComponent("brain").path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let waiting = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "waiting_for_user",
                "--section", "Step 8: Integrations",
                "--note", "Need Gmail credential gateway choice for email-to-brain",
            ]
        )
        var progress = try progressObject(in: stateURL)
        XCTAssertEqual(waiting.exitCode, 0, "stdout: \(waiting.stdout) stderr: \(waiting.stderr)")
        XCTAssertEqual(waitingForUserSection(in: progress), "Step 8: Integrations")

        let completed = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 8: Integrations",
            ]
        )
        progress = try progressObject(in: stateURL)

        XCTAssertEqual(completed.exitCode, 0, "stdout: \(completed.stdout) stderr: \(completed.stderr)")
        XCTAssertNil(progress["waitingForUser"])
    }

    func testLegacyFreeformWaitingDoesNotBlockAfterVerifyReceiptComplete() throws {
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
            method: "user_created_repo"
        )
        try writeActiveProgress(
            stateURL,
            targetPath: vault.path,
            completedSections: [
                "Step 4: Import and Index",
                "Step 9: Verify",
            ],
            waitingForUser: "Need Gmail credential gateway choice for email-to-brain: ClawVisor or Google OAuth2 direct"
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": bin.path]
        )

        XCTAssertTrue(store.isSetupCompleted(selectedVaultPath: nil))
    }

    func testReportRejectsTargetFlagsOutsideCreateBrainCompletion() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        let progress = try progressObject(in: stateURL)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("target_flags_not_allowed"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertNil(progress["resolvedTargetKey"])
    }

    func testReportGuardSupportsAgentAssistedRoleMapping() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root, includeRenamedSearchMode: true)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path)
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )

        let unknownResult = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step X: Retrieval Budget",
            ]
        )
        XCTAssertNotEqual(unknownResult.exitCode, 0)
        XCTAssertTrue(unknownResult.stdout.contains("section_role_unknown"), "stdout: \(unknownResult.stdout) stderr: \(unknownResult.stderr)")

        let mappingResult = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "mapped_role",
                "--section", "Step X: Retrieval Budget",
                "--role", "search_mode",
                "--evidence", "agent read the section as search mode setup",
            ]
        )
        let retryResult = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step X: Retrieval Budget",
            ]
        )
        let state = try stateObject(in: stateURL)
        let sectionRoles = try XCTUnwrap(state["sectionRoles"] as? [String: Any])

        XCTAssertEqual(mappingResult.exitCode, 0, "stdout: \(mappingResult.stdout) stderr: \(mappingResult.stderr)")
        XCTAssertEqual(retryResult.exitCode, 0, "stdout: \(retryResult.stdout) stderr: \(retryResult.stderr)")
        XCTAssertFalse(sectionRoles.isEmpty)
    }

    func testReportGuardDoesNotMapStep7OrUpgradeTokenReuseSectionsToSearchMode() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root, includeTokenReuseNonRoleSections: true)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path, searchMode: nil)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path)
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )

        let step7 = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
            ]
        )
        let upgrade = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Upgrade",
            ]
        )
        let importStart = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "started",
                "--section", "Step 4: Import and Index",
            ]
        )

        XCTAssertEqual(step7.exitCode, 0, "stdout: \(step7.stdout) stderr: \(step7.stderr)")
        XCTAssertEqual(upgrade.exitCode, 0, "stdout: \(upgrade.stdout) stderr: \(upgrade.stderr)")
        XCTAssertNotEqual(importStart.exitCode, 0)
        XCTAssertTrue(importStart.stdout.contains("search_mode_not_completed"), "stdout: \(importStart.stdout) stderr: \(importStart.stderr)")
    }

    func testReportGuardRejectsAgentMappedSearchModeUntilConfigIsExplicitlySet() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root, includeRenamedSearchMode: true)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path, searchMode: nil)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path)
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "mapped_role",
                "--section", "Step X: Retrieval Budget",
                "--role", "search_mode",
                "--evidence", "agent read the section as search mode setup",
            ]
        )

        let searchModeCompleted = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step X: Retrieval Budget",
            ]
        )
        let importStart = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "started",
                "--section", "Step 4: Import and Index",
            ]
        )

        XCTAssertNotEqual(searchModeCompleted.exitCode, 0)
        XCTAssertTrue(
            searchModeCompleted.stdout.contains("search_mode_not_configured"),
            "stdout: \(searchModeCompleted.stdout) stderr: \(searchModeCompleted.stderr)"
        )
        XCTAssertNotEqual(importStart.exitCode, 0)
        XCTAssertTrue(importStart.stdout.contains("search_mode_not_completed"), "stdout: \(importStart.stdout) stderr: \(importStart.stderr)")
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

    private func writeActiveProgress(
        _ stateURL: URL,
        targetPath: String,
        completedSections: [String],
        waitingForUser: String? = nil
    ) throws {
        let data = try Data(contentsOf: stateURL)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let key = "vault:\((targetPath as NSString).standardizingPath)"
        object["currentRunId"] = "gbrain-test-run"
        var progress: [String: Any] = [
            "launchDirectory": targetPath,
            "resolvedTargetKey": key,
            "targetResolution": [
                "status": "resolved",
                "method": "user_created_repo",
                "confirmedAt": "2026-06-02T00:00:00Z",
            ],
            "completedSections": completedSections,
            "nextSection": "Step 4: Import and Index",
        ]
        if let waitingForUser {
            progress["waitingForUser"] = waitingForUser
        }
        object["progress"] = progress
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: stateURL, options: .atomic)
    }

    private func receiptTarget(in stateURL: URL, targetPath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: stateURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let receipt = try XCTUnwrap(object["receipt"] as? [String: Any])
        let targets = try XCTUnwrap(receipt["targets"] as? [String: Any])
        let key = "vault:\((targetPath as NSString).standardizingPath)"
        return try XCTUnwrap(targets[key] as? [String: Any])
    }

    private func globalReadiness(in stateURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: stateURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let receipt = try XCTUnwrap(object["receipt"] as? [String: Any])
        return try XCTUnwrap(receipt["globalReadiness"] as? [String: Any])
    }

    private func rewriteReceiptVerifiedAt(
        _ stateURL: URL,
        targetPath: String,
        value: String
    ) throws {
        let data = try Data(contentsOf: stateURL)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var receipt = try XCTUnwrap(object["receipt"] as? [String: Any])
        var globalReadiness = try XCTUnwrap(receipt["globalReadiness"] as? [String: Any])
        globalReadiness["verifiedAt"] = value
        receipt["globalReadiness"] = globalReadiness
        var targets = try XCTUnwrap(receipt["targets"] as? [String: Any])
        let key = "vault:\((targetPath as NSString).standardizingPath)"
        var target = try XCTUnwrap(targets[key] as? [String: Any])
        target["verifiedAt"] = value
        targets[key] = target
        receipt["targets"] = targets
        object["receipt"] = receipt
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: stateURL, options: .atomic)
    }

    private func stateObject(in stateURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: stateURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func helperPayload(_ stdout: String) throws -> [String: Any] {
        let data = try XCTUnwrap(stdout.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func setupPacketContent(_ launch: ZebraGBrainOnboardingStore.LaunchContext) throws -> String {
        try String(contentsOfFile: launch.setupPacketPath, encoding: .utf8)
    }

    private struct HelperRunResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    private func runHelper(
        stateURL: URL,
        path: String,
        arguments: [String]
    ) throws -> HelperRunResult {
        let helper = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-onboarding", isDirectory: false)
        let process = Process()
        process.executableURL = helper
        process.arguments = arguments
        process.environment = [
            "PATH": "\(path):/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
            "ZEBRA_GBRAIN_STATE": stateURL.path,
            "ZEBRA_GBRAIN_HOME": stateURL.deletingLastPathComponent().path,
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return HelperRunResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    @discardableResult
    private func recordEmbeddingDecision(
        stateURL: URL,
        path: String,
        decision: String = "defer_embeddings"
    ) throws -> HelperRunResult {
        try runHelper(
            stateURL: stateURL,
            path: path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 2: API Keys",
                "--embedding-decision", decision,
            ]
        )
    }

    private func writeGuardDocs(
        root: URL,
        includeRenamedSearchMode: Bool = false,
        includeTokenReuseNonRoleSections: Bool = false
    ) throws -> URL {
        let repo = root.appendingPathComponent("gbrain-docs-source", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let searchModeSection = includeRenamedSearchMode
            ? """

            ## Step X: Retrieval Budget

            Pick retrieval settings after the brain is created.
            """
            : """

            ## Step 3.5: Confirm search mode with the user (DO NOT SKIP)

            Choose conservative, balanced, or tokenmax.
            Run `gbrain config set search.mode <mode>` and verify with `gbrain search modes`.
            """
        let nonRoleSections = includeTokenReuseNonRoleSections
            ? """

            ## Step 7: Recurring Jobs

            Run `gbrain sync --repo ~/brain && gbrain embed --stale`.
            Run `gbrain doctor --json && gbrain embed --stale`.

            ## Upgrade

            If `gbrain post-upgrade` prints the cost matrix, ask the user whether to keep tokenmax.
            Then run `gbrain config set search.mode <mode>`.
            See Step 3.5 for conservative, balanced, and tokenmax details.
            """
            : ""
        try """
        # Install

        ## Step 1: Install GBrain

        Install with `bun install -g github:garrytan/gbrain`.
        Verify with `gbrain --version`.

        ## Step 2: API Keys

        Ask for ZEROENTROPY_API_KEY, OPENAI_API_KEY, or ANTHROPIC_API_KEY.

        ## Step 3: Create the Brain

        Run `gbrain init`.
        Run `gbrain doctor --json`.
        The user's markdown files and brain repo are separate from this tool repo.
        Ask the user where their files are, or create a new brain repo.
        \(searchModeSection)

        ## Step 4: Import and Index

        Run `gbrain import ~/brain/ --no-embed`.
        Run `gbrain embed --stale`.

        ## Step 9: Verify

        Read `docs/GBRAIN_VERIFY.md` and run all verification checks.
        \(nonRoleSections)
        """
        .write(to: repo.appendingPathComponent("INSTALL_FOR_AGENTS.md"), atomically: true, encoding: .utf8)
        try "# GBrain\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        return repo
    }

    private func installFakeGBrain(
        root: URL,
        sourceId: String,
        localPath: String,
        searchMode: String? = "balanced"
    ) throws -> URL {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        try writeFakeGBrainScript(script, sourceId: sourceId, localPath: localPath, searchMode: searchMode, shebang: "#!/bin/sh")
        return bin
    }

    private func installFakeGBrainWithTransientSources(root: URL) throws -> URL {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "gbrain test"
          exit 0
        fi
        if [ "$1" = "doctor" ]; then
          echo '{"ok":true}'
          exit 0
        fi
        if [ "$1" = "sources" ]; then
          echo "GBrain: Timed out waiting for PGLite lock." >&2
          exit 1
        fi
        exit 1
        """
        .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return bin
    }

    private func installFakeGBrainWithTransientDoctor(root: URL, localPath: String) throws -> URL {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "gbrain test"
          exit 0
        fi
        if [ "$1" = "doctor" ]; then
          echo "GBrain: Timed out waiting for PGLite lock." >&2
          exit 1
        fi
        if [ "$1" = "sources" ] && [ "$2" = "current" ]; then
          echo '{"source_id":"brain"}'
          exit 0
        fi
        if [ "$1" = "sources" ] && [ "$2" = "list" ]; then
          echo '{"sources":[{"id":"brain","local_path":"\(localPath)"}]}'
          exit 0
        fi
        exit 1
        """
        .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return bin
    }

    private func installFakeGBrainWithOnlyCycleFreshnessFailure(root: URL, localPath: String) throws -> URL {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "gbrain test"
          exit 0
        fi
        if [ "$1" = "doctor" ]; then
          echo '{"checks":[{"name":"connection","status":"ok"},{"name":"cycle_freshness","status":"fail","message":"Source has never completed a full cycle"}]}'
          exit 1
        fi
        if [ "$1" = "sources" ] && [ "$2" = "current" ]; then
          echo '{"source_id":"brain"}'
          exit 0
        fi
        if [ "$1" = "sources" ] && [ "$2" = "list" ]; then
          echo '{"sources":[{"id":"brain","local_path":"\(localPath)"}]}'
          exit 0
        fi
        exit 1
        """
        .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
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
        try writeFakeGBrainScript(
            script,
            sourceId: sourceId,
            localPath: localPath,
            searchMode: "balanced",
            shebang: "#!/usr/bin/env fakebun"
        )
    }

    private func writeFakeGBrainScript(
        _ script: URL,
        sourceId: String,
        localPath: String,
        searchMode: String?,
        shebang: String
    ) throws {
        let escapedPath = localPath.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let searchModeBlock: String
        if let searchMode {
            searchModeBlock = """
            if [ "$1" = "config" ] && [ "$2" = "get" ] && [ "$3" = "search.mode" ]; then
              echo "\(searchMode)"
              exit 0
            fi
            """
        } else {
            searchModeBlock = """
            if [ "$1" = "config" ] && [ "$2" = "get" ] && [ "$3" = "search.mode" ]; then
              echo "Config key not found: search.mode" >&2
              exit 1
            fi
            """
        }
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
        \(searchModeBlock)
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

    private func writeProgress(
        _ stateURL: URL,
        completedSections: [String],
        waitingForUser: String?,
        nextSection: String
    ) throws {
        let data = try Data(contentsOf: stateURL)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var progress = try XCTUnwrap(object["progress"] as? [String: Any])
        progress["completedSections"] = completedSections
        progress["nextSection"] = nextSection
        if let waitingForUser {
            progress["waitingForUser"] = waitingForUser
        } else {
            progress.removeValue(forKey: "waitingForUser")
        }
        object["progress"] = progress
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: stateURL, options: .atomic)
    }

    private func progressObject(in stateURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: stateURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["progress"] as? [String: Any])
    }

    private func waitingForUserReason(in progress: [String: Any]) -> String? {
        if let value = progress["waitingForUser"] as? String {
            return value
        }
        let value = progress["waitingForUser"] as? [String: Any]
        return value?["reason"] as? String
            ?? value?["note"] as? String
            ?? value?["section"] as? String
    }

    private func waitingForUserSection(in progress: [String: Any]) -> String? {
        if progress["waitingForUser"] is String {
            return nil
        }
        let value = progress["waitingForUser"] as? [String: Any]
        return value?["section"] as? String
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
