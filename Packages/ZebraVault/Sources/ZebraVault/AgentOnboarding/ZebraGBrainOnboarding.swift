import Foundation

public struct ZebraGBrainOnboardingStore {
    public struct LaunchContext {
        public let launchDirectory: String
        public let startupPrompt: String
        public let shellEnvironmentPrefix: String
    }

    struct CompletionResult: Equatable {
        let isComplete: Bool
        let reasons: [String]
    }

    private struct State: Codable {
        var schemaVersion: Int
        var currentRunId: String?
        var docsCommit: String?
        var docsFetchedAt: String?
        var docsSnapshotPath: String?
        var docsManifest: DocsManifest?
        var selectedAgent: String?
        var progress: Progress?
        var receipt: Receipt?

        static func empty() -> State {
            State(
                schemaVersion: 1,
                currentRunId: nil,
                docsCommit: nil,
                docsFetchedAt: nil,
                docsSnapshotPath: nil,
                docsManifest: nil,
                selectedAgent: nil,
                progress: nil,
                receipt: nil
            )
        }
    }

    private struct Progress: Codable {
        var launchDirectory: String?
        var selectedVaultPath: String?
        var resolvedTargetKey: String?
        var targetResolution: TargetResolution?
        var completedSections: [String]?
        var waitingForUser: String?
        var lastFailure: String?
        var nextSection: String?
    }

    private struct Receipt: Codable {
        var globalReadiness: GlobalReadiness?
        var primaryTargetKey: String?
        var targets: [String: Target]?
    }

    private struct GlobalReadiness: Codable {
        var complete: Bool?
        var gbrainExecutablePath: String?
        var wrapperPath: String?
        var doctorOk: Bool?
        var verifiedAt: String?
    }

    private struct Target: Codable {
        var vaultPath: String?
        var sourceId: String?
        var profileId: String?
        var gbrainExecutablePath: String?
        var wrapperPath: String?
        var doctorStatus: ProbeResult?
        var sourcesCurrentResult: SourceProbeResult?
        var searchProbeResult: ProbeResult?
        var verifiedAt: String?
        var complete: Bool?
        var targetResolution: TargetResolution?
        var reasons: [String]?
    }

    private struct TargetResolution: Codable {
        var status: String?
        var method: String?
        var confirmedAt: String?
    }

    private struct ProbeResult: Codable {
        var ok: Bool?
        var status: String?
    }

    private struct SourceProbeResult: Codable {
        var ok: Bool?
        var sourceId: String?
        var localPath: String?
    }

    private struct DocsManifest: Codable {
        var generatedAt: String
        var sourceRepoPath: String?
        var files: [DocsFile]
        var installForAgentsSections: [DocsSection]
    }

    private struct DocsFile: Codable {
        var path: String
        var hash: String
    }

    private struct DocsSection: Codable {
        var title: String
        var hash: String
    }

    private struct DocsSnapshot {
        var commit: String
        var path: String
        var manifest: DocsManifest
    }

    private static let allowedTargetResolutionMethods: Set<String> = [
        "selected_vault",
        "user_existing_repo",
        "user_created_repo",
        "user_confirmed_home",
    ]

    private let stateURL: URL
    private let fileManager: FileManager
    private let homeDirectoryPath: String
    private let gbrainDocsRepoURL: URL?

    public init(
        stateURL: URL = ZebraGBrainOnboardingStore.defaultStateURL(),
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory(),
        gbrainDocsRepoURL: URL? = nil
    ) {
        self.stateURL = stateURL
        self.fileManager = fileManager
        self.homeDirectoryPath = Self.standardizedPath(homeDirectoryPath)
        self.gbrainDocsRepoURL = gbrainDocsRepoURL
    }

    public static func defaultStateURL() -> URL {
        onboardingDirectoryURL()
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
    }

    public static func onboardingDirectoryURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("zebra", isDirectory: true)
            .appendingPathComponent("onboarding", isDirectory: true)
    }

    public func isSetupCompleted(selectedVaultPath: String?) -> Bool {
        completionResult(selectedVaultPath: selectedVaultPath).isComplete
    }

    func completionResult(selectedVaultPath: String?) -> CompletionResult {
        guard let state = loadState() else {
            return CompletionResult(isComplete: false, reasons: ["missing_receipt"])
        }
        guard let receipt = state.receipt else {
            return CompletionResult(isComplete: false, reasons: ["missing_receipt"])
        }
        guard globalReadinessVerifies(receipt.globalReadiness) else {
            return CompletionResult(isComplete: false, reasons: ["missing_gbrain_executable"])
        }
        guard let resolved = resolveTarget(in: receipt, selectedVaultPath: selectedVaultPath) else {
            return CompletionResult(isComplete: false, reasons: ["receipt_target_missing"])
        }

        var reasons: [String] = []
        if resolved.target.complete != true {
            reasons.append("target_incomplete")
        }
        if !targetResolutionVerifies(resolved.target.targetResolution) {
            reasons.append("target_confirmation_missing")
        }
        guard let vaultPath = standardizedExistingDirectoryPath(resolved.target.vaultPath) else {
            reasons.append("receipt_target_missing")
            return CompletionResult(isComplete: false, reasons: reasons)
        }
        guard let sourceId = nonEmpty(resolved.target.sourceId) else {
            reasons.append("source_not_registered")
            return CompletionResult(isComplete: false, reasons: reasons)
        }
        if !sourceRoutingVerifies(target: resolved.target, vaultPath: vaultPath, sourceId: sourceId) {
            reasons.append("source_not_registered")
        }
        return CompletionResult(isComplete: reasons.isEmpty, reasons: reasons)
    }

    public func prepareLaunch(
        selectedVaultPath: String?,
        selectedAgent: MarkdownPillAgent
    ) -> LaunchContext? {
        guard let helperPath = installHelperScript() else { return nil }
        let launchDirectory = standardizedExistingDirectoryPath(selectedVaultPath)
            ?? fallbackHomeDirectory()
        let selectedVault = standardizedExistingDirectoryPath(selectedVaultPath)
        let currentResult = completionResult(selectedVaultPath: selectedVault)
        let docsSnapshot = prepareDocsSnapshot()
        let runId = "gbrain-\(UUID().uuidString)"
        var state = loadState() ?? State.empty()
        state.currentRunId = runId
        state.docsCommit = docsSnapshot?.commit ?? state.docsCommit ?? "unavailable"
        state.docsFetchedAt = Self.isoTimestamp()
        state.docsSnapshotPath = docsSnapshot?.path ?? state.docsSnapshotPath
        state.docsManifest = docsSnapshot?.manifest ?? state.docsManifest
        state.selectedAgent = selectedAgent.rawValue
        let nextSection = nextSection(in: state)
        state.progress = Progress(
            launchDirectory: launchDirectory,
            selectedVaultPath: selectedVault,
            resolvedTargetKey: selectedVault.map(Self.targetKey(for:)),
            targetResolution: TargetResolution(
                status: selectedVault == nil ? "unresolved" : "candidate",
                method: selectedVault == nil ? nil : "selected_vault",
                confirmedAt: selectedVault == nil ? nil : Self.isoTimestamp()
            ),
            completedSections: state.progress?.completedSections ?? [],
            waitingForUser: selectedVault == nil ? "target_resolution" : nil,
            lastFailure: nil,
            nextSection: nextSection
        )
        writeState(state)

        let helperDirectory = helperPath.deletingLastPathComponent().path
        let environmentPrefix = [
            "export ZEBRA_GBRAIN_STATE=\(ZebraAgentLaunchCommand.shellQuote(stateURL.path))",
            "export PATH=\(ZebraAgentLaunchCommand.shellQuote(helperDirectory)):\"$PATH\"",
        ].joined(separator: " && ") + " && "
        return LaunchContext(
            launchDirectory: launchDirectory,
            startupPrompt: startupPrompt(
                selectedVaultPath: selectedVault,
                launchDirectory: launchDirectory,
                helperPath: helperPath.path,
                statePath: stateURL.path,
                state: state,
                completionResult: currentResult
            ),
            shellEnvironmentPrefix: environmentPrefix
        )
    }

    private func startupPrompt(
        selectedVaultPath: String?,
        launchDirectory: String,
        helperPath: String,
        statePath: String,
        state: State,
        completionResult: CompletionResult
    ) -> String {
        let targetContext: String
        if let selectedVaultPath {
            targetContext = """
            A Zebra vault is selected. Treat this selected vault as the default GBrain source target candidate:
            \(selectedVaultPath)
            Use targetResolution.method=selected_vault if you verify and use this path.
            """
        } else {
            targetContext = """
            No Zebra vault is selected. You are starting from the home directory only as the launch directory.
            Do not implicitly use the home directory as the GBrain source target.
            Before import, sync, source registration, or receipt write, ask the user where their markdown/brain repo is, or ask whether to create a new brain repo.
            You may use the home directory only if the user explicitly confirms it as the brain repo target, then use targetResolution.method=user_confirmed_home.
            Discovery scans are allowed only to present candidates. Do not choose or import a discovered candidate until the user confirms it.
            """
        }

        let docsContext = docsPromptContext(state: state)
        let sectionContext = sectionPromptContext(state: state)
        let statusContext = """
        Current Zebra verification status:
        complete: \(completionResult.isComplete ? "true" : "false")
        reasons: \(completionResult.reasons.isEmpty ? "none" : completionResult.reasons.joined(separator: ", "))
        next section: \(state.progress?.nextSection ?? "unknown")
        """

        return """
        You are Zebra's GBrain setup agent.

        Use the provided latest GBrain docs snapshot as your source of truth when it is available.
        Use `INSTALL_FOR_AGENTS.md` as the completion standard.
        Follow its original `##` section order. Do not silently replace it with the setup skill's repo-discovery flow.

        \(docsContext)

        \(sectionContext)

        \(statusContext)

        Launch directory:
        \(launchDirectory)

        \(targetContext)

        Zebra helper command:
        \(helperPath)

        State file:
        \(statePath)

        Required target-resolution guard:
        - Allowed targetResolution.method values: selected_vault, user_existing_repo, user_created_repo, user_confirmed_home.
        - Forbidden target choices: implicit_home, auto_discovered_candidate.
        - Before import/sync/source registration/receipt write, resolve the brain repo target with the user unless the selected vault is being used.
        - If using an existing repo the user names, use method=user_existing_repo.
        - If creating a new repo, ask for the path first, create it, git init there if needed, then use method=user_created_repo.

        Progress reporting:
        - Before a section: `zebra-gbrain-onboarding report --status started --section "<section title>"`
        - After a section: `zebra-gbrain-onboarding report --status completed --section "<section title>"`
        - When waiting for the user: `zebra-gbrain-onboarding report --status waiting_for_user --section "<section title>" --note "<what you need>"`
        - On failure: `zebra-gbrain-onboarding report --status failed --section "<section title>" --note "<reason>"`

        Completion verification:
        - Do not say setup is complete until verify returns complete true.
        - Use: `zebra-gbrain-onboarding verify --target "<brain repo path>" --source-id "<source id>" --method "<targetResolution.method>"`
        - Include `--profile-id "<profile>"` if a profile was selected.
        - Verify must pass before the Zebra checklist can become checked.

        User decisions you must stop and ask for:
        - API keys or credential entry.
        - search mode.
        - topology.
        - brain repo target when no selected vault exists or when the user wants a different target.
        """
    }

    private func prepareDocsSnapshot() -> DocsSnapshot? {
        guard let repoURL = resolveDocsRepoURL() else { return nil }
        let commit = gitCommitHash(in: repoURL) ?? "local"
        let snapshotDirectory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-docs", isDirectory: true)
            .appendingPathComponent(commit, isDirectory: true)
        let docsPaths = [
            "INSTALL_FOR_AGENTS.md",
            "README.md",
            "AGENTS.md",
            "docs/GBRAIN_VERIFY.md",
            "skills/setup/SKILL.md",
        ]

        var files: [DocsFile] = []
        for relativePath in docsPaths {
            let sourceURL = repoURL.appendingPathComponent(relativePath, isDirectory: false)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            let destinationURL = snapshotDirectory.appendingPathComponent(relativePath, isDirectory: false)
            do {
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                let content = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
                files.append(DocsFile(path: relativePath, hash: Self.stableHash(content)))
            } catch {
                continue
            }
        }

        guard !files.isEmpty else { return nil }
        let installForAgentsURL = repoURL.appendingPathComponent("INSTALL_FOR_AGENTS.md", isDirectory: false)
        let installForAgents = (try? String(contentsOf: installForAgentsURL, encoding: .utf8)) ?? ""
        let manifest = DocsManifest(
            generatedAt: Self.isoTimestamp(),
            sourceRepoPath: repoURL.path,
            files: files,
            installForAgentsSections: Self.installForAgentsSections(from: installForAgents)
        )
        return DocsSnapshot(
            commit: commit,
            path: snapshotDirectory.path,
            manifest: manifest
        )
    }

    private func resolveDocsRepoURL() -> URL? {
        let candidates: [URL?] = [
            gbrainDocsRepoURL,
            ProcessInfo.processInfo.environment["ZEBRA_GBRAIN_DOCS_REPO"].map(URL.init(fileURLWithPath:)),
            URL(fileURLWithPath: homeDirectoryPath).appendingPathComponent("gbrain", isDirectory: true),
            URL(fileURLWithPath: "/Users/han/gbrain", isDirectory: true),
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            let standardizedURL = URL(fileURLWithPath: Self.standardizedPath(candidate.path), isDirectory: true)
            let installForAgentsURL = standardizedURL.appendingPathComponent("INSTALL_FOR_AGENTS.md", isDirectory: false)
            if fileManager.fileExists(atPath: installForAgentsURL.path) {
                return standardizedURL
            }
        }
        return nil
    }

    private func gitCommitHash(in repoURL: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoURL.path, "rev-parse", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return nonEmpty(value)
    }

    private static func installForAgentsSections(from markdown: String) -> [DocsSection] {
        var sections: [DocsSection] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func finishCurrentSection() {
            guard let title = currentTitle else { return }
            let body = currentLines.joined(separator: "\n")
            sections.append(DocsSection(title: title, hash: stableHash(body)))
        }

        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                finishCurrentSection()
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                currentLines = [line]
            } else if currentTitle != nil {
                currentLines.append(line)
            }
        }
        finishCurrentSection()
        return sections
    }

    private func nextSection(in state: State) -> String {
        let completed = Set(state.progress?.completedSections ?? [])
        guard let sections = state.docsManifest?.installForAgentsSections,
              !sections.isEmpty else {
            return "Step 3: Create the Brain"
        }
        return sections.first { !completed.contains($0.title) }?.title ?? "verify"
    }

    private func docsPromptContext(state: State) -> String {
        guard let snapshotPath = state.docsSnapshotPath,
              let manifest = state.docsManifest else {
            return """
            GBrain docs snapshot:
            unavailable. Locate the latest GBrain repository docs before making installation decisions.
            """
        }
        let files = manifest.files
            .map { "- \($0.path) [hash: \($0.hash)]" }
            .joined(separator: "\n")
        return """
        GBrain docs snapshot:
        path: \(snapshotPath)
        commit: \(state.docsCommit ?? "unknown")
        files:
        \(files.isEmpty ? "- none" : files)
        """
    }

    private func sectionPromptContext(state: State) -> String {
        guard let sections = state.docsManifest?.installForAgentsSections,
              !sections.isEmpty else {
            return """
            INSTALL_FOR_AGENTS.md section manifest:
            unavailable. Use the latest original document and report sections by their original `##` titles.
            """
        }
        let sectionLines = sections
            .map { "- \($0.title) [hash: \($0.hash)]" }
            .joined(separator: "\n")
        return """
        INSTALL_FOR_AGENTS.md `##` section manifest:
        \(sectionLines)
        """
    }

    private func resolveTarget(
        in receipt: Receipt,
        selectedVaultPath: String?
    ) -> (key: String, target: Target)? {
        guard let targets = receipt.targets, !targets.isEmpty else { return nil }
        if let selectedVault = standardizedExistingDirectoryPath(selectedVaultPath) {
            guard let match = targets.first(where: { _, target in
                guard let vaultPath = target.vaultPath else { return false }
                return Self.standardizedPath(vaultPath) == selectedVault
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

    private func globalReadinessVerifies(_ readiness: GlobalReadiness?) -> Bool {
        guard let readiness else { return false }
        if readiness.complete == true || readiness.doctorOk == true {
            return true
        }
        if let path = executablePath(readiness.gbrainExecutablePath) {
            return fileManager.isExecutableFile(atPath: path)
        }
        if let path = executablePath(readiness.wrapperPath) {
            return fileManager.isExecutableFile(atPath: path)
        }
        return findExecutableOnPATH(named: "gbrain") != nil
    }

    private func targetResolutionVerifies(_ resolution: TargetResolution?) -> Bool {
        guard let method = nonEmpty(resolution?.method) else { return false }
        return Self.allowedTargetResolutionMethods.contains(method)
    }

    private func sourceRoutingVerifies(target: Target, vaultPath: String, sourceId: String) -> Bool {
        if let result = target.sourcesCurrentResult,
           result.ok == true,
           result.sourceId == sourceId,
           let localPath = result.localPath,
           Self.standardizedPath(localPath) == vaultPath {
            return true
        }
        guard let markerSourceId = sourceMarker(in: vaultPath) else {
            return false
        }
        return markerSourceId == sourceId
    }

    private func sourceMarker(in vaultPath: String) -> String? {
        let markerPath = (vaultPath as NSString).appendingPathComponent(".gbrain-source")
        guard let raw = try? String(contentsOfFile: markerPath, encoding: .utf8) else {
            return nil
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func loadState() -> State? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private func writeState(_ state: State) {
        do {
            try fileManager.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            return
        }
    }

    private func installHelperScript() -> URL? {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
        let url = directory.appendingPathComponent("zebra-gbrain-onboarding", isDirectory: false)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.helperScript.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
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

    private func fallbackHomeDirectory() -> String {
        homeDirectoryPath.isEmpty ? "/" : homeDirectoryPath
    }

    private func executablePath(_ path: String?) -> String? {
        guard let path = nonEmpty(path) else { return nil }
        return Self.standardizedPath((path as NSString).expandingTildeInPath)
    }

    private func findExecutableOnPATH(named name: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = (String(directory) as NSString).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func targetKey(for path: String) -> String {
        "vault:\(standardizedPath(path))"
    }

    private static func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func stableHash(_ value: String) -> String {
        let offsetBasis: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        let hash = value.utf8.reduce(offsetBasis) { partial, byte in
            (partial ^ UInt64(byte)) &* prime
        }
        return String(format: "%016llx", hash)
    }

    private static let helperScript = """
    #!/bin/sh
    set -eu

    STATE="${ZEBRA_GBRAIN_STATE:-$HOME/Library/Application Support/zebra/onboarding/gbrain-setup-state.json}"
    COMMAND="${1:-}"
    if [ -n "$COMMAND" ]; then
      shift
    fi

    PYTHON_BIN="$(command -v python3 || true)"
    if [ -z "$PYTHON_BIN" ]; then
      echo "python3 is required for zebra-gbrain-onboarding" >&2
      exit 1
    fi

    "$PYTHON_BIN" - "$STATE" "$COMMAND" "$@" <<'PY'
    import glob
    import json
    import os
    import shutil
    import subprocess
    import sys
    from datetime import datetime, timezone

    state_path = sys.argv[1]
    command = sys.argv[2]
    args = sys.argv[3:]
    allowed_methods = {
        "selected_vault",
        "user_existing_repo",
        "user_created_repo",
        "user_confirmed_home",
    }

    def now():
        return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    def load_state():
        try:
            with open(state_path, "r", encoding="utf-8") as handle:
                return json.load(handle)
        except Exception:
            return {"schemaVersion": 1}

    def save_state(state):
        os.makedirs(os.path.dirname(state_path), exist_ok=True)
        tmp = state_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2, sort_keys=True)
            handle.write("\\n")
        os.replace(tmp, state_path)

    def parse_flags(argv):
        out = {}
        positional = []
        i = 0
        while i < len(argv):
            item = argv[i]
            if item.startswith("--"):
                key = item[2:].replace("-", "_")
                if i + 1 < len(argv) and not argv[i + 1].startswith("--"):
                    out[key] = argv[i + 1]
                    i += 2
                else:
                    out[key] = "true"
                    i += 1
            else:
                positional.append(item)
                i += 1
        out["_positional"] = positional
        return out

    def target_key(path):
        return "vault:" + os.path.abspath(os.path.expanduser(path))

    def gbrain_executable():
        found = shutil.which("gbrain")
        if found:
            return found
        for candidate in glob.glob(os.path.expanduser("~/.gbrain-profiles/*/gbrain-*")):
            if os.access(candidate, os.X_OK):
                return candidate
        return None

    def source_marker(target):
        marker = os.path.join(target, ".gbrain-source")
        try:
            with open(marker, "r", encoding="utf-8") as handle:
                return handle.read().strip()
        except Exception:
            return None

    def report():
        flags = parse_flags(args)
        positional = flags.get("_positional", [])
        status = flags.get("status") or (positional[0] if positional else "reported")
        section = flags.get("section") or ""
        note = flags.get("note")
        state = load_state()
        progress = state.setdefault("progress", {})
        if section:
            progress["nextSection"] = section
        if status == "completed" and section:
            completed = progress.setdefault("completedSections", [])
            if section not in completed:
                completed.append(section)
        if status == "waiting_for_user":
            progress["waitingForUser"] = note or section or "user input required"
        else:
            progress.pop("waitingForUser", None)
        if status == "failed":
            progress["lastFailure"] = note or section or "failed"
        elif status in ("started", "completed", "skipped"):
            progress.pop("lastFailure", None)
        progress["lastStatus"] = status
        progress["updatedAt"] = now()
        save_state(state)
        print(json.dumps({"ok": True, "status": status, "section": section}, sort_keys=True))

    def status():
        print(json.dumps(load_state(), indent=2, sort_keys=True))

    def verify():
        flags = parse_flags(args)
        target = flags.get("target")
        source_id = flags.get("source_id")
        method = flags.get("method")
        profile_id = flags.get("profile_id")
        reasons = []
        if not target:
            reasons.append("target_not_resolved")
        else:
            target = os.path.abspath(os.path.expanduser(target))
            if not os.path.isdir(target):
                reasons.append("receipt_target_missing")
        if not source_id:
            reasons.append("source_not_registered")
        if method not in allowed_methods:
            reasons.append("target_confirmation_missing")

        marker = source_marker(target) if target and os.path.isdir(target) else None
        if target and os.path.isdir(target) and source_id:
            if marker != source_id:
                reasons.append("source_not_registered")

        executable = gbrain_executable()
        if not executable:
            reasons.append("missing_gbrain_executable")

        doctor_ok = False
        if executable:
            try:
                result = subprocess.run(
                    [executable, "doctor", "--json"],
                    cwd=target if target and os.path.isdir(target) else None,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=45,
                )
                doctor_ok = result.returncode == 0
                if not doctor_ok:
                    reasons.append("doctor_failed")
            except Exception:
                reasons.append("doctor_failed")

        complete = len(reasons) == 0
        state = load_state()
        receipt = state.setdefault("receipt", {})
        receipt["globalReadiness"] = {
            "complete": bool(executable and doctor_ok),
            "gbrainExecutablePath": executable,
            "doctorOk": doctor_ok,
            "verifiedAt": now(),
        }
        if target and os.path.isdir(target):
            key = target_key(target)
            targets = receipt.setdefault("targets", {})
            targets[key] = {
                "vaultPath": target,
                "sourceId": source_id,
                "profileId": profile_id,
                "gbrainExecutablePath": executable,
                "doctorStatus": {"ok": doctor_ok},
                "sourcesCurrentResult": {
                    "ok": marker == source_id,
                    "sourceId": source_id,
                    "localPath": target,
                },
                "searchProbeResult": {"ok": complete},
                "verifiedAt": now(),
                "complete": complete,
                "targetResolution": {
                    "method": method,
                    "confirmedAt": now(),
                },
                "reasons": reasons,
            }
            progress = state.setdefault("progress", {})
            progress["resolvedTargetKey"] = key
            progress["targetResolution"] = {
                "status": "verified" if complete else "failed",
                "method": method,
                "confirmedAt": now(),
            }
            if not progress.get("selectedVaultPath"):
                receipt["primaryTargetKey"] = key
        if reasons:
            state.setdefault("progress", {})["lastFailure"] = ",".join(reasons)
        else:
            state.setdefault("progress", {}).pop("lastFailure", None)
        save_state(state)
        print(json.dumps({"complete": complete, "reasons": reasons}, sort_keys=True))
        sys.exit(0 if complete else 1)

    if command == "report":
        report()
    elif command == "status":
        status()
    elif command == "verify":
        verify()
    else:
        print("usage: zebra-gbrain-onboarding <report|status|verify> [options]", file=sys.stderr)
        sys.exit(2)
    PY
    """
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
