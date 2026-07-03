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

    func testCachedCompletionRequiresGlobalReadinessComplete() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: vault.path,
            sourceId: "main",
            method: "user_existing_repo",
            globalReadinessComplete: false
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let result = store.cachedCompletionResult(selectedVaultPath: nil)

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.reasons, ["receipt_incomplete"])
    }

    func testCachedCompletionRequiresResolvedTargetComplete() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: vault.path,
            sourceId: "main",
            method: "user_existing_repo",
            complete: false
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let result = store.cachedCompletionResult(selectedVaultPath: nil)

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.reasons, ["receipt_incomplete"])
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

    func testLiveVerifierAllowsCycleFreshnessOnlyAsMaintenancePending() throws {
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

        XCTAssertTrue(store.isSetupCompleted(selectedVaultPath: nil))
        let target = try receiptTarget(in: stateURL, targetPath: vault.path)
        XCTAssertEqual(target["complete"] as? Bool, true)
        XCTAssertEqual(target["status"] as? String, "verified_with_maintenance_pending")
        XCTAssertEqual(target["reasons"] as? [String], [])
        XCTAssertEqual(target["warnings"] as? [String], ["maintenance_pending:cycle_freshness"])
        let doctorStatus = try XCTUnwrap(target["doctorStatus"] as? [String: Any])
        XCTAssertEqual(doctorStatus["status"] as? String, "failed")
        XCTAssertEqual(doctorStatus["failedChecks"] as? [String], ["cycle_freshness"])
        let syncProbe = try XCTUnwrap(target["syncProbeResult"] as? [String: Any])
        XCTAssertEqual(syncProbe["status"] as? String, "ok")
        let embeddingProbe = try XCTUnwrap(target["embeddingProbeResult"] as? [String: Any])
        XCTAssertEqual(embeddingProbe["status"] as? String, "ok")
    }

    func testWaitingForUserDoesNotBlockReceiptBasedCompletion() throws {
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
            completedSections: [],
            waitingForUser: "topology_resolution"
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": bin.path]
        )

        let result = store.completionResult(selectedVaultPath: nil)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.reasons, [])
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

    func testLiveVerifierFailsRuntimeProbeEvenWithPreviousVerification() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "brain\n".write(to: vault.appendingPathComponent(".gbrain-source"), atomically: true, encoding: .utf8)
        let bin = try installFakeGBrainWithPGLiteWasmSourceProbeFailure(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: vault.path,
            sourceId: "brain",
            method: "user_created_repo",
            complete: false,
            sourceVerification: true
        )

        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["PATH": bin.path]
        )

        XCTAssertFalse(store.isSetupCompleted(selectedVaultPath: nil))
        let target = try receiptTarget(in: stateURL, targetPath: vault.path)
        XCTAssertEqual(target["complete"] as? Bool, false)
        XCTAssertEqual(target["status"] as? String, "failed")
        XCTAssertEqual(target["reasons"] as? [String], ["pglite_wasm_runtime_error"])
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

    func testReceiptCompleteActiveRunCompletesWithoutImportIndexReport() throws {
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
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.reasons, [])
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
        XCTAssertTrue(launch.startupPrompt.contains("current section prompt"))
        XCTAssertFalse(launch.startupPrompt.contains("Do not implicitly use the home directory"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("gbrain-setup-packets").path))
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
        XCTAssertTrue(launch.startupPrompt.contains("section prompt"), launch.startupPrompt)
    }

    func testPrepareLaunchUsesKoreanAppLanguagePolicyInBootstrap() throws {
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

        XCTAssertTrue(launch.startupPrompt.contains("Your first visible response must be a brief Korean sentence"))
        XCTAssertTrue(launch.startupPrompt.contains("Preserve `Zebra GBrain setup` and `section prompt` exactly."))
        XCTAssertFalse(launch.startupPrompt.contains("Zebra GBrain setup을 시작합니다"))
        XCTAssertTrue(launch.startupPrompt.unicodeScalars.allSatisfy { $0.isASCII })
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
        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root, name: "gbrain")
        let prepareResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        try writeProgress(
            stateURL,
            completedSections: ["Step 1: Install GBrain", "Step 2: API Keys"],
            waitingForUser: "brain_repo_target_resolution",
            nextSection: "Step 3: Create the Brain"
        )
        let launcherResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: [
                "write-runtime-launcher",
                "--runtime", "hermes",
                "--executable", "/tmp/hermes",
                "--run-id", launch.runId,
            ]
        )
        let progress = try progressObject(in: stateURL)
        let prompt = try launcherPrompt(from: launcherResult.stdout)
        let recommendedBrainPath = root.appendingPathComponent("brain", isDirectory: true).path

        XCTAssertEqual(launcherResult.exitCode, 0, "stdout:\n\(launcherResult.stdout)\nstderr:\n\(launcherResult.stderr)")
        XCTAssertTrue(launch.startupPrompt.contains("Zebra GBrain setup is starting"))
        XCTAssertTrue(prompt.contains("Ask only for the Step 3 brain repo target now"), prompt)
        XCTAssertTrue(prompt.contains("1. Create a new brain repo at \(recommendedBrainPath) (recommended)"), prompt)
        XCTAssertTrue(prompt.contains("2. Use an existing markdown/brain repo path that the user provides"), prompt)
        XCTAssertTrue(prompt.contains("3. Create a new brain repo at a custom path"), prompt)
        XCTAssertTrue(prompt.contains("Do not present Zebra's onboarding work directory"), prompt)
        XCTAssertTrue(prompt.contains("Do not silently choose `--no-embedding`"), prompt)
        XCTAssertTrue(prompt.contains("without asking for another yes/no confirmation"), prompt)
        XCTAssertFalse(prompt.contains("ask for yes/no confirmation before creating"), prompt)
        XCTAssertFalse(prompt.contains("Ask only for the Step 3 topology decision now"), prompt)
        XCTAssertEqual(waitingForUserReason(in: progress), "brain_repo_target_resolution")
        XCTAssertEqual(progress["nextSection"] as? String, "Step 3: Create the Brain")
    }

    func testStep3PromptIncludesNumberedBrainRepoTargetOptionsBeforeWaitingState() throws {
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
        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root, name: "gbrain")
        let prepareResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        try writeProgress(
            stateURL,
            completedSections: ["Step 1: Install GBrain", "Step 2: API Keys"],
            waitingForUser: nil,
            nextSection: "Step 3: Create the Brain"
        )
        let launcherResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: [
                "write-runtime-launcher",
                "--runtime", "hermes",
                "--executable", "/tmp/hermes",
                "--run-id", launch.runId,
            ]
        )
        let prompt = try launcherPrompt(from: launcherResult.stdout)
        let recommendedBrainPath = root.appendingPathComponent("brain", isDirectory: true).path

        XCTAssertEqual(launcherResult.exitCode, 0, "stdout:\n\(launcherResult.stdout)\nstderr:\n\(launcherResult.stderr)")
        XCTAssertTrue(prompt.contains("When asking for the brain repo target, present exactly this numbered prompt to the user:"), prompt)
        XCTAssertTrue(prompt.contains("Choose the brain repo target using one of these numbered options."), prompt)
        XCTAssertTrue(prompt.contains("1. Create a new brain repo at \(recommendedBrainPath) (recommended)"), prompt)
        XCTAssertTrue(prompt.contains("2. Use an existing markdown/brain repo path that the user provides"), prompt)
        XCTAssertTrue(prompt.contains("3. Create a new brain repo at a custom path"), prompt)
        XCTAssertTrue(prompt.contains("Interpret user choice 1 as the recommended path with targetResolution.method=user_created_repo."), prompt)
        XCTAssertTrue(prompt.contains("Interpret user choice 2 as an existing repo path with targetResolution.method=user_existing_repo"), prompt)
        XCTAssertTrue(prompt.contains("Interpret user choice 3 as a new custom repo path with targetResolution.method=user_created_repo"), prompt)
        XCTAssertTrue(prompt.contains("Do not ask only as an open-ended path question"), prompt)
    }

    func testSectionSnapshotsReflectManifestProgressAndCurrentSection() throws {
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
            completedSections: ["Step 1: Install GBrain"],
            waitingForUser: nil,
            nextSection: "Step 2: API Keys"
        )

        let snapshots = store.sectionSnapshotsFromCachedState(
            isParentRunning: false,
            showsStartForActiveSection: true,
            wasStartedBefore: true
        )
        let prepare = try XCTUnwrap(snapshots.first { $0.title == "Check and clone GBrain repo" })
        let install = try XCTUnwrap(snapshots.first { $0.title == "Step 1: Install GBrain" })
        let credentials = try XCTUnwrap(snapshots.first { $0.title == "Step 2: API Keys" })
        let future = try XCTUnwrap(snapshots.first { $0.title == "Step 4: Import and Index" })

        XCTAssertEqual(snapshots.first?.title, "Check and clone GBrain repo")
        XCTAssertTrue(prepare.isCompleted)
        XCTAssertFalse(prepare.isActive)
        XCTAssertTrue(install.isCompleted)
        XCTAssertFalse(install.isActive)
        XCTAssertTrue(credentials.isActive)
        XCTAssertTrue(credentials.showsStart)
        XCTAssertTrue(credentials.wasStartedBefore)
        XCTAssertFalse(future.isCompleted)
        XCTAssertFalse(future.isActive)
        XCTAssertFalse(future.showsStart)
    }

    func testSectionSnapshotsUseWaitingSectionAsCurrentSection() throws {
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
            waitingForUser: nil,
            nextSection: "Step 4: Import and Index"
        )
        try writeStructuredWaitingForUser(
            stateURL,
            section: "Step 3: Create the Brain",
            reason: "brain_repo_target_resolution"
        )

        let snapshots = store.sectionSnapshotsFromCachedState(
            isParentRunning: true,
            showsStartForActiveSection: false,
            wasStartedBefore: false
        )
        let prepare = try XCTUnwrap(snapshots.first { $0.title == "Check and clone GBrain repo" })
        let waiting = try XCTUnwrap(snapshots.first { $0.title == "Step 3: Create the Brain" })
        let next = try XCTUnwrap(snapshots.first { $0.title == "Step 4: Import and Index" })

        XCTAssertTrue(prepare.isCompleted)
        XCTAssertFalse(prepare.isActive)
        XCTAssertTrue(waiting.isActive)
        XCTAssertTrue(waiting.isWaitingForUser)
        XCTAssertTrue(waiting.isRunning)
        XCTAssertFalse(waiting.showsStart)
        XCTAssertFalse(next.isActive)
        XCTAssertFalse(next.isRunning)
    }

    func testSectionSnapshotsAreEmptyWithoutDocsManifest() throws {
        let root = try makeTemporaryDirectory()
        let store = ZebraGBrainOnboardingStore(
            stateURL: root.appendingPathComponent("state.json"),
            homeDirectoryPath: root.path
        )

        XCTAssertEqual(
            store.sectionSnapshotsFromCachedState(
                isParentRunning: false,
                showsStartForActiveSection: true,
                wasStartedBefore: false
            ),
            []
        )
    }

    func testSectionSnapshotsAreEmptyBeforeDocsManifest() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let snapshots = store.sectionSnapshotsFromCachedState(
            isParentRunning: true,
            showsStartForActiveSection: false,
            wasStartedBefore: true
        )

        XCTAssertEqual(snapshots, [])
    }

    func testSectionSnapshotsUseRecommendedSourceDocsBeforeManifest() throws {
        let root = try makeTemporaryDirectory()
        _ = try writeFakeGBrainSourceRepo(root: root, name: "gbrain")
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let snapshots = store.sectionSnapshotsFromCachedState(
            isParentRunning: true,
            showsStartForActiveSection: false,
            wasStartedBefore: true
        )
        let prepare = try XCTUnwrap(snapshots.first { $0.title == "Check and clone GBrain repo" })
        let install = try XCTUnwrap(snapshots.first { $0.title == "Step 1: Install GBrain" })

        XCTAssertEqual(snapshots.map(\.title), [
            "Check and clone GBrain repo",
            "Step 1: Install GBrain",
            "Step 2: API Keys",
        ])
        XCTAssertFalse(prepare.isCompleted)
        XCTAssertTrue(prepare.isActive)
        XCTAssertTrue(prepare.isRunning)
        XCTAssertFalse(prepare.showsStart)
        XCTAssertFalse(install.isCompleted)
        XCTAssertFalse(install.isActive)
        XCTAssertFalse(install.isRunning)
        XCTAssertFalse(install.showsStart)
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

    func testPrepareSourceRepoManifestKeepsOnlyNumberedSetupSections() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = root.appendingPathComponent("gbrain-source", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceRepo.appendingPathComponent("skills", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        # Install

        ## Step 0: If you are not Claude Code

        Read agent protocol.

        ## Step 1: Install GBrain

        Install.

        ## Step 3.5: Confirm search mode with the user (DO NOT SKIP)

        Choose search mode.

        ## Step 6: Identity (optional)

        Run the soul-audit skill or accept minimal defaults.

        ## Step 9: Verify

        Verify.

        ## Upgrade

        Upgrade existing installs.

        ## v0.42.0+ onboard surface (NEW)

        Run health checks after install.
        """
        .write(to: sourceRepo.appendingPathComponent("INSTALL_FOR_AGENTS.md"), atomically: true, encoding: .utf8)
        try "# GBrain\n".write(to: sourceRepo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try #"{"name":"gbrain","bin":{"gbrain":"bin/gbrain"}}"#.write(
            to: sourceRepo.appendingPathComponent("package.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try #"{"skills":[]}"#.write(
            to: sourceRepo
                .appendingPathComponent("skills", isDirectory: true)
                .appendingPathComponent("manifest.json", isDirectory: false),
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
        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let state = try stateObject(in: stateURL)
        let manifest = try XCTUnwrap(state["docsManifest"] as? [String: Any])
        let sections = try XCTUnwrap(manifest["installForAgentsSections"] as? [[String: Any]])
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(sections.compactMap { $0["title"] as? String }, [
            "Step 1: Install GBrain",
            "Step 3.5: Confirm search mode with the user (DO NOT SKIP)",
            "Step 6: Identity (optional)",
            "Step 9: Verify",
        ])
        XCTAssertEqual(progress["nextSection"] as? String, "Step 1: Install GBrain")
    }

    func testRuntimeLauncherPromptUsesPreparedRecommendedHomeRepoAndRequiresGlobalLocalInstall() throws {
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
        let launcherResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: [
                "write-runtime-launcher",
                "--runtime", "hermes",
                "--executable", "/tmp/hermes",
                "--run-id", launch.runId,
            ]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(launcherResult.exitCode, 0, "stdout:\n\(launcherResult.stdout)\nstderr:\n\(launcherResult.stderr)")
        let prompt = try launcherPrompt(from: launcherResult.stdout)
        XCTAssertTrue(prompt.contains("Zebra GBrain setup: current section is `Step 1: Install GBrain`."), prompt)
        XCTAssertTrue(prompt.contains("INSTALL_FOR_AGENTS.md section body:"), prompt)
        XCTAssertTrue(prompt.contains("Zebra section boundary rules:"), prompt)
        XCTAssertTrue(prompt.contains("Active GBrain source repo: \(sourceRepo.path)."), prompt)
        XCTAssertTrue(prompt.contains("Zebra's recommended `~/gbrain` path"), prompt)
        XCTAssertTrue(prompt.contains("`bun install`, then `bun install -g .`"), prompt)
        XCTAssertFalse(prompt.contains("github:garrytan/gbrain"), prompt)
    }

    func testRuntimeLauncherPromptUsesBunLinkForCustomSourceRepo() throws {
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
        let launcherResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: [
                "write-runtime-launcher",
                "--runtime", "hermes",
                "--executable", "/tmp/hermes",
                "--run-id", launch.runId,
            ]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(launcherResult.exitCode, 0, "stdout:\n\(launcherResult.stdout)\nstderr:\n\(launcherResult.stderr)")
        let prompt = try launcherPrompt(from: launcherResult.stdout)
        XCTAssertTrue(prompt.contains("Active GBrain source repo: \(sourceRepo.path)."), prompt)
        XCTAssertTrue(prompt.contains("not Zebra's recommended `~/gbrain` path"), prompt)
        XCTAssertTrue(prompt.contains("`bun install`, then `bun link`"), prompt)
        XCTAssertTrue(prompt.contains("user-visible `gbrain` command"), prompt)
        XCTAssertFalse(prompt.contains("`bun install`, then `bun install -g .`"), prompt)
    }

    func testRuntimeLauncherPromptUsesCurrentSectionBodyForEmbeddingKeyStorage() throws {
        let root = try makeTemporaryDirectory()
        let docs = try writeGuardDocs(root: root)
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root, name: "gbrain")
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: root.appendingPathComponent("brain").path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: docs,
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )
        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let prepareResult = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let step1Report = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        let launcherResult = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "write-runtime-launcher",
                "--runtime", "hermes",
                "--executable", "/tmp/hermes",
                "--run-id", launch.runId,
            ]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(step1Report.exitCode, 0, "stdout:\n\(step1Report.stdout)\nstderr:\n\(step1Report.stderr)")
        XCTAssertEqual(launcherResult.exitCode, 0, "stdout:\n\(launcherResult.stdout)\nstderr:\n\(launcherResult.stderr)")

        let prompt = try launcherPrompt(from: launcherResult.stdout)
        XCTAssertTrue(prompt.contains("Zebra GBrain setup: current section is `Step 2: API Keys`."), prompt)
        XCTAssertTrue(prompt.contains("Show this exact key prompt next, before reporting the section:"), prompt)
        XCTAssertTrue(prompt.contains("Enter ZEROENTROPY_API_KEY."), prompt)
        XCTAssertTrue(prompt.contains("After the user provides the key, configure it using the saving instructions already present in this prompt's `INSTALL_FOR_AGENTS.md section body`."), prompt)
        XCTAssertTrue(prompt.contains("Do not reread files or open separate docs for those instructions."), prompt)
        XCTAssertTrue(prompt.contains("Then report this section with `--embedding-decision provider_key --embedding-provider zeroentropy --embedding-key-env ZEROENTROPY_API_KEY`."), prompt)
        XCTAssertTrue(prompt.contains("Never write API key values to Zebra state, progress, report flags, logs, or summaries."), prompt)
        XCTAssertTrue(prompt.contains("Zebra state records only provider metadata."), prompt)
        XCTAssertFalse(prompt.contains("configure-embedding-key"), prompt)
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
        let launcherResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            languageCode: "ko",
            arguments: [
                "write-runtime-launcher",
                "--runtime", "openclaw",
                "--executable", "/tmp/openclaw",
                "--run-id", launch.runId,
                "--agent-id", "zebra-gbrain-setup-test",
                "--session", "agent:zebra-gbrain-setup-test:\(launch.runId)",
            ]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
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
        let promptPath = try bootstrapPromptPath(from: script)
        let prompt = try String(contentsOfFile: promptPath, encoding: .utf8)
        let syntaxCheck = try runExecutable(
            URL(fileURLWithPath: "/bin/sh"),
            environment: [:],
            arguments: ["-n", launcherPath]
        )

        XCTAssertTrue(script.contains("zebra-gbrain-onboarding prepare-openclaw-agent --executable '/tmp/openclaw' --agent-id 'zebra-gbrain-setup-test'"), script)
        XCTAssertTrue(script.contains("cd \"$ZEBRA_GBRAIN_SOURCE_REPO\""), script)
        XCTAssertTrue(script.contains("ZEBRA_GBRAIN_BOOTSTRAP_PROMPT_PATH='\(promptPath)'"), script)
        XCTAssertTrue(script.contains("ZEBRA_GBRAIN_BOOTSTRAP_PROMPT=$(cat \"$ZEBRA_GBRAIN_BOOTSTRAP_PROMPT_PATH\")"), script)
        XCTAssertTrue(script.contains("exec '/tmp/openclaw' tui --local --session 'agent:zebra-gbrain-setup-test:\(launch.runId)' --message \"$ZEBRA_GBRAIN_BOOTSTRAP_PROMPT\""), script)
        XCTAssertFalse(script.contains("Zebra GBrain setup"), script)
        XCTAssertTrue(prompt.contains("Zebra GBrain setup"), prompt)
        XCTAssertTrue(prompt.contains("current section prompt"), prompt)
        XCTAssertTrue(prompt.contains("Use Zebra's app language (Korean) for user-facing prose."), prompt)
        XCTAssertTrue(prompt.contains("INSTALL_FOR_AGENTS.md section body:"), prompt)
        XCTAssertTrue(prompt.contains("Zebra section boundary rules:"), prompt)
        XCTAssertEqual(syntaxCheck.exitCode, 0, "stdout:\n\(syntaxCheck.stdout)\nstderr:\n\(syntaxCheck.stderr)\nscript:\n\(script)")
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
        let launcherResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            languageCode: "ko",
            arguments: [
                "write-runtime-launcher",
                "--runtime", "hermes",
                "--executable", "/tmp/hermes",
                "--run-id", launch.runId,
            ]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
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
        let promptPath = try bootstrapPromptPath(from: script)
        let prompt = try String(contentsOfFile: promptPath, encoding: .utf8)
        let syntaxCheck = try runExecutable(
            URL(fileURLWithPath: "/bin/sh"),
            environment: [:],
            arguments: ["-n", launcherPath]
        )

        XCTAssertTrue(script.contains("cd \"$ZEBRA_GBRAIN_SOURCE_REPO\""), script)
        XCTAssertTrue(script.contains("ZEBRA_GBRAIN_BOOTSTRAP_PROMPT_PATH='\(promptPath)'"), script)
        XCTAssertTrue(script.contains("ZEBRA_GBRAIN_BOOTSTRAP_PROMPT=$(cat \"$ZEBRA_GBRAIN_BOOTSTRAP_PROMPT_PATH\")"), script)
        XCTAssertTrue(script.contains("exec '/tmp/hermes' chat --tui --source zebra-gbrain-onboarding --query \"$ZEBRA_GBRAIN_BOOTSTRAP_PROMPT\""), script)
        XCTAssertFalse(script.contains("Zebra GBrain setup"), script)
        XCTAssertTrue(prompt.contains("Zebra GBrain setup"), prompt)
        XCTAssertTrue(prompt.contains("current section prompt"), prompt)
        XCTAssertTrue(prompt.contains("Use Zebra's app language (Korean) for user-facing prose."), prompt)
        XCTAssertTrue(prompt.contains("INSTALL_FOR_AGENTS.md section body:"), prompt)
        XCTAssertTrue(prompt.contains("Zebra section boundary rules:"), prompt)
        XCTAssertEqual(syntaxCheck.exitCode, 0, "stdout:\n\(syntaxCheck.stdout)\nstderr:\n\(syntaxCheck.stderr)\nscript:\n\(script)")
    }

    func testHelperInstallDoesNotCreateGBrainWrapper() throws {
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
        let helperBin = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: helperBin.appendingPathComponent("zebra-gbrain-onboarding").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: helperBin.appendingPathComponent("launchctl").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: helperBin.appendingPathComponent("gbrain").path))
    }

    func testRunGBrainPrefersSourceRepoNodeModulesBinary() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root)
        let nodeBin = sourceRepo.appendingPathComponent("node_modules/.bin", isDirectory: true)
        let localBin = sourceRepo.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
        try """
        #!/bin/sh
        echo "node $*"
        """
        .write(to: nodeBin.appendingPathComponent("gbrain", isDirectory: false), atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        echo "bin $*"
        """
        .write(to: localBin.appendingPathComponent("gbrain", isDirectory: false), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nodeBin.appendingPathComponent("gbrain").path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: localBin.appendingPathComponent("gbrain").path)
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
            path: "",
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let versionResult = try runHelper(
            stateURL: stateURL,
            path: "",
            arguments: ["run-gbrain", "--", "--version"]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(versionResult.exitCode, 0, "stdout:\n\(versionResult.stdout)\nstderr:\n\(versionResult.stderr)")
        XCTAssertEqual(versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "node --version")
    }

    func testRunGBrainUsesSourceRepoBinWhenNodeModulesBinaryIsMissing() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root)
        let localBin = sourceRepo.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
        try """
        #!/bin/sh
        echo "bin $*"
        """
        .write(to: localBin.appendingPathComponent("gbrain", isDirectory: false), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: localBin.appendingPathComponent("gbrain").path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try runHelper(
            stateURL: stateURL,
            path: "",
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let versionResult = try runHelper(
            stateURL: stateURL,
            path: "",
            arguments: ["run-gbrain", "--", "--version"]
        )

        XCTAssertEqual(versionResult.exitCode, 0, "stdout:\n\(versionResult.stdout)\nstderr:\n\(versionResult.stderr)")
        XCTAssertEqual(versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "bin --version")
    }

    func testRunGBrainRunsSourceRepoCliTsWhenNoBuiltBinaryExists() throws {
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
        let versionResult = try runHelper(
            stateURL: stateURL,
            path: fakeBunBin.path,
            arguments: ["run-gbrain", "--", "--version"]
        )

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(versionResult.exitCode, 0, "stdout:\n\(versionResult.stdout)\nstderr:\n\(versionResult.stderr)")
        XCTAssertEqual(versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "gbrain source cli")
    }

    func testRunGBrainDoesNotFallbackToArbitraryPathGBrain() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root)
        let pathBin = root.appendingPathComponent("path-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: pathBin, withIntermediateDirectories: true)
        try """
        #!/bin/sh
        echo "path $*"
        """
        .write(to: pathBin.appendingPathComponent("gbrain", isDirectory: false), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pathBin.appendingPathComponent("gbrain").path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )

        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try runHelper(
            stateURL: stateURL,
            path: pathBin.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        let versionResult = try runHelper(
            stateURL: stateURL,
            path: pathBin.path,
            arguments: ["run-gbrain", "--", "--version"]
        )

        XCTAssertEqual(versionResult.exitCode, 127, "stdout:\n\(versionResult.stdout)\nstderr:\n\(versionResult.stderr)")
        XCTAssertTrue(versionResult.stderr.contains("active GBrain source CLI is unavailable"), versionResult.stderr)
        XCTAssertFalse(versionResult.stdout.contains("path --version"), versionResult.stdout)
    }

    func testRunGBrainBlocksAutopilotInstallUntilRecurringJobsDecision() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root)
        try FileManager.default.createDirectory(
            at: sourceRepo.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        let log = root.appendingPathComponent("run-gbrain-autopilot.log")
        try """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(log.path)'
        exit 0
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
        let blocked = try runHelper(
            stateURL: stateURL,
            path: fakeBunBin.path,
            arguments: ["run-gbrain", "--", "autopilot", "--install", "--repo", root.appendingPathComponent("brain").path]
        )
        let approval = try runHelper(
            stateURL: stateURL,
            path: fakeBunBin.path,
            arguments: [
                "report",
                "--status", "started",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "autopilot_install",
            ]
        )
        let allowed = try runHelper(
            stateURL: stateURL,
            path: fakeBunBin.path,
            arguments: ["run-gbrain", "--", "autopilot", "--install", "--repo", root.appendingPathComponent("brain").path]
        )
        let forwardedArgs = try String(contentsOf: log, encoding: .utf8)

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(blocked.exitCode, 78, "stdout:\n\(blocked.stdout)\nstderr:\n\(blocked.stderr)")
        XCTAssertTrue(blocked.stderr.contains("recurring_jobs_decision=autopilot_install"), blocked.stderr)
        XCTAssertEqual(approval.exitCode, 0, "stdout:\n\(approval.stdout)\nstderr:\n\(approval.stderr)")
        XCTAssertEqual(allowed.exitCode, 0, "stdout:\n\(allowed.stdout)\nstderr:\n\(allowed.stderr)")
        XCTAssertTrue(forwardedArgs.contains("autopilot --install --repo"), forwardedArgs)
    }

    func testLaunchctlWrapperBlocksPersistentStartUntilRecurringJobsDecision() throws {
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
        let launchctlWrapper = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("launchctl", isDirectory: false)
        let fakeBin = root.appendingPathComponent("fake-launchctl-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        let fakeLaunchctl = fakeBin.appendingPathComponent("launchctl", isDirectory: false)
        let log = root.appendingPathComponent("launchctl-wrapper.log")
        try """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(log.path)'
        exit 0
        """
        .write(to: fakeLaunchctl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeLaunchctl.path)
        let environment = [
            "PATH": "\(fakeBin.path):/usr/bin:/bin",
            "ZEBRA_GBRAIN_STATE": stateURL.path,
        ]
        let plist = root.appendingPathComponent("com.gbrain.autopilot.plist")

        let blocked = try runExecutable(
            launchctlWrapper,
            environment: environment,
            arguments: ["load", plist.path]
        )
        let approval = try runHelper(
            stateURL: stateURL,
            path: fakeBin.path,
            arguments: [
                "report",
                "--status", "started",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "platform_scheduler_install",
            ]
        )
        let allowed = try runExecutable(
            launchctlWrapper,
            environment: environment,
            arguments: ["load", plist.path]
        )
        let forwardedArgs = try String(contentsOf: log, encoding: .utf8)

        XCTAssertNotEqual(blocked.exitCode, 0, "stdout:\n\(blocked.stdout)\nstderr:\n\(blocked.stderr)")
        XCTAssertTrue(blocked.stderr.contains("recurring_jobs_decision=platform_scheduler_install"), blocked.stderr)
        XCTAssertEqual(approval.exitCode, 0, "stdout:\n\(approval.stdout)\nstderr:\n\(approval.stderr)")
        XCTAssertEqual(allowed.exitCode, 0, "stdout:\n\(allowed.stdout)\nstderr:\n\(allowed.stderr)")
        XCTAssertTrue(forwardedArgs.contains("load \(plist.path)"), forwardedArgs)
    }

    func testPreparePlatformSchedulerBlocksUntilPlatformSchedulerDecision() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let fake = try writeFakePlatformRuntime(root: root, runtime: "openclaw")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"]
        )
        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeRuntimeReceipt(stateURL: stateURL, runtime: "openclaw", executable: fake.executable)

        let result = try runHelper(
            stateURL: stateURL,
            path: fake.bin.path,
            arguments: ["prepare-platform-scheduler"]
        )

        XCTAssertEqual(result.exitCode, 78, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stderr.contains("recurring_jobs_decision=platform_scheduler_install"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fake.log.path))
    }

    func testPreparePlatformSchedulerInstallsAndStartsOpenClawGatewayAfterDecision() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let fake = try writeFakePlatformRuntime(root: root, runtime: "openclaw")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"]
        )
        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeRuntimeReceipt(stateURL: stateURL, runtime: "openclaw", executable: fake.executable)
        _ = try recordRecurringJobsDecision(stateURL: stateURL, path: fake.bin.path, decision: "platform_scheduler_install")

        let result = try runHelper(
            stateURL: stateURL,
            path: fake.bin.path,
            arguments: ["prepare-platform-scheduler"]
        )
        let payload = try helperPayload(result.stdout)
        let state = try stateObject(in: stateURL)
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let platformScheduler = try XCTUnwrap(progress["platformScheduler"] as? [String: Any])
        let log = try String(contentsOf: fake.log, encoding: .utf8)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["runtime"] as? String, "openclaw")
        XCTAssertEqual(platformScheduler["ready"] as? Bool, true)
        XCTAssertEqual(platformScheduler["alreadyRunning"] as? Bool, false)
        XCTAssertTrue(log.contains("openclaw gateway status --json --require-rpc --timeout 5000"), log)
        XCTAssertTrue(log.contains("openclaw gateway install --json"), log)
        XCTAssertTrue(log.contains("openclaw gateway start"), log)
    }

    func testPreparePlatformSchedulerInstallsAndStartsHermesGatewayAfterDecision() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let fake = try writeFakePlatformRuntime(root: root, runtime: "hermes")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"]
        )
        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeRuntimeReceipt(stateURL: stateURL, runtime: "hermes", executable: fake.executable)
        _ = try recordRecurringJobsDecision(stateURL: stateURL, path: fake.bin.path, decision: "platform_scheduler_install")

        let result = try runHelper(
            stateURL: stateURL,
            path: fake.bin.path,
            arguments: ["prepare-platform-scheduler"]
        )
        let payload = try helperPayload(result.stdout)
        let state = try stateObject(in: stateURL)
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let platformScheduler = try XCTUnwrap(progress["platformScheduler"] as? [String: Any])
        let log = try String(contentsOf: fake.log, encoding: .utf8)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["runtime"] as? String, "hermes")
        XCTAssertEqual(platformScheduler["ready"] as? Bool, true)
        XCTAssertEqual(platformScheduler["alreadyRunning"] as? Bool, false)
        XCTAssertTrue(log.contains("hermes-python -c"), log)
        XCTAssertTrue(log.contains("hermes gateway install"), log)
        XCTAssertTrue(log.contains("hermes gateway start"), log)
    }

    func testPreparePlatformSchedulerFindsHermesVenvPythonForShimExecutable() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let fake = try writeFakePlatformRuntime(root: root, runtime: "hermes")
        let shimBin = root.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: shimBin, withIntermediateDirectories: true)
        let shim = shimBin.appendingPathComponent("hermes", isDirectory: false)
        try String(contentsOf: fake.executable, encoding: .utf8).write(to: shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        let venvBin = root.appendingPathComponent(".hermes/hermes-agent/venv/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: venvBin, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: fake.bin.appendingPathComponent("python", isDirectory: false),
            to: venvBin.appendingPathComponent("python", isDirectory: false)
        )
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"]
        )
        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeRuntimeReceipt(stateURL: stateURL, runtime: "hermes", executable: shim)
        _ = try recordRecurringJobsDecision(stateURL: stateURL, path: shimBin.path, decision: "platform_scheduler_install")

        let result = try runHelper(
            stateURL: stateURL,
            path: shimBin.path,
            arguments: ["prepare-platform-scheduler"]
        )
        let state = try stateObject(in: stateURL)
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let platformScheduler = try XCTUnwrap(progress["platformScheduler"] as? [String: Any])
        let log = try String(contentsOf: fake.log, encoding: .utf8)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(platformScheduler["ready"] as? Bool, true)
        XCTAssertTrue(log.contains("hermes-python -c"), log)
        XCTAssertTrue(log.contains("hermes gateway install"), log)
        XCTAssertTrue(log.contains("hermes gateway start"), log)
    }

    func testRecurringJobsReportRejectsPlatformSchedulerInstallWhenSchedulerNotReady() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let fake = try writeFakePlatformRuntime(root: root, runtime: "hermes")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"]
        )
        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeRuntimeReceipt(stateURL: stateURL, runtime: "hermes", executable: fake.executable)
        _ = try recordRecurringJobsDecision(stateURL: stateURL, path: fake.bin.path, decision: "platform_scheduler_install")

        let result = try runHelper(
            stateURL: stateURL,
            path: fake.bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "platform_scheduler_install",
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("platform_scheduler_prepare_required"), result.stdout)
    }

    func testPreparePlatformSchedulerSkipsInstallWhenGatewayAlreadyRunning() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let fake = try writeFakePlatformRuntime(root: root, runtime: "openclaw", initialStatus: "running")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"]
        )
        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeRuntimeReceipt(stateURL: stateURL, runtime: "openclaw", executable: fake.executable)
        _ = try recordRecurringJobsDecision(stateURL: stateURL, path: fake.bin.path, decision: "platform_scheduler_install")

        let result = try runHelper(
            stateURL: stateURL,
            path: fake.bin.path,
            arguments: ["prepare-platform-scheduler"]
        )
        let state = try stateObject(in: stateURL)
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let platformScheduler = try XCTUnwrap(progress["platformScheduler"] as? [String: Any])
        let log = try String(contentsOf: fake.log, encoding: .utf8)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(platformScheduler["alreadyRunning"] as? Bool, true)
        XCTAssertFalse(log.contains("gateway install"), log)
        XCTAssertFalse(log.contains("gateway start"), log)
    }

    func testPreparePlatformSchedulerRecordsFailureWhenGatewayDoesNotBecomeReady() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let fake = try writeFakePlatformRuntime(root: root, runtime: "openclaw", initialStatus: "always-fail")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"]
        )
        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeRuntimeReceipt(stateURL: stateURL, runtime: "openclaw", executable: fake.executable)
        _ = try recordRecurringJobsDecision(stateURL: stateURL, path: fake.bin.path, decision: "platform_scheduler_install")

        let result = try runHelper(
            stateURL: stateURL,
            path: fake.bin.path,
            arguments: ["prepare-platform-scheduler"]
        )
        let state = try stateObject(in: stateURL)
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let platformScheduler = try XCTUnwrap(progress["platformScheduler"] as? [String: Any])
        let log = try String(contentsOf: fake.log, encoding: .utf8)

        XCTAssertNotEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(progress["lastFailure"] as? String, "platform_scheduler_prepare_failed")
        XCTAssertEqual(platformScheduler["ready"] as? Bool, false)
        XCTAssertTrue(result.stdout.contains("statusAfter"), result.stdout)
        XCTAssertTrue(log.contains("openclaw gateway install --json"), log)
        XCTAssertTrue(log.contains("openclaw gateway start"), log)
    }

    func testRecurringJobsPlatformInstallCompletionVerifiesAgentRunnableLiveSyncSetupBeforeReport() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let fakeRuntime = try writeFakePlatformRuntime(
            root: root,
            runtime: "openclaw",
            liveSyncTargetPath: target.path
        )
        let fakeGBrain = try installFakeGBrainForStep7SaveReadiness(
            root: root,
            sourceId: "brain",
            localPath: target.path
        )
        let path = "\(fakeRuntime.bin.path):\(fakeGBrain.bin.path)"
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"]
        )
        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeState(
            stateURL,
            targetPath: target.path,
            sourceId: "brain",
            method: "user_created_repo",
            sourceVerification: true
        )
        try writeRuntimeReceipt(stateURL: stateURL, runtime: "openclaw", executable: fakeRuntime.executable)
        _ = try recordRecurringJobsDecision(stateURL: stateURL, path: path, decision: "platform_scheduler_install")
        let prepare = try runHelper(stateURL: stateURL, path: path, arguments: ["prepare-platform-scheduler"])

        let report = try runHelper(
            stateURL: stateURL,
            path: path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "platform_scheduler_install",
            ]
        )
        let state = try stateObject(in: stateURL)
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let completedSections = try XCTUnwrap(progress["completedSections"] as? [String])
        let gbrainLog = try String(contentsOf: fakeGBrain.log, encoding: .utf8)
        let runtimeLog = try String(contentsOf: fakeRuntime.log, encoding: .utf8)

        XCTAssertEqual(prepare.exitCode, 0, "stdout:\n\(prepare.stdout)\nstderr:\n\(prepare.stderr)")
        XCTAssertEqual(report.exitCode, 0, "stdout:\n\(report.stdout)\nstderr:\n\(report.stderr)")
        XCTAssertTrue(completedSections.contains("Step 7: Recurring Jobs"))
        XCTAssertTrue(runtimeLog.contains("openclaw cron list --json"), runtimeLog)
        XCTAssertTrue(gbrainLog.contains("gbrain sources current --json"), gbrainLog)
        XCTAssertTrue(gbrainLog.contains("gbrain sources list --json"), gbrainLog)
        XCTAssertFalse(gbrainLog.contains("gbrain sync --repo \(target.path) --yes"), gbrainLog)
        XCTAssertFalse(gbrainLog.contains("gbrain embed --stale"), gbrainLog)
        XCTAssertFalse(gbrainLog.contains("gbrain status --json"), gbrainLog)
    }

    func testRecurringJobsPlatformInstallCompletionDoesNotRequireSaveTimestamp() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root.appendingPathComponent("state.json")
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let fakeRuntime = try writeFakePlatformRuntime(
            root: root,
            runtime: "openclaw",
            liveSyncTargetPath: target.path
        )
        let fakeGBrain = try installFakeGBrainForStep7SaveReadiness(
            root: root,
            sourceId: "brain",
            localPath: target.path,
            statusTimestampAfterSync: false
        )
        let path = "\(fakeRuntime.bin.path):\(fakeGBrain.bin.path)"
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"]
        )
        XCTAssertNotNil(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeState(
            stateURL,
            targetPath: target.path,
            sourceId: "brain",
            method: "user_created_repo",
            sourceVerification: true
        )
        try writeRuntimeReceipt(stateURL: stateURL, runtime: "openclaw", executable: fakeRuntime.executable)
        _ = try recordRecurringJobsDecision(stateURL: stateURL, path: path, decision: "platform_scheduler_install")
        _ = try runHelper(stateURL: stateURL, path: path, arguments: ["prepare-platform-scheduler"])

        let report = try runHelper(
            stateURL: stateURL,
            path: path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "platform_scheduler_install",
            ]
        )
        let state = try stateObject(in: stateURL)
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let completedSections = try XCTUnwrap(progress["completedSections"] as? [String])
        let gbrainLog = try String(contentsOf: fakeGBrain.log, encoding: .utf8)

        XCTAssertEqual(report.exitCode, 0, "stdout:\n\(report.stdout)\nstderr:\n\(report.stderr)")
        XCTAssertTrue(completedSections.contains("Step 7: Recurring Jobs"))
        XCTAssertFalse(gbrainLog.contains("gbrain sync --repo \(target.path) --yes"), gbrainLog)
        XCTAssertFalse(gbrainLog.contains("gbrain status --json"), gbrainLog)
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
        let runGBrainVersion = try runHelper(
            stateURL: stateURL,
            path: fakeBunBin.path,
            arguments: ["run-gbrain", "--", "--version"]
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
        XCTAssertEqual(runGBrainVersion.exitCode, 0, "stdout:\n\(runGBrainVersion.stdout)\nstderr:\n\(runGBrainVersion.stderr)")
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
        let runGBrainVersion = try runHelper(
            stateURL: stateURL,
            path: fakeBunBin.path,
            arguments: ["run-gbrain", "--", "--version"]
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
        XCTAssertEqual(runGBrainVersion.exitCode, 0, "stdout:\n\(runGBrainVersion.stdout)\nstderr:\n\(runGBrainVersion.stderr)")
        XCTAssertNotEqual(reportWithoutLinkedGBrain.exitCode, 0, "stdout:\n\(reportWithoutLinkedGBrain.stdout)\nstderr:\n\(reportWithoutLinkedGBrain.stderr)")
        XCTAssertTrue(reportWithoutLinkedGBrain.stdout.contains("gbrain_version_failed"), reportWithoutLinkedGBrain.stdout)
        XCTAssertEqual(reportWithLinkedGBrain.exitCode, 0, "stdout:\n\(reportWithLinkedGBrain.stdout)\nstderr:\n\(reportWithLinkedGBrain.stderr)")
    }

    func testReportCompletedReturnsNextSectionPromptFromDocsSnapshot() throws {
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

        // Mutate the source docs after launch. The prompt must still come from
        // this run's docsSnapshotPath, not from a later external document edit.
        try """
        # Install

        ## Step 1: Install GBrain

        Mutated install body.

        ## Step 2: API Keys

        MUTATED STEP 2 BODY THAT MUST NOT APPEAR.
        """
        .write(to: repo.appendingPathComponent("INSTALL_FOR_AGENTS.md"), atomically: true, encoding: .utf8)

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        let nextPromptPath = try XCTUnwrap(payload["nextPromptPath"] as? String)
        let promptFile = try String(contentsOfFile: nextPromptPath, encoding: .utf8)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["nextSection"] as? String, "Step 2: API Keys")
        XCTAssertFalse(nextPrompt.isEmpty)
        XCTAssertTrue(nextPrompt.contains("GBrain needs an embeddings provider so it can search documents."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. ZEROENTROPY_API_KEY (recommended)"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("https://dashboard.zeroentropy.dev"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. OPENAI_API_KEY"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("https://platform.openai.com/api-keys"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. VOYAGE_API_KEY"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("https://dashboard.voyageai.com"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("4. defer embeddings"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("set one of `OPENAI_API_KEY`, `ZEROENTROPY_API_KEY`, or `VOYAGE_API_KEY` in the environment"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("Run `gbrain init`"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("MUTATED STEP 2 BODY"), nextPrompt)
        XCTAssertEqual(promptFile.trimmingCharacters(in: .whitespacesAndNewlines), nextPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testReportRejectDoesNotReturnNextPrompt() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": root.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        let payload = try helperPayload(result.stdout)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(payload["reason"] as? String, "gbrain_version_failed")
        XCTAssertNil(payload["nextPrompt"])
        XCTAssertNil(payload["nextPromptPath"])
    }

    func testReportCompletedForStep2ReturnsStep3PromptWithZebraHardGates() throws {
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
            completedSections: ["Step 1: Install GBrain"],
            waitingForUser: nil,
            nextSection: "Step 2: API Keys"
        )

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            environment: ["ZEROENTROPY_API_KEY": "ambient-zeroentropy-key"],
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 2: API Keys",
                "--embedding-decision", "provider_key",
                "--embedding-provider", "zeroentropy",
                "--embedding-key-env", "ZEROENTROPY_API_KEY",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["nextSection"] as? String, "Step 3: Create the Brain")
        XCTAssertTrue(nextPrompt.contains("Run `gbrain init`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("do not run `gbrain init`, `gbrain init --pglite`, or Supabase/Postgres setup until the user has explicitly chosen topology"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. PGLite (recommended)"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. Postgres"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. Supabase"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("--topology <pglite|postgres|supabase>"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Do not run `gbrain init --pglite --no-embedding`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Ask for the brain repo target separately"), nextPrompt)
    }

    func testReportCompletedForStep2ReturnsKoreanStep3TopologyOptionsWhenLanguageIsKorean() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: root.appendingPathComponent("brain").path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path],
            appPreferredLocalizations: ["ko"],
            preferredLanguages: ["ko"]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeProgress(
            stateURL,
            completedSections: ["Step 1: Install GBrain"],
            waitingForUser: nil,
            nextSection: "Step 2: API Keys"
        )

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            languageCode: "ko",
            environment: ["ZEROENTROPY_API_KEY": "ambient-zeroentropy-key"],
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 2: API Keys",
                "--embedding-decision", "provider_key",
                "--embedding-provider", "zeroentropy",
                "--embedding-key-env", "ZEROENTROPY_API_KEY",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["nextSection"] as? String, "Step 3: Create the Brain")
        XCTAssertTrue(nextPrompt.contains("Step 3 database topology를 아래 번호 중 하나로 선택해 주세요"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. PGLite (recommended) — 로컬 embedded Postgres입니다"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. Postgres — 기존 Postgres database를 사용합니다"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. Supabase — hosted 또는 큰 brain을 위한 managed Postgres입니다"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("--topology <pglite|postgres|supabase>"), nextPrompt)
    }

    func testReportCompletedForStep3RequiresNumberedSearchModePromptFromSectionBody() throws {
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
            environment: ["PATH": bin.path],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path, decision: "provider_key")

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--topology", "pglite",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["nextSection"] as? String, "Step 3.5: Confirm search mode with the user (DO NOT SKIP)")
        XCTAssertTrue(nextPrompt.contains("extract the available option labels and descriptions from this INSTALL_FOR_AGENTS.md section body"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("present them to the user as a numbered list"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("If the section body expresses options inline"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("rewrite those labels into separate `1.`, `2.`, `3.` lines"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Preserve the section body's option labels, descriptions, and order"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Do not hardcode, add, remove, or rename search mode options if the section body changes"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Do not ask with an unnumbered comma-separated sentence"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Map the user's chosen number back to the exact selected mode label from the section body"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("1. conservative"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("2. balanced"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("3. tokenmax"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("gbrain config set search.mode <mode>"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("gbrain search modes"), nextPrompt)
    }

    func testReportCompletedForStep3CarriesExistingSearchModeChoiceIntoStep35Prompt() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path, searchMode: "conservative")
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path, decision: "provider_key")

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--topology", "pglite",
                "--target", target.path,
                "--method", "user_created_repo",
                "--search-mode", "conservative",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        let progress = try progressObject(in: stateURL)
        let decision = try XCTUnwrap(progress["searchModeDecision"] as? [String: Any])

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["nextSection"] as? String, "Step 3.5: Confirm search mode with the user (DO NOT SKIP)")
        XCTAssertEqual(decision["mode"] as? String, "conservative")
        XCTAssertEqual(decision["sourceSection"] as? String, "Step 3: Create the Brain")
        XCTAssertTrue(nextPrompt.contains("The user already chose search mode `conservative` during `Step 3: Create the Brain`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Do not ask the user to choose search mode again"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("gbrain config set search.mode conservative"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("gbrain search modes"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("If Zebra hard gates say the user already chose a mode earlier, do not ask again."), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("present them to the user as a numbered list"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("Ask only for Step 3 decisions that are not already resolved"), nextPrompt)
    }

    func testReportCompletedBeforeRenamedRecurringJobsReturnsDecisionGatePrompt() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root, includeRenamedRecurringJobs: true)
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
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path, decision: "provider_key")
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--topology", "pglite",
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
        let payload = try helperPayload(result.stdout)
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["nextSection"] as? String, "Step 8: Background Sync")
        XCTAssertTrue(nextPrompt.contains("This section sets up scheduled automatic work that keeps the brain up to date."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Choose how to keep the brain up to date:"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Step 3 topology is `pglite`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. Platform scheduler (recommended)"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. GBrain autopilot"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. Manual setup"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("4. Do later"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. Platform scheduler (recommended) -> `--recurring-jobs-decision platform_scheduler_install`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. GBrain autopilot -> `--recurring-jobs-decision autopilot_install`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. Manual setup -> `--recurring-jobs-decision manual_scheduler`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("4. Do later -> `--recurring-jobs-decision defer`"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("GBrain autopilot (recommended)"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("gbrain autopilot --install"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("zebra-gbrain-onboarding run-gbrain -- autopilot --install"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("zebra-gbrain-onboarding prepare-platform-scheduler"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("openclaw cron create --name \"GBrain save\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Create exactly these four core jobs"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("openclaw cron create --name \"GBrain live sync\" --every 15m"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("openclaw cron create --name \"GBrain auto-update\" --cron \"0 9 * * *\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("openclaw cron create --name \"GBrain dream cycle\" --cron \"0 2 * * *\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("openclaw cron create --name \"GBrain weekly health\" --cron \"0 6 * * 1\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("--no-deliver --json"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("hermes cron create \"every 15m\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("hermes cron create \"0 9 * * *\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("hermes cron create \"0 2 * * *\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("hermes cron create \"0 6 * * 1\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("omit `--deliver`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Recurring jobs target key is `vault:\(target.path)`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Recurring jobs target path is `\(target.path)`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("gbrain sync --repo '\(target.path)' --yes && gbrain embed --stale"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("gbrain dream --dir '\(target.path)'"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("--workdir \"\(target.path)\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("gbrain remote ping"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("zebra-gbrain-onboarding check-launchd-bun-path"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("before running `zebra-gbrain-onboarding run-gbrain -- autopilot --install --repo '\(target.path)'`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Only after `check-launchd-bun-path` returns ok"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("waiting_for_user"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("recurring_jobs_decision"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("--recurring-jobs-decision <defer|manual_scheduler|platform_scheduler_install|autopilot_install>"), nextPrompt)
    }

    func testRecurringJobsPromptRecommendsAutopilotForPostgresAndSupabase() throws {
        for topology in ["postgres", "supabase"] {
            let root = try makeTemporaryDirectory()
            let repo = try writeGuardDocs(root: root, includeCanonicalRecurringJobs: true)
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
            _ = try runHelper(
                stateURL: stateURL,
                path: bin.path,
                arguments: [
                    "report",
                    "--status", "completed",
                    "--section", "Step 1: Install GBrain",
                ]
            )
            _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path, decision: "provider_key")
            _ = try runHelper(
                stateURL: stateURL,
                path: bin.path,
                arguments: [
                    "report",
                    "--status", "completed",
                    "--section", "Step 3: Create the Brain",
                    "--topology", topology,
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
            let payload = try helperPayload(result.stdout)
            let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)

            XCTAssertEqual(result.exitCode, 0, "topology=\(topology) stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
            XCTAssertEqual(payload["nextSection"] as? String, "Step 7: Recurring Jobs")
            XCTAssertTrue(nextPrompt.contains("Step 3 topology is `\(topology)`"), nextPrompt)
            XCTAssertTrue(nextPrompt.contains("This section sets up scheduled automatic work that keeps the brain up to date."), nextPrompt)
            XCTAssertTrue(nextPrompt.contains("Choose how to keep the brain up to date:"), nextPrompt)
            XCTAssertTrue(nextPrompt.contains("1. GBrain autopilot (recommended)"), nextPrompt)
            XCTAssertTrue(nextPrompt.contains("2. Platform scheduler"), nextPrompt)
            XCTAssertTrue(nextPrompt.contains("3. Manual setup"), nextPrompt)
            XCTAssertTrue(nextPrompt.contains("4. Do later"), nextPrompt)
            XCTAssertTrue(nextPrompt.contains("1. GBrain autopilot (recommended) -> `--recurring-jobs-decision autopilot_install`"), nextPrompt)
            XCTAssertTrue(nextPrompt.contains("2. Platform scheduler -> `--recurring-jobs-decision platform_scheduler_install`"), nextPrompt)
            XCTAssertTrue(nextPrompt.contains("3. Manual setup -> `--recurring-jobs-decision manual_scheduler`"), nextPrompt)
            XCTAssertTrue(nextPrompt.contains("4. Do later -> `--recurring-jobs-decision defer`"), nextPrompt)
            XCTAssertFalse(nextPrompt.contains("1. Platform scheduler (recommended)"), nextPrompt)
        }
    }

    func testRecurringJobsPromptRecommendsPlatformSchedulerForPGLiteStep7() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root, includeCanonicalRecurringJobs: true)
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
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path, decision: "provider_key")
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--topology", "pglite",
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
        let payload = try helperPayload(result.stdout)
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["nextSection"] as? String, "Step 7: Recurring Jobs")
        XCTAssertTrue(nextPrompt.contains("Step 3 topology is `pglite`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("This section sets up scheduled automatic work that keeps the brain up to date."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Choose how to keep the brain up to date:"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. Platform scheduler (recommended)"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("zebra-gbrain-onboarding prepare-platform-scheduler"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("openclaw cron create --name \"GBrain save\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Create exactly these four core jobs"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("openclaw cron create --name \"GBrain live sync\" --every 15m"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("openclaw cron create --name \"GBrain auto-update\" --cron \"0 9 * * *\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("openclaw cron create --name \"GBrain dream cycle\" --cron \"0 2 * * *\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("openclaw cron create --name \"GBrain weekly health\" --cron \"0 6 * * 1\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("--no-deliver --json"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("hermes cron create \"every 15m\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("hermes cron create \"0 9 * * *\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("hermes cron create \"0 2 * * *\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("hermes cron create \"0 6 * * 1\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("omit `--deliver`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("gbrain sync --repo '\(target.path)' --yes && gbrain embed --stale"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("gbrain dream --dir '\(target.path)'"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("--workdir \"\(target.path)\""), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. GBrain autopilot"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. Manual setup"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("4. Do later"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. Platform scheduler (recommended) -> `--recurring-jobs-decision platform_scheduler_install`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. GBrain autopilot -> `--recurring-jobs-decision autopilot_install`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. Manual setup -> `--recurring-jobs-decision manual_scheduler`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("4. Do later -> `--recurring-jobs-decision defer`"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("GBrain autopilot (recommended)"), nextPrompt)
    }

    func testRecurringJobsPromptUsesKoreanForPGLiteRecommendationWhenLanguageIsKorean() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root, includeCanonicalRecurringJobs: true)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path],
            appPreferredLocalizations: ["ko"],
            preferredLanguages: ["ko"]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            languageCode: "ko",
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            languageCode: "ko",
            environment: ["ZEROENTROPY_API_KEY": "ambient-zeroentropy-key"],
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 2: API Keys",
                "--embedding-decision", "provider_key",
                "--embedding-provider", "zeroentropy",
                "--embedding-key-env", "ZEROENTROPY_API_KEY",
            ]
        )
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            languageCode: "ko",
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--topology", "pglite",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            languageCode: "ko",
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3.5: Confirm search mode with the user (DO NOT SKIP)",
            ]
        )

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            languageCode: "ko",
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 4: Import and Index",
                "--source-id", "brain",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["nextSection"] as? String, "Step 7: Recurring Jobs")
        XCTAssertTrue(nextPrompt.contains("이 단계는 brain을 최신 상태로 유지하기 위한 정기 자동 작업을 설정하는 단계입니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("설정하면 Zebra가 주기적으로 새 변경사항을 가져오고, 검색용 데이터를 갱신하고, 상태를 점검합니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("지금 설정하지 않아도 Zebra는 계속 사용할 수 있고, 나중에 다시 켤 수 있습니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Step 3에서 PGLite를 선택했기 때문에 Platform scheduler를 추천합니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("brain을 최신 상태로 유지할 방식을 선택해 주세요:"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. Platform scheduler (recommended) — 선택한 agent가 로컬 brain의 정기 작업을 실행합니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. GBrain autopilot — agent scheduler를 쓰기 어려울 때 GBrain이 정기 작업을 실행합니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. 직접 설정 — launchd, crontab, 외부 cron 등을 직접 구성합니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("4. 나중에 하기 — 지금은 정기 자동 작업을 설정하지 않습니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. Platform scheduler (recommended) -> `--recurring-jobs-decision platform_scheduler_install`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. GBrain autopilot -> `--recurring-jobs-decision autopilot_install`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. 직접 설정 -> `--recurring-jobs-decision manual_scheduler`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("4. 나중에 하기 -> `--recurring-jobs-decision defer`"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("GBrain autopilot (recommended)"), nextPrompt)
    }

    func testRecurringJobsPromptUsesKoreanForPostgresRecommendationWhenLanguageIsKorean() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root, includeCanonicalRecurringJobs: true)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path],
            appPreferredLocalizations: ["ko"],
            preferredLanguages: ["ko"]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            languageCode: "ko",
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            languageCode: "ko",
            environment: ["ZEROENTROPY_API_KEY": "ambient-zeroentropy-key"],
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 2: API Keys",
                "--embedding-decision", "provider_key",
                "--embedding-provider", "zeroentropy",
                "--embedding-key-env", "ZEROENTROPY_API_KEY",
            ]
        )
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            languageCode: "ko",
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--topology", "postgres",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            languageCode: "ko",
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3.5: Confirm search mode with the user (DO NOT SKIP)",
            ]
        )

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            languageCode: "ko",
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 4: Import and Index",
                "--source-id", "brain",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["nextSection"] as? String, "Step 7: Recurring Jobs")
        XCTAssertTrue(nextPrompt.contains("이 단계는 brain을 최신 상태로 유지하기 위한 정기 자동 작업을 설정하는 단계입니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Step 3에서 Postgres를 선택했기 때문에 GBrain autopilot을 추천합니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("brain을 최신 상태로 유지할 방식을 선택해 주세요:"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. GBrain autopilot (recommended) — durable database setup에 맞게 GBrain이 정기 작업을 실행합니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. Platform scheduler — 이미 agent scheduler를 운영 기준으로 쓰고 있을 때 선택합니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. 직접 설정 — launchd, crontab, Railway cron 등 외부 scheduler를 직접 구성합니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("4. 나중에 하기 — 지금은 정기 자동 작업을 설정하지 않습니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. GBrain autopilot (recommended) -> `--recurring-jobs-decision autopilot_install`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. Platform scheduler -> `--recurring-jobs-decision platform_scheduler_install`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. 직접 설정 -> `--recurring-jobs-decision manual_scheduler`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("4. 나중에 하기 -> `--recurring-jobs-decision defer`"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("Platform scheduler (recommended)"), nextPrompt)
    }

    func testRecurringJobsPromptHasNoRecommendationWhenTopologyIsUnknown() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root, includeCanonicalRecurringJobs: true)
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
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path, decision: "provider_key")
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--topology", "pglite",
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
        try removeTopologyDecision(from: stateURL)

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
        let payload = try helperPayload(result.stdout)
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["nextSection"] as? String, "Step 7: Recurring Jobs")
        XCTAssertTrue(nextPrompt.contains("Step 3 topology is `unknown`"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Zebra could not confirm the Step 3 database choice, so these options have no recommendation."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. Platform scheduler — the selected agent runs scheduled work for the brain."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. GBrain autopilot — GBrain runs scheduled work."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. Manual setup — configure launchd, crontab, or external cron yourself."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("4. Do later — do not set up scheduled automatic work now."), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("(recommended)"), nextPrompt)
    }

    func testReportCompletedForLastSectionReturnsCompletePromptWhenReceiptVerified() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let installForAgentsURL = repo.appendingPathComponent("INSTALL_FOR_AGENTS.md")
        let installForAgents = try String(contentsOf: installForAgentsURL, encoding: .utf8)
        try (installForAgents + """

        ## Upgrade

        Upgrade existing installs.
        """).write(to: installForAgentsURL, atomically: true, encoding: .utf8)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: target.path,
            sourceId: "brain",
            method: "user_created_repo",
            complete: true,
            sourceVerification: true
        )
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeProgress(
            stateURL,
            completedSections: [
                "Step 1: Install GBrain",
                "Step 2: API Keys",
                "Step 3: Create the Brain",
                "Step 3.5: Confirm search mode with the user (DO NOT SKIP)",
                "Step 4: Import and Index",
            ],
            waitingForUser: nil,
            nextSection: "Step 9: Verify"
        )

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 9: Verify",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["nextSection"] as? String, "complete")
        XCTAssertTrue(nextPrompt.contains("Zebra GBrain setup is complete."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Do not run `zebra-gbrain-onboarding verify` again."), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("## Step"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("Upgrade existing installs"), nextPrompt)
    }

    func testBootstrapVerifyPromptReportsCompletionWhenReceiptAlreadyVerified() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: target.path,
            sourceId: "brain",
            method: "user_created_repo",
            complete: true,
            sourceVerification: true
        )
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let prepareResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: ["prepare-source-repo", "--path", sourceRepo.path]
        )
        try writeProgress(
            stateURL,
            completedSections: [
                "Step 1: Install GBrain",
                "Step 2: API Keys",
                "Step 3: Create the Brain",
                "Step 3.5: Confirm search mode with the user (DO NOT SKIP)",
                "Step 4: Import and Index",
            ],
            waitingForUser: nil,
            nextSection: "verify"
        )

        let launcherResult = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: [
                "write-runtime-launcher",
                "--runtime", "hermes",
                "--executable", "/tmp/hermes",
                "--run-id", launch.runId,
            ]
        )
        let prompt = try launcherPrompt(from: launcherResult.stdout)

        XCTAssertEqual(prepareResult.exitCode, 0, "stdout:\n\(prepareResult.stdout)\nstderr:\n\(prepareResult.stderr)")
        XCTAssertEqual(launcherResult.exitCode, 0, "stdout:\n\(launcherResult.stdout)\nstderr:\n\(launcherResult.stderr)")
        XCTAssertTrue(prompt.contains("final verification already passed"), prompt)
        XCTAssertTrue(prompt.contains("Do not run `zebra-gbrain-onboarding verify` again."), prompt)
        XCTAssertTrue(prompt.contains("zebra-gbrain-onboarding report --status completed --section \"verify\""), prompt)
    }

    func testReportCompletedForSyntheticVerifyMovesNextSectionToComplete() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: target.path)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: target.path,
            sourceId: "brain",
            method: "user_created_repo",
            complete: true,
            sourceVerification: true
        )
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        try writeProgress(
            stateURL,
            completedSections: [
                "Step 1: Install GBrain",
                "Step 2: API Keys",
                "Step 3: Create the Brain",
                "Step 3.5: Confirm search mode with the user (DO NOT SKIP)",
                "Step 4: Import and Index",
                "Step 9: Verify",
            ],
            waitingForUser: nil,
            nextSection: "verify"
        )

        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "verify",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let progress = try progressObject(in: stateURL)
        let completedSections = try XCTUnwrap(progress["completedSections"] as? [String])

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["nextSection"] as? String, "complete")
        XCTAssertEqual(progress["nextSection"] as? String, "complete")
        XCTAssertTrue(completedSections.contains("verify"))
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
        XCTAssertTrue(result.stdout.contains("Clone into this path"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Preparing GBrain source repo at: \(homeRepo.path)"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertFalse(result.stdout.contains("Y/n"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
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
        XCTAssertTrue(result.stdout.contains("Use this repo"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Using GBrain source repo: \(homeRepo.path)"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertFalse(result.stdout.contains("Y/n"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let state = try stateObject(in: stateURL)
        let binding = try XCTUnwrap(state["activeGBrainBinding"] as? [String: Any])

        XCTAssertEqual(binding["sourceRepoPath"] as? String, homeRepo.path)
        XCTAssertEqual(binding["sourceRepoStatus"] as? String, "reused")
        XCTAssertFalse(FileManager.default.fileExists(atPath: homeRepo.appendingPathComponent("node_modules").path))
    }

    func testPrepareSourceRepoWithTerminalAbortMenuRowAborts() throws {
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
            set timeout 10
            spawn $env(HELPER_PATH) prepare-source-repo
            expect {
                "Use Up/Down" { send "jj\\r" }
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect {
                "GBrain source repo preparation was aborted" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect eof
            set wait_status [wait]
            exit [lindex $wait_status 3]
            """
        )

        XCTAssertNotEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertNil(try stateObject(in: stateURL)["activeGBrainBinding"])
        XCTAssertEqual(try progressObject(in: stateURL)["lastFailure"] as? String, "source_repo_prepare_aborted")
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
            set timeout 10
            spawn $env(HELPER_PATH) prepare-source-repo
            expect {
                "Use this repo" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            send "j\\r"
            expect {
                "Waiting for a custom GBrain source repo path" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect {
                "A different GBrain source repo path is required" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect {
                "Custom GBrain source repo path" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            send "$env(INVALID_CUSTOM_PATH)\\r"
            expect {
                "Clone into" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect {
                "Retry this same path" { send "q" }
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect {
                "GBrain source repo preparation was aborted" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect eof
            set wait_status [wait]
            exit [lindex $wait_status 3]
            """
        )

        XCTAssertNotEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("\(invalidCustomPath.path) is not a GBrain source repo."), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Clone into \(invalidCustomPath.path)/gbrain"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Retry this same path"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Choose another path"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertFalse(result.stdout.contains("Y/n"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertFalse(result.stdout.contains("Choose:"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
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
            set timeout 10
            spawn $env(HELPER_PATH) prepare-source-repo
            expect {
                "Use this repo" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            send "j\\r"
            expect {
                "Waiting for a custom GBrain source repo path" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect {
                "A different GBrain source repo path is required" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect {
                "Custom GBrain source repo path" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            send "Users/han/project\\r"
            expect {
                "Custom path must start with / or ~" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            send "q\\r"
            expect {
                "GBrain source repo preparation was aborted" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect eof
            set wait_status [wait]
            exit [lindex $wait_status 3]
            """
        )

        XCTAssertNotEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertFalse(result.stdout.contains("Y/n"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
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
            set timeout 10
            spawn $env(HELPER_PATH) prepare-source-repo
            expect {
                "Use this repo" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            send "j\\r"
            expect {
                "Waiting for a custom GBrain source repo path" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect {
                "A different GBrain source repo path is required" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect {
                "Custom GBrain source repo path" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            send "~/project-gbrain\\r"
            expect eof
            set wait_status [wait]
            exit [lindex $wait_status 3]
            """
        )
        let state = try stateObject(in: stateURL)
        let binding = try XCTUnwrap(state["activeGBrainBinding"] as? [String: Any])

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Preparing GBrain source repo at: \(customRepo.path)"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertFalse(result.stdout.contains("Y/n"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(binding["sourceRepoPath"] as? String, customRepo.path)
        XCTAssertEqual(binding["sourceRepoStatus"] as? String, "cloned")
    }

    func testPrepareSourceRepoWithTerminalDumbTermUsesNumericFallback() throws {
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
        let result = try runHelperWithTerminalScript(
            stateURL: stateURL,
            homePath: root.path,
            extraEnvironment: ["TERM": "dumb"],
            script: """
            set timeout 60
            spawn $env(HELPER_PATH) prepare-source-repo
            expect "Selection:"
            send "1\\r"
            expect eof
            set wait_status [wait]
            exit [lindex $wait_status 3]
            """
        )
        let state = try stateObject(in: stateURL)
        let binding = try XCTUnwrap(state["activeGBrainBinding"] as? [String: Any])

        XCTAssertEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Using GBrain source repo: \(homeRepo.path)"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertFalse(result.stdout.contains("Y/n"), "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(binding["sourceRepoPath"] as? String, homeRepo.path)
    }

    func testPrepareSourceRepoWithTerminalDumbTermAbortMenuNumberAborts() throws {
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
            extraEnvironment: ["TERM": "dumb"],
            script: """
            set timeout 10
            spawn $env(HELPER_PATH) prepare-source-repo
            expect {
                "Selection:" { send "3\\r" }
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect {
                "GBrain source repo preparation was aborted" {}
                timeout { exit 124 }
                eof { exit 125 }
            }
            expect eof
            set wait_status [wait]
            exit [lindex $wait_status 3]
            """
        )

        XCTAssertNotEqual(result.exitCode, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertNil(try stateObject(in: stateURL)["activeGBrainBinding"])
        XCTAssertEqual(try progressObject(in: stateURL)["lastFailure"] as? String, "source_repo_prepare_aborted")
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

    func testPrepareLaunchClearsStaleInitialTopologyGateFromProgress() throws {
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

        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let progress = try progressObject(in: stateURL)

        XCTAssertNil(waitingForUserReason(in: progress))
        XCTAssertEqual(progress["nextSection"] as? String, "Step 1: Install GBrain")
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

        XCTAssertTrue(launch.startupPrompt.contains("Zebra GBrain setup is starting"))
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

        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let state = try String(contentsOf: stateURL, encoding: .utf8)

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

    func testReportGuardRejectsCreateBrainCompletionWithoutTopology() throws {
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
        let payload = try helperPayload(result.stdout)
        let progress = try progressObject(in: stateURL)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(payload["reason"] as? String, "topology_decision_required")
        XCTAssertNil(progress["topologyDecision"])
        XCTAssertFalse((progress["completedSections"] as? [String] ?? []).contains("Step 3: Create the Brain"))
    }

    func testReportGuardRejectsCreateBrainCompletionWithInvalidTopology() throws {
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
                "--topology", "sqlite",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let progress = try progressObject(in: stateURL)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(payload["reason"] as? String, "invalid_topology_decision")
        XCTAssertNil(progress["topologyDecision"])
        XCTAssertFalse((progress["completedSections"] as? [String] ?? []).contains("Step 3: Create the Brain"))
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
                "--topology", "pglite",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let progress = try progressObject(in: stateURL)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("brain_repo_target_unresolved"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertEqual(waitingForUserReason(in: progress), "brain_repo_target_resolution")
        XCTAssertEqual(payload["nextAction"] as? String, "ask_user_for_brain_repo_target")
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        XCTAssertTrue(nextPrompt.contains("Choose the brain repo target using one of these numbered options."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. Create a new brain repo"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. Use an existing markdown/brain repo path"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. Create a new brain repo at a custom path"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("--method"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("targetResolution.method"), nextPrompt)
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
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        XCTAssertEqual(payload["targetPrompt"] as? String, nextPrompt)
        XCTAssertTrue(nextPrompt.contains("brain repo target을 아래 번호 중 하나로 선택해 주세요"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. \(root.appendingPathComponent("brain", isDirectory: true).path)에 새 brain repo를 만듭니다"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. 사용자가 제공하는 기존 markdown/brain repo path를 사용합니다"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. custom path에 새 brain repo를 만듭니다"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("--method"), nextPrompt)
        XCTAssertFalse(nextPrompt.contains("targetResolution.method"), nextPrompt)
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
                "--topology", "pglite",
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
                "--topology", "pglite",
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
                "--topology", "pglite",
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
                "--topology", "pglite",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        let progress = try progressObject(in: stateURL)
        let targetResolution = try XCTUnwrap(progress["targetResolution"] as? [String: Any])
        let topologyDecision = try XCTUnwrap(progress["topologyDecision"] as? [String: Any])

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue((progress["completedSections"] as? [String] ?? []).contains("Step 3: Create the Brain"))
        XCTAssertEqual(topologyDecision["topology"] as? String, "pglite")
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
                "--topology", "pglite",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        let progress = try progressObject(in: stateURL)

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue((progress["completedSections"] as? [String] ?? []).contains("Step 3: Create the Brain"))
        XCTAssertFalse(result.stdout.contains("doctor_failed"), "stdout: \(result.stdout) stderr: \(result.stderr)")
    }

    func testReportGuardRejectsCreateBrainDoctorFailureWithDiagnostics() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrainWithOnlyCycleFreshnessFailure(
            root: root,
            localPath: target.path,
            doctorChecksJSON: #"{"checks":[{"name":"sync_freshness","status":"fail"},{"name":"cycle_freshness","status":"fail"}]}"#
        )
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
                "--topology", "pglite",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let progress = try progressObject(in: stateURL)
        let details = try XCTUnwrap(progress["lastFailureDetails"] as? [String: Any])

        XCTAssertNotEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertEqual(payload["reason"] as? String, "doctor_failed")
        XCTAssertEqual(payload["doctorFailedChecks"] as? [String], ["sync_freshness", "cycle_freshness"])
        XCTAssertEqual(payload["doctorCwd"] as? String, target.path)
        XCTAssertEqual(payload["doctorExitCode"] as? Int, 1)
        XCTAssertEqual(details["doctorFailedChecks"] as? [String], ["sync_freshness", "cycle_freshness"])
        XCTAssertEqual(details["doctorCwd"] as? String, target.path)
    }

    func testReportGuardReusesDoctorDiagnosticsAndClearsDetailsAfterSuccess() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        let doctorLog = root.appendingPathComponent("doctor-calls.log")
        let successMarker = root.appendingPathComponent("doctor-ok")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrainWithOnlyCycleFreshnessFailure(
            root: root,
            localPath: target.path,
            doctorChecksJSON: #"{"checks":[{"name":"sync_freshness","status":"fail"},{"name":"cycle_freshness","status":"fail"}]}"#,
            doctorCallLogPath: doctorLog.path,
            successMarkerPath: successMarker.path
        )
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path)

        let arguments = [
            "report",
            "--status", "completed",
            "--section", "Step 3: Create the Brain",
            "--topology", "pglite",
            "--target", target.path,
            "--method", "user_created_repo",
        ]
        let failed = try runHelper(stateURL: stateURL, path: bin.path, arguments: arguments)
        XCTAssertNotEqual(failed.exitCode, 0, "stdout: \(failed.stdout) stderr: \(failed.stderr)")
        XCTAssertEqual(try String(contentsOf: doctorLog, encoding: .utf8).split(separator: "\n").count, 1)
        XCTAssertNotNil(try progressObject(in: stateURL)["lastFailureDetails"])

        try "".write(to: successMarker, atomically: true, encoding: .utf8)
        let succeeded = try runHelper(stateURL: stateURL, path: bin.path, arguments: arguments)
        let progress = try progressObject(in: stateURL)

        XCTAssertEqual(succeeded.exitCode, 0, "stdout: \(succeeded.stdout) stderr: \(succeeded.stderr)")
        XCTAssertEqual(try String(contentsOf: doctorLog, encoding: .utf8).split(separator: "\n").count, 2)
        XCTAssertNil(progress["lastFailure"])
        XCTAssertNil(progress["lastFailureDetails"])
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
                "--topology", "pglite",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("embedding_provider_required"), "stdout: \(result.stdout) stderr: \(result.stderr)")
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
        XCTAssertEqual(decision["provider"] as? String, "zeroentropy")
        XCTAssertEqual(decision["keyEnvName"] as? String, "ZEROENTROPY_API_KEY")
        XCTAssertNil(decision["keySource"])
        XCTAssertNil(decision["apiKey"])
        XCTAssertNil(decision["key"])
        XCTAssertFalse(try String(contentsOf: stateURL, encoding: .utf8).contains("ambient-zeroentropy-key"))
        XCTAssertTrue((progress["completedSections"] as? [String] ?? []).contains("Step 2: API Keys"))
    }

    func testReportRequiresEmbeddingProviderBeforeCompletingCredentials() throws {
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
                "--section", "Step 2: API Keys",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let prompt = try XCTUnwrap(payload["embeddingProviderPrompt"] as? String)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(payload["reason"] as? String, "embedding_provider_required")
        XCTAssertTrue(prompt.contains("1. ZEROENTROPY_API_KEY (recommended)"), prompt)
        XCTAssertTrue(prompt.contains("4. defer embeddings"), prompt)
    }

    func testReportCompletesSelectedEmbeddingProviderWithoutKeySource() throws {
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
                "--section", "Step 2: API Keys",
                "--embedding-decision", "provider_key",
                "--embedding-provider", "openai",
                "--embedding-key-env", "OPENAI_API_KEY",
            ]
        )
        let progress = try progressObject(in: stateURL)
        let decision = try XCTUnwrap(progress["embeddingDecision"] as? [String: Any])

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertEqual(decision["decision"] as? String, "provider_key")
        XCTAssertEqual(decision["provider"] as? String, "openai")
        XCTAssertEqual(decision["keyEnvName"] as? String, "OPENAI_API_KEY")
        XCTAssertNil(decision["keySource"])
        XCTAssertTrue((progress["completedSections"] as? [String] ?? []).contains("Step 2: API Keys"))
    }

    func testConfigureEmbeddingKeyCommandIsNotExposedByHelper() throws {
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
                "configure-embedding-key",
                "--provider", "zeroentropy",
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("usage: zebra-gbrain-onboarding"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertFalse(result.stderr.contains("configure-embedding-key"), "stdout: \(result.stdout) stderr: \(result.stderr)")
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
                "--topology", "pglite",
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
                "--topology", "pglite",
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

    func testReportGuardRejectsUserCreatedGitRepoWithoutInitialCommitBeforeImportCompletion() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try runGit(["init"], cwd: target)
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
                "--topology", "pglite",
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
        let payload = try helperPayload(result.stdout)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["reason"] as? String, "brain_repo_initial_commit_missing")
        XCTAssertEqual(payload["nextAction"] as? String, "create_initial_brain_commit")
        XCTAssertEqual(
            payload["suggestedCommand"] as? String,
            "zebra-gbrain-onboarding create-initial-brain-commit --target '\(target.path)'"
        )
    }

    func testInitialCommitHelperAllowsUserCreatedGitRepoImportCompletionAfterRepair() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try runGit(["init"], cwd: target)
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
                "--topology", "pglite",
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

        let repair = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "create-initial-brain-commit",
                "--target", target.path,
            ]
        )
        let repairPayload = try helperPayload(repair.stdout)
        let importReport = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 4: Import and Index",
                "--source-id", "brain",
            ]
        )
        let progress = try progressObject(in: stateURL)

        XCTAssertEqual(repair.exitCode, 0, "stdout: \(repair.stdout) stderr: \(repair.stderr)")
        XCTAssertEqual(repairPayload["status"] as? String, "created")
        XCTAssertEqual(repairPayload["createdMarker"] as? Bool, true)
        XCTAssertNotNil(try gitHeadCommit(in: target))
        XCTAssertEqual(importReport.exitCode, 0, "stdout: \(importReport.stdout) stderr: \(importReport.stderr)")
        XCTAssertTrue((progress["completedSections"] as? [String] ?? []).contains("Step 4: Import and Index"))
    }

    func testStep4PromptIncludesInitialCommitRepairFlow() throws {
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
            environment: ["PATH": bin.path],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en"]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 1: Install GBrain",
            ]
        )
        _ = try recordEmbeddingDecision(stateURL: stateURL, path: bin.path)
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--topology", "pglite",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        let result = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3.5: Confirm search mode with the user (DO NOT SKIP)",
            ]
        )
        let payload = try helperPayload(result.stdout)
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(
            nextPrompt.contains("Before import/embed/sync, verify the resolved brain repo target has an initial git commit."),
            nextPrompt
        )
        XCTAssertTrue(
            nextPrompt.contains("If Zebra rejects completion with `brain_repo_initial_commit_missing`, run `zebra-gbrain-onboarding create-initial-brain-commit --target <brain repo path>`"),
            nextPrompt
        )
        XCTAssertTrue(
            nextPrompt.contains("Then rerun import/sync and report completion again."),
            nextPrompt
        )
    }

    func testInitialCommitHelperOnEmptyGitRepoCreatesMarkerCommit() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try runGit(["init"], cwd: target)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: [
                "create-initial-brain-commit",
                "--target", target.path,
            ]
        )
        let payload = try helperPayload(result.stdout)
        let marker = target.appendingPathComponent(".zebra-initialized", isDirectory: false)

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["status"] as? String, "created")
        XCTAssertEqual(payload["createdMarker"] as? Bool, true)
        XCTAssertEqual(payload["identityMode"] as? String, "inline_zebra")
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "Zebra initialized this brain repository so GBrain can sync from an initial git commit.\n")
        XCTAssertNotNil(try gitHeadCommit(in: target))
    }

    func testInitialCommitHelperCommitsExistingFilesWithoutReadme() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try runGit(["init"], cwd: target)
        try "hello\n".write(to: target.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: [
                "create-initial-brain-commit",
                "--target", target.path,
            ]
        )
        let payload = try helperPayload(result.stdout)

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertEqual(payload["status"] as? String, "created")
        XCTAssertEqual(payload["createdMarker"] as? Bool, false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent(".zebra-initialized").path))
        XCTAssertEqual(try gitOutput(["show", "--name-only", "--format=", "HEAD"], cwd: target).trimmingCharacters(in: .whitespacesAndNewlines), "notes.md")
    }

    func testInitialCommitHelperOnRepoWithExistingHeadIsNoopSuccess() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try runGit(["init"], cwd: target)
        try "hello\n".write(to: target.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], cwd: target)
        try runGit([
            "-c", "user.name=Zebra Test",
            "-c", "user.email=zebra-test@example.com",
            "commit",
            "-m", "Existing commit",
        ], cwd: target)
        let existingHead = try XCTUnwrap(gitHeadCommit(in: target))
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: [
                "create-initial-brain-commit",
                "--target", target.path,
            ]
        )
        let payload = try helperPayload(result.stdout)

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertEqual(payload["status"] as? String, "already_committed")
        XCTAssertEqual(payload["commit"] as? String, existingHead)
        XCTAssertEqual(payload["createdMarker"] as? Bool, false)
        XCTAssertEqual(payload["identityMode"] as? String, "none")
        XCTAssertEqual(try gitOutput(["rev-list", "--count", "HEAD"], cwd: target).trimmingCharacters(in: .whitespacesAndNewlines), "1")
    }

    func testInitialCommitHelperFailsOnNonGitDirectoryWithoutMarker() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            arguments: [
                "create-initial-brain-commit",
                "--target", target.path,
            ]
        )
        let payload = try helperPayload(result.stdout)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["reason"] as? String, "brain_repo_not_git_repo")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent(".zebra-initialized").path))
    }

    func testInitialCommitHelperUsesInlineIdentityWithoutWritingGitConfig() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        let isolatedHome = root.appendingPathComponent("isolated-home", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: isolatedHome, withIntermediateDirectories: true)
        try runGit(["init"], cwd: target)
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: root.path,
            environment: [
                "HOME": isolatedHome.path,
                "XDG_CONFIG_HOME": isolatedHome.appendingPathComponent(".config", isDirectory: true).path,
            ],
            arguments: [
                "create-initial-brain-commit",
                "--target", target.path,
            ]
        )
        let payload = try helperPayload(result.stdout)
        let identity = try gitOutput(["log", "-1", "--format=%an <%ae>|%cn <%ce>"], cwd: target)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let localConfig = try String(contentsOf: target.appendingPathComponent(".git/config"), encoding: .utf8)

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertEqual(payload["identityMode"] as? String, "inline_zebra")
        XCTAssertEqual(identity, "Zebra Onboarding <zebra-onboarding@offlight.local>|Zebra Onboarding <zebra-onboarding@offlight.local>")
        XCTAssertFalse(FileManager.default.fileExists(atPath: isolatedHome.appendingPathComponent(".gitconfig").path))
        XCTAssertFalse(localConfig.contains("Zebra Onboarding"))
        XCTAssertFalse(localConfig.contains("zebra-onboarding@offlight.local"))
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
                "--topology", "pglite",
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
        let sourceVerification = try XCTUnwrap(targetReceipt["sourceVerification"] as? [String: Any])
        XCTAssertEqual(sourceVerification["sourceId"] as? String, "brain")
        XCTAssertEqual(sourceVerification["targetPath"] as? String, target.path)
        XCTAssertEqual(sourceVerification["method"] as? String, "sources_current_and_list")
    }

    func testImportCompletionRecordsSourceVerificationFromExistingTargetSourceId() throws {
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
                "--topology", "pglite",
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

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        let targetReceipt = try receiptTarget(in: stateURL, targetPath: target.path)
        let sourceVerification = try XCTUnwrap(targetReceipt["sourceVerification"] as? [String: Any])
        XCTAssertEqual(sourceVerification["sourceId"] as? String, "brain")
        XCTAssertEqual(sourceVerification["targetPath"] as? String, target.path)
        XCTAssertEqual(sourceVerification["method"] as? String, "sources_current_and_list")
    }

    func testHelperVerifyFailsCompleteReceiptWhenSourceProbeIsTransient() throws {
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

        XCTAssertEqual(result.exitCode, 1, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(#""complete": false"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("pglite_busy"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        let receipt = try receiptTarget(in: stateURL, targetPath: target.path)
        XCTAssertEqual(receipt["complete"] as? Bool, false)
        XCTAssertEqual(receipt["status"] as? String, "failed")
        XCTAssertEqual(receipt["reasons"] as? [String], ["pglite_busy"])
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

    func testHelperVerifyFailsRuntimeProbeEvenWithPreviousVerification() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrainWithPGLiteWasmSourceProbeFailure(root: root)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: target.path,
            sourceId: "brain",
            method: "user_created_repo",
            complete: false,
            sourceVerification: true
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
        XCTAssertTrue(result.stdout.contains(#""complete": false"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("pglite_wasm_runtime_error"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertFalse(result.stdout.contains("source_not_registered"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        let receipt = try receiptTarget(in: stateURL, targetPath: target.path)
        XCTAssertEqual(receipt["complete"] as? Bool, false)
        XCTAssertEqual(receipt["status"] as? String, "failed")
        XCTAssertEqual(receipt["reasons"] as? [String], ["pglite_wasm_runtime_error"])
        let sourcesCurrentResult = try XCTUnwrap(receipt["sourcesCurrentResult"] as? [String: Any])
        XCTAssertEqual(sourcesCurrentResult["status"] as? String, "error")
        XCTAssertEqual(sourcesCurrentResult["reason"] as? String, "pglite_wasm_runtime_error")
    }

    func testHelperVerifyFailsRuntimeProbeWithoutPreviousVerification() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrainWithPGLiteWasmSourceProbeFailure(root: root)
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
        XCTAssertTrue(result.stdout.contains(#""complete": false"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("pglite_wasm_runtime_error"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertFalse(result.stdout.contains("source_not_registered"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        let receipt = try receiptTarget(in: stateURL, targetPath: target.path)
        XCTAssertEqual(receipt["complete"] as? Bool, false)
        XCTAssertEqual(receipt["reasons"] as? [String], ["pglite_wasm_runtime_error"])
    }

    func testHelperVerifyKeepsActualMismatchAsSourceNotRegistered() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        let other = root.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: other.path)
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: target.path,
            sourceId: "brain",
            method: "user_created_repo",
            complete: false,
            sourceVerification: true
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
        XCTAssertTrue(result.stdout.contains("source_not_registered"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertFalse(result.stdout.contains("verified_with_warnings"), "stdout: \(result.stdout) stderr: \(result.stderr)")
    }

    func testHelperRecoverCycleFreshnessRunsDream() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let fake = try installFakeGBrainWithAutopilot(
            root: root,
            sourceId: "team",
            localPath: target.path,
            cycleFreshnessUntilDream: true
        )
        let stateURL = root.appendingPathComponent("state.json")
        try writeState(
            stateURL,
            targetPath: target.path,
            sourceId: "team",
            method: "user_created_repo",
            complete: false,
            sourceVerification: true
        )
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": fake.bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: fake.bin.path,
            environment: ["HOME": root.path],
            arguments: [
                "recover-cycle-freshness",
                "--target", target.path,
                "--source-id", "team",
            ]
        )

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(#""status": "recovered"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(#""status": "verified"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(#""ran": true"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(#""sourceId": "team"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        let log = try String(contentsOf: fake.log, encoding: .utf8)
        XCTAssertTrue(log.contains("gbrain dream --source team"), log)
        XCTAssertFalse(log.contains("launchctl unload"), log)
        XCTAssertFalse(log.contains("launchctl load"), log)
    }

    func testHelperRecoverCycleFreshnessDoesNotDreamForUnexpectedDoctorBlocker() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let fake = try installFakeGBrainWithAutopilot(
            root: root,
            sourceId: "brain",
            localPath: target.path,
            cycleFreshnessUntilDream: true,
            extraDoctorBlocker: true
        )
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": fake.bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: fake.bin.path,
            environment: ["HOME": root.path],
            arguments: [
                "recover-cycle-freshness",
                "--target", target.path,
                "--source-id", "brain",
            ]
        )

        XCTAssertEqual(result.exitCode, 1, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("unexpected_doctor_blockers"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(#""ran": false"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fake.log.path))
    }

    func testHelperRecoverCycleFreshnessDoesNotDreamWhenSourceProbeMismatches() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        let otherTarget = root.appendingPathComponent("other-brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherTarget, withIntermediateDirectories: true)
        let fake = try installFakeGBrainWithAutopilot(
            root: root,
            sourceId: "brain",
            localPath: target.path,
            listedLocalPath: otherTarget.path,
            cycleFreshnessUntilDream: true
        )
        let stateURL = root.appendingPathComponent("state.json")
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            gbrainDocsRepoURL: repo,
            environment: ["PATH": fake.bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: fake.bin.path,
            environment: ["HOME": root.path],
            arguments: [
                "recover-cycle-freshness",
                "--target", target.path,
                "--source-id", "brain",
            ]
        )

        XCTAssertEqual(result.exitCode, 1, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("source_not_registered"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(#""status": "mismatch"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(#""ran": false"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fake.log.path))
    }

    func testHelperVerifyFailsCompleteReceiptWhenDoctorProbeIsTransient() throws {
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

        XCTAssertEqual(result.exitCode, 1, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(#""complete": false"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("pglite_busy"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        let receipt = try receiptTarget(in: stateURL, targetPath: target.path)
        XCTAssertEqual(receipt["complete"] as? Bool, false)
        XCTAssertEqual(receipt["status"] as? String, "failed")
        XCTAssertEqual(receipt["reasons"] as? [String], ["pglite_busy"])
        let globalReadiness = try globalReadiness(in: stateURL)
        XCTAssertEqual(globalReadiness["complete"] as? Bool, false)
    }

    func testHelperVerifyAllowsCycleFreshnessOnlyAsMaintenancePending() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let fake = try installFakeGBrainWithAutopilot(
            root: root,
            sourceId: "brain",
            localPath: target.path,
            cycleFreshnessUntilDream: true
        )
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
            environment: ["PATH": fake.bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: fake.bin.path,
            environment: ["HOME": root.path],
            arguments: [
                "verify",
                "--target", target.path,
                "--source-id", "brain",
                "--method", "user_created_repo",
            ]
        )

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        let payload = try helperPayload(result.stdout)
        XCTAssertEqual(payload["complete"] as? Bool, true)
        XCTAssertEqual(payload["status"] as? String, "verified_with_maintenance_pending")
        XCTAssertEqual(payload["doctorOk"] as? Bool, false)
        XCTAssertEqual(payload["doctorEffectiveOk"] as? Bool, true)
        XCTAssertEqual(payload["doctorFailedChecks"] as? [String], ["cycle_freshness"])
        XCTAssertEqual(payload["warnings"] as? [String], ["maintenance_pending:cycle_freshness"])
        let autoRecovery = try XCTUnwrap(payload["autoRecovery"] as? [String: Any])
        XCTAssertEqual(autoRecovery["ran"] as? Bool, false)
        XCTAssertEqual(autoRecovery["status"] as? String, "maintenance_pending")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fake.log.path))
        let receipt = try receiptTarget(in: stateURL, targetPath: target.path)
        XCTAssertEqual(receipt["complete"] as? Bool, true)
        XCTAssertEqual(receipt["status"] as? String, "verified_with_maintenance_pending")
        XCTAssertEqual(receipt["reasons"] as? [String], [])
        XCTAssertEqual(receipt["doctorFailedChecks"] as? [String], ["cycle_freshness"])
        XCTAssertEqual(receipt["warnings"] as? [String], ["maintenance_pending:cycle_freshness"])
        let doctorStatus = try XCTUnwrap(receipt["doctorStatus"] as? [String: Any])
        XCTAssertEqual(doctorStatus["status"] as? String, "failed")
        XCTAssertEqual(doctorStatus["failedChecks"] as? [String], ["cycle_freshness"])
        let syncProbe = try XCTUnwrap(receipt["syncProbeResult"] as? [String: Any])
        XCTAssertEqual(syncProbe["status"] as? String, "ok")
        let embeddingProbe = try XCTUnwrap(receipt["embeddingProbeResult"] as? [String: Any])
        XCTAssertEqual(embeddingProbe["status"] as? String, "ok")
        let searchProbe = try XCTUnwrap(receipt["searchProbeResult"] as? [String: Any])
        XCTAssertEqual(searchProbe["status"] as? String, "skipped_no_content")
    }

    func testHelperVerifyDoesNotDreamForUnexpectedDoctorBlocker() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let fake = try installFakeGBrainWithAutopilot(
            root: root,
            sourceId: "brain",
            localPath: target.path,
            cycleFreshnessUntilDream: true,
            extraDoctorBlocker: true
        )
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
            environment: ["PATH": fake.bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: fake.bin.path,
            environment: ["HOME": root.path],
            arguments: [
                "verify",
                "--target", target.path,
                "--source-id", "brain",
                "--method", "user_created_repo",
            ]
        )

        XCTAssertEqual(result.exitCode, 1, "stdout: \(result.stdout) stderr: \(result.stderr)")
        let payload = try helperPayload(result.stdout)
        XCTAssertEqual(payload["doctorFailedChecks"] as? [String], ["cycle_freshness", "embedding_freshness"])
        let autoRecovery = try XCTUnwrap(payload["autoRecovery"] as? [String: Any])
        XCTAssertEqual(autoRecovery["ran"] as? Bool, false)
        XCTAssertEqual(autoRecovery["status"] as? String, "unsupported_doctor_failed_checks")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fake.log.path))
    }

    func testHelperVerifyDoesNotDreamWhenVerifyInvocationHasAnotherBlocker() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let fake = try installFakeGBrainWithAutopilot(
            root: root,
            sourceId: "brain",
            localPath: target.path,
            cycleFreshnessUntilDream: true
        )
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
            environment: ["PATH": fake.bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: fake.bin.path,
            environment: ["HOME": root.path],
            arguments: [
                "verify",
                "--target", target.path,
                "--source-id", "brain",
                "--method", "invalid_method",
            ]
        )

        XCTAssertEqual(result.exitCode, 1, "stdout: \(result.stdout) stderr: \(result.stderr)")
        let payload = try helperPayload(result.stdout)
        XCTAssertEqual(payload["doctorFailedChecks"] as? [String], ["cycle_freshness"])
        XCTAssertEqual(payload["reasons"] as? [String], ["target_confirmation_missing", "doctor_failed"])
        let autoRecovery = try XCTUnwrap(payload["autoRecovery"] as? [String: Any])
        XCTAssertEqual(autoRecovery["ran"] as? Bool, false)
        XCTAssertEqual(autoRecovery["status"] as? String, "unsupported_doctor_failed_checks")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fake.log.path))
    }

    func testHelperVerifyDoesNotDreamWhenSourceProbeMismatches() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        let otherTarget = root.appendingPathComponent("other-brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherTarget, withIntermediateDirectories: true)
        let fake = try installFakeGBrainWithAutopilot(
            root: root,
            sourceId: "brain",
            localPath: target.path,
            listedLocalPath: otherTarget.path,
            cycleFreshnessUntilDream: true
        )
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
            environment: ["PATH": fake.bin.path]
        )
        _ = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))

        let result = try runHelper(
            stateURL: stateURL,
            path: fake.bin.path,
            environment: ["HOME": root.path],
            arguments: [
                "verify",
                "--target", target.path,
                "--source-id", "brain",
                "--method", "user_created_repo",
            ]
        )

        XCTAssertEqual(result.exitCode, 1, "stdout: \(result.stdout) stderr: \(result.stderr)")
        let payload = try helperPayload(result.stdout)
        XCTAssertEqual(payload["doctorFailedChecks"] as? [String], ["cycle_freshness"])
        let autoRecovery = try XCTUnwrap(payload["autoRecovery"] as? [String: Any])
        XCTAssertEqual(autoRecovery["ran"] as? Bool, false)
        XCTAssertEqual(autoRecovery["status"] as? String, "source_probe_not_verified")
        XCTAssertEqual(autoRecovery["reason"] as? String, "source_not_registered")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fake.log.path))
    }

    func testHelperVerifyFailsCycleFreshnessPendingWhenInstallProbesFail() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root)
        let target = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let bin = try installFakeGBrainWithOnlyCycleFreshnessFailure(
            root: root,
            localPath: target.path,
            supportsInstallProbes: false
        )
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
        let payload = try helperPayload(result.stdout)
        XCTAssertEqual(payload["complete"] as? Bool, false)
        XCTAssertEqual(payload["doctorOk"] as? Bool, false)
        XCTAssertEqual(payload["doctorEffectiveOk"] as? Bool, false)
        XCTAssertEqual(payload["doctorFailedChecks"] as? [String], ["cycle_freshness"])
        let autoRecovery = try XCTUnwrap(payload["autoRecovery"] as? [String: Any])
        XCTAssertEqual(autoRecovery["ran"] as? Bool, false)
        XCTAssertEqual(autoRecovery["status"] as? String, "maintenance_probe_failed")
        let reasons = payload["reasons"] as? [String] ?? []
        XCTAssertTrue(reasons.contains("sync_not_verified"))
        XCTAssertTrue(reasons.contains("stats_not_verified"))
        XCTAssertTrue(reasons.contains("embedding_not_verified"))
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
                "--topology", "pglite",
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
                "--topology", "pglite",
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
                "--section", "Step 3.6: Retrieval Budget",
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
                "--section", "Step 3.6: Retrieval Budget",
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
                "--section", "Step 3.6: Retrieval Budget",
            ]
        )
        let state = try stateObject(in: stateURL)
        let sectionRoles = try XCTUnwrap(state["sectionRoles"] as? [String: Any])

        XCTAssertEqual(mappingResult.exitCode, 0, "stdout: \(mappingResult.stdout) stderr: \(mappingResult.stderr)")
        XCTAssertEqual(retryResult.exitCode, 0, "stdout: \(retryResult.stdout) stderr: \(retryResult.stderr)")
        XCTAssertFalse(sectionRoles.isEmpty)
    }

    func testReportGuardRequiresDecisionForRecurringJobsButNotUpgradeTokenReuseSections() throws {
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
                "--topology", "pglite",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )

        let step7WithoutDecision = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
            ]
        )
        let step7WithDeferDecision = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "defer",
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

        XCTAssertNotEqual(step7WithoutDecision.exitCode, 0, "stdout: \(step7WithoutDecision.stdout) stderr: \(step7WithoutDecision.stderr)")
        XCTAssertTrue(step7WithoutDecision.stdout.contains("recurring_jobs_decision_required"), "stdout: \(step7WithoutDecision.stdout) stderr: \(step7WithoutDecision.stderr)")
        XCTAssertEqual(step7WithDeferDecision.exitCode, 0, "stdout: \(step7WithDeferDecision.stdout) stderr: \(step7WithDeferDecision.stderr)")
        XCTAssertEqual(upgrade.exitCode, 0, "stdout: \(upgrade.stdout) stderr: \(upgrade.stderr)")
        XCTAssertNotEqual(importStart.exitCode, 0)
        XCTAssertTrue(importStart.stdout.contains("search_mode_not_completed"), "stdout: \(importStart.stdout) stderr: \(importStart.stderr)")
    }

    func testRecurringJobsDecisionIsScopedByTargetPath() throws {
        let root = try makeTemporaryDirectory()
        let repo = try writeGuardDocs(root: root, includeTokenReuseNonRoleSections: true)
        let targetA = root.appendingPathComponent("brain-a", isDirectory: true)
        let targetB = root.appendingPathComponent("brain-b", isDirectory: true)
        try FileManager.default.createDirectory(at: targetA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetB, withIntermediateDirectories: true)
        let bin = try installFakeGBrain(root: root, sourceId: "brain", localPath: targetA.path, searchMode: nil)
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
                "--topology", "pglite",
                "--target", targetA.path,
                "--method", "user_created_repo",
            ]
        )
        let targetADecision = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "defer",
            ]
        )
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 3: Create the Brain",
                "--topology", "pglite",
                "--target", targetB.path,
                "--method", "user_created_repo",
            ]
        )
        let targetBWithoutDecision = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
            ]
        )
        let state = try stateObject(in: stateURL)
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let decisions = try XCTUnwrap(progress["recurringJobsDecisionByTarget"] as? [String: Any])

        XCTAssertEqual(targetADecision.exitCode, 0, "stdout: \(targetADecision.stdout) stderr: \(targetADecision.stderr)")
        XCTAssertNotNil(decisions["vault:\(targetA.path)"])
        XCTAssertNil(decisions["vault:\(targetB.path)"])
        XCTAssertNotEqual(targetBWithoutDecision.exitCode, 0, "stdout: \(targetBWithoutDecision.stdout) stderr: \(targetBWithoutDecision.stderr)")
        XCTAssertTrue(targetBWithoutDecision.stdout.contains("recurring_jobs_decision_required"), "stdout: \(targetBWithoutDecision.stdout) stderr: \(targetBWithoutDecision.stderr)")
    }

    func testReportGuardRejectsAutopilotInstallCompletionWhenLaunchdCannotRunBun() throws {
        let fixture = try prepareAutopilotInstallCompletionGuardFixture()

        let result = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "autopilot_install",
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("bun_missing_for_launchd_autopilot"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("repair_launchd_bun_path"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("repair-launchd-bun-path"), "stdout: \(result.stdout) stderr: \(result.stderr)")
    }

    func testCheckLaunchdBunPathFailsBeforeAutopilotInstallWhenLaunchdCannotRunBun() throws {
        let fixture = try prepareAutopilotInstallCompletionGuardFixture()

        let result = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: ["check-launchd-bun-path"]
        )

        XCTAssertNotEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(#""ok": false"#), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("bun_missing_for_launchd_autopilot"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("repair_launchd_bun_path"), "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("repair-launchd-bun-path"), "stdout: \(result.stdout) stderr: \(result.stderr)")
    }

    func testCheckLaunchdBunPathPassesAfterRepairBeforeAutopilotInstall() throws {
        let fixture = try prepareAutopilotInstallCompletionGuardFixture()
        try installFakeLaunchdBun(home: fixture.root)

        let before = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: ["check-launchd-bun-path"]
        )
        let repair = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: ["repair-launchd-bun-path"]
        )
        let after = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: ["check-launchd-bun-path"]
        )

        XCTAssertNotEqual(before.exitCode, 0, "stdout: \(before.stdout) stderr: \(before.stderr)")
        XCTAssertTrue(before.stdout.contains("bun_missing_for_launchd_autopilot"), "stdout: \(before.stdout) stderr: \(before.stderr)")
        XCTAssertEqual(repair.exitCode, 0, "stdout: \(repair.stdout) stderr: \(repair.stderr)")
        XCTAssertEqual(after.exitCode, 0, "stdout: \(after.stdout) stderr: \(after.stderr)")
        XCTAssertTrue(after.stdout.contains(#""status": "ready"#), "stdout: \(after.stdout) stderr: \(after.stderr)")
        XCTAssertTrue(after.stdout.contains(#""bunVersionOk": true"#), "stdout: \(after.stdout) stderr: \(after.stderr)")
    }

    func testReportGuardAllowsAutopilotInstallCompletionWhenLaunchdCanRunBun() throws {
        let fixture = try prepareAutopilotInstallCompletionGuardFixture()
        try installFakeLaunchdBun(home: fixture.root)
        try """
        export PATH="$HOME/.bun/bin:$PATH"
        """
        .write(to: fixture.root.appendingPathComponent(".zshenv", isDirectory: false), atomically: true, encoding: .utf8)

        let result = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "autopilot_install",
            ]
        )

        XCTAssertEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
    }

    func testRepairLaunchdBunPathAddsZshenvPathAndAllowsCompletion() throws {
        let fixture = try prepareAutopilotInstallCompletionGuardFixture()
        try installFakeLaunchdBun(home: fixture.root)
        let before = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "autopilot_install",
            ]
        )

        let repair = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: ["repair-launchd-bun-path"]
        )
        let after = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "autopilot_install",
            ]
        )
        let zshenv = try String(
            contentsOf: fixture.root.appendingPathComponent(".zshenv", isDirectory: false),
            encoding: .utf8
        )

        XCTAssertNotEqual(before.exitCode, 0, "stdout: \(before.stdout) stderr: \(before.stderr)")
        XCTAssertTrue(before.stdout.contains("bun_missing_for_launchd_autopilot"), "stdout: \(before.stdout) stderr: \(before.stderr)")
        XCTAssertEqual(repair.exitCode, 0, "stdout: \(repair.stdout) stderr: \(repair.stderr)")
        XCTAssertTrue(repair.stdout.contains(#""ok": true"#), "stdout: \(repair.stdout) stderr: \(repair.stderr)")
        XCTAssertTrue(repair.stdout.contains(#""bunVersionOk": true"#), "stdout: \(repair.stdout) stderr: \(repair.stderr)")
        XCTAssertTrue(zshenv.contains("Zebra GBrain launchd bun PATH"), zshenv)
        XCTAssertTrue(zshenv.contains(#"export PATH="$HOME/.bun/bin:$PATH""#), zshenv)
        XCTAssertEqual(after.exitCode, 0, "stdout: \(after.stdout) stderr: \(after.stderr)")
    }

    func testRepairLaunchdBunPathIsIdempotent() throws {
        let fixture = try prepareAutopilotInstallCompletionGuardFixture()
        try installFakeLaunchdBun(home: fixture.root)

        let first = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: ["repair-launchd-bun-path"]
        )
        let second = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: ["repair-launchd-bun-path"]
        )
        let zshenv = try String(
            contentsOf: fixture.root.appendingPathComponent(".zshenv", isDirectory: false),
            encoding: .utf8
        )
        let markerCount = zshenv.components(separatedBy: "# >>> Zebra GBrain launchd bun PATH >>>").count - 1

        XCTAssertEqual(first.exitCode, 0, "stdout: \(first.stdout) stderr: \(first.stderr)")
        XCTAssertEqual(second.exitCode, 0, "stdout: \(second.stdout) stderr: \(second.stderr)")
        XCTAssertEqual(markerCount, 1, zshenv)
        XCTAssertTrue(second.stdout.contains(#""zshenvUpdated": false"#), "stdout: \(second.stdout) stderr: \(second.stderr)")
    }

    func testRepairLaunchdBunPathIgnoresCommentedBunPath() throws {
        let fixture = try prepareAutopilotInstallCompletionGuardFixture()
        try installFakeLaunchdBun(home: fixture.root)
        let zshenvURL = fixture.root.appendingPathComponent(".zshenv", isDirectory: false)
        try """
        # export PATH="$HOME/.bun/bin:$PATH"
        """
        .write(to: zshenvURL, atomically: true, encoding: .utf8)

        let repair = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: ["repair-launchd-bun-path"]
        )
        let completed = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "autopilot_install",
            ]
        )
        let zshenv = try String(contentsOf: zshenvURL, encoding: .utf8)
        let markerCount = zshenv.components(separatedBy: "# >>> Zebra GBrain launchd bun PATH >>>").count - 1

        XCTAssertEqual(repair.exitCode, 0, "stdout: \(repair.stdout) stderr: \(repair.stderr)")
        XCTAssertTrue(repair.stdout.contains(#""zshenvUpdated": true"#), "stdout: \(repair.stdout) stderr: \(repair.stderr)")
        XCTAssertEqual(markerCount, 1, zshenv)
        XCTAssertEqual(completed.exitCode, 0, "stdout: \(completed.stdout) stderr: \(completed.stderr)")
    }

    func testRepairLaunchdBunPathFailsWhenBunMissing() throws {
        let fixture = try prepareAutopilotInstallCompletionGuardFixture()
        let zshenv = fixture.root.appendingPathComponent(".zshenv", isDirectory: false)

        let repair = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: ["repair-launchd-bun-path"]
        )

        XCTAssertNotEqual(repair.exitCode, 0, "stdout: \(repair.stdout) stderr: \(repair.stderr)")
        XCTAssertTrue(repair.stdout.contains("bun_missing"), "stdout: \(repair.stdout) stderr: \(repair.stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: zshenv.path))
    }

    func testReportGuardRejectsAutopilotInstallCompletionWhenBunVersionFails() throws {
        let fixture = try prepareAutopilotInstallCompletionGuardFixture()
        try installFakeLaunchdBun(home: fixture.root, versionExitCode: 64)
        try """
        export PATH="$HOME/.bun/bin:$PATH"
        """
        .write(to: fixture.root.appendingPathComponent(".zshenv", isDirectory: false), atomically: true, encoding: .utf8)

        let result = try runHelper(
            stateURL: fixture.stateURL,
            path: fixture.bin.path,
            arguments: [
                "report",
                "--status", "completed",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "autopilot_install",
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0, "stdout: \(result.stdout) stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("bun_unusable_for_launchd_autopilot"), "stdout: \(result.stdout) stderr: \(result.stderr)")
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
                "--topology", "pglite",
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
                "--section", "Step 3.6: Retrieval Budget",
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
                "--section", "Step 3.6: Retrieval Budget",
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
        complete: Bool = true,
        globalReadinessComplete: Bool = true,
        sourceVerification: Bool = false
    ) throws {
        let key = "vault:\((targetPath as NSString).standardizingPath)"
        let sourceVerificationJSON = sourceVerification
            ? """
                ,
                "sourceVerification": {
                  "sourceId": "\(sourceId)",
                  "targetPath": "\(targetPath)",
                  "verifiedAt": "2026-06-02T00:00:00Z",
                  "method": "sources_current_and_list",
                  "gbrainExecutablePath": null,
                  "gbrainVersion": "gbrain test"
                }
            """
            : ""
        let json = """
        {
          "schemaVersion": 1,
          "receipt": {
            "globalReadiness": {
              "complete": \(globalReadinessComplete ? "true" : "false")
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
                \(sourceVerificationJSON)
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

    private func writeRuntimeReceipt(stateURL: URL, runtime: String, executable: URL) throws {
        let runtimeStateURL = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let json = """
        {
          "schemaVersion": 1,
          "receipt": {
            "complete": true,
            "runtime": "\(runtime)",
            "executablePath": "\(executable.path)",
            "version": "test",
            "provider": "test",
            "keySource": "test",
            "checks": {
              "credentials": true,
              "runtimeConfigCommand": true,
              "llmCall": true
            },
            "reasons": []
          }
        }
        """
        try json.write(to: runtimeStateURL, atomically: true, encoding: .utf8)
    }

    private func recordRecurringJobsDecision(
        stateURL: URL,
        path: String,
        decision: String,
        section: String = "Step 7: Recurring Jobs"
    ) throws -> HelperRunResult {
        try runHelper(
            stateURL: stateURL,
            path: path,
            arguments: [
                "report",
                "--status", "started",
                "--section", section,
                "--recurring-jobs-decision", decision,
            ]
        )
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

    private func removeTopologyDecision(from stateURL: URL) throws {
        let data = try Data(contentsOf: stateURL)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var progress = try XCTUnwrap(object["progress"] as? [String: Any])
        progress.removeValue(forKey: "topologyDecision")
        object["progress"] = progress
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: stateURL, options: .atomic)
    }

    private func helperPayload(_ stdout: String) throws -> [String: Any] {
        let data = try XCTUnwrap(stdout.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func bootstrapPromptPath(from launcherScript: String) throws -> String {
        let prefix = "ZEBRA_GBRAIN_BOOTSTRAP_PROMPT_PATH='"
        guard let line = launcherScript
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix(prefix) && $0.hasSuffix("'") }) else {
            throw NSError(domain: "ZebraGBrainOnboardingStoreTests.promptPath", code: 1)
        }
        return String(line.dropFirst(prefix.count).dropLast())
    }

    private func launcherPrompt(from launcherStdout: String) throws -> String {
        let prefix = "export ZEBRA_GBRAIN_RUNTIME_LAUNCHER='"
        let launcherPath = String(
            launcherStdout
                .dropFirst(prefix.count)
                .split(separator: "'", maxSplits: 1)
                .first ?? ""
        )
        let script = try String(contentsOfFile: launcherPath, encoding: .utf8)
        let promptPath = try bootstrapPromptPath(from: script)
        return try String(contentsOfFile: promptPath, encoding: .utf8)
    }

    private struct HelperRunResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    private struct AutopilotInstallCompletionGuardFixture {
        var root: URL
        var stateURL: URL
        var bin: URL
    }

    private func prepareAutopilotInstallCompletionGuardFixture() throws -> AutopilotInstallCompletionGuardFixture {
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
                "--topology", "pglite",
                "--target", target.path,
                "--method", "user_created_repo",
            ]
        )
        _ = try runHelper(
            stateURL: stateURL,
            path: bin.path,
            arguments: [
                "report",
                "--status", "started",
                "--section", "Step 7: Recurring Jobs",
                "--recurring-jobs-decision", "autopilot_install",
            ]
        )
        return AutopilotInstallCompletionGuardFixture(root: root, stateURL: stateURL, bin: bin)
    }

    private func installFakeLaunchdBun(
        home: URL,
        versionExitCode: Int = 0
    ) throws {
        let bunBin = home
            .appendingPathComponent(".bun", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bunBin, withIntermediateDirectories: true)
        let bun = bunBin.appendingPathComponent("bun", isDirectory: false)
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "1.0.0"
          exit \(versionExitCode)
        fi
        exit 64
        """
        .write(to: bun, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bun.path)
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
                "Use Up/Down" { send "\(escapedReply)" }
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
        var arguments = [
            "report",
            "--status", "completed",
            "--section", "Step 2: API Keys",
            "--embedding-decision", decision,
        ]
        if decision == "provider_key" {
            arguments.append(contentsOf: [
                "--embedding-provider", "zeroentropy",
                "--embedding-key-env", "ZEROENTROPY_API_KEY",
            ])
        }
        return try runHelper(
            stateURL: stateURL,
            path: path,
            arguments: arguments
        )
    }

    private func writeGuardDocs(
        root: URL,
        includeRenamedSearchMode: Bool = false,
        includeTokenReuseNonRoleSections: Bool = false,
        includeRenamedRecurringJobs: Bool = false,
        includeCanonicalRecurringJobs: Bool = false
    ) throws -> URL {
        let repo = root.appendingPathComponent("gbrain-docs-source", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let searchModeSection = includeRenamedSearchMode
            ? """

            ## Step 3.6: Retrieval Budget

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
        let recurringJobsSection = includeRenamedRecurringJobs
            ? """

            ## Step 8: Background Sync

            Set up a persistent background service using your platform scheduler.
            Or use `gbrain autopilot --install --repo ~/brain`.
            """
            : ""
        let canonicalRecurringJobsSection = includeCanonicalRecurringJobs
            ? """

            ## Step 7: Recurring Jobs

            Set up using your platform's scheduler, or use `gbrain autopilot --install`.
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
        \(recurringJobsSection)
        \(canonicalRecurringJobsSection)

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

    private func writeFakePlatformRuntime(
        root: URL,
        runtime: String,
        initialStatus: String = "stopped",
        liveSyncTargetPath: String? = nil
    ) throws -> (bin: URL, executable: URL, log: URL) {
        let bin = root.appendingPathComponent("fake-\(runtime)-platform-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let executable = bin.appendingPathComponent(runtime, isDirectory: false)
        let log = root.appendingPathComponent("\(runtime)-platform.log", isDirectory: false)
        let ready = root.appendingPathComponent("\(runtime)-gateway-ready", isDirectory: false)
        if runtime == "hermes" {
            let python = bin.appendingPathComponent("python", isDirectory: false)
            let probeBlock: String
            switch initialStatus {
            case "running":
                probeBlock = """
                  echo '{"running": true, "pid": 123}'
                  exit 0
                """
            case "always-fail":
                probeBlock = """
                  echo '{"running": false, "pid": null}'
                  exit 0
                """
            default:
                probeBlock = """
                  if [ -f '\(ready.path)' ]; then
                    echo '{"running": true, "pid": 123}'
                    exit 0
                  fi
                  echo '{"running": false, "pid": null}'
                  exit 0
                """
            }
            try """
            #!/bin/sh
            set -eu
            printf 'hermes-python %s\\n' "$*" >> '\(log.path)'
            if [ "$1" = "-c" ]; then
            \(probeBlock)
            fi
            echo "unexpected hermes python args: $*" >&2
            exit 64
            """
            .write(to: python, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        }
        let statusBlock: String
        switch initialStatus {
        case "running":
            if runtime == "hermes" {
                statusBlock = """
                  if [ "$1" = "gateway" ] && [ "$2" = "status" ]; then
                    echo '✓ Gateway is running (PID: 123)'
                    exit 0
                  fi
                """
            } else {
                statusBlock = """
                  if [ "$1" = "gateway" ] && [ "$2" = "status" ]; then
                    echo '{"ready":true}'
                    exit 0
                  fi
                """
            }
        case "always-fail":
            if runtime == "hermes" {
                statusBlock = """
                  if [ "$1" = "gateway" ] && [ "$2" = "status" ]; then
                    echo '✗ Gateway is not running'
                    exit 0
                  fi
                """
            } else {
                statusBlock = """
                  if [ "$1" = "gateway" ] && [ "$2" = "status" ]; then
                    echo '{"ready":false}'
                    exit 1
                  fi
                """
            }
        default:
            if runtime == "hermes" {
                statusBlock = """
                  if [ "$1" = "gateway" ] && [ "$2" = "status" ]; then
                    if [ -f '\(ready.path)' ]; then
                      echo '✓ Gateway is running (PID: 123)'
                      exit 0
                    fi
                    echo '✗ Gateway is not running'
                    exit 0
                  fi
                """
            } else {
                statusBlock = """
                  if [ "$1" = "gateway" ] && [ "$2" = "status" ]; then
                    if [ -f '\(ready.path)' ]; then
                      echo '{"ready":true}'
                      exit 0
                    fi
                    echo '{"ready":false}'
                    exit 1
                  fi
                """
            }
        }
        let liveSyncCronBlock: String
        if runtime == "openclaw", let liveSyncTargetPath {
            let escapedTarget = liveSyncTargetPath.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            liveSyncCronBlock = """
            if [ "$1" = "cron" ] && [ "$2" = "list" ]; then
              echo '{"jobs":[{"name":"GBrain live sync","message":"Run: gbrain sync --repo \(escapedTarget) --yes && gbrain embed --stale, then run: gbrain status."},{"name":"GBrain auto-update","message":"Run: gbrain check-update --json."}]}'
              exit 0
            fi
            """
        } else {
            liveSyncCronBlock = ""
        }
        try """
        #!/bin/sh
        set -eu
        printf '\(runtime) %s\\n' "$*" >> '\(log.path)'
        \(statusBlock)
        \(liveSyncCronBlock)
        if [ "$1" = "gateway" ] && [ "$2" = "install" ]; then
          exit 0
        fi
        if [ "$1" = "gateway" ] && [ "$2" = "start" ]; then
          touch '\(ready.path)'
          exit 0
        fi
        echo "unexpected \(runtime) args: $*" >&2
        exit 64
        """
        .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executable.path
        )
        return (bin, executable, log)
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

    private func gitOutput(_ arguments: [String], cwd: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(stderrText)")
            throw NSError(domain: "ZebraGBrainOnboardingStoreTests.git", code: Int(process.terminationStatus))
        }
        return stdoutText
    }

    private func gitHeadCommit(in cwd: URL) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--verify", "HEAD"]
        process.currentDirectoryURL = cwd
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        let text = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : text.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func installFakeGBrainForStep7SaveReadiness(
        root: URL,
        sourceId: String,
        localPath: String,
        statusTimestampAfterSync: Bool = true
    ) throws -> (bin: URL, log: URL) {
        let bin = root.appendingPathComponent("fake-step7-gbrain-bin", isDirectory: true)
        let log = root.appendingPathComponent("step7-gbrain.log")
        let syncedMarker = root.appendingPathComponent("step7-live-sync.done")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        let escapedPath = localPath.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let statusTimestampBlock = statusTimestampAfterSync
            ? #""last_sync_at":"2026-06-21T00:00:00Z""#
            : #""last_sync_at":null"#
        try """
        #!/bin/sh
        set -eu
        printf 'gbrain %s\\n' "$*" >> '\(log.path)'
        if [ "$1" = "--version" ]; then
          echo "gbrain test"
          exit 0
        fi
        if [ "$1" = "sources" ] && [ "$2" = "current" ]; then
          echo '{"source_id":"\(sourceId)"}'
          exit 0
        fi
        if [ "$1" = "sources" ] && [ "$2" = "list" ]; then
          echo '{"sources":[{"id":"\(sourceId)","local_path":"\(escapedPath)"}]}'
          exit 0
        fi
        if [ "$1" = "sync" ]; then
          if [ "$2" = "--repo" ] && [ "$3" = "\(localPath)" ] && [ "$4" = "--yes" ]; then
            touch '\(syncedMarker.path)'
            echo '{"ok":true}'
            exit 0
          fi
          echo "unexpected sync args: $*" >&2
          exit 64
        fi
        if [ "$1" = "embed" ] && [ "$2" = "--stale" ]; then
          [ -f '\(syncedMarker.path)' ]
          echo '{"ok":true}'
          exit 0
        fi
        if [ "$1" = "status" ] && [ "$2" = "--json" ]; then
          if [ -f '\(syncedMarker.path)' ]; then
            echo '{"sync":{"sources":[{"id":"\(sourceId)","local_path":"\(escapedPath)",\(statusTimestampBlock)}]}}'
          else
            echo '{"sync":{"sources":[{"id":"\(sourceId)","local_path":"\(escapedPath)","last_sync_at":null}]}}'
          fi
          exit 0
        fi
        exit 1
        """
        .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (bin, log)
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

    private func installFakeGBrainWithPGLiteWasmSourceProbeFailure(root: URL) throws -> URL {
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
          echo "PGLite failed to initialize its WASM runtime." >&2
          echo "Most common cause: the macOS 26.3 WASM bug" >&2
          echo "Original error: Aborted()." >&2
          exit 1
        fi
        exit 1
        """
        .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return bin
    }

    private func installFakeGBrainWithAutopilot(
        root: URL,
        sourceId: String,
        localPath: String,
        listedLocalPath: String? = nil,
        releaseLockAfterUnload: Bool = true,
        doctorRequiresNoLock: Bool = false,
        restoreFails: Bool = false,
        malformedSourceList: Bool = false,
        cycleFreshnessUntilDream: Bool = false,
        extraDoctorBlocker: Bool = false
    ) throws -> (bin: URL, log: URL) {
        let bin = root.appendingPathComponent("fake-gbrain-bin", isDirectory: true)
        let log = root.appendingPathComponent("autopilot-calls.log")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        let launchctl = bin.appendingPathComponent("launchctl", isDirectory: false)
        let sourceListPath = listedLocalPath ?? localPath
        let escapedPath = sourceListPath.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let doctorLockCheck = doctorRequiresNoLock
            ? """
              if [ -f "$HOME/.gbrain/autopilot.lock" ]; then
                echo "GBrain: Timed out waiting for PGLite lock." >&2
                exit 1
              fi
            """
            : ""
        let unloadLockRelease = releaseLockAfterUnload
            ? """
              if [ "$1" = "unload" ]; then
                ( sleep 0.2; rm -f "$HOME/.gbrain/autopilot.lock" ) >/dev/null 2>&1 &
              fi
            """
            : ""
        let restoreExit = restoreFails
            ? """
              if [ "$1" = "load" ]; then
                exit 1
              fi
            """
            : ""
        let doctorBlock: String
        if cycleFreshnessUntilDream {
            doctorBlock = extraDoctorBlocker
                ? """
                  if [ "$1" = "doctor" ]; then
                    \(doctorLockCheck)
                    echo '{"checks":[{"name":"connection","status":"ok"},{"name":"cycle_freshness","status":"fail"},{"name":"embedding_freshness","status":"fail"}]}'
                    exit 1
                  fi
                """
                : """
                  if [ "$1" = "doctor" ]; then
                    \(doctorLockCheck)
                    if [ -f "$HOME/.gbrain/cycle.done" ]; then
                      echo '{"ok":true}'
                      exit 0
                    fi
                    echo '{"checks":[{"name":"connection","status":"ok"},{"name":"cycle_freshness","status":"fail"}]}'
                    exit 1
                  fi
                """
        } else {
            doctorBlock = """
              if [ "$1" = "doctor" ]; then
                \(doctorLockCheck)
                echo '{"ok":true}'
                exit 0
              fi
            """
        }
        let sourceListBlock = malformedSourceList
            ? """
              echo '{"sources":"bad"}'
              exit 0
            """
            : """
              echo '{"sources":[{"id":"\(sourceId)","local_path":"\(escapedPath)"}]}'
              exit 0
            """
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "gbrain test"
          exit 0
        fi
        \(doctorBlock)
        if [ "$1" = "dream" ]; then
          printf 'gbrain %s\\n' "$*" >> '\(log.path)'
          if [ "$2" = "--source" ] && [ "$3" = "\(sourceId)" ]; then
            mkdir -p "$HOME/.gbrain"
            touch "$HOME/.gbrain/cycle.done"
            echo '{"ok":true}'
            exit 0
          fi
          echo "Source not found" >&2
          exit 1
        fi
        if [ "$1" = "sources" ] && [ "$2" = "current" ]; then
          echo '{"source_id":"\(sourceId)"}'
          exit 0
        fi
        if [ "$1" = "sources" ] && [ "$2" = "list" ]; then
          \(sourceListBlock)
        fi
        if [ "$1" = "config" ] && [ "$2" = "get" ] && [ "$3" = "sync.last_run" ]; then
          echo "2026-06-02T00:00:00Z"
          exit 0
        fi
        if [ "$1" = "stats" ]; then
          echo "Pages:     1"
          echo "Chunks:    1"
          echo "Embedded:  1"
          echo "Links:     0"
          echo "Tags:      0"
          echo "Timeline:  0"
          exit 0
        fi
        if [ "$1" = "search" ]; then
          echo "[1.0000] note/test -- matched text"
          exit 0
        fi
        exit 1
        """
        .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try """
        #!/bin/sh
        printf 'launchctl %s\\n' "$*" >> '\(log.path)'
        \(unloadLockRelease)
        \(restoreExit)
        exit 0
        """
        .write(to: launchctl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launchctl.path)
        return (bin, log)
    }

    private func installLocalPGLiteAutopilotFixture(root: URL) throws {
        let gbrainHome = root.appendingPathComponent(".gbrain", isDirectory: true)
        try FileManager.default.createDirectory(at: gbrainHome, withIntermediateDirectories: true)
        try #"{"engine":"pglite","database_path":"brain.pglite"}"#.write(
            to: gbrainHome.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8
        )
        try "\(ProcessInfo.processInfo.processIdentifier)\n".write(to: gbrainHome.appendingPathComponent("autopilot.lock"), atomically: true, encoding: .utf8)
        let launchAgents = root
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        try "<plist />\n".write(
            to: launchAgents.appendingPathComponent("com.gbrain.autopilot.plist"),
            atomically: true,
            encoding: .utf8
        )
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
        if [ "$1" = "config" ] && [ "$2" = "get" ] && [ "$3" = "sync.last_run" ]; then
          echo "2026-06-02T00:00:00Z"
          exit 0
        fi
        if [ "$1" = "stats" ]; then
          echo "Pages:     1"
          echo "Chunks:    1"
          echo "Embedded:  1"
          echo "Links:     0"
          echo "Tags:      0"
          echo "Timeline:  0"
          exit 0
        fi
        if [ "$1" = "search" ]; then
          echo "[1.0000] note/test -- matched text"
          exit 0
        fi
        exit 1
        """
        .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return bin
    }

    private func installFakeGBrainWithOnlyCycleFreshnessFailure(
        root: URL,
        localPath: String,
        supportsInstallProbes: Bool = true,
        doctorChecksJSON: String = #"{"checks":[{"name":"connection","status":"ok"},{"name":"cycle_freshness","status":"fail","message":"Source has never completed a full cycle"}]}"#,
        doctorCallLogPath: String? = nil,
        successMarkerPath: String? = nil
    ) throws -> URL {
        let bin = root.appendingPathComponent("fake-gbrain-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        let doctorCallLogBlock = doctorCallLogPath.map { path in
            """
              printf 'doctor\\n' >> '\(path)'
            """
        } ?? ""
        let doctorSuccessBlock = successMarkerPath.map { path in
            """
              if [ -f '\(path)' ]; then
                echo '{"ok":true}'
                exit 0
              fi
            """
        } ?? ""
        let probeBlock: String
        if supportsInstallProbes {
            probeBlock = """
            if [ "$1" = "config" ] && [ "$2" = "get" ] && [ "$3" = "sync.last_run" ]; then
              echo "2026-06-02T00:00:00Z"
              exit 0
            fi
            if [ "$1" = "stats" ]; then
              echo "Pages:     1"
              echo "Chunks:    1"
              echo "Embedded:  1"
              echo "Links:     0"
              echo "Tags:      0"
              echo "Timeline:  0"
              exit 0
            fi
            if [ "$1" = "search" ]; then
              echo "[1.0000] note/test -- matched text"
              exit 0
            fi
            """
        } else {
            probeBlock = ""
        }
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "gbrain test"
          exit 0
        fi
        if [ "$1" = "doctor" ]; then
        \(doctorCallLogBlock)
        \(doctorSuccessBlock)
          echo '\(doctorChecksJSON)'
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
        \(probeBlock)
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

    private func writeStructuredWaitingForUser(
        _ stateURL: URL,
        section: String,
        reason: String
    ) throws {
        let data = try Data(contentsOf: stateURL)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var progress = try XCTUnwrap(object["progress"] as? [String: Any])
        progress["waitingForUser"] = [
            "section": section,
            "reason": reason,
            "note": reason,
            "createdAt": "2026-06-12T00:00:00Z",
        ]
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
