import Foundation

public struct ZebraGBrainAdapterOnboardingStore {
    public struct LaunchContext {
        public let launchDirectory: String
        public let startupLine: String
    }

    public struct CompletionResult: Equatable {
        public let isComplete: Bool
        public let reasons: [String]
    }

    private struct State: Codable {
        var schemaVersion: Int
        var adapterSourceBinding: AdapterSourceBinding?
        var receipt: Receipt?
    }

    private struct AdapterSourceBinding: Codable {
        var repoPath: String?
        var remote: String?
        var ref: String?
        var commit: String?
        var status: String?
    }

    private struct Receipt: Codable {
        var complete: Bool?
        var targetKey: String?
        var targetVaultPath: String?
        var adapterRepoPath: String?
        var adapterRemote: String?
        var adapterRef: String?
        var adapterCommit: String?
        var installerPath: String?
        var installedAt: String?
        var verifiedAt: String?
        var checks: [String: Bool]?
        var reasons: [String]?
    }

    private struct GBrainState: Codable {
        var activeGBrainBinding: ActiveGBrainBinding?
        var receipt: GBrainReceipt?
    }

    private struct ActiveGBrainBinding: Codable {
        var sourceRepoPath: String?
        var sourceRepoStatus: String?
        var gbrainHomePath: String?
        var confirmedAt: String?
    }

    private struct GBrainReceipt: Codable {
        var globalReadiness: GlobalReadiness?
        var primaryTargetKey: String?
        var targets: [String: GBrainTarget]?
    }

    private struct GlobalReadiness: Codable {
        var complete: Bool?
    }

    private struct GBrainTarget: Codable {
        var vaultPath: String?
        var complete: Bool?
    }

    private let stateURL: URL
    private let gbrainOnboardingStateURL: URL
    private let fileManager: FileManager
    private let homeDirectoryPath: String

    public init(
        stateURL: URL = ZebraGBrainAdapterOnboardingStore.defaultStateURL(),
        gbrainOnboardingStateURL: URL = ZebraGBrainOnboardingStore.defaultStateURL(),
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory()
    ) {
        self.stateURL = stateURL
        self.gbrainOnboardingStateURL = gbrainOnboardingStateURL
        self.fileManager = fileManager
        self.homeDirectoryPath = Self.standardizedPath(homeDirectoryPath)
    }

    public static func defaultStateURL() -> URL {
        ZebraGBrainOnboardingStore.onboardingDirectoryURL()
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
    }

    public func isSetupCompleted(selectedVaultPath: String?) -> Bool {
        cachedCompletionResult(selectedVaultPath: selectedVaultPath).isComplete
    }

    public func cachedCompletionResult(selectedVaultPath: String?) -> CompletionResult {
        guard let state = loadState(),
              let receipt = state.receipt else {
            return CompletionResult(isComplete: false, reasons: ["missing_receipt"])
        }
        guard receipt.complete == true else {
            return CompletionResult(
                isComplete: false,
                reasons: nonEmpty(receipt.reasons) ?? ["receipt_incomplete"]
            )
        }
        guard let gbrainState = loadGBrainState(),
              let gbrainReceipt = gbrainState.receipt else {
            return CompletionResult(isComplete: false, reasons: ["gbrain_receipt_missing"])
        }
        guard gbrainReceipt.globalReadiness?.complete == true else {
            return CompletionResult(isComplete: false, reasons: ["gbrain_receipt_incomplete"])
        }
        guard let resolved = resolveTarget(in: gbrainReceipt, selectedVaultPath: selectedVaultPath),
              resolved.target.complete == true else {
            return CompletionResult(isComplete: false, reasons: ["gbrain_target_missing"])
        }
        guard receipt.targetKey == resolved.key else {
            return CompletionResult(isComplete: false, reasons: ["target_key_mismatch"])
        }
        guard let targetVaultPath = standardizedExistingDirectoryPath(receipt.targetVaultPath),
              let resolvedVaultPath = standardizedExistingDirectoryPath(resolved.target.vaultPath),
              targetVaultPath == resolvedVaultPath else {
            return CompletionResult(isComplete: false, reasons: ["target_path_mismatch"])
        }
        guard let sourceRepoPath = standardizedExistingDirectoryPath(gbrainState.activeGBrainBinding?.sourceRepoPath) else {
            return CompletionResult(isComplete: false, reasons: ["gbrain_source_binding_missing"])
        }
        guard let adapterRepoPath = standardizedExistingDirectoryPath(receipt.adapterRepoPath) else {
            return CompletionResult(isComplete: false, reasons: ["adapter_repo_missing"])
        }
        guard adapterRepoPath == expectedAdapterRepoPath(sourceRepoPath: sourceRepoPath) else {
            return CompletionResult(isComplete: false, reasons: ["adapter_repo_path_mismatch"])
        }
        let checks = installedChecks(targetVaultPath: targetVaultPath)
        let failedChecks = checks
            .filter { !$0.value }
            .map(\.key)
            .sorted()
        guard failedChecks.isEmpty else {
            return CompletionResult(isComplete: false, reasons: failedChecks.map { "missing:\($0)" })
        }
        return CompletionResult(isComplete: true, reasons: [])
    }

    public func prepareLaunch(selectedVaultPath: String?) -> LaunchContext? {
        guard let helperPath = installHelperScript() else { return nil }
        let launchDirectory = onboardingWorkDirectoryPath()
        let helperDirectory = helperPath.deletingLastPathComponent().path
        var commands = [
            "cd \(ZebraAgentLaunchCommand.shellQuote(launchDirectory))",
            "export ZEBRA_GBRAIN_ADAPTER_STATE=\(ZebraAgentLaunchCommand.shellQuote(stateURL.path))",
            "export ZEBRA_GBRAIN_SETUP_STATE=\(ZebraAgentLaunchCommand.shellQuote(gbrainOnboardingStateURL.path))",
            "export ZEBRA_GBRAIN_ADAPTER_HOME=\(ZebraAgentLaunchCommand.shellQuote(homeDirectoryPath))",
            "export PATH=\(ZebraAgentLaunchCommand.shellQuote(helperDirectory)):\"$PATH\"",
        ]
        if let selectedVaultPath = standardizedExistingDirectoryPath(selectedVaultPath) {
            commands.append("export ZEBRA_GBRAIN_ADAPTER_SELECTED_VAULT=\(ZebraAgentLaunchCommand.shellQuote(selectedVaultPath))")
        }
        commands.append("\(ZebraAgentLaunchCommand.shellQuote(helperPath.path)) run")
        return LaunchContext(
            launchDirectory: launchDirectory,
            startupLine: commands.joined(separator: " && ") + "\r"
        )
    }

    func stateDirectoryPath() -> String {
        Self.standardizedPath(stateURL.deletingLastPathComponent().path)
    }

    private func loadState() -> State? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private func loadGBrainState() -> GBrainState? {
        guard let data = try? Data(contentsOf: gbrainOnboardingStateURL) else { return nil }
        return try? JSONDecoder().decode(GBrainState.self, from: data)
    }

    private func resolveTarget(
        in receipt: GBrainReceipt,
        selectedVaultPath: String?
    ) -> (key: String, target: GBrainTarget)? {
        guard let targets = receipt.targets, !targets.isEmpty else { return nil }
        if let selectedVault = standardizedExistingDirectoryPath(selectedVaultPath) {
            guard let match = targets.first(where: { _, target in
                guard let vaultPath = target.vaultPath else { return false }
                return Self.standardizedPath((vaultPath as NSString).expandingTildeInPath) == selectedVault
            }) else {
                return nil
            }
            return (match.key, match.value)
        }
        guard let primaryTargetKey = nonEmpty(receipt.primaryTargetKey),
              let target = targets[primaryTargetKey] else {
            return nil
        }
        return (primaryTargetKey, target)
    }

    private func installedChecks(targetVaultPath: String) -> [String: Bool] {
        let targetURL = URL(fileURLWithPath: targetVaultPath, isDirectory: true)
        return [
            "adapterSkillRouter": fileExists(targetURL, ".gbrain-adapter/skills/router/SKILL.md"),
            "adapterSkillDailyTaskManager": fileExists(targetURL, ".gbrain-adapter/skills/daily-task-manager/SKILL.md"),
            "adapterSkillDailyTaskPrep": fileExists(targetURL, ".gbrain-adapter/skills/daily-task-prep/SKILL.md"),
            "adapterSkillSourceToTasks": fileExists(targetURL, ".gbrain-adapter/skills/source-to-tasks/SKILL.md"),
            "adapterSkillZebraDailyPlanner": fileExists(targetURL, ".gbrain-adapter/skills/zebra-daily-planner/SKILL.md"),
            "goalsReadme": fileExists(targetURL, "goals/README.md"),
            "tasksReadme": fileExists(targetURL, "tasks/README.md"),
            "resolverBlock": adapterBlockExists(targetURL, "RESOLVER.md"),
            "schemaBlock": adapterBlockExists(targetURL, "schema.md"),
            "agentsBlock": adapterBlockExists(targetURL, "AGENTS.md"),
        ]
    }

    private func fileExists(_ root: URL, _ relativePath: String) -> Bool {
        fileManager.fileExists(atPath: root.appendingPathComponent(relativePath, isDirectory: false).path)
    }

    private func adapterBlockExists(_ root: URL, _ relativePath: String) -> Bool {
        let url = root.appendingPathComponent(relativePath, isDirectory: false)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains("<!-- gbrain-adapter:begin goals-tasks -->")
            && text.contains("<!-- gbrain-adapter:end goals-tasks -->")
    }

    private func installHelperScript() -> URL? {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
        let url = directory.appendingPathComponent("zebra-gbrain-adapter-onboarding", isDirectory: false)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.helperScript.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
    }

    private func onboardingWorkDirectoryPath() -> String {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-adapter-work", isDirectory: true)
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

    private func expectedAdapterRepoPath(sourceRepoPath: String) -> String {
        let sourceRepoURL = URL(fileURLWithPath: sourceRepoPath, isDirectory: true)
        return Self.standardizedPath(
            sourceRepoURL
                .deletingLastPathComponent()
                .appendingPathComponent("gbrain-adapter", isDirectory: true)
                .path
        )
    }

    private static func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private func nonEmpty(_ values: [String]?) -> [String]? {
        guard let values, !values.isEmpty else { return nil }
        return values
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static let helperScript = """
    #!/bin/sh
    set -eu

    STATE="${ZEBRA_GBRAIN_ADAPTER_STATE:-$HOME/Library/Application Support/zebra/onboarding/gbrain-adapter-state.json}"
    COMMAND="${1:-run}"
    if [ $# -gt 0 ]; then
      shift
    fi

    PYTHON_BIN="$(command -v python3 || true)"
    if [ -z "$PYTHON_BIN" ]; then
      echo "python3 is required for zebra-gbrain-adapter-onboarding" >&2
      exit 1
    fi

    "$PYTHON_BIN" - "$STATE" "$COMMAND" "$@" <<'PY'
    import json
    import os
    import shutil
    import subprocess
    import sys
    from datetime import datetime, timezone
    from pathlib import Path

    state_path = Path(sys.argv[1]).expanduser()
    command = sys.argv[2] or "run"
    home = Path(os.environ.get("ZEBRA_GBRAIN_ADAPTER_HOME") or str(Path.home())).expanduser()
    gbrain_state_path = Path(
        os.environ.get("ZEBRA_GBRAIN_SETUP_STATE")
        or str(home / "Library/Application Support/zebra/onboarding/gbrain-setup-state.json")
    ).expanduser()
    selected_vault = os.environ.get("ZEBRA_GBRAIN_ADAPTER_SELECTED_VAULT") or ""
    adapter_remote = os.environ.get("ZEBRA_GBRAIN_ADAPTER_REMOTE") or "https://github.com/namho-hong/gbrain-adapter.git"
    adapter_ref = os.environ.get("ZEBRA_GBRAIN_ADAPTER_REF") or "main"

    required_source_files = [
        "scripts/install.sh",
        "skills/router/SKILL.md",
        "skills/daily-task-manager/SKILL.md",
        "skills/daily-task-prep/SKILL.md",
        "skills/source-to-tasks/SKILL.md",
        "skills/zebra-daily-planner/SKILL.md",
        "templates/blocks/RESOLVER.goals-tasks.md",
        "templates/blocks/schema.goals-tasks.md",
        "templates/blocks/AGENTS.goals-tasks.md",
        "templates/goals/README.md",
        "templates/tasks/README.md",
    ]

    install_paths = [
        ("adapterSkillRouter", ".gbrain-adapter/skills/router/SKILL.md"),
        ("adapterSkillDailyTaskManager", ".gbrain-adapter/skills/daily-task-manager/SKILL.md"),
        ("adapterSkillDailyTaskPrep", ".gbrain-adapter/skills/daily-task-prep/SKILL.md"),
        ("adapterSkillSourceToTasks", ".gbrain-adapter/skills/source-to-tasks/SKILL.md"),
        ("adapterSkillZebraDailyPlanner", ".gbrain-adapter/skills/zebra-daily-planner/SKILL.md"),
        ("goalsReadme", "goals/README.md"),
        ("tasksReadme", "tasks/README.md"),
    ]

    block_paths = [
        ("resolverBlock", "RESOLVER.md"),
        ("schemaBlock", "schema.md"),
        ("agentsBlock", "AGENTS.md"),
    ]

    def now():
        return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    def load_json(path):
        try:
            with path.open("r", encoding="utf-8") as handle:
                return json.load(handle)
        except Exception:
            return {}

    def load_state():
        state = load_json(state_path)
        if not isinstance(state, dict):
            state = {}
        state.setdefault("schemaVersion", 1)
        return state

    def save_state(state):
        state_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = state_path.with_suffix(state_path.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2, sort_keys=True)
            handle.write("\\n")
        os.replace(tmp, state_path)

    def update_progress(phase, **fields):
        state = load_state()
        progress = state.get("progress") or {}
        progress.update(fields)
        progress["phase"] = phase
        progress["updatedAt"] = now()
        state["progress"] = progress
        save_state(state)

    def fail(reason, **fields):
        fields.setdefault("reasons", [reason])
        fields["lastFailure"] = reason
        update_progress("failed", **fields)
        print("zebra-gbrain-adapter-onboarding failed: " + reason, file=sys.stderr)
        sys.exit(1)

    def run_process(argv, *, cwd=None, check=True, timeout=180):
        result = subprocess.run(
            argv,
            cwd=str(cwd) if cwd else None,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
        if check and result.returncode != 0:
            message = "command_failed:" + " ".join(argv)
            if result.stderr.strip():
                message += ":" + result.stderr.strip().splitlines()[-1]
            raise RuntimeError(message)
        return result

    def standardized(path):
        return str(Path(path).expanduser().resolve(strict=False))

    def existing_directory(path):
        if not path:
            return ""
        candidate = Path(path).expanduser()
        if not candidate.is_dir():
            return ""
        return standardized(candidate)

    def gbrain_state():
        state = load_json(gbrain_state_path)
        if not isinstance(state, dict):
            return {}
        return state

    def resolve_target(state):
        receipt = state.get("receipt") or {}
        readiness = receipt.get("globalReadiness") or {}
        if not readiness.get("complete"):
            fail("gbrain_receipt_incomplete")
        targets = receipt.get("targets") or {}
        if not isinstance(targets, dict) or not targets:
            fail("gbrain_target_missing")
        if selected_vault:
            selected = standardized(selected_vault)
            for key, target in targets.items():
                if standardized((target or {}).get("vaultPath") or "") == selected:
                    if not (target or {}).get("complete"):
                        fail("gbrain_target_incomplete", targetKey=key)
                    return key, target
            fail("selected_vault_not_in_gbrain_receipt", selectedVault=selected)
        key = receipt.get("primaryTargetKey")
        target = targets.get(key or "")
        if not key or not target:
            fail("gbrain_primary_target_missing")
        if not target.get("complete"):
            fail("gbrain_target_incomplete", targetKey=key)
        return key, target

    def active_source_repo_path(state):
        binding = state.get("activeGBrainBinding") or {}
        source_repo = existing_directory(binding.get("sourceRepoPath") or "")
        if not source_repo:
            fail("gbrain_source_binding_missing")
        return Path(source_repo)

    def adapter_repo_path_for_source(source_repo):
        return source_repo.parent / "gbrain-adapter"

    def is_valid_adapter_repo(path):
        return all((path / rel).exists() for rel in required_source_files)

    def repo_commit(path):
        result = run_process(["git", "-C", str(path), "rev-parse", "HEAD"], check=False)
        return result.stdout.strip() if result.returncode == 0 else ""

    def ensure_git():
        if not shutil.which("git"):
            fail("git_missing")

    def ensure_adapter_repo(source_repo):
        ensure_git()
        adapter_repo = adapter_repo_path_for_source(source_repo)
        adapter_repo.parent.mkdir(parents=True, exist_ok=True)
        if adapter_repo.exists() and any(adapter_repo.iterdir()):
            if not (adapter_repo / ".git").exists() or not is_valid_adapter_repo(adapter_repo):
                fail("adapter_repo_path_blocked", adapterRepoPath=standardized(adapter_repo))
            update_progress(
                "updating_adapter_repo",
                adapterRepoPath=standardized(adapter_repo),
                adapterRemote=adapter_remote,
                adapterRef=adapter_ref,
            )
            run_process(["git", "-C", str(adapter_repo), "fetch", "--tags", "origin"], check=False)
            try:
                run_process(["git", "-C", str(adapter_repo), "checkout", adapter_ref])
            except Exception as error:
                fail("adapter_repo_checkout_failed", adapterRepoPath=standardized(adapter_repo), detail=str(error))
            run_process(["git", "-C", str(adapter_repo), "pull", "--ff-only"], check=False)
            status = "updated"
        else:
            update_progress(
                "cloning_adapter_repo",
                adapterRepoPath=standardized(adapter_repo),
                adapterRemote=adapter_remote,
                adapterRef=adapter_ref,
            )
            try:
                run_process(["git", "clone", adapter_remote, str(adapter_repo)])
                run_process(["git", "-C", str(adapter_repo), "checkout", adapter_ref])
            except Exception as error:
                fail("adapter_repo_clone_failed", adapterRepoPath=standardized(adapter_repo), detail=str(error))
            status = "cloned"
        if not is_valid_adapter_repo(adapter_repo):
            fail("adapter_repo_invalid", adapterRepoPath=standardized(adapter_repo))
        commit = repo_commit(adapter_repo)
        state = load_state()
        state["adapterSourceBinding"] = {
            "repoPath": standardized(adapter_repo),
            "remote": adapter_remote,
            "ref": adapter_ref,
            "commit": commit,
            "status": status,
            "confirmedAt": now(),
        }
        save_state(state)
        return adapter_repo, commit, status

    def target_dirty_status(target):
        result = run_process(["git", "-C", str(target), "rev-parse", "--is-inside-work-tree"], check=False)
        if result.returncode != 0:
            return ""
        paths = [
            "RESOLVER.md",
            "schema.md",
            "AGENTS.md",
            "goals/README.md",
            "tasks/README.md",
            ".gbrain-adapter",
        ]
        status = run_process(["git", "-C", str(target), "status", "--porcelain", "--"] + paths, check=False)
        return status.stdout.strip() if status.returncode == 0 else ""

    def installer_command(installer, target, dry_run):
        if os.access(installer, os.X_OK):
            argv = [str(installer), "--brain", str(target)]
        else:
            argv = ["/bin/bash", str(installer), "--brain", str(target)]
        if dry_run:
            argv.append("--dry-run")
        return argv

    def run_installer(adapter_repo, target):
        installer = adapter_repo / "scripts/install.sh"
        if not installer.exists():
            fail("adapter_installer_missing", adapterRepoPath=standardized(adapter_repo))
        update_progress("dry_run", adapterRepoPath=standardized(adapter_repo), targetVaultPath=standardized(target))
        try:
            run_process(installer_command(installer, target, True), timeout=120)
        except Exception as error:
            fail("adapter_dry_run_failed", detail=str(error), adapterRepoPath=standardized(adapter_repo), targetVaultPath=standardized(target))
        update_progress("installing", adapterRepoPath=standardized(adapter_repo), targetVaultPath=standardized(target))
        try:
            run_process(installer_command(installer, target, False), timeout=120)
        except Exception as error:
            fail("adapter_install_failed", detail=str(error), adapterRepoPath=standardized(adapter_repo), targetVaultPath=standardized(target))
        return installer

    def installed_checks(target):
        checks = {}
        for key, rel in install_paths:
            checks[key] = (target / rel).exists()
        for key, rel in block_paths:
            try:
                text = (target / rel).read_text(encoding="utf-8")
            except Exception:
                text = ""
            checks[key] = (
                "<!-- gbrain-adapter:begin goals-tasks -->" in text
                and "<!-- gbrain-adapter:end goals-tasks -->" in text
            )
        return checks

    def write_receipt(target_key, target, adapter_repo, commit, installer, checks):
        complete = all(checks.values())
        reasons = [] if complete else ["missing:" + key for key, value in sorted(checks.items()) if not value]
        state = load_state()
        state["receipt"] = {
            "complete": complete,
            "targetKey": target_key,
            "targetVaultPath": standardized(target),
            "adapterRepoPath": standardized(adapter_repo),
            "adapterRemote": adapter_remote,
            "adapterRef": adapter_ref,
            "adapterCommit": commit,
            "installerPath": standardized(installer),
            "installedAt": now(),
            "verifiedAt": now(),
            "checks": checks,
            "reasons": reasons,
        }
        progress = state.get("progress") or {}
        progress.update({
            "phase": "complete" if complete else "failed",
            "targetKey": target_key,
            "targetVaultPath": standardized(target),
            "adapterRepoPath": standardized(adapter_repo),
            "adapterCommit": commit,
            "updatedAt": now(),
        })
        if reasons:
            progress["lastFailure"] = "adapter_verify_failed"
            progress["reasons"] = reasons
        state["progress"] = progress
        save_state(state)
        return complete, reasons

    def run():
        gbrain = gbrain_state()
        target_key, target_record = resolve_target(gbrain)
        source_repo = active_source_repo_path(gbrain)
        target_path = existing_directory(target_record.get("vaultPath") or "")
        if not target_path:
            fail("target_vault_missing", targetKey=target_key)
        target = Path(target_path)
        dirty = target_dirty_status(target)
        if dirty:
            fail("target_dirty", targetKey=target_key, targetVaultPath=target_path, dirtyStatus=dirty)
        adapter_repo, commit, _ = ensure_adapter_repo(source_repo)
        installer = run_installer(adapter_repo, target)
        checks = installed_checks(target)
        complete, reasons = write_receipt(target_key, target, adapter_repo, commit, installer, checks)
        if not complete:
            fail("adapter_verify_failed", targetKey=target_key, targetVaultPath=target_path, reasons=reasons)
        print(json.dumps({"ok": True, "targetKey": target_key, "targetVaultPath": target_path, "adapterRepoPath": standardized(adapter_repo)}, sort_keys=True))

    def status():
        payload = {
            "statePath": str(state_path),
            "gbrainStatePath": str(gbrain_state_path),
            "selectedVault": selected_vault,
            "state": load_state(),
        }
        print(json.dumps(payload, indent=2, sort_keys=True))

    if command == "run":
        run()
    elif command == "status":
        status()
    else:
        fail("unknown_command:" + command)
    PY
    """
}
