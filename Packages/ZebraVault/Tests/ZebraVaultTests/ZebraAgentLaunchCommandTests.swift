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
        XCTAssertFalse(line.contains("--model"))
        XCTAssertFalse(line.contains("\r\r"))
    }

    func testGBrainCodexLaunchCanCarryExplicitModel() throws {
        let cwd = try makeTemporaryDirectory()

        let line = MarkdownChatPillCommand.shellStartupLineForGBrainSetup(
            agent: .codex,
            cwd: cwd.path,
            userPrompt: "Set up GBrain",
            model: "gpt-5.5"
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && codex"))
        XCTAssertTrue(line.contains("--model 'gpt-5.5'"))
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
        XCTAssertTrue(line.contains("--model 'gpt-5.5'"))
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
        XCTAssertTrue(line.contains("claude --permission-mode auto --model 'opus'"))
    }

    func testChainedGBrainRuntimeCommandFileUsesInjectedAgentExecutable() throws {
        let cwd = try makeTemporaryDirectory()
        let commandFileURL = try makeTemporaryDirectory()
            .appendingPathComponent("chained-step2-command.sh", isDirectory: false)
        let launch = ZebraGBrainRuntimeOnboardingStore.LaunchContext(
            launchDirectory: cwd.path,
            startupLine: "",
            startupPrompt: "Set up Step 2 runtime",
            helperPath: "/tmp/zebra-gbrain-runtime-onboarding",
            documentPath: "/tmp/gbrain-runtime-agent-onboarding.md",
            shellEnvironmentPrefix: "export ZEBRA_GBRAIN_RUNTIME_STATE='/tmp/state.json' && "
        )

        XCTAssertTrue(ZebraOnboardingChecklistCommand.writeChainedGBrainRuntimeCommandFile(
            launch: launch,
            commandFileURL: commandFileURL
        ))

        let raw = try String(contentsOf: commandFileURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("case \"${ZEBRA_SELECTED_AGENT}\" in"))
        XCTAssertTrue(raw.contains("claude)"))
        XCTAssertTrue(raw.contains("codex)"))
        XCTAssertTrue(raw.contains("antigravity)"))
        XCTAssertTrue(raw.contains("\"$ZEBRA_AGENT_EXECUTABLE\" --permission-mode auto"))
        XCTAssertTrue(raw.contains("\"$ZEBRA_AGENT_EXECUTABLE\" --permission-mode auto --model 'opus'"))
        XCTAssertTrue(raw.contains("\"$ZEBRA_AGENT_EXECUTABLE\" -C '\(cwd.path)'"))
        XCTAssertTrue(raw.contains("\"$ZEBRA_AGENT_EXECUTABLE\" -C '\(cwd.path)' --model 'gpt-5.5'"))
        XCTAssertTrue(raw.contains("\"$ZEBRA_AGENT_EXECUTABLE\" --prompt-interactive"))
        XCTAssertFalse(raw.contains("\r"))
        XCTAssertEqual(try octalPermissions(atPath: commandFileURL.path), 0o600)
    }

    func testChainedGBrainRuntimeCodexCommandDoesNotPersistCodexConfigDuringGeneration() throws {
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
            agent: .codex,
            codexConfigURL: configURL,
            executableShellExpression: "\"$ZEBRA_AGENT_EXECUTABLE\"",
            shouldPrepareCodexGBrainSetupConfig: false
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
        XCTAssertTrue(line.contains("\"$ZEBRA_AGENT_EXECUTABLE\" -C '\(cwd.path)'"))
        XCTAssertTrue(line.contains("--model 'gpt-5.5'"))
        XCTAssertTrue(line.contains("--ask-for-approval on-request"))
        XCTAssertTrue(line.contains("'approvals_reviewer=\"auto_review\"'"))
        XCTAssertTrue(line.contains("'projects.\"\(cwd.path)\".trust_level=\"trusted\"'"))
    }

    func testAgentOnboardingScriptCommandQuotesContinueCommandFile() {
        let line = ZebraAgentOnboardingScriptCommand.shellStartupLine(
            scriptPath: "/tmp/zebra-agent-onboarding",
            command: .run,
            cwd: "/Users/han/project/it's-zebra",
            languageCode: "ko-KR",
            continueWithCommandFile: "/Users/han/Library/Application Support/zebra/onboarding/chained step2.sh"
        )

        XCTAssertEqual(
            line,
            "'/tmp/zebra-agent-onboarding' 'run' '--cwd' '/Users/han/project/it'\\''s-zebra' '--language' 'ko' '--continue-with-command-file' '/Users/han/Library/Application Support/zebra/onboarding/chained step2.sh'\r"
        )
    }

    func testAgentPreferencesRoundTripPrimaryExecutablePath() throws {
        let preferencesURL = try makeTemporaryDirectory()
            .appendingPathComponent("preferences.json", isDirectory: false)
        let store = ZebraAgentPreferenceStore(fileURL: preferencesURL)

        try store.save(ZebraAgentPreferences(
            primaryAgent: .codex,
            primaryAgentExecutablePath: "/opt/homebrew/bin/codex",
            updatedBy: "test"
        ))

        let loaded = store.load()
        XCTAssertEqual(loaded.primaryAgent, .codex)
        XCTAssertEqual(loaded.primaryAgentExecutablePath, "/opt/homebrew/bin/codex")
        XCTAssertEqual(loaded.updatedBy, "test")
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
        XCTAssertFalse(line.contains("--model"))
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
        XCTAssertFalse(line.contains("--model"))
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
        XCTAssertFalse(line.contains("--model"))
        XCTAssertFalse(line.contains("\r\r"))
    }

    func testGBrainClaudeLaunchCanCarryExplicitModel() throws {
        let cwd = try makeTemporaryDirectory()

        let line = MarkdownChatPillCommand.shellStartupLineForGBrainSetup(
            agent: .claude,
            cwd: cwd.path,
            userPrompt: "Set up GBrain",
            model: "opus"
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && claude --permission-mode auto --model 'opus' --append-system-prompt"))
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

        let line = ZebraSourceOnboardingGmailCommand.shellStartupLine(
            agent: .codex,
            launchDirectory: cwd.path
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && codex -C '\(cwd.path)'"))
        XCTAssertTrue(line.contains("-c 'projects.\"\(cwd.path)\".trust_level=\"trusted\"'"))
        XCTAssertTrue(line.contains("--ask-for-approval on-request"))
        XCTAssertTrue(line.contains("'approvals_reviewer=\"auto_review\"'"))
        XCTAssertTrue(line.contains("using Codex"))
        XCTAssertTrue(line.contains("CLAWVISOR_TASK_ID"))
        XCTAssertTrue(line.contains("https://app.clawvisor.com/register"))
        XCTAssertTrue(line.contains("Create GBrain agent"))
        XCTAssertTrue(line.contains("1. Open https://app.clawvisor.com/register"))
        XCTAssertTrue(line.contains("2. In Clawvisor"))
        XCTAssertTrue(line.contains("3. Continue through Google service authorization"))
        XCTAssertTrue(line.contains("4. When Clawvisor reaches the final Env vars step"))
        XCTAssertFalse(line.contains("authoritative setup packet"))
        XCTAssertFalse(line.contains("read the setup packet"))
        XCTAssertFalse(line.contains("setup packet is at"))
        XCTAssertFalse(line.contains("zebra-source-onboarding gmail status"))
        XCTAssertFalse(line.contains("On your first response, run"))
        XCTAssertFalse(line.contains("waitingForUser"))
        XCTAssertFalse(line.contains("nextSection"))
        XCTAssertFalse(line.contains("CLAWVISOR_GMAIL_TASK_ID"))
        XCTAssertFalse(line.contains("ZEBRA_CLAWVISOR_GMAIL_ACCOUNT"))
        XCTAssertFalse(line.contains("claude --append-system-prompt"))
        XCTAssertFalse(line.contains("dangerously-bypass"))
    }

    func testClawvisorClaudeOnboardingLaunchUsesSessionAutoPermission() throws {
        let cwd = try makeTemporaryDirectory()

        let line = ZebraSourceOnboardingGmailCommand.shellStartupLine(
            agent: .claude,
            launchDirectory: cwd.path
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && claude --permission-mode auto --append-system-prompt"))
        XCTAssertTrue(line.contains("CLAWVISOR_TASK_ID"))
        XCTAssertTrue(line.contains("https://app.clawvisor.com/register"))
        XCTAssertFalse(line.contains("dangerously-bypass"))
    }

    func testClawvisorEmailPromptInjectsLocalizedConnectionSteps() {
        let korean = ZebraSourceOnboardingGmailCommand.gbrainAgentSystemPrompt(
            agentDisplayName: "Codex",
            language: .ko
        )
        XCTAssertTrue(korean.contains("Zebra는 Clawvisor를 통해 Gmail, Calendar, Contacts 접근 권한을 안전하게 연결합니다."))
        XCTAssertTrue(korean.contains("아래 순서대로 진행하세요."))
        XCTAssertTrue(korean.contains("1. https://app.clawvisor.com/register 을 열고 Google로 sign up 또는 sign in 하세요."))
        XCTAssertTrue(korean.contains("2. Clawvisor에서 왼쪽 sidebar의 Agents를 열고 GBrain을 선택한 뒤 Create GBrain agent를 클릭하세요."))
        XCTAssertTrue(korean.contains("3. Google service authorization과 task approval을 이어서 진행하세요."))
        XCTAssertTrue(korean.contains("4. 마지막 Env vars step에 도달하면 세 줄의 export env lines를 이 터미널에 그대로 붙여넣으세요."))
        XCTAssertLessThan(
            korean.range(of: "Zebra는 Clawvisor를 통해")!.lowerBound,
            korean.range(of: "1. https://app.clawvisor.com/register")!.lowerBound
        )
        XCTAssertTrue(korean.contains("zebra-source-onboarding gmail verify-connection"))
        XCTAssertTrue(korean.contains("Do not search the web for Clawvisor API docs"))
        XCTAssertFalse(korean.contains("GET $CLAWVISOR_URL/api/tasks/$CLAWVISOR_TASK_ID"))
        XCTAssertTrue(korean.contains("use concise Korean prose"))
        XCTAssertFalse(korean.contains("read the setup packet"))
        XCTAssertFalse(korean.contains("authoritative setup packet"))

        let english = ZebraSourceOnboardingGmailCommand.gbrainAgentSystemPrompt(
            agentDisplayName: "Codex",
            language: .en
        )
        XCTAssertTrue(english.contains("Zebra securely connects Gmail, Calendar, and Contacts access through Clawvisor."))
        XCTAssertTrue(english.contains("Follow the steps below."))
        XCTAssertTrue(english.contains("1. Open https://app.clawvisor.com/register and sign up or sign in with Google."))
        XCTAssertTrue(english.contains("2. In Clawvisor, use the left sidebar to open Agents, choose GBrain, and click Create GBrain agent."))
        XCTAssertTrue(english.contains("3. Continue through Google service authorization and task approval."))
        XCTAssertTrue(english.contains("4. When Clawvisor reaches the final Env vars step, paste the three exported env lines into this terminal."))
        XCTAssertTrue(english.contains("use concise English prose"))
        XCTAssertFalse(english.contains("read the setup packet"))
        XCTAssertFalse(english.contains("authoritative setup packet"))
    }

    func testClawvisorCodexOnboardingPersistsFolderTrust() throws {
        let cwd = try makeTemporaryDirectory()
        let configURL = try makeTemporaryDirectory()
            .appendingPathComponent("config.toml", isDirectory: false)

        XCTAssertTrue(ZebraSourceOnboardingGmailCommand.markCodexProjectTrusted(
            cwd: cwd.path,
            configURL: configURL
        ))
        XCTAssertTrue(ZebraSourceOnboardingGmailCommand.markCodexProjectTrusted(
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

        let plan = ZebraSourceOnboardingGmailCommand.launchPlan(
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

        let plan = ZebraSourceOnboardingGmailCommand.launchPlan(
            agent: .codex,
            launchDirectory: cwd.path,
            codexConfigURL: configURL,
            onboardingDirectoryURL: onboardingDirectoryURL
        )

        XCTAssertFalse(plan.launchEnvironmentReady)
        XCTAssertTrue(plan.startupLine.contains("codex"))
    }

    func testClawvisorEmailFlowKindIgnoresRuntimeSelection() {
        let runtime = ZebraGBrainRuntimeOnboardingStore.SelectedRuntime(
            runtime: "openclaw",
            executablePath: "/tmp/openclaw"
        )

        XCTAssertEqual(
            ZebraSourceOnboardingGmailCommand.resolveFlowKind(agent: .claude, selectedRuntime: runtime),
            .claudeCode
        )
        XCTAssertEqual(
            ZebraSourceOnboardingGmailCommand.resolveFlowKind(agent: .codex, selectedRuntime: runtime),
            .genericAgent
        )
    }

    func testClawvisorEmailFlowKindTreatsHermesRuntimeAsPrimaryAgentFlow() {
        let runtime = ZebraGBrainRuntimeOnboardingStore.SelectedRuntime(
            runtime: "hermes",
            executablePath: "/tmp/hermes"
        )

        XCTAssertEqual(
            ZebraSourceOnboardingGmailCommand.resolveFlowKind(agent: .claude, selectedRuntime: runtime),
            .claudeCode
        )
        XCTAssertEqual(
            ZebraSourceOnboardingGmailCommand.resolveFlowKind(agent: .codex, selectedRuntime: runtime),
            .genericAgent
        )
    }

    func testSourceOnboardingGmailLaunchPlanWritesSetupPacketAndHelper() throws {
        let cwd = try makeTemporaryDirectory()
        let configURL = try makeTemporaryDirectory()
            .appendingPathComponent("config.toml", isDirectory: false)
        let onboardingDirectoryURL = try makeTemporaryDirectory()
        let runtime = ZebraGBrainRuntimeOnboardingStore.SelectedRuntime(
            runtime: "openclaw",
            executablePath: "/tmp/openclaw"
        )

        let plan = ZebraSourceOnboardingGmailCommand.launchPlan(
            agent: .codex,
            launchDirectory: cwd.path,
            codexConfigURL: configURL,
            onboardingDirectoryURL: onboardingDirectoryURL,
            selectedRuntime: runtime
        )

        let setupPacketPath = try XCTUnwrap(plan.setupPacketPath)
        let setupPacket = try String(contentsOfFile: setupPacketPath, encoding: .utf8)
        XCTAssertEqual(plan.flowKind, .genericAgent)
        XCTAssertTrue(setupPacket.contains("Clawvisor email flow kind: genericAgent"))
        XCTAssertTrue(setupPacket.contains("GBrain runtime receipt: openclaw"))
        XCTAssertTrue(setupPacket.contains("https://app.clawvisor.com/register"))
        XCTAssertTrue(setupPacket.contains("sign up or sign in with Google"))
        XCTAssertTrue(setupPacket.contains("1. Open https://app.clawvisor.com/register"))
        XCTAssertTrue(setupPacket.contains("2. In Clawvisor"))
        XCTAssertTrue(setupPacket.contains("open Agents, choose"))
        XCTAssertTrue(setupPacket.contains("GBrain, and click Create GBrain agent"))
        XCTAssertTrue(setupPacket.contains("3. Continue through Google service authorization"))
        XCTAssertTrue(setupPacket.contains("4. When Clawvisor reaches the final Env vars step"))
        XCTAssertTrue(setupPacket.contains("CLAWVISOR_TASK_ID"))
        XCTAssertTrue(setupPacket.contains("zebra-source-onboarding gmail verify-connection"))
        XCTAssertTrue(setupPacket.contains("Source Onboarding state"))
        XCTAssertFalse(setupPacket.contains("GET $CLAWVISOR_URL/api/tasks/$CLAWVISOR_TASK_ID"))
        XCTAssertFalse(setupPacket.contains("OpenClaw integration guide"))
        XCTAssertFalse(setupPacket.contains("On your first response, run `zebra-source-onboarding gmail status`"))
        XCTAssertFalse(setupPacket.contains("zebra-source-onboarding gmail status"))
        XCTAssertFalse(setupPacket.contains("continue from `waitingForUser`"))
        XCTAssertFalse(setupPacket.contains("waitingForUser"))
        XCTAssertFalse(setupPacket.contains("`nextSection`"))
        XCTAssertFalse(setupPacket.contains("nextSection"))
        XCTAssertFalse(setupPacket.contains("## Progress Reporting"))
        XCTAssertFalse(setupPacket.contains("report --status started"))
        XCTAssertFalse(setupPacket.contains("CLAWVISOR_GMAIL_TASK_ID"))
        XCTAssertFalse(setupPacket.contains("ZEBRA_CLAWVISOR_GMAIL_ACCOUNT"))
        XCTAssertFalse(plan.startupLine.contains("zebra-source-onboarding gmail status"))
        XCTAssertFalse(plan.startupLine.contains("authoritative setup packet"))
        XCTAssertFalse(plan.startupLine.contains("read the setup packet"))
        XCTAssertFalse(plan.startupLine.contains("setup packet is at"))
        XCTAssertFalse(plan.startupLine.contains("waitingForUser"))
        XCTAssertFalse(plan.startupLine.contains("nextSection"))
        XCTAssertTrue(plan.startupLine.contains("ZEBRA_SOURCE_ONBOARDING_STATE"))
        XCTAssertTrue(plan.startupLine.contains("zebra-source-onboarding"))
        XCTAssertEqual(
            plan.statePath,
            onboardingDirectoryURL
                .appendingPathComponent("source-onboarding-state.json", isDirectory: false)
                .path
        )

        XCTAssertEqual(try octalPermissions(atPath: setupPacketPath), 0o600)
        XCTAssertEqual(
            try octalPermissions(
                atPath: onboardingDirectoryURL
                    .appendingPathComponent("bin/zebra-source-onboarding")
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

        XCTAssertTrue(ZebraSourceOnboardingGmailCommand.markCodexProjectTrusted(
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

        let line = ZebraSourceOnboardingGmailCommand.shellStartupLine(
            agent: .antigravity,
            launchDirectory: cwd.path
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && agy --prompt-interactive --add-dir '\(cwd.path)'"))
        XCTAssertTrue(line.contains("using Antigravity"))
        XCTAssertTrue(line.contains("CLAWVISOR_TASK_ID"))
        XCTAssertTrue(line.contains("https://app.clawvisor.com/register"))
        XCTAssertTrue(line.contains("Create GBrain agent"))
        XCTAssertTrue(line.contains("1. Open https://app.clawvisor.com/register"))
        XCTAssertTrue(line.contains("2. In Clawvisor"))
        XCTAssertTrue(line.contains("3. Continue through Google service authorization"))
        XCTAssertTrue(line.contains("4. When Clawvisor reaches the final Env vars step"))
        XCTAssertFalse(line.contains("authoritative setup packet"))
        XCTAssertFalse(line.contains("read the setup packet"))
        XCTAssertFalse(line.contains("setup packet is at"))
        XCTAssertFalse(line.contains("zebra-source-onboarding gmail status"))
        XCTAssertFalse(line.contains("On your first response, run"))
        XCTAssertFalse(line.contains("waitingForUser"))
        XCTAssertFalse(line.contains("nextSection"))
        XCTAssertFalse(line.contains("CLAWVISOR_GMAIL_TASK_ID"))
        XCTAssertFalse(line.contains("ZEBRA_CLAWVISOR_GMAIL_ACCOUNT"))
        XCTAssertFalse(line.contains("claude --append-system-prompt"))
    }

    func testClawvisorReadyPrimaryRequiresSavedInstalledAndConfiguredAgent() {
        let preferences = ZebraAgentPreferences(primaryAgent: .codex)

        XCTAssertEqual(
            ZebraSourceOnboardingGmailCommand.readyPrimaryAgent(
                preferences: preferences,
                candidates: [agentCandidate(id: .codex, installState: .installed, authState: .configPresent)]
            ),
            .codex
        )
        XCTAssertNil(ZebraSourceOnboardingGmailCommand.readyPrimaryAgent(
            preferences: ZebraAgentPreferences(primaryAgent: nil),
            candidates: [agentCandidate(id: .codex, installState: .installed, authState: .configPresent)]
        ))
        XCTAssertNil(ZebraSourceOnboardingGmailCommand.readyPrimaryAgent(
            preferences: preferences,
            candidates: [agentCandidate(id: .codex, installState: .missing, authState: .configPresent)]
        ))
        XCTAssertNil(ZebraSourceOnboardingGmailCommand.readyPrimaryAgent(
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
