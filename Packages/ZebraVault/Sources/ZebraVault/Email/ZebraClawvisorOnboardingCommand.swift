import Foundation

/// Builds the shell command that drops the user into their primary agent
/// with a prompt that walks them through the Clawvisor GBrain env handoff.
/// Used by the email sidebar's "Connect" CTA and the
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
        setupPacketPath: String?,
        language: ZebraOnboardingLanguage = .current()
    ) -> String {
        let languagePrefix = "\(language.promptPolicy)\n\n\(language.clawvisorFlowPresentationInstruction)"
        if setupPacketPath != nil {
            return """
            \(languagePrefix)

            \(setupPacketContent(flowKind: flowKind, agent: agent, selectedRuntime: nil, completedSections: [], nextSection: nil, waitingForUser: nil, lastFailure: nil, language: language))

            Internal note: do not mention local files or local onboarding state to the user. Start by giving the numbered Clawvisor connection instructions.
            """
        }
        return "\(languagePrefix)\n\n\(setupPacketContent(flowKind: flowKind, agent: agent, selectedRuntime: nil, completedSections: [], nextSection: firstSectionTitle(flowKind: flowKind), waitingForUser: nil, lastFailure: nil, language: language))"
    }

    static func setupPacketContent(
        flowKind: FlowKind,
        agent: MarkdownPillAgent,
        selectedRuntime: ZebraGBrainRuntimeOnboardingStore.SelectedRuntime?,
        completedSections: [String],
        nextSection: String?,
        waitingForUser: String?,
        lastFailure: String?,
        language: ZebraOnboardingLanguage = .current()
    ) -> String {
        let targetDescription: String
        switch flowKind {
        case .claudeCode:
            targetDescription = "Claude Code"
        case .genericAgent:
            targetDescription = "\(agent.agentKind.displayName) via the Clawvisor generic agent flow"
        }
        return """
        # Zebra Clawvisor Email Onboarding Instructions

        These are the instructions for the current Zebra email onboarding run.

        - Primary terminal agent: \(agent.agentKind.displayName)
        - GBrain runtime receipt: \(selectedRuntime?.runtime ?? "none")
        - Clawvisor email flow kind: \(flowKind.rawValue)
        - Clawvisor integration target: \(targetDescription)
        - Completion source of truth: canonical Clawvisor env plus Zebra's email repair state
        - Required env keys: `CLAWVISOR_URL`, `CLAWVISOR_AGENT_TOKEN`, `CLAWVISOR_TASK_ID`

        ## Important behavior

        This is not a state-tracked onboarding wizard. Do not inspect local onboarding progress before instructing the user, and do not infer the user's current Clawvisor UI step. Use the instructions below as a setup guide, and only perform verification after the user pastes the three env lines.

        \(flowInstructions(flowKind: flowKind, agent: agent, language: language))
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
            lastFailure: existingState?.lastFailure,
            language: .current()
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
            return "Connect GBrain in Clawvisor and paste the three env lines"
        }
    }

    private static func flowInstructions(
        flowKind: FlowKind,
        agent: MarkdownPillAgent,
        language: ZebraOnboardingLanguage
    ) -> String {
        switch flowKind {
        case .claudeCode, .genericAgent:
            return gbrainAgentSystemPrompt(agentDisplayName: agent.agentKind.displayName, language: language)
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
            "CLAWVISOR_TASK_ID",
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

    static func gbrainAgentSystemPrompt(
        agentDisplayName: String,
        language: ZebraOnboardingLanguage = .current()
    ) -> String {
        """
You are Zebra's Clawvisor onboarding helper. The user just clicked
"Gmail 연결" in Zebra and was dropped into this \(agentDisplayName)
session.

Your job is to guide the user through Clawvisor's **Connect an Agent →
GBrain** flow and then complete the local setup yourself. The user-facing
instruction must be a numbered list with exactly these four user-facing steps
in Zebra's app language:

\(language.clawvisorEmailConnectionSteps)

Those three canonical env vars are:

    export CLAWVISOR_URL="https://app.clawvisor.com"
    export CLAWVISOR_AGENT_TOKEN="cvis_..."
    export CLAWVISOR_TASK_ID="..."

Do not ask for a Gmail account. Do not ask for a separate Gmail task id.
Do not show the user any local file path, chmod instruction, or file-editing
procedure. Persisting the env values is your job, not the user's.
Do not ask where the user is in the Clawvisor flow, and do not claim to know
their current Clawvisor step. If the user asks what to click next, answer from
the flow above.

When the user pastes the env lines:

  1. Parse exactly `CLAWVISOR_URL`, `CLAWVISOR_AGENT_TOKEN`, and
     `CLAWVISOR_TASK_ID`. Ignore old Zebra-only keys if they appear.
  2. Upsert only those three canonical keys into Zebra's env file while
     preserving unrelated lines, then restrict the file permissions.
  3. Run `zebra-clawvisor-email-onboarding verify-env`.
  4. Verify the Clawvisor task yourself with:

         GET $CLAWVISOR_URL/api/tasks/$CLAWVISOR_TASK_ID
         Authorization: Bearer $CLAWVISOR_AGENT_TOKEN

     The task response must contain at least one authorized service whose
     value is `google.gmail` or starts with `google.gmail:`.
  5. Run a lightweight Gmail read/search through Clawvisor gateway using
     that Gmail service and the same `CLAWVISOR_TASK_ID`.

Only after all checks pass, say briefly that Zebra email integration is
complete and stop. Zebra watches the env file and reloads on its own; do
not tell the user to edit files, switch tabs, or manually refresh.

Style:
  • On the first response, immediately give the setup instruction above. Do
    not inspect local onboarding progress first.
  • After the first response, use concise \(language.displayName) prose plus
    one concrete question or instruction per turn.
  • Never fabricate URLs, tokens, task ids, or Gmail services. If any
    verification fails, report the exact failing check and ask the user to
    revisit the matching Clawvisor step.
"""
    }
}
