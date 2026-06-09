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
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let expectedWorkDirectory = root.appendingPathComponent("gbrain-work", isDirectory: true)
        var isDirectory: ObjCBool = false

        XCTAssertEqual(launch.launchDirectory, expectedWorkDirectory.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedWorkDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(launch.allowTrustedAutomation)
        XCTAssertFalse(launch.allowLaunchDirectoryTrust)
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

    func testPrepareLaunchBootstrapPromptIsSingleLineForTerminalStartup() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["ko"],
            preferredLanguages: ["ko-KR"]
        )

        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        XCTAssertFalse(launch.startupPrompt.contains("\n"), launch.startupPrompt)
        XCTAssertFalse(launch.startupPrompt.contains("\r"), launch.startupPrompt)
        XCTAssertTrue(launch.startupPrompt.contains("Zebra GBrain setup"), launch.startupPrompt)
        XCTAssertTrue(launch.startupPrompt.contains("setup packet"), launch.startupPrompt)
        XCTAssertTrue(launch.startupPrompt.contains(launch.setupPacketPath), launch.startupPrompt)
    }

    func testPrepareLaunchUsesKoreanAppLanguagePolicyInBootstrapAndPacket() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["ko"],
            preferredLanguages: ["ko-KR"]
        )

        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let packet = try setupPacketContent(launch)

        XCTAssertTrue(launch.startupPrompt.contains("Your first visible response must be a brief Korean sentence"))
        XCTAssertTrue(launch.startupPrompt.contains("Preserve `Zebra GBrain setup` and `setup packet` exactly."))
        XCTAssertFalse(launch.startupPrompt.contains("Zebra GBrain setup을 시작합니다"))
        XCTAssertTrue(launch.startupPrompt.unicodeScalars.allSatisfy { $0.isASCII })
        XCTAssertTrue(packet.contains("Use Zebra's app language (Korean) for user-facing prose."))
        XCTAssertTrue(packet.contains("Preserve technical terms, domain terminology, product names, commands, identifiers, file paths, environment variables, API names, CLI flags, JSON keys, error codes, and quoted/source text in their original English spelling."))
        XCTAssertTrue(packet.contains("provider key provided: `OPENAI_API_KEY`, `ZEROENTROPY_API_KEY`, `VOYAGE_API_KEY` 중 하나를 environment에 설정한 뒤 계속합니다."))
        XCTAssertTrue(packet.contains("defer embeddings: 지금 `gbrain init --pglite --no-embedding`으로 초기화합니다. embeddings는 나중에 설정할 수 있습니다."))
        XCTAssertTrue(packet.contains("새 brain repo를 만듭니다 (recommended)"))
        XCTAssertTrue(packet.contains("기존 markdown/brain repo path를 사용합니다"))
        XCTAssertTrue(packet.contains("custom path에 새 brain repo를 만듭니다"))
        XCTAssertFalse(packet.contains("provider key provided: set one of `OPENAI_API_KEY`, `ZEROENTROPY_API_KEY`, or `VOYAGE_API_KEY`"))
        XCTAssertFalse(packet.contains("Use Zebra's app language (English) for user-facing prose."))
    }

    func testOnboardingLanguageFallsBackToEnglishForUnsupportedLocale() {
        let language = ZebraOnboardingLanguage.current(
            appPreferredLocalizations: ["fr"],
            preferredLanguages: ["fr-FR"],
            currentLocaleIdentifier: "fr_FR"
        )

        XCTAssertEqual(language, .en)
        XCTAssertTrue(language.promptPolicy.contains("Use Zebra's app language (English)"))
    }

    func testOnboardingLanguageUsesAppPreferredLocalizationBeforeSystemLocale() {
        let language = ZebraOnboardingLanguage.current(
            appPreferredLocalizations: ["ja"],
            preferredLanguages: ["ko-KR"],
            currentLocaleIdentifier: "ko_KR"
        )

        XCTAssertEqual(language, .ja)
        XCTAssertTrue(language.promptPolicy.contains("Use Zebra's app language (Japanese)"))
    }

    func testPrepareLaunchPreservesBrainRepoTargetResolutionGate() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
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

    func testPrepareSourceRepoClonesMissingPathAndRecordsLocalDocsSnapshot() throws {
        let root = try makeTemporaryDirectory()
        let remote = try writeFakeGBrainRemoteRepo(root: root)
        let target = root.appendingPathComponent("custom-gbrain", isDirectory: true)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            environment: ["ZEBRA_GBRAIN_SOURCE_REMOTE": remote.path],
            arguments: ["prepare-source-repo", "--path", target.path]
        )
        let state = try stateObject(in: stateURL)
        let binding = try XCTUnwrap(state["activeGBrainBinding"] as? [String: Any])
        let manifest = try XCTUnwrap(state["docsManifest"] as? [String: Any])
        let snapshotPath = try XCTUnwrap(state["docsSnapshotPath"] as? String)
        let bindingPath = try XCTUnwrap(binding["sourceRepoPath"] as? String)
        let manifestSourcePath = try XCTUnwrap(manifest["sourceRepoPath"] as? String)
        let envResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["active-source-env"]
        )

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(envResult.exitCode, 0, "stdout:\n\(envResult.stdout)\nstderr:\n\(envResult.stderr)")
        XCTAssertEqual(binding["sourceRepoStatus"] as? String, "cloned")
        XCTAssertEqual(URL(fileURLWithPath: bindingPath).lastPathComponent, "custom-gbrain")
        XCTAssertEqual(manifest["sourceKind"] as? String, "local")
        XCTAssertEqual(URL(fileURLWithPath: manifestSourcePath).lastPathComponent, "custom-gbrain")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("INSTALL_FOR_AGENTS.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: (snapshotPath as NSString).appendingPathComponent("INSTALL_FOR_AGENTS.md")))
        XCTAssertTrue(envResult.stdout.contains("export ZEBRA_GBRAIN_SOURCE_REPO='\(target.path)'"), envResult.stdout)
        XCTAssertTrue(envResult.stdout.contains("export GBRAIN_HOME='\(root.path)'"), envResult.stdout)
        XCTAssertNil((state["receipt"] as? [String: Any])?["sourceRepoInstall"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("node_modules").path))
    }

    func testWriteSetupPacketUsesPreparedRecommendedHomeRepoAndRequiresGlobalLocalInstall() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root, name: "gbrain")
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )
        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let prepareResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let packetResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["write-setup-packet", "--path", launch.setupPacketPath]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(packetResult.exitCode, 0, "stdout:\n\(packetResult.stdout)\nstderr:\n\(packetResult.stderr)")
        let packet = try setupPacketContent(launch)
        XCTAssertTrue(packet.contains("sourceRepoPath: \(sourceRepo.path)"), packet)
        XCTAssertTrue(packet.contains("sourceRepoIsRecommended: true"), packet)
        XCTAssertTrue(packet.contains("installMode: recommended_home_global"), packet)
        XCTAssertTrue(packet.contains("`bun install`, then `bun install -g .`"), packet)
        XCTAssertFalse(packet.contains("github:garrytan/gbrain"), packet)
        XCTAssertTrue(packet.contains("===== BEGIN ZEBRA RUNTIME UPDATE (AUTHORITATIVE) ====="), packet)
        XCTAssertTrue(packet.contains("For source repo, install mode, docs snapshot, next section, and waitingForUser, this block overrides older matching context below."), packet)
        XCTAssertTrue(packet.contains("When Step 3 is the current section, before `gbrain init`, ask only for the topology decision."), packet)
        XCTAssertTrue(packet.contains("Record the user's Step 2 embedding decision"), packet)
        XCTAssertTrue(packet.contains("Before Step 4 import/embed/sync"), packet)
        XCTAssertTrue(packet.contains("After the user chooses search mode"), packet)
        XCTAssertTrue(packet.contains("If report rejects a section because the role is unknown"), packet)
        XCTAssertTrue(packet.contains("User decision rule:"), packet)
        let updateRange = try XCTUnwrap(packet.range(of: "===== BEGIN ZEBRA RUNTIME UPDATE (AUTHORITATIVE) ====="))
        let fullPacketRange = try XCTUnwrap(packet.range(of: "You are Zebra's GBrain setup agent."))
        XCTAssertLessThan(updateRange.lowerBound, fullPacketRange.lowerBound)
    }

    func testWriteSetupPacketUsesBunLinkForCustomSourceRepo() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root, name: "custom-gbrain")
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )
        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let prepareResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let packetResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["write-setup-packet", "--path", launch.setupPacketPath]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(packetResult.exitCode, 0, "stdout:\n\(packetResult.stdout)\nstderr:\n\(packetResult.stderr)")
        let packet = try setupPacketContent(launch)
        XCTAssertTrue(packet.contains("sourceRepoPath: \(sourceRepo.path)"), packet)
        XCTAssertTrue(packet.contains("sourceRepoIsRecommended: false"), packet)
        XCTAssertTrue(packet.contains("installMode: custom_source_repo_linked"), packet)
        XCTAssertTrue(packet.contains("`bun install`, then `bun link`"), packet)
        XCTAssertTrue(packet.contains("Step 1 must expose the active source repo through the user-visible `gbrain` command first"), packet)
        let updateStart = try XCTUnwrap(packet.range(of: "===== BEGIN ZEBRA RUNTIME UPDATE (AUTHORITATIVE) ====="))
        let updateEnd = try XCTUnwrap(packet.range(of: "===== END ZEBRA RUNTIME UPDATE ====="))
        let updateBlock = String(packet[updateStart.lowerBound..<updateEnd.upperBound])
        XCTAssertFalse(updateBlock.contains("`bun install`, then `bun install -g .`"), packet)
    }

    func testWriteRuntimeLauncherMovesOpenClawPromptIntoLauncherScript() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root, name: "gbrain")
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["ko"],
            preferredLanguages: ["ko-KR"]
        )
        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let prepareResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let packetResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["write-setup-packet", "--path", launch.setupPacketPath]
        )
        let launcherResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            languageCode: "ko",
            arguments: [
                "write-runtime-launcher",
                "--runtime", "openclaw",
                "--executable", "/tmp/openclaw",
                "--setup-packet", launch.setupPacketPath,
                "--run-id", launch.runId,
                "--agent-id", "zebra-gbrain-setup-test",
                "--session", "agent:zebra-gbrain-setup-test:\(launch.runId)",
            ]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(packetResult.exitCode, 0, "stdout:\n\(packetResult.stdout)\nstderr:\n\(packetResult.stderr)")
        XCTAssertEqual(launcherResult.exitCode, 0, "stdout:\n\(launcherResult.stdout)\nstderr:\n\(launcherResult.stderr)")
        XCTAssertFalse(launcherResult.stdout.contains("Zebra GBrain setup"), launcherResult.stdout)
        let prefix = "export ZEBRA_GBRAIN_RUNTIME_LAUNCHER='"
        XCTAssertTrue(launcherResult.stdout.hasPrefix(prefix), launcherResult.stdout)
        let launcherPath = String(
            launcherResult.stdout
                .dropFirst(prefix.count)
                .split(separator: "'", maxSplits: 1)
                .first ?? ""
        )
        let script = try String(contentsOfFile: launcherPath, encoding: .utf8)

        XCTAssertTrue(script.contains("zebra-gbrain-onboarding prepare-openclaw-agent --executable '/tmp/openclaw' --agent-id 'zebra-gbrain-setup-test'"), script)
        XCTAssertTrue(script.contains("cd \"$ZEBRA_GBRAIN_SOURCE_REPO\""), script)
        XCTAssertTrue(script.contains("exec '/tmp/openclaw' tui --local --session 'agent:zebra-gbrain-setup-test:\(launch.runId)' --message '"), script)
        XCTAssertTrue(script.contains("Zebra GBrain setup"), script)
        XCTAssertTrue(script.contains("setup packet"), script)
        XCTAssertTrue(script.contains(launch.setupPacketPath), script)
    }

    func testWriteRuntimeLauncherStartsHermesTUIWithSetupPrompt() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root, name: "gbrain")
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["ko"],
            preferredLanguages: ["ko-KR"]
        )
        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let prepareResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let packetResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["write-setup-packet", "--path", launch.setupPacketPath]
        )
        let launcherResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            languageCode: "ko",
            arguments: [
                "write-runtime-launcher",
                "--runtime", "hermes",
                "--executable", "/tmp/hermes",
                "--setup-packet", launch.setupPacketPath,
                "--run-id", launch.runId,
            ]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(packetResult.exitCode, 0, "stdout:\n\(packetResult.stdout)\nstderr:\n\(packetResult.stderr)")
        XCTAssertEqual(launcherResult.exitCode, 0, "stdout:\n\(launcherResult.stdout)\nstderr:\n\(launcherResult.stderr)")
        XCTAssertFalse(launcherResult.stdout.contains("Zebra GBrain setup"), launcherResult.stdout)
        let prefix = "export ZEBRA_GBRAIN_RUNTIME_LAUNCHER='"
        XCTAssertTrue(launcherResult.stdout.hasPrefix(prefix), launcherResult.stdout)
        let launcherPath = String(
            launcherResult.stdout
                .dropFirst(prefix.count)
                .split(separator: "'", maxSplits: 1)
                .first ?? ""
        )
        let script = try String(contentsOfFile: launcherPath, encoding: .utf8)

        XCTAssertTrue(script.contains("cd \"$ZEBRA_GBRAIN_SOURCE_REPO\""), script)
        XCTAssertTrue(script.contains("exec '/tmp/hermes' chat --tui --source zebra-gbrain-onboarding --query '"), script)
        XCTAssertTrue(script.contains("Zebra GBrain setup"), script)
        XCTAssertTrue(script.contains("setup packet"), script)
        XCTAssertTrue(script.contains(launch.setupPacketPath), script)
    }

    func testInstalledGBrainWrapperRunsSourceRepoCliTsWhenNoBuiltBinaryExists() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root)
        try FileManager.default.createDirectory(
            at: sourceRepo.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "gbrain source cli"
          exit 0
        fi
        exit 64
        """
        .write(to: sourceRepo.appendingPathComponent("src/cli.ts", isDirectory: false), atomically: true, encoding: .utf8)
        let fakeBunBin = root.appendingPathComponent("fake-bun-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBunBin, withIntermediateDirectories: true)
        let bun = fakeBunBin.appendingPathComponent("bun", isDirectory: false)
        try """
        #!/bin/sh
        exec /bin/sh "$@"
        """
        .write(to: bun, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bun.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let prepareResult = try runHelper(
            stateURL: stateURL,
            path: fakeBunBin.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let wrapper = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("gbrain", isDirectory: false)
        let versionResult = try runExecutable(
            wrapper,
            environment: [
                "PATH": "\(fakeBunBin.path):/usr/bin:/bin",
                "ZEBRA_GBRAIN_STATE": stateURL.path,
            ],
            arguments: ["--version"]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(versionResult.exitCode, 0, "stdout:\n\(versionResult.stdout)\nstderr:\n\(versionResult.stderr)")
        XCTAssertEqual(versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "gbrain source cli")
    }

    func testRecommendedHomeInstallReportRequiresGlobalGBrainNotWrapperFallback() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root, name: "gbrain")
        try FileManager.default.createDirectory(
            at: sourceRepo.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "gbrain source cli"
          exit 0
        fi
        exit 64
        """
        .write(to: sourceRepo.appendingPathComponent("src/cli.ts", isDirectory: false), atomically: true, encoding: .utf8)
        let fakeBunBin = root.appendingPathComponent("fake-bun-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBunBin, withIntermediateDirectories: true)
        let bun = fakeBunBin.appendingPathComponent("bun", isDirectory: false)
        try """
        #!/bin/sh
        exec /bin/sh "$@"
        """
        .write(to: bun, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bun.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let prepareResult = try runHelper(
            stateURL: stateURL,
            path: fakeBunBin.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let wrapper = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("gbrain", isDirectory: false)
        let wrapperVersion = try runExecutable(
            wrapper,
            environment: [
                "PATH": "\(fakeBunBin.path):/usr/bin:/bin",
                "ZEBRA_GBRAIN_STATE": stateURL.path,
            ],
            arguments: ["--version"]
        )
        let reportWithoutGlobal = try runHelper(
            stateURL: stateURL,
            path: fakeBunBin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        let globalBin = root.appendingPathComponent("global-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: globalBin, withIntermediateDirectories: true)
        let globalGBrain = globalBin.appendingPathComponent("gbrain", isDirectory: false)
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "gbrain global"
          exit 0
        fi
        exit 64
        """
        .write(to: globalGBrain, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: globalGBrain.path)
        let reportWithGlobal = try runHelper(
            stateURL: stateURL,
            path: "\(globalBin.path):\(fakeBunBin.path)",
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(wrapperVersion.exitCode, 0, "stdout:\n\(wrapperVersion.stdout)\nstderr:\n\(wrapperVersion.stderr)")
        XCTAssertNotEqual(reportWithoutGlobal.exitCode, 0, "stdout:\n\(reportWithoutGlobal.stdout)\nstderr:\n\(reportWithoutGlobal.stderr)")
        XCTAssertTrue(reportWithoutGlobal.stdout.contains("gbrain_version_failed"), reportWithoutGlobal.stdout)
        XCTAssertEqual(reportWithGlobal.exitCode, 0, "stdout:\n\(reportWithGlobal.stdout)\nstderr:\n\(reportWithGlobal.stderr)")
    }

    func testCustomSourceRepoInstallReportRequiresLinkedGBrainNotWrapperFallback() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root, name: "custom-gbrain")
        try FileManager.default.createDirectory(
            at: sourceRepo.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "gbrain source cli"
          exit 0
        fi
        exit 64
        """
        .write(to: sourceRepo.appendingPathComponent("src/cli.ts", isDirectory: false), atomically: true, encoding: .utf8)
        let fakeBunBin = root.appendingPathComponent("fake-bun-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBunBin, withIntermediateDirectories: true)
        let bun = fakeBunBin.appendingPathComponent("bun", isDirectory: false)
        try """
        #!/bin/sh
        exec /bin/sh "$@"
        """
        .write(to: bun, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bun.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let prepareResult = try runHelper(
            stateURL: stateURL,
            path: fakeBunBin.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let wrapper = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("gbrain", isDirectory: false)
        let wrapperVersion = try runExecutable(
            wrapper,
            environment: [
                "PATH": "\(fakeBunBin.path):/usr/bin:/bin",
                "ZEBRA_GBRAIN_STATE": stateURL.path,
            ],
            arguments: ["--version"]
        )
        let reportWithoutLinkedGBrain = try runHelper(
            stateURL: stateURL,
            path: fakeBunBin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        let globalBin = root.appendingPathComponent("global-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: globalBin, withIntermediateDirectories: true)
        let linkedGBrain = globalBin.appendingPathComponent("gbrain", isDirectory: false)
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "gbrain linked"
          exit 0
        fi
        exit 64
        """
        .write(to: linkedGBrain, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: linkedGBrain.path)
        let reportWithLinkedGBrain = try runHelper(
            stateURL: stateURL,
            path: "\(globalBin.path):\(fakeBunBin.path)",
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(wrapperVersion.exitCode, 0, "stdout:\n\(wrapperVersion.stdout)\nstderr:\n\(wrapperVersion.stderr)")
        XCTAssertNotEqual(reportWithoutLinkedGBrain.exitCode, 0, "stdout:\n\(reportWithoutLinkedGBrain.stdout)\nstderr:\n\(reportWithoutLinkedGBrain.stderr)")
        XCTAssertTrue(reportWithoutLinkedGBrain.stdout.contains("gbrain_version_failed"), reportWithoutLinkedGBrain.stdout)
        XCTAssertEqual(reportWithLinkedGBrain.exitCode, 0, "stdout:\n\(reportWithLinkedGBrain.stdout)\nstderr:\n\(reportWithLinkedGBrain.stderr)")
    }

    func testPrepareOpenClawAgentCreatesMissingAgentForActiveSourceRepo() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        let fakeOpenClaw = try writeFakeOpenClaw(root: root, agentsJSON: "[]")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let prepareResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let agentResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-openclaw-agent", "--executable", fakeOpenClaw.executable.path]
        )
        let payload = try helperPayload(agentResult.stdout)
        let log = try String(contentsOf: fakeOpenClaw.log, encoding: .utf8)

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(agentResult.exitCode, 0, "stdout:\n\(agentResult.stdout)\nstderr:\n\(agentResult.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["status"] as? String, "created")
        XCTAssertEqual(payload["agentId"] as? String, "zebra-gbrain-setup")
        XCTAssertEqual(payload["workspace"] as? String, sourceRepo.path)
        XCTAssertTrue(
            log.contains("agents add zebra-gbrain-setup --workspace \(sourceRepo.path) --non-interactive"),
            log
        )
    }

    func testPrepareOpenClawAgentRejectsExistingAgentWithDifferentWorkspace() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        let fakeOpenClaw = try writeFakeOpenClaw(
            root: root,
            agentsJSON: #"[{"id":"zebra-gbrain-setup","workspace":"/tmp/other-gbrain"}]"#
        )
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let prepareResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let agentResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-openclaw-agent", "--executable", fakeOpenClaw.executable.path]
        )
        let log = try String(contentsOf: fakeOpenClaw.log, encoding: .utf8)

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertNotEqual(agentResult.exitCode, 0)
        XCTAssertTrue(agentResult.stdout.contains("openclaw_agent_workspace_mismatch:"), agentResult.stdout)
        XCTAssertTrue(agentResult.stdout.contains("other-gbrain"), agentResult.stdout)
        XCTAssertFalse(log.contains("agents add"), log)
    }

    func testPrepareSourceRepoDoesNotPersistOrPrintDatabaseURL() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        let secretURL = "postgres://user:secret-password@example.test/gbrain"
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            environment: ["GBRAIN_DATABASE_URL": secretURL],
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let envResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            environment: ["GBRAIN_DATABASE_URL": secretURL],
            arguments: ["active-source-env"]
        )
        let stateText = try String(contentsOf: stateURL, encoding: .utf8)
        let state = try stateObject(in: stateURL)
        let binding = try XCTUnwrap(state["activeGBrainBinding"] as? [String: Any])

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(envResult.exitCode, 0, "stdout:\n\(envResult.stdout)\nstderr:\n\(envResult.stderr)")
        XCTAssertNil(binding["databaseURL"])
        XCTAssertFalse(result.stdout.contains(secretURL), result.stdout)
        XCTAssertFalse(envResult.stdout.contains(secretURL), envResult.stdout)
        XCTAssertFalse(stateText.contains(secretURL), stateText)
        XCTAssertTrue(envResult.stdout.contains("DATABASE_URL"), envResult.stdout)
        XCTAssertTrue(envResult.stdout.contains("GBRAIN_DATABASE_URL"), envResult.stdout)
    }

    func testPrepareSourceRepoResetsProgressWhenDocsManifestChanges() throws {
        let root = try makeTemporaryDirectory()
        let oldRepo = try writeFakeGBrainSourceRepo(
            root: root,
            name: "old-gbrain-source",
            installSectionTitle: "Step 1: Old Install",
            credentialsSectionTitle: "Step 2: Old Keys"
        )
        let newRepo = try writeFakeGBrainSourceRepo(
            root: root,
            name: "new-gbrain-source",
            installSectionTitle: "Step 1: New Install",
            credentialsSectionTitle: "Step 2: New Keys"
        )
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: oldRepo,
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeProgress(
            stateURL,
            completedSections: ["Step 1: Old Install", "Step 2: Old Keys"],
            waitingForUser: "topology_resolution",
            nextSection: "Step 3: Create the Brain"
        )
        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo", "--path", newRepo.path]
        )
        let progress = try progressObject(in: stateURL)
        let state = try stateObject(in: stateURL)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(progress["completedSections"] as? [String], [])
        XCTAssertEqual(progress["nextSection"] as? String, "Step 1: New Install")
        XCTAssertEqual(progress["launchDirectory"] as? String, newRepo.path)
        XCTAssertNil(progress["waitingForUser"])
        let sectionRoles = try XCTUnwrap(state["sectionRoles"] as? [String: Any])
        XCTAssertTrue(sectionRoles.isEmpty)
    }

    func testPrepareSourceRepoReusesValidRepoWithoutInstallMutation() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root, name: "existing-gbrain")
        let sentinel = sourceRepo.appendingPathComponent("sentinel.txt", isDirectory: false)
        try "keep\n".write(to: sentinel, atomically: true, encoding: .utf8)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let state = try stateObject(in: stateURL)
        let binding = try XCTUnwrap(state["activeGBrainBinding"] as? [String: Any])

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(binding["sourceRepoStatus"] as? String, "reused")
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceRepo.appendingPathComponent("node_modules").path))
    }

    func testPrepareSourceRepoRejectsOccupiedInvalidPathWithoutOverwrite() throws {
        let root = try makeTemporaryDirectory()
        let target = root.appendingPathComponent("not-gbrain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let sentinel = target.appendingPathComponent("sentinel.txt", isDirectory: false)
        try "do not overwrite\n".write(to: sentinel, atomically: true, encoding: .utf8)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo", "--path", target.path]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("gbrain_source_repo_occupied_invalid"), "stdout:\n\(result.stdout)")
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "do not overwrite\n")
        XCTAssertNil(try stateObject(in: stateURL)["activeGBrainBinding"])
    }

    func testPrepareSourceRepoWithoutPathFailsInsteadOfUsingDefaultWhenStdinIsNotTerminal() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo"]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("No terminal stdin is available"), "stderr:\n\(result.stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("gbrain").path))
        XCTAssertNil(try stateObject(in: stateURL)["activeGBrainBinding"])
    }

    func testPrepareSourceRepoWithoutPathShowsKoreanPromptUnavailableMessage() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["ko"],
            preferredLanguages: ["ko"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            languageCode: "ko",
            arguments: ["prepare-source-repo"]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("GBrain source repo path를 입력할 수 있는 terminal stdin이 없습니다."), "stderr:\n\(result.stderr)")
    }

    func testPrepareSourceRepoWithTerminalClonesRecommendedHomeRepo() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's terminal prompt")
        }

        let root = try makeTemporaryDirectory()
        let remote = try writeFakeGBrainRemoteRepo(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        let homeRepo = root.appendingPathComponent("gbrain", isDirectory: true)
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let result = try runHelperWithTerminal(
            stateURL: stateURL,
            homePath: root.path,
            environment: ["ZEBRA_GBRAIN_SOURCE_REMOTE": remote.path],
            reply: "\r"
        )
        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("activeGBrainBinding"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let state = try stateObject(in: stateURL)
        let binding = try XCTUnwrap(state["activeGBrainBinding"] as? [String: Any])

        XCTAssertEqual(binding["sourceRepoPath"] as? String, homeRepo.path)
        XCTAssertEqual(binding["sourceRepoStatus"] as? String, "cloned")
        XCTAssertTrue(FileManager.default.fileExists(atPath: homeRepo.appendingPathComponent("INSTALL_FOR_AGENTS.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: homeRepo.appendingPathComponent("node_modules").path))
    }

    func testPrepareSourceRepoWithTerminalReusesRecommendedHomeRepo() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's terminal prompt")
        }

        let root = try makeTemporaryDirectory()
        let homeRepo = try writeFakeGBrainSourceRepo(root: root, name: "gbrain")
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let result = try runHelperWithTerminal(
            stateURL: stateURL,
            homePath: root.path,
            reply: "\r"
        )
        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("activeGBrainBinding"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let state = try stateObject(in: stateURL)
        let binding = try XCTUnwrap(state["activeGBrainBinding"] as? [String: Any])

        XCTAssertEqual(binding["sourceRepoPath"] as? String, homeRepo.path)
        XCTAssertEqual(binding["sourceRepoStatus"] as? String, "reused")
        XCTAssertFalse(FileManager.default.fileExists(atPath: homeRepo.appendingPathComponent("node_modules").path))
    }

    func testPrepareSourceRepoWithTerminalRejectsInvalidCustomPathBeforeBinding() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's terminal prompt")
        }

        let root = try makeTemporaryDirectory()
        _ = try writeFakeGBrainSourceRepo(root: root, name: "gbrain")
        let invalidCustomPath = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidCustomPath, withIntermediateDirectories: true)
        try "not gbrain\n".write(
            to: invalidCustomPath.appendingPathComponent("README.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let result = try runHelperWithTerminalScript(
            stateURL: stateURL,
            homePath: root.path,
            extraEnvironment: ["INVALID_CUSTOM_PATH": invalidCustomPath.path],
            script: """
            set timeout 60
            spawn $env(HELPER_PATH) prepare-source-repo
            expect "Y/n"
            send "n\\r"
            expect "A different GBrain source repo path is required"
            expect "Custom GBrain source repo path"
            send "$env(INVALID_CUSTOM_PATH)\\r"
            expect "Choose:"
            send "q\\r"
            expect eof
            set wait_status [wait]
            exit [lindex $wait_status 3]
            """
        )

        XCTAssertNotEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("\(invalidCustomPath.path) is not a GBrain source repo."), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("[1] Clone into \(invalidCustomPath.path)/gbrain"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("[2] Retry this same path"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("[3] Choose another path"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertNil(try stateObject(in: stateURL)["activeGBrainBinding"])
        XCTAssertEqual(try progressObject(in: stateURL)["lastFailure"] as? String, "source_repo_prepare_aborted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidCustomPath.appendingPathComponent("gbrain").path))
    }

    func testPrepareSourceRepoWithTerminalRejectsRelativeCustomPathBeforeBinding() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's terminal prompt")
        }

        let root = try makeTemporaryDirectory()
        _ = try writeFakeGBrainSourceRepo(root: root, name: "gbrain")
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let result = try runHelperWithTerminalScript(
            stateURL: stateURL,
            homePath: root.path,
            script: """
            set timeout 60
            spawn $env(HELPER_PATH) prepare-source-repo
            expect "Y/n"
            send "n\\r"
            expect "A different GBrain source repo path is required"
            expect "Custom GBrain source repo path"
            send "Users/han/project\\r"
            expect "Custom path must start with / or ~"
            send "q\\r"
            expect eof
            set wait_status [wait]
            exit [lindex $wait_status 3]
            """
        )

        XCTAssertNotEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertNil(try stateObject(in: stateURL)["activeGBrainBinding"])
        XCTAssertEqual(try progressObject(in: stateURL)["lastFailure"] as? String, "source_repo_prepare_aborted")
    }

    func testPrepareSourceRepoWithTerminalAcceptsTildeCustomPath() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's terminal prompt")
        }

        let root = try makeTemporaryDirectory()
        _ = try writeFakeGBrainSourceRepo(root: root, name: "gbrain")
        let remote = try writeFakeGBrainRemoteRepo(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        let customRepo = root.appendingPathComponent("project-gbrain", isDirectory: true)
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let result = try runHelperWithTerminalScript(
            stateURL: stateURL,
            homePath: root.path,
            extraEnvironment: ["ZEBRA_GBRAIN_SOURCE_REMOTE": remote.path],
            script: """
            set timeout 60
            spawn $env(HELPER_PATH) prepare-source-repo
            expect "Y/n"
            send "n\\r"
            expect "A different GBrain source repo path is required"
            expect "Custom GBrain source repo path"
            send "~/project-gbrain\\r"
            expect eof
            set wait_status [wait]
            exit [lindex $wait_status 3]
            """
        )
        let state = try stateObject(in: stateURL)
        let binding = try XCTUnwrap(state["activeGBrainBinding"] as? [String: Any])

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(binding["sourceRepoPath"] as? String, customRepo.path)
        XCTAssertEqual(binding["sourceRepoStatus"] as? String, "cloned")
    }

    func testDynamicGBrainSetupCommandUsesSourceRepoShellCwd() {
        let line = MarkdownChatPillCommand.shellStartupLineForGBrainSetup(
            agent: .codex,
            cwdShellExpression: "\"$ZEBRA_GBRAIN_SOURCE_REPO\"",
            userPrompt: "setup",
            allowTrustedAutomation: true
        )

        XCTAssertTrue(line.contains("cd \"$ZEBRA_GBRAIN_SOURCE_REPO\" && codex"), line)
        XCTAssertTrue(line.contains("-C \"$ZEBRA_GBRAIN_SOURCE_REPO\""), line)
    }

    func testPrepareLaunchClearsStaleInitialTopologyGateFromPacketStatus() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
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
            gbrainDocsRepoURL: repo,
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
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

    func testPrepareLaunchDoesNotUsePrefetchedRemoteDocsSnapshotRecord() throws {
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

        XCTAssertTrue(packet.contains("pending. The launch wrapper prepares the local GBrain source repo"))
        XCTAssertFalse(packet.contains("path: \(snapshot.path)"))
        XCTAssertFalse(packet.contains("cached-ref"))
        XCTAssertFalse(state.contains("\"docsSnapshotPath\""))
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
            languageCode: "ko",
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
        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options.first?["path"] as? String, root.appendingPathComponent("brain", isDirectory: true).path)
        XCTAssertTrue((options.first?["description"] as? String)?.contains("새 brain repo를 만듭니다") == true)
        XCTAssertTrue((options[1]["description"] as? String)?.contains("기존 markdown/brain repo path를 사용합니다") == true)
        XCTAssertTrue((options[2]["description"] as? String)?.contains("custom path에 새 brain repo를 만듭니다") == true)
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
        languageCode: String? = nil,
        environment extraEnvironment: [String: String] = [:],
        arguments: [String]
    ) throws -> HelperRunResult {
        let helper = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-onboarding", isDirectory: false)
        let process = Process()
        process.executableURL = helper
        process.arguments = arguments
        var environment = [
            "PATH": "\(path):/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
            "ZEBRA_GBRAIN_STATE": stateURL.path,
            "ZEBRA_GBRAIN_HOME": stateURL.deletingLastPathComponent().path,
        ]
        if let languageCode {
            environment["ZEBRA_ONBOARDING_LANGUAGE"] = languageCode
        }
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment
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

    private func runExecutable(
        _ executable: URL,
        environment: [String: String],
        arguments: [String]
    ) throws -> HelperRunResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
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

    private func runHelperWithTerminal(
        stateURL: URL,
        homePath: String,
        languageCode: String? = nil,
        environment extraEnvironment: [String: String] = [:],
        reply: String
    ) throws -> HelperRunResult {
        let escapedReply = reply
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return try runHelperWithTerminalScript(
            stateURL: stateURL,
            homePath: homePath,
            languageCode: languageCode,
            extraEnvironment: extraEnvironment,
            script: """
            set timeout 60
            spawn $env(HELPER_PATH) prepare-source-repo
            expect {
                "Y/n" { send "\(escapedReply)" }
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect eof
            set wait_status [wait]
            exit [lindex $wait_status 3]
            """
        )
    }

    private func runHelperWithTerminalScript(
        stateURL: URL,
        homePath: String,
        languageCode: String? = nil,
        extraEnvironment: [String: String] = [:],
        script: String
    ) throws -> HelperRunResult {
        let helper = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-onboarding", isDirectory: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
        process.arguments = ["-c", script]
        var environment = [
            "HELPER_PATH": helper.path,
            "HOME": homePath,
            "PATH": "\(homePath):/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
            "ZEBRA_GBRAIN_STATE": stateURL.path,
            "ZEBRA_GBRAIN_HOME": stateURL.deletingLastPathComponent().path,
        ]
        if let languageCode {
            environment["ZEBRA_ONBOARDING_LANGUAGE"] = languageCode
        }
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment
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

    @discardableResult
    private func writeFakeGBrainSourceRepo(
        root: URL,
        name: String = "gbrain-source",
        installSectionTitle: String = "Step 1: Install GBrain",
        credentialsSectionTitle: String = "Step 2: API Keys"
    ) throws -> URL {
        let repo = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent("skills", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        # Install

        ## \(installSectionTitle)

        Run `bun install` from this source repo.

        ## \(credentialsSectionTitle)

        Configure credentials.
        """
        .write(to: repo.appendingPathComponent("INSTALL_FOR_AGENTS.md"), atomically: true, encoding: .utf8)
        try "# GBrain\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try #"{"name":"gbrain","bin":{"gbrain":"bin/gbrain"}}"#.write(
            to: repo.appendingPathComponent("package.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try #"{"skills":[]}"#.write(
            to: repo
                .appendingPathComponent("skills", isDirectory: true)
                .appendingPathComponent("manifest.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        return repo
    }

    private func writeFakeGBrainRemoteRepo(root: URL) throws -> URL {
        let repo = try writeFakeGBrainSourceRepo(root: root, name: "remote-gbrain")
        try runGit(["init"], cwd: repo)
        try runGit(["add", "."], cwd: repo)
        try runGit([
            "-c", "user.name=Zebra Test",
            "-c", "user.email=zebra-test@example.com",
            "commit",
            "-m", "Initial test gbrain repo",
        ], cwd: repo)
        return repo
    }

    private func writeFakeOpenClaw(root: URL, agentsJSON: String) throws -> (executable: URL, log: URL) {
        let bin = root.appendingPathComponent("fake-openclaw-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let executable = bin.appendingPathComponent("openclaw", isDirectory: false)
        let log = root.appendingPathComponent("openclaw.log", isDirectory: false)
        let agents = root.appendingPathComponent("openclaw-agents.json", isDirectory: false)
        try agentsJSON.write(to: agents, atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        set -eu
        printf '%s\\n' "$*" >> '\(log.path)'
        if [ "$1" = "agents" ] && [ "$2" = "list" ] && [ "$3" = "--json" ]; then
          cat '\(agents.path)'
          exit 0
        fi
        if [ "$1" = "agents" ] && [ "$2" = "add" ]; then
          exit 0
        fi
        echo "unexpected openclaw args: $*" >&2
        exit 64
        """
        .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executable.path
        )
        return (executable, log)
    }

    private func runGit(_ arguments: [String], cwd: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        let stderr = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(stderrText)")
            throw NSError(domain: "ZebraGBrainOnboardingStoreTests.git", code: Int(process.terminationStatus))
        }
    }

    private func installFakeGBrain(
        root: URL,
        sourceId: String,
        localPath: String,
        searchMode: String? = "balanced"
    ) throws -> URL {
        let bin = root.appendingPathComponent("fake-gbrain-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        try writeFakeGBrainScript(script, sourceId: sourceId, localPath: localPath, searchMode: searchMode, shebang: "#!/bin/sh")
        return bin
    }

    private func installFakeGBrainWithTransientSources(root: URL) throws -> URL {
        let bin = root.appendingPathComponent("fake-gbrain-bin", isDirectory: true)
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
        let bin = root.appendingPathComponent("fake-gbrain-bin", isDirectory: true)
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
        let bin = root.appendingPathComponent("fake-gbrain-bin", isDirectory: true)
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
