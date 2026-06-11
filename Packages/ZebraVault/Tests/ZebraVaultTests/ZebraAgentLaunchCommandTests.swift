import XCTest
@testable import ZebraVault

final class ZebraAgentLaunchCommandTests: XCTestCase {
    func testCodexOnboardingLaunchStartsInteractiveCliWithoutPrompt() {
        let line = ZebraAgentLaunchCommand.shellStartupLine(
            agent: .codex,
            cwd: "/tmp/work dir",
            systemPrompt: "System context",
            userPrompt: "What is 'next'?"
        )

        XCTAssertEqual(line, "cd '/tmp/work dir' && codex\r")
        XCTAssertFalse(line.contains("System context"))
        XCTAssertFalse(line.contains("What is"))
    }

    func testClaudeOnboardingLaunchStartsInteractiveCliWithoutPrompt() {
        let line = ZebraAgentLaunchCommand.shellStartupLine(
            agent: .claude,
            cwd: "/tmp/work",
            systemPrompt: "Zebra setup",
            userPrompt: "Continue\nnow"
        )

        XCTAssertEqual(
            line,
            "cd '/tmp/work' && claude\r"
        )
        XCTAssertFalse(line.contains("--append-system-prompt"))
        XCTAssertFalse(line.contains("Zebra setup"))
    }

    func testAntigravityOnboardingLaunchStartsInteractiveCliWithoutPrompt() {
        let line = ZebraAgentLaunchCommand.shellStartupLine(
            agent: .antigravity,
            cwd: "/tmp/work",
            systemPrompt: "Zebra setup",
            userPrompt: "Continue"
        )

        XCTAssertEqual(
            line,
            "cd '/tmp/work' && agy\r"
        )
        XCTAssertFalse(line.contains("--prompt-interactive"))
        XCTAssertFalse(line.contains("--add-dir"))
        XCTAssertFalse(line.contains("Zebra setup"))
    }

    func testChatPillAntigravityLaunchUsesInteractivePromptAndAddDir() throws {
        let cwd = try makeTemporaryDirectory()

        let line = MarkdownChatPillCommand.shellStartupLine(
            agent: .antigravity,
            markdownFilePath: nil,
            surface: .fallback(typeLabel: "general"),
            userPrompt: "Check this",
            launchDirectory: cwd.path
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && agy --prompt-interactive --add-dir '\(cwd.path)' '"))
        XCTAssertFalse(line.contains(" --cwd "))
        XCTAssertFalse(line.contains("agy -p"))
        XCTAssertFalse(line.contains("gemini"))
    }

    func testGBrainCodexLaunchUsesAutoReviewWithoutDroppingTrustOverride() throws {
        let cwd = try makeTemporaryDirectory()

        let line = MarkdownChatPillCommand.shellStartupLineForGBrainSetup(
            agent: .codex,
            cwd: cwd.path,
            userPrompt: "Set up GBrain"
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && codex"))
        XCTAssertTrue(line.contains("-C '\(cwd.path)'"))
        XCTAssertTrue(line.contains("--sandbox workspace-write"))
        XCTAssertTrue(line.contains("--ask-for-approval on-request"))
        XCTAssertTrue(line.contains("'approvals_reviewer=\"auto_review\"'"))
        XCTAssertTrue(line.contains("'projects.\"\(cwd.path)\".trust_level=\"trusted\"'"))
        XCTAssertFalse(line.contains("\r\r"))
    }

    func testGBrainCodexSetupPersistsAutoReviewConfigAndProjectTrust() throws {
        let cwd = try makeTemporaryDirectory()
        let configURL = try makeTemporaryDirectory()
            .appendingPathComponent("config.toml", isDirectory: false)

        XCTAssertTrue(MarkdownChatPillCommand.prepareCodexGBrainSetupConfig(
            cwd: cwd.path,
            configURL: configURL
        ))
        XCTAssertTrue(MarkdownChatPillCommand.prepareCodexGBrainSetupConfig(
            cwd: cwd.path,
            configURL: configURL
        ))

        let raw = try String(contentsOf: configURL, encoding: .utf8)
        let section = "[projects.\"\(cwd.path)\"]"
        XCTAssertEqual(raw.components(separatedBy: "approvals_reviewer = \"auto_review\"").count - 1, 1)
        XCTAssertEqual(raw.components(separatedBy: section).count - 1, 1)
        XCTAssertTrue(raw.contains("trust_level = \"trusted\""))
        XCTAssertFalse(raw.contains("dangerously-bypass"))
    }

    func testGBrainCodexSetupReplacesExistingAutoReviewAndUntrustedProject() throws {
        let cwd = try makeTemporaryDirectory()
        let configURL = try makeTemporaryDirectory()
            .appendingPathComponent("config.toml", isDirectory: false)
        try """
        model = "gpt-5"
        approvals_reviewer = "manual"

        [projects.\"\(cwd.path)\"]
        trust_level = "untrusted"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(MarkdownChatPillCommand.prepareCodexGBrainSetupConfig(
            cwd: cwd.path,
            configURL: configURL
        ))

        let raw = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("model = \"gpt-5\""))
        XCTAssertTrue(raw.contains("approvals_reviewer = \"auto_review\""))
        XCTAssertTrue(raw.contains("[projects.\"\(cwd.path)\"]"))
        XCTAssertTrue(raw.contains("trust_level = \"trusted\""))
        XCTAssertFalse(raw.contains("approvals_reviewer = \"manual\""))
        XCTAssertFalse(raw.contains("trust_level = \"untrusted\""))
    }

    func testGBrainRuntimeCodexLaunchPersistsAutoReviewConfigWithoutApprovalPolicy() throws {
        let cwd = try makeTemporaryDirectory()
        let configURL = try makeTemporaryDirectory()
            .appendingPathComponent("config.toml", isDirectory: false)
        let launch = ZebraGBrainRuntimeOnboardingStore.LaunchContext(
            launchDirectory: cwd.path,
            startupLine: "",
            startupPrompt: "Set up Step 2 runtime",
            helperPath: "/tmp/zebra-gbrain-runtime-onboarding",
            documentPath: "/tmp/gbrain-runtime-agent-onboarding.md",
            shellEnvironmentPrefix: "export ZEBRA_GBRAIN_RUNTIME_STATE='/tmp/state.json' && "
        )

        let line = ZebraOnboardingChecklistCommand.gbrainRuntimeStartupLine(
            launch: launch,
            agent: .codex,
            codexConfigURL: configURL
        )

        let raw = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("approvals_reviewer = \"auto_review\""))
        XCTAssertTrue(raw.contains("[projects.\"\(cwd.path)\"]"))
        XCTAssertTrue(raw.contains("trust_level = \"trusted\""))
        XCTAssertFalse(raw.contains("approval_policy"))
        XCTAssertTrue(line.contains("--ask-for-approval on-request"))
        XCTAssertTrue(line.contains("'approvals_reviewer=\"auto_review\"'"))
    }

    func testGBrainRuntimeNonCodexLaunchDoesNotWriteCodexAutoReviewConfig() throws {
        let cwd = try makeTemporaryDirectory()
        let configURL = try makeTemporaryDirectory()
            .appendingPathComponent("config.toml", isDirectory: false)
        let launch = ZebraGBrainRuntimeOnboardingStore.LaunchContext(
            launchDirectory: cwd.path,
            startupLine: "",
            startupPrompt: "Set up Step 2 runtime",
            helperPath: "/tmp/zebra-gbrain-runtime-onboarding",
            documentPath: "/tmp/gbrain-runtime-agent-onboarding.md",
            shellEnvironmentPrefix: ""
        )

        let line = ZebraOnboardingChecklistCommand.gbrainRuntimeStartupLine(
            launch: launch,
            agent: .claude,
            codexConfigURL: configURL
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
        XCTAssertTrue(line.contains("claude --permission-mode auto"))
    }

    func testGBrainCodexLaunchWithoutSelectedVaultDisablesTrustedAutomation() throws {
        let cwd = try makeTemporaryDirectory()

        let line = MarkdownChatPillCommand.shellStartupLineForGBrainSetup(
            agent: .codex,
            cwd: cwd.path,
            userPrompt: "Set up GBrain",
            allowTrustedAutomation: false
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && codex"))
        XCTAssertTrue(line.contains("-C '\(cwd.path)'"))
        XCTAssertFalse(line.contains("--sandbox workspace-write"))
        XCTAssertTrue(line.contains("--ask-for-approval on-request"))
        XCTAssertTrue(line.contains("'approvals_reviewer=\"auto_review\"'"))
        XCTAssertFalse(line.contains("trust_level=\"trusted\""))
        XCTAssertFalse(line.contains("\r\r"))
    }

    func testGBrainCodexLaunchCanTrustSafeWorkdirWithoutTrustedAutomation() throws {
        let cwd = try makeTemporaryDirectory()

        let line = MarkdownChatPillCommand.shellStartupLineForGBrainSetup(
            agent: .codex,
            cwd: cwd.path,
            userPrompt: "Set up GBrain",
            allowTrustedAutomation: false,
            allowLaunchDirectoryTrust: true
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && codex"))
        XCTAssertTrue(line.contains("-C '\(cwd.path)'"))
        XCTAssertFalse(line.contains("--sandbox workspace-write"))
        XCTAssertTrue(line.contains("--ask-for-approval on-request"))
        XCTAssertTrue(line.contains("'approvals_reviewer=\"auto_review\"'"))
        XCTAssertTrue(line.contains("'projects.\"\(cwd.path)\".trust_level=\"trusted\"'"))
        XCTAssertFalse(line.contains("\r\r"))
    }

    func testGBrainClaudeLaunchUsesAutoPermissionModeWithSystemPrompt() throws {
        let cwd = try makeTemporaryDirectory()

        let line = MarkdownChatPillCommand.shellStartupLineForGBrainSetup(
            agent: .claude,
            cwd: cwd.path,
            userPrompt: "Set up GBrain"
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && claude --permission-mode auto --append-system-prompt"))
        XCTAssertTrue(line.contains("'Set up GBrain'"))
        XCTAssertFalse(line.contains("\r\r"))
    }

    func testGBrainClaudeLaunchWithoutSelectedVaultDisablesAutoPermission() throws {
        let cwd = try makeTemporaryDirectory()

        let line = MarkdownChatPillCommand.shellStartupLineForGBrainSetup(
            agent: .claude,
            cwd: cwd.path,
            userPrompt: "Set up GBrain",
            allowTrustedAutomation: false
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && claude --append-system-prompt"))
        XCTAssertFalse(line.contains("--permission-mode auto"))
        XCTAssertFalse(line.contains("\r\r"))
    }

    func testClawvisorCodexOnboardingLaunchCarriesPrompt() throws {
        let cwd = try makeTemporaryDirectory()

        let line = ZebraClawvisorOnboardingCommand.shellStartupLine(
            agent: .codex,
            launchDirectory: cwd.path
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && codex -C '\(cwd.path)'"))
        XCTAssertTrue(line.contains("-c 'projects.\"\(cwd.path)\".trust_level=\"trusted\"'"))
        XCTAssertTrue(line.contains("using Codex"))
        XCTAssertTrue(line.contains("CLAWVISOR_GMAIL_TASK_ID"))
        XCTAssertFalse(line.contains("claude --append-system-prompt"))
        XCTAssertFalse(line.contains("dangerously-bypass"))
    }

    func testClawvisorCodexOnboardingPersistsFolderTrust() throws {
        let cwd = try makeTemporaryDirectory()
        let configURL = try makeTemporaryDirectory()
            .appendingPathComponent("config.toml", isDirectory: false)

        XCTAssertTrue(ZebraClawvisorOnboardingCommand.markCodexProjectTrusted(
            cwd: cwd.path,
            configURL: configURL
        ))
        XCTAssertTrue(ZebraClawvisorOnboardingCommand.markCodexProjectTrusted(
            cwd: cwd.path,
            configURL: configURL
        ))

        let raw = try String(contentsOf: configURL, encoding: .utf8)
        let section = "[projects.\"\(cwd.path)\"]"
        XCTAssertEqual(raw.components(separatedBy: section).count - 1, 1)
        XCTAssertTrue(raw.contains(section))
        XCTAssertTrue(raw.contains("trust_level = \"trusted\""))
        XCTAssertFalse(raw.contains("dangerously-bypass"))
    }

    func testClawvisorCodexLaunchPlanReportsReadyWhenTrustIsWritten() throws {
        let cwd = try makeTemporaryDirectory()
        let configURL = try makeTemporaryDirectory()
            .appendingPathComponent("config.toml", isDirectory: false)
        let onboardingDirectoryURL = try makeTemporaryDirectory()

        let plan = ZebraClawvisorOnboardingCommand.launchPlan(
            agent: .codex,
            launchDirectory: cwd.path,
            codexConfigURL: configURL,
            onboardingDirectoryURL: onboardingDirectoryURL
        )

        let raw = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(plan.launchEnvironmentReady)
        XCTAssertTrue(raw.contains("[projects.\"\(cwd.path)\"]"))
        XCTAssertTrue(raw.contains("trust_level = \"trusted\""))
    }

    func testClawvisorCodexLaunchPlanReportsNotReadyWhenTrustCannotBeWritten() throws {
        let cwd = try makeTemporaryDirectory()
        let configURL = try makeTemporaryDirectory()
            .appendingPathComponent("config.toml", isDirectory: true)
        let onboardingDirectoryURL = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)

        let plan = ZebraClawvisorOnboardingCommand.launchPlan(
            agent: .codex,
            launchDirectory: cwd.path,
            codexConfigURL: configURL,
            onboardingDirectoryURL: onboardingDirectoryURL
        )

        XCTAssertFalse(plan.launchEnvironmentReady)
        XCTAssertTrue(plan.startupLine.contains("codex"))
    }

    func testClawvisorEmailFlowKindUsesOpenClawRuntimeOverPrimaryAgent() {
        let runtime = ZebraGBrainRuntimeOnboardingStore.SelectedRuntime(
            runtime: "openclaw",
            executablePath: "/tmp/openclaw"
        )

        XCTAssertEqual(
            ZebraClawvisorOnboardingCommand.resolveFlowKind(agent: .claude, selectedRuntime: runtime),
            .openClaw
        )
        XCTAssertEqual(
            ZebraClawvisorOnboardingCommand.resolveFlowKind(agent: .codex, selectedRuntime: runtime),
            .openClaw
        )
    }

    func testClawvisorEmailFlowKindTreatsHermesRuntimeAsPrimaryAgentFlow() {
        let runtime = ZebraGBrainRuntimeOnboardingStore.SelectedRuntime(
            runtime: "hermes",
            executablePath: "/tmp/hermes"
        )

        XCTAssertEqual(
            ZebraClawvisorOnboardingCommand.resolveFlowKind(agent: .claude, selectedRuntime: runtime),
            .claudeCode
        )
        XCTAssertEqual(
            ZebraClawvisorOnboardingCommand.resolveFlowKind(agent: .codex, selectedRuntime: runtime),
            .genericAgent
        )
    }

    func testClawvisorLaunchPlanWritesSetupPacketStateAndHelper() throws {
        let cwd = try makeTemporaryDirectory()
        let configURL = try makeTemporaryDirectory()
            .appendingPathComponent("config.toml", isDirectory: false)
        let onboardingDirectoryURL = try makeTemporaryDirectory()
        let runtime = ZebraGBrainRuntimeOnboardingStore.SelectedRuntime(
            runtime: "openclaw",
            executablePath: "/tmp/openclaw"
        )

        let plan = ZebraClawvisorOnboardingCommand.launchPlan(
            agent: .codex,
            launchDirectory: cwd.path,
            codexConfigURL: configURL,
            onboardingDirectoryURL: onboardingDirectoryURL,
            selectedRuntime: runtime
        )

        let setupPacketPath = try XCTUnwrap(plan.setupPacketPath)
        let setupPacket = try String(contentsOfFile: setupPacketPath, encoding: .utf8)
        XCTAssertEqual(plan.flowKind, .openClaw)
        XCTAssertTrue(setupPacket.contains("Clawvisor email flow kind: openClaw"))
        XCTAssertTrue(setupPacket.contains("GBrain runtime receipt: openclaw"))
        XCTAssertTrue(setupPacket.contains("OpenClaw integration"))
        XCTAssertTrue(plan.startupLine.contains("zebra-clawvisor-email-onboarding"))
        XCTAssertTrue(plan.startupLine.contains(setupPacketPath))

        let stateData = try Data(contentsOf: URL(fileURLWithPath: plan.statePath))
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: stateData) as? [String: Any])
        XCTAssertEqual(state["primaryAgent"] as? String, "codex")
        XCTAssertEqual(state["selectedRuntime"] as? String, "openclaw")
        XCTAssertEqual(state["flowKind"] as? String, "openClaw")
        XCTAssertEqual(state["completedSections"] as? [String], [])

        XCTAssertEqual(try octalPermissions(atPath: setupPacketPath), 0o600)
        XCTAssertEqual(try octalPermissions(atPath: plan.statePath), 0o600)
        XCTAssertEqual(
            try octalPermissions(
                atPath: onboardingDirectoryURL
                    .appendingPathComponent("bin/zebra-clawvisor-email-onboarding")
                    .path
            ),
            0o755
        )
    }

    func testClawvisorCodexOnboardingReplacesExistingUntrustedFolderEntry() throws {
        let cwd = try makeTemporaryDirectory()
        let configURL = try makeTemporaryDirectory()
            .appendingPathComponent("config.toml", isDirectory: false)
        try """
        model = "gpt-5"

        [projects.\"\(cwd.path)\"]
        trust_level = "untrusted"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(ZebraClawvisorOnboardingCommand.markCodexProjectTrusted(
            cwd: cwd.path,
            configURL: configURL
        ))

        let raw = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("[projects.\"\(cwd.path)\"]"))
        XCTAssertTrue(raw.contains("trust_level = \"trusted\""))
        XCTAssertFalse(raw.contains("trust_level = \"untrusted\""))
    }

    func testClawvisorAntigravityOnboardingLaunchCarriesPrompt() throws {
        let cwd = try makeTemporaryDirectory()

        let line = ZebraClawvisorOnboardingCommand.shellStartupLine(
            agent: .antigravity,
            launchDirectory: cwd.path
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && agy --prompt-interactive --add-dir '\(cwd.path)'"))
        XCTAssertTrue(line.contains("using Antigravity"))
        XCTAssertTrue(line.contains("CLAWVISOR_GMAIL_TASK_ID"))
        XCTAssertFalse(line.contains("claude --append-system-prompt"))
    }

    func testClawvisorReadyPrimaryRequiresSavedInstalledAndConfiguredAgent() {
        let preferences = ZebraAgentPreferences(primaryAgent: .codex)

        XCTAssertEqual(
            ZebraClawvisorOnboardingCommand.readyPrimaryAgent(
                preferences: preferences,
                candidates: [agentCandidate(id: .codex, installState: .installed, authState: .configPresent)]
            ),
            .codex
        )
        XCTAssertNil(ZebraClawvisorOnboardingCommand.readyPrimaryAgent(
            preferences: ZebraAgentPreferences(primaryAgent: nil),
            candidates: [agentCandidate(id: .codex, installState: .installed, authState: .configPresent)]
        ))
        XCTAssertNil(ZebraClawvisorOnboardingCommand.readyPrimaryAgent(
            preferences: preferences,
            candidates: [agentCandidate(id: .codex, installState: .missing, authState: .configPresent)]
        ))
        XCTAssertNil(ZebraClawvisorOnboardingCommand.readyPrimaryAgent(
            preferences: preferences,
            candidates: [agentCandidate(id: .codex, installState: .installed, authState: .unknown)]
        ))
    }

    func testOnboardingStartupCommandRunsScriptWithCwd() {
        let line = ZebraAgentOnboardingStartup.shellStartupLine(
            scriptPath: "/Applications/Zebra.app/Contents/Resources/zebra-agent-onboarding",
            cwd: "/Users/han/zebra phase3",
            languageCode: "en"
        )

        XCTAssertEqual(
            line,
            "'/Applications/Zebra.app/Contents/Resources/zebra-agent-onboarding' 'run' '--cwd' '/Users/han/zebra phase3' '--language' 'en'\n"
        )
    }

    func testOnboardingStartupCommandQuotesSingleQuotes() {
        let line = ZebraAgentOnboardingStartup.shellStartupLine(
            scriptPath: "/tmp/zebra-agent-onboarding",
            cwd: "/Users/han/project/it's-zebra",
            languageCode: "ko-KR"
        )

        XCTAssertEqual(
            line,
            "'/tmp/zebra-agent-onboarding' 'run' '--cwd' '/Users/han/project/it'\\''s-zebra' '--language' 'ko'\n"
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZebraAgentLaunchCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url.standardizedFileURL
    }

    private func agentCandidate(
        id: ZebraAgentKind,
        installState: ZebraAgentInstallState,
        authState: ZebraAgentAuthState
    ) -> ZebraAgentInstallCandidate {
        ZebraAgentInstallCandidate(
            id: id,
            displayName: id.displayName,
            binaryName: id.binaryName,
            executablePath: installState == .installed ? "/usr/local/bin/\(id.binaryName)" : nil,
            appBundlePath: nil,
            version: nil,
            installState: installState,
            authState: authState,
            terminalLaunchable: installState == .installed,
            recommendedAction: installState == .installed ? .launch : .install
        )
    }

    private func octalPermissions(atPath path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue & 0o777
    }
}
