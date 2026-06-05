import Foundation

/// Builds the shell command that drops the user into their primary agent
/// with a prompt that walks them through Clawvisor sign-up and writing
/// `~/.gbrain/.env`. Used by the email sidebar's "Connect" CTA and the
/// onboarding checklist email step so the flow lives inside an agent terminal
/// instead of a separate Settings form.
///
/// Modeled after `MarkdownChatPillCommand.shellStartupLine` but with no
/// dependency on a markdown file or surface context — the system prompt is
/// self-contained.
public enum ZebraClawvisorOnboardingCommand {
    public enum FlowKind: String, Equatable, Sendable {
        case claudeCode
        case genericAgent
        case openClaw
    }

    public struct LaunchPlan {
        public let launchDirectory: String
        public let agent: MarkdownPillAgent
        public let flowKind: FlowKind
        public let launchEnvironmentReady: Bool
        public let startupLine: String
        public let setupPacketPath: String?
        public let statePath: String
    }

    public static func launchPlan(agent: MarkdownPillAgent) -> LaunchPlan {
        launchPlan(
            agent: agent,
            launchDirectory: launchDirectory(),
            codexConfigURL: codexConfigURL(),
            onboardingDirectoryURL: ZebraGBrainOnboardingStore.onboardingDirectoryURL(),
            selectedRuntime: ZebraGBrainRuntimeOnboardingStore().selectedRuntimeForGBrainSetup()
        )
    }

    static func launchPlan(
        agent: MarkdownPillAgent,
        launchDirectory: String,
        codexConfigURL: URL,
        onboardingDirectoryURL: URL = ZebraGBrainOnboardingStore.onboardingDirectoryURL(),
        selectedRuntime: ZebraGBrainRuntimeOnboardingStore.SelectedRuntime? = nil
    ) -> LaunchPlan {
        let environment = prepareLaunchEnvironmentResult(
            agent: agent,
            launchDirectory: launchDirectory,
            codexConfigURL: codexConfigURL
        )
        let flowKind = resolveFlowKind(agent: agent, selectedRuntime: selectedRuntime)
        let setup = prepareSetupContext(
            agent: agent,
            flowKind: flowKind,
            selectedRuntime: selectedRuntime,
            onboardingDirectoryURL: onboardingDirectoryURL
        )
        return LaunchPlan(
            launchDirectory: environment.launchDirectory,
            agent: agent,
            flowKind: flowKind,
            launchEnvironmentReady: environment.isReady,
            startupLine: shellStartupLine(
                agent: agent,
                flowKind: flowKind,
                setupPacketPath: setup.setupPacketPath,
                helperDirectoryPath: setup.helperDirectoryPath,
                launchDirectory: environment.launchDirectory
            ),
            setupPacketPath: setup.setupPacketPath,
            statePath: setup.statePath
        )
    }

    static func resolveFlowKind(
        agent: MarkdownPillAgent,
        selectedRuntime: ZebraGBrainRuntimeOnboardingStore.SelectedRuntime?
    ) -> FlowKind {
        if selectedRuntime?.runtime == "openclaw" {
            return .openClaw
        }
        if agent == .claude {
            return .claudeCode
        }
        return .genericAgent
    }

    public static func readyPrimaryAgent(
        preferenceStore: ZebraAgentPreferenceStore = ZebraAgentPreferenceStore(),
        scanner: ZebraAgentInstallScanner = ZebraAgentInstallScanner()
    ) -> MarkdownPillAgent? {
        readyPrimaryAgent(
            preferences: preferenceStore.load(),
            candidates: scanner.scan()
        )
    }

    static func readyPrimaryAgent(
        preferences: ZebraAgentPreferences,
        candidates: [ZebraAgentInstallCandidate]
    ) -> MarkdownPillAgent? {
        guard let primaryAgent = preferences.primaryAgent else {
            return nil
        }
        let candidate = candidates.first { $0.id == primaryAgent }
        guard candidate?.installState == .installed,
              candidate?.terminalLaunchable == true,
              candidate?.authState == .configPresent else {
            return nil
        }
        return MarkdownPillAgent(agentKind: primaryAgent)
    }

    /// Prepares the launch directory and pre-accepts Claude's trust dialog
    /// for it so the user doesn't have to dismiss a "trust this folder"
    /// prompt mid-onboarding when Claude is the selected agent. Both
    /// operations are idempotent — safe to call on every click and safe even
    /// if other gbrain tooling already manages `~/.gbrain`. Returns the
    /// directory the caller should `cd` into.
    @discardableResult
    public static func prepareLaunchEnvironment(agent: MarkdownPillAgent = .claude) -> String {
        prepareLaunchEnvironmentResult(
            agent: agent,
            launchDirectory: launchDirectory(),
            codexConfigURL: codexConfigURL()
        ).launchDirectory
    }

    private struct LaunchEnvironment {
        let launchDirectory: String
        let isReady: Bool
    }

    private static func prepareLaunchEnvironmentResult(
        agent: MarkdownPillAgent,
        launchDirectory directory: String,
        codexConfigURL: URL
    ) -> LaunchEnvironment {
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory)
        var isReady = true
        if agent == .codex {
            isReady = markCodexProjectTrusted(cwd: directory, configURL: codexConfigURL)
        }
        isReady = MarkdownChatPillCommand.prepareLaunchEnvironment(
            agent: agent,
            markdownFilePath: nil,
            launchDirectory: directory
        ) && isReady
        return LaunchEnvironment(launchDirectory: directory, isReady: isReady)
    }

    public static func shellStartupLine(
        agent: MarkdownPillAgent,
        launchDirectory: String? = nil
    ) -> String {
        let cwd = launchDirectory ?? self.launchDirectory()
        let flowKind = resolveFlowKind(agent: agent, selectedRuntime: nil)
        return "\(agentInvocation(agent: agent, flowKind: flowKind, setupPacketPath: nil, helperDirectoryPath: nil, cwd: cwd))\r"
    }

    /// `~/.gbrain` — a scoped onboarding directory rather than the user's
    /// full home so Claude's trust grant stays narrow. Existing gbrain
    /// tooling already writes there, so we never own the directory's
    /// contents — we only ensure it exists and is trust-marked.
    private static func launchDirectory() -> String {
        let home = NSHomeDirectory()
        guard !home.isEmpty else { return "~/.gbrain" }
        return (home as NSString).appendingPathComponent(".gbrain")
    }

    static func systemPrompt(for agent: MarkdownPillAgent) -> String {
        systemPrompt(flowKind: resolveFlowKind(agent: agent, selectedRuntime: nil), agent: agent, setupPacketPath: nil)
    }

    static func systemPrompt(
        flowKind: FlowKind,
        agent: MarkdownPillAgent,
        setupPacketPath: String?
    ) -> String {
        let language = ZebraOnboardingLanguage.current()
        let languagePrefix = "\(language.promptPolicy)\n\n\(language.clawvisorFlowPresentationInstruction)"
        if let setupPacketPath {
            return """
            \(languagePrefix)

            You are Zebra's Clawvisor email onboarding helper. The authoritative setup packet is at:
            \(setupPacketPath)

            On your first response, run `zebra-clawvisor-email-onboarding status`, read the complete setup packet, and continue from the recorded `waitingForUser` or `nextSection`. If the state file is missing or contradictory, infer the safest next action from the setup packet and request only concrete missing values such as a token, task id, Gmail account, or copied dashboard command. Use `zebra-clawvisor-email-onboarding report` after each section changes state.
            """
        }
        return "\(languagePrefix)\n\n\(setupPacketContent(flowKind: flowKind, agent: agent, selectedRuntime: nil, completedSections: [], nextSection: firstSectionTitle(flowKind: flowKind), waitingForUser: nil, lastFailure: nil))"
    }

    static func setupPacketContent(
        flowKind: FlowKind,
        agent: MarkdownPillAgent,
        selectedRuntime: ZebraGBrainRuntimeOnboardingStore.SelectedRuntime?,
        completedSections: [String],
        nextSection: String?,
        waitingForUser: String?,
        lastFailure: String?
    ) -> String {
        let targetDescription: String
        switch flowKind {
        case .claudeCode:
            targetDescription = "Claude Code"
        case .genericAgent:
            targetDescription = "\(agent.agentKind.displayName) via the Clawvisor generic agent flow"
        case .openClaw:
            targetDescription = "OpenClaw integration, guided from \(agent.agentKind.displayName)"
        }
        return """
        # Zebra Clawvisor Email Onboarding Packet

        This packet is the authoritative instruction for the current Zebra email onboarding run.

        - Primary terminal agent: \(agent.agentKind.displayName)
        - GBrain runtime receipt: \(selectedRuntime?.runtime ?? "none")
        - Clawvisor email flow kind: \(flowKind.rawValue)
        - Clawvisor integration target: \(targetDescription)
        - Completion source of truth: `~/.gbrain/.env` plus Zebra's email repair state
        - Required env target: `~/.gbrain/.env`
        - Completed sections: \(completedSections.isEmpty ? "none" : completedSections.joined(separator: ", "))
        - Next section: \(nextSection ?? "not recorded")
        - Waiting for user: \(waitingForUser ?? "none")
        - Last failure: \(lastFailure ?? "none")

        ## Progress Reporting

        Report progress with:

        ```sh
        zebra-clawvisor-email-onboarding report --status started --section "<section title>"
        zebra-clawvisor-email-onboarding report --status completed --section "<section title>"
        zebra-clawvisor-email-onboarding report --status waiting_for_user --section "<section title>" --note "<what is needed>"
        zebra-clawvisor-email-onboarding report --status failed --section "<section title>" --note "<reason>"
        zebra-clawvisor-email-onboarding status
        zebra-clawvisor-email-onboarding verify-env
        ```

        Do not store Clawvisor tokens, Gmail tokens, callback secrets, or other secrets in the state file.

        \(flowInstructions(flowKind: flowKind, agent: agent))
        """
    }

    static func initialUserPrompt(for agent: MarkdownPillAgent) -> String {
        "Help me connect my Gmail to Zebra through Clawvisor using \(agent.agentKind.displayName)."
    }

    private static func shellStartupLine(
        agent: MarkdownPillAgent,
        flowKind: FlowKind,
        setupPacketPath: String?,
        helperDirectoryPath: String?,
        launchDirectory: String
    ) -> String {
        "\(agentInvocation(agent: agent, flowKind: flowKind, setupPacketPath: setupPacketPath, helperDirectoryPath: helperDirectoryPath, cwd: launchDirectory))\r"
    }

    private static func agentInvocation(
        agent: MarkdownPillAgent,
        flowKind: FlowKind,
        setupPacketPath: String?,
        helperDirectoryPath: String?,
        cwd: String
    ) -> String {
        let resolvedCwd = validLaunchDirectoryCwd(cwd) ?? NSHomeDirectory()
        let systemPrompt = systemPrompt(flowKind: flowKind, agent: agent, setupPacketPath: setupPacketPath)
        let userPrompt = singleLineShellArgument(initialUserPrompt(for: agent))
        let visiblePrompt = "\(systemPrompt)\n\n\(userPrompt)"
        let pathPrefix = helperDirectoryPath.map { "export PATH=\(shellQuote($0)):\"$PATH\" && " } ?? ""

        switch agent {
        case .codex:
            var parts = [
                "cd \(shellQuote(resolvedCwd)) && \(pathPrefix)codex",
                "-C \(shellQuote(resolvedCwd))",
            ]
            if let trustOverride = codexFolderTrustOverride(for: resolvedCwd) {
                parts.append("-c \(shellQuote(trustOverride))")
            }
            parts.append(shellQuote(visiblePrompt))
            return parts.joined(separator: " ")
        case .claude:
            return "cd \(shellQuote(resolvedCwd)) && \(pathPrefix)claude --append-system-prompt \(shellQuote(systemPrompt)) \(shellQuote(userPrompt))"
        case .antigravity:
            return "cd \(shellQuote(resolvedCwd)) && \(pathPrefix)agy --prompt-interactive --add-dir \(shellQuote(resolvedCwd)) \(shellQuote(visiblePrompt))"
        }
    }

    private static func codexFolderTrustOverride(for cwd: String) -> String? {
        guard let trustCwd = codexTrustedCwd(cwd) else {
            return nil
        }
        return "projects.\"\(trustCwd)\".trust_level=\"trusted\""
    }

    @discardableResult
    static func markCodexProjectTrusted(
        cwd: String,
        configURL: URL = codexConfigURL()
    ) -> Bool {
        guard let trustCwd = codexTrustedCwd(cwd) else {
            return false
        }
        let sectionHeader = "[projects.\"\(trustCwd)\"]"
        let raw = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let updated = upsertingCodexProjectTrust(in: raw, sectionHeader: sectionHeader)
        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try updated.write(to: configURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    static func upsertingCodexProjectTrust(
        in raw: String,
        sectionHeader: String
    ) -> String {
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let sectionIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == sectionHeader }) else {
            var output = raw
            if !output.isEmpty, !output.hasSuffix("\n") {
                output.append("\n")
            }
            if !output.isEmpty {
                output.append("\n")
            }
            output.append("\(sectionHeader)\ntrust_level = \"trusted\"\n")
            return output
        }

        let sectionEnd = lines[(sectionIndex + 1)...].firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        } ?? lines.endIndex

        if let trustLineIndex = lines[(sectionIndex + 1)..<sectionEnd].firstIndex(where: { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("trust_level")
        }) {
            lines[trustLineIndex] = "trust_level = \"trusted\""
        } else {
            lines.insert("trust_level = \"trusted\"", at: sectionIndex + 1)
        }

        return lines.joined(separator: "\n")
    }

    private static func codexConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)
    }

    private static func codexTrustedCwd(_ cwd: String) -> String? {
        guard let trustCwd = validLaunchDirectoryCwd(cwd),
              trustCwd != "/",
              trustCwd != standardizedPath(NSHomeDirectory()) else {
            return nil
        }
        for scalar in trustCwd.unicodeScalars {
            if scalar == "\"" || scalar == "\\" || scalar.value < 0x20 {
                return nil
            }
        }
        return trustCwd
    }

    private static func validLaunchDirectoryCwd(_ cwd: String?) -> String? {
        guard let cwd else { return nil }
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let standardized = standardizedPath((trimmed as NSString).expandingTildeInPath)
        guard standardized.hasPrefix("/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return standardized
    }

    private static func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func singleLineShellArgument(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private struct SetupContext {
        let statePath: String
        let setupPacketPath: String?
        let helperDirectoryPath: String?
    }

    private struct EmailOnboardingState: Codable {
        var schemaVersion: Int
        var currentRunId: String
        var primaryAgent: String
        var selectedRuntime: String?
        var flowKind: String
        var completedSections: [String]
        var nextSection: String?
        var waitingForUser: String?
        var lastFailure: String?
        var updatedAt: String
    }

    private static func prepareSetupContext(
        agent: MarkdownPillAgent,
        flowKind: FlowKind,
        selectedRuntime: ZebraGBrainRuntimeOnboardingStore.SelectedRuntime?,
        onboardingDirectoryURL: URL
    ) -> SetupContext {
        let stateURL = onboardingDirectoryURL
            .appendingPathComponent("clawvisor-email-state.json", isDirectory: false)
        let helperURL = installHelperScript(onboardingDirectoryURL: onboardingDirectoryURL)
        let existingState = loadState(stateURL: stateURL)
        let runId = UUID().uuidString.lowercased()
        let completedSections = existingState?.completedSections ?? []
        let nextSection = existingState?.nextSection ?? firstSectionTitle(flowKind: flowKind)
        let packet = setupPacketContent(
            flowKind: flowKind,
            agent: agent,
            selectedRuntime: selectedRuntime,
            completedSections: completedSections,
            nextSection: nextSection,
            waitingForUser: existingState?.waitingForUser,
            lastFailure: existingState?.lastFailure
        )
        let packetURL = writeSetupPacket(
            packet,
            runId: runId,
            onboardingDirectoryURL: onboardingDirectoryURL
        )
        let state = EmailOnboardingState(
            schemaVersion: 1,
            currentRunId: runId,
            primaryAgent: agent.agentKind.rawValue,
            selectedRuntime: selectedRuntime?.runtime,
            flowKind: flowKind.rawValue,
            completedSections: completedSections,
            nextSection: nextSection,
            waitingForUser: existingState?.waitingForUser,
            lastFailure: existingState?.lastFailure,
            updatedAt: isoNow()
        )
        writeState(state, to: stateURL)
        return SetupContext(
            statePath: stateURL.path,
            setupPacketPath: packetURL?.path,
            helperDirectoryPath: helperURL?.deletingLastPathComponent().path
        )
    }

    private static func loadState(stateURL: URL) -> EmailOnboardingState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(EmailOnboardingState.self, from: data)
    }

    private static func writeState(_ state: EmailOnboardingState, to stateURL: URL) {
        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: stateURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        } catch {
            return
        }
    }

    private static func writeSetupPacket(
        _ content: String,
        runId: String,
        onboardingDirectoryURL: URL
    ) -> URL? {
        let directory = onboardingDirectoryURL
            .appendingPathComponent("clawvisor-email-setup-packets", isDirectory: true)
        let url = directory.appendingPathComponent("\(runId).md", isDirectory: false)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
    }

    private static func installHelperScript(onboardingDirectoryURL: URL) -> URL? {
        let directory = onboardingDirectoryURL.appendingPathComponent("bin", isDirectory: true)
        let url = directory.appendingPathComponent("zebra-clawvisor-email-onboarding", isDirectory: false)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try helperScript.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
    }

    private static func firstSectionTitle(flowKind: FlowKind) -> String {
        switch flowKind {
        case .claudeCode, .genericAgent:
            return "Sign up for Clawvisor Cloud and connect Gmail"
        case .openClaw:
            return "Prepare the OpenClaw Clawvisor integration"
        }
    }

    private static func flowInstructions(flowKind: FlowKind, agent: MarkdownPillAgent) -> String {
        switch flowKind {
        case .claudeCode:
            return claudeCodeSystemPrompt
        case .genericAgent:
            return genericAgentSystemPrompt(agentDisplayName: agent.agentKind.displayName)
        case .openClaw:
            return openClawSystemPrompt(agentDisplayName: agent.agentKind.displayName)
        }
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static let helperScript = """
    #!/bin/sh
    set -eu

    STATE="${ZEBRA_CLAWVISOR_EMAIL_STATE:-$HOME/Library/Application Support/zebra/onboarding/clawvisor-email-state.json}"
    COMMAND="${1:-status}"
    if [ $# -gt 0 ]; then
      shift
    fi

    PYTHON_BIN="$(command -v python3 || true)"
    if [ -z "$PYTHON_BIN" ]; then
      echo "python3 is required for zebra-clawvisor-email-onboarding" >&2
      exit 1
    fi

    "$PYTHON_BIN" - "$STATE" "$COMMAND" "$@" <<'PY'
    import json
    import os
    import sys
    from datetime import datetime, timezone
    from pathlib import Path

    state_path = Path(sys.argv[1]).expanduser()
    command = sys.argv[2] if len(sys.argv) > 2 else "status"
    args = sys.argv[3:]

    def now():
        return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    def load_state():
        try:
            with state_path.open("r", encoding="utf-8") as handle:
                return json.load(handle)
        except Exception:
            return {"schemaVersion": 1, "completedSections": []}

    def save_state(state):
        state_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = state_path.with_suffix(state_path.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2, sort_keys=True)
            handle.write("\\n")
        os.replace(tmp, state_path)
        os.chmod(state_path, 0o600)

    def option(name, default=""):
        flag = "--" + name
        if flag not in args:
            return default
        index = args.index(flag)
        if index + 1 >= len(args):
            return default
        return args[index + 1]

    def verify_env():
        env_path = Path.home() / ".gbrain" / ".env"
        required = [
            "CLAWVISOR_URL",
            "CLAWVISOR_AGENT_TOKEN",
            "CLAWVISOR_GMAIL_TASK_ID",
            "ZEBRA_CLAWVISOR_GMAIL_ACCOUNT",
        ]
        try:
            raw = env_path.read_text(encoding="utf-8")
        except Exception:
            print(json.dumps({"ok": False, "missing": required, "path": str(env_path)}, sort_keys=True))
            return 1
        present = set()
        for line in raw.splitlines():
            if "=" not in line or line.lstrip().startswith("#"):
                continue
            key, value = line.split("=", 1)
            if key.strip() in required and value.strip():
                present.add(key.strip())
        missing = [key for key in required if key not in present]
        print(json.dumps({"ok": not missing, "missing": missing, "path": str(env_path)}, sort_keys=True))
        return 0 if not missing else 1

    if command == "status":
        print(json.dumps(load_state(), indent=2, sort_keys=True))
        raise SystemExit(0)

    if command == "verify-env":
        raise SystemExit(verify_env())

    if command == "report":
        status = option("status")
        section = option("section")
        note = option("note")
        if not status or not section:
            print("report requires --status and --section", file=sys.stderr)
            raise SystemExit(2)
        state = load_state()
        completed = list(state.get("completedSections") or [])
        if status == "completed" and section not in completed:
            completed.append(section)
        state["completedSections"] = completed
        state["nextSection"] = "" if status == "completed" else section
        state["waitingForUser"] = note if status == "waiting_for_user" else None
        state["lastFailure"] = note if status == "failed" else None
        state["updatedAt"] = now()
        save_state(state)
        print(json.dumps({"ok": True, "status": status, "section": section}, sort_keys=True))
        raise SystemExit(0)

    print("unknown command: " + command, file=sys.stderr)
    raise SystemExit(2)
    PY
    """

    /// System prompt for the Claude Code flow specifically. Mirrors the
    /// "Connect an agent → Claude Code" tab on the Clawvisor dashboard:
    /// curl-download the setup skill, run `/clawvisor-setup`, approve the
    /// pending connection, then mirror the credentials into `~/.gbrain/.env`
    /// so Zebra's desktop email client can read them.
    static let claudeCodeSystemPrompt: String = """
You are Zebra's Clawvisor onboarding helper. The user just clicked
"Gmail 연결" in Zebra's email sidebar and was dropped into this Claude
Code session.

The flow:

  1. **Sign up for Clawvisor Cloud** — https://app.clawvisor.com/login
     (free trial, no credit card required). In the dashboard's left
     sidebar (Overview, Get Started, Tasks, Accounts, Policy, Agents,
     Activity, Settings, Billing), have the user click **"Get
     Started"**.

  2. **Connect a service → Gmail.** On the Get Started page the first
     card is "Connect a service". Have the user link their Gmail (and
     optionally Google Calendar) there. Clawvisor stores the
     credentials in its own vault; agents never see them directly.

  3. **Connect an agent → Claude Code.** On the same Get Started
     page, the second card is "Connect an agent". The user clicks
     **"Claude Code"** (this onboarding session itself is Claude
     Code, so that's the right tab). Clawvisor opens an Agents page
     with a one-line `curl` command under "Install the setup
     command" — the URL inside that curl carries a `user_id` unique
     to the user. The full line looks like:

         curl -sf "https://app.clawvisor.com/skill/clawvisor-setup.md?user_id=<UUID>" \\
           --create-dirs -o ~/.claude/commands/clawvisor-setup.md

     Tell the user to copy that exact line off their own Agents page
     and paste it into THIS terminal, then run it. Do not invent the
     `user_id` — only the user can read the personalized line off
     their dashboard.

  4. **Run `/clawvisor-setup`** in this Claude Code session (note
     the order: `clawvisor` then `setup`). Claude walks the user
     through registering as an agent, configuring the environment,
     and verifying the connection. If you see "No commands match",
     step 3 didn't land the file in `~/.claude/commands/` yet — go
     re-run the curl line.

  5. **Approve the connection in the dashboard.** During the
     `/clawvisor-setup` flow Claude Code sends a connection request
     to Clawvisor. Tell the user to switch to the dashboard's Agents
     page and approve it in the **"Pending Connections"** section.
     After approval, `/clawvisor-setup` finishes automatically and
     runs a smoke test.

  6. **Create Zebra's standing Gmail task.** Zebra's inbox sync is
     an ongoing workflow, not a 30-minute session task. When you
     create the Clawvisor task whose id Zebra will store, call
     `POST /api/tasks` with `"lifetime": "standing"` and do not set
     `expires_in_seconds`. The standing task remains active until the
     user revokes it from the Clawvisor dashboard.

\(standingGmailTaskInstructions())

     The read actions, draft creation, archive, and `send_message` may
     auto-execute because Zebra itself is the user-visible approval
     surface. Zebra only calls `send_message` after the user explicitly
     submits the draft in the app, so Clawvisor should not require a
     second per-request approval. The task id returned by this standing
     task is the value for `CLAWVISOR_GMAIL_TASK_ID` in the next step.

  7. **Write the credentials into `~/.gbrain/.env`** (NOT
     `~/.claude/settings.json`). The Clawvisor setup skill suggests
     writing the agent token to `~/.claude/settings.json` so Claude
     Code itself can call Clawvisor APIs. **That path is not what
     Zebra needs.** Zebra's desktop email client is a separate Swift
     process that reads ONLY `~/.gbrain/.env` — it does not look at
     `~/.claude/settings.json` and never will, because the two
     processes are independent.

     If `/clawvisor-setup` tries to edit `~/.claude/settings.json`
     and gets blocked (auto mode or otherwise), don't troubleshoot
     that path — it isn't where Zebra reads from. Just write the
     same credentials into `~/.gbrain/.env` instead:

         CLAWVISOR_URL=https://app.clawvisor.com
         CLAWVISOR_AGENT_TOKEN=<the cvis_... token from /clawvisor-setup>
         CLAWVISOR_GMAIL_TASK_ID=<the standing Gmail task id from step 6>
         ZEBRA_CLAWVISOR_GMAIL_ACCOUNT=<the user's Gmail address>

     Preserve any other lines already in `~/.gbrain/.env` — only
     touch these four keys. Then `chmod 600 ~/.gbrain/.env`.

     If the setup flow only reported a token (no separate task id),
     ask the user to read the task id off the Tasks page of the
     Clawvisor dashboard. Never invent values.

When `~/.gbrain/.env` is written, the onboarding is complete — say so
briefly and stop. Zebra's email sidebar watches that file and reloads
on its own; do NOT tell the user to switch tabs or click an inbox
refresh button.

Style:
  • On the first response, run `zebra-clawvisor-email-onboarding status`,
    read the setup packet, and continue from `waitingForUser` or
    `nextSection`. If the state file is missing or contradictory, infer
    the safest next action from the setup packet and request only
    concrete missing values such as a token, task id, Gmail account, or
    copied dashboard command.
  • Don't re-explain steps already listed in `completedSections`.
  • After the first response, use one short paragraph + a single question
    per turn. Follow the language policy above for user-facing prose.
  • Never fabricate URLs, agent install commands, slash command
    names, or `user_id` values. The `curl` line in step 3 carries
    a personalized `user_id` — only the user can read it off their
    own Agents page in the dashboard.
  • The slash command name is `/clawvisor-setup`, not
    `/setup-clawvisor`. Do not invert the order.
  • If install or registration fails, have the user re-open the
    dashboard's Agents page and re-copy the curl line rather than
    improvising a fix.
"""

    static func genericAgentSystemPrompt(agentDisplayName: String) -> String {
        """
You are Zebra's Clawvisor onboarding helper. The user just clicked
"Gmail 연결" in Zebra and was dropped into this \(agentDisplayName)
session.

Your job is to help the user connect Gmail to Zebra through Clawvisor.
Do not install Claude-only slash commands. Use Clawvisor's generic
agent flow: verify or obtain `CLAWVISOR_URL`, create or obtain an
agent token, create Zebra's standing Gmail task, then write the final
values into `~/.gbrain/.env`.

The flow:

  1. **Sign up for Clawvisor Cloud** — https://app.clawvisor.com/login
     (free trial, no credit card required). Have the user connect
     Gmail from the dashboard before creating Zebra's task.

  2. **Create or obtain an agent token.** If the user has a local
     Clawvisor CLI/server, follow the generic agent guide:

         clawvisor agent create zebra-\(agentDisplayName.lowercased()) --replace --json

     If the user is using Clawvisor Cloud, have them create or copy an
     agent token from the dashboard's Agents page. Never invent tokens.
     The token is shown only once, so ask the user to copy it carefully.

  3. **Verify the generic agent connection.** Set:

         CLAWVISOR_URL=https://app.clawvisor.com
         CLAWVISOR_AGENT_TOKEN=<the user's agent token>

     If the user is self-hosting or using a local server, use their
     actual Clawvisor URL instead. Verify with:

         curl -sf -H "Authorization: Bearer $CLAWVISOR_AGENT_TOKEN" \\
           "$CLAWVISOR_URL/api/skill/catalog" | head -20

     A 401 means the token is invalid. A connection failure means the
     URL is wrong or Clawvisor is not running.

  4. **Create Zebra's standing Gmail task.** Zebra's inbox sync is an
     ongoing workflow, not a 30-minute session task. Create the task
     with `"lifetime": "standing"` and do not set
     `expires_in_seconds`.

\(standingGmailTaskInstructions())

     The returned task id is `CLAWVISOR_GMAIL_TASK_ID`.

  5. **Write the credentials into `~/.gbrain/.env`.** Zebra reads this
     file directly:

         CLAWVISOR_URL=<Clawvisor URL>
         CLAWVISOR_AGENT_TOKEN=<agent token>
         CLAWVISOR_GMAIL_TASK_ID=<standing Gmail task id>
         ZEBRA_CLAWVISOR_GMAIL_ACCOUNT=<the user's Gmail address>

     Preserve any other lines already in `~/.gbrain/.env` and run
     `chmod 600 ~/.gbrain/.env`.

When `~/.gbrain/.env` is written, the onboarding is complete. Say so
briefly and stop. Zebra's email sidebar watches that file and reloads
on its own; do not tell the user to switch tabs or click refresh.

Style:
  • On the first response, run `zebra-clawvisor-email-onboarding status`,
    read the setup packet, and continue from `waitingForUser` or
    `nextSection`. If the state file is missing or contradictory, infer
    the safest next action from the setup packet and request only
    concrete missing values such as a token, task id, Gmail account, or
    copied dashboard command.
  • After the first response, use one short paragraph + a single
    question per turn. Korean is fine; the user's UI is Korean.
  • Never fabricate URLs, tokens, task ids, Gmail accounts, or install
    commands. Ask the user to copy values from their Clawvisor dashboard
    or local Clawvisor CLI output.
"""
    }

    static func openClawSystemPrompt(agentDisplayName: String) -> String {
        """
You are Zebra's Clawvisor onboarding helper. The user just clicked
"Gmail 연결" in Zebra and was dropped into this \(agentDisplayName)
session.

Your job is to guide the user through the Clawvisor OpenClaw integration
target. \(agentDisplayName) is only the terminal agent explaining and
driving the setup; do not treat it as the Clawvisor integration target.

The flow:

  1. **Open the Clawvisor OpenClaw integration guide.** Use the user's
     local copy if available, otherwise have them refer to:
     https://github.com/clawvisor/clawvisor/blob/main/docs/INTEGRATE_OPENCLAW.md

  2. **Install the Clawvisor pieces into OpenClaw.** Follow the guide's
     OpenClaw skill, webhook extension, callback, and environment setup.
     Do not install Claude-only slash commands for this flow.

  3. **Connect Gmail in Clawvisor.** Have the user connect Gmail through
     Clawvisor so the standing task can authorize Gmail read, draft,
     send, archive, thread, and attachment actions.

  4. **Create Zebra's standing Gmail task.** Zebra's inbox sync is an
     ongoing workflow, not a 30-minute session task. Create the task
     with `"lifetime": "standing"` and do not set
     `expires_in_seconds`.

\(standingGmailTaskInstructions())

  5. **Write Zebra's desktop env file.** Even though the integration
     target is OpenClaw, Zebra still reads only this file:

         CLAWVISOR_URL=<Clawvisor URL>
         CLAWVISOR_AGENT_TOKEN=<agent token>
         CLAWVISOR_GMAIL_TASK_ID=<standing Gmail task id>
         ZEBRA_CLAWVISOR_GMAIL_ACCOUNT=<the user's Gmail address>

     Preserve any other lines already in `~/.gbrain/.env` and run
     `chmod 600 ~/.gbrain/.env`.

When `~/.gbrain/.env` is written, the onboarding is complete. Say so
briefly and stop. Zebra's email sidebar watches that file and reloads
on its own; do not tell the user to switch tabs or click refresh.

Style:
  • On the first response, run `zebra-clawvisor-email-onboarding status`,
    read the setup packet, and continue from `waitingForUser` or
    `nextSection`. If the state file is missing or contradictory, infer
    the safest next action from the setup packet and request only
    concrete missing values such as a token, task id, Gmail account, or
    copied dashboard command.
  • Keep reminding yourself that OpenClaw is the Clawvisor integration
    target, while \(agentDisplayName) is the guide in this terminal.
  • Never fabricate URLs, tokens, task ids, Gmail accounts, callback
    secrets, or install commands.
"""
    }

    private static func standingGmailTaskInstructions() -> String {
        return """
     Use this scope exactly, replacing `<account>` with the user's
     Gmail address:

         curl -s -X POST "$CLAWVISOR_URL/api/tasks?wait=true" \\
           -H "Authorization: Bearer $CLAWVISOR_AGENT_TOKEN" \\
           -H "Content-Type: application/json" \\
           -d '{
             "purpose": "Zebra desktop email client: continuous inbox sync, read message bodies on user open, draft and send replies on user submit, archive on user action",
             "lifetime": "standing",
             "authorized_actions": [
               {
                 "service": "google.gmail:<account>",
                 "action": "list_messages",
                 "auto_execute": true,
                 "expected_use": "List recent Gmail messages so Zebra can keep the inbox sidebar in sync"
               },
               {
                 "service": "google.gmail:<account>",
                 "action": "get_message",
                 "auto_execute": true,
                 "expected_use": "Read one selected Gmail message when the user opens it in Zebra"
               },
               {
                 "service": "google.gmail:<account>",
                 "action": "get_thread",
                 "auto_execute": true,
                 "expected_use": "Read a selected Gmail thread so Zebra can show the conversation"
               },
               {
                 "service": "google.gmail:<account>",
                 "action": "get_attachment",
                 "auto_execute": true,
                 "expected_use": "Fetch an attachment only when the user opens it from a message in Zebra"
               },
               {
                 "service": "google.gmail:<account>",
                 "action": "create_draft",
                 "auto_execute": true,
                 "expected_use": "Create or update a Gmail draft from text the user composed in Zebra"
               },
               {
                 "service": "google.gmail:<account>",
                 "action": "send_message",
                 "auto_execute": true,
                 "expected_use": "Send a Gmail reply only after the user explicitly submits it in Zebra"
               },
               {
                 "service": "google.gmail:<account>",
                 "action": "archive_message",
                 "auto_execute": true,
                 "expected_use": "Archive a Gmail message only when the user triggers archive in Zebra"
               }
             ]
           }'
    """
    }
}
