import Foundation

public struct ZebraGBrainOnboardingStore {
    public struct LaunchContext {
        public let launchDirectory: String
        public let startupPrompt: String
        public let setupPacketPath: String
        public let shellEnvironmentPrefix: String
        public let allowTrustedAutomation: Bool
        public let allowLaunchDirectoryTrust: Bool
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
        var sectionRoles: [String: SectionRoleRecord]?
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
                sectionRoles: nil,
                progress: nil,
                receipt: nil
            )
        }
    }

    private struct SectionRoleRecord: Codable {
        var section: String?
        var sectionHash: String?
        var role: String?
        var roleSource: String?
        var roleConfidence: String?
        var roleEvidence: [String]?
        var updatedAt: String?
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

    private struct GlobalReadiness: Codable, Equatable {
        var complete: Bool?
        var gbrainExecutablePath: String?
        var wrapperPath: String?
        var doctorOk: Bool?
        var verifiedAt: String?
    }

    private struct Target: Codable, Equatable {
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

    private struct TargetResolution: Codable, Equatable {
        var status: String?
        var method: String?
        var confirmedAt: String?
    }

    private struct ProbeResult: Codable, Equatable {
        var ok: Bool?
        var status: String?
    }

    private struct SourceProbeResult: Codable, Equatable {
        var ok: Bool?
        var sourceId: String?
        var localPath: String?
    }

    private struct DocsManifest: Codable {
        var generatedAt: String
        var sourceRepoPath: String?
        var sourceKind: String?
        var sourceRef: String?
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

    private struct LiveVerificationResult {
        var complete: Bool
        var reasons: [String]
        var globalReadiness: GlobalReadiness
        var target: Target
    }

    private struct ProcessRunResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
        var timedOut: Bool
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
    private let environment: [String: String]

    public init(
        stateURL: URL = ZebraGBrainOnboardingStore.defaultStateURL(),
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory(),
        gbrainDocsRepoURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.stateURL = stateURL
        self.fileManager = fileManager
        self.homeDirectoryPath = Self.standardizedPath(homeDirectoryPath)
        self.gbrainDocsRepoURL = gbrainDocsRepoURL
        self.environment = environment
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
        if let waitingForUser = nonEmpty(state.progress?.waitingForUser) {
            return CompletionResult(isComplete: false, reasons: ["waiting_for_user:\(waitingForUser)"])
        }
        guard let receipt = state.receipt else {
            return CompletionResult(isComplete: false, reasons: ["missing_receipt"])
        }
        guard let resolved = resolveTarget(in: receipt, selectedVaultPath: selectedVaultPath) else {
            return CompletionResult(isComplete: false, reasons: ["receipt_target_missing"])
        }

        var reasons: [String] = []
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
        if !reasons.isEmpty {
            return CompletionResult(isComplete: false, reasons: reasons)
        }
        if activeRunRequiresImportIndexCompletion(in: state),
           !hasCompletedImportIndex(in: state) {
            reasons.append("import_index_not_completed")
            return CompletionResult(isComplete: false, reasons: reasons)
        }

        let live = liveVerificationResult(target: resolved.target, vaultPath: vaultPath, sourceId: sourceId)
        updateReceipt(with: live, targetKey: resolved.key)
        return CompletionResult(isComplete: live.complete, reasons: live.reasons)
    }

    private func activeRunRequiresImportIndexCompletion(in state: State) -> Bool {
        guard let progress = state.progress else { return false }
        return state.currentRunId != nil
            || progress.nextSection != nil
            || progress.waitingForUser != nil
            || !(progress.completedSections ?? []).isEmpty
    }

    private func hasCompletedImportIndex(in state: State) -> Bool {
        guard let completedSections = state.progress?.completedSections else { return false }
        return completedSections.contains { Self.isImportIndexSectionTitle($0) }
    }

    private static func isImportIndexSectionTitle(_ title: String) -> Bool {
        let normalized = normalizedSectionTitle(title)
        return normalized.contains("step 4")
            && normalized.contains("import")
            && normalized.contains("index")
    }

    private static func normalizedSectionTitle(_ title: String) -> String {
        let scalars = title.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars)
            .split(separator: " ")
            .joined(separator: " ")
    }

    public func prepareLaunch(
        selectedVaultPath: String?,
        selectedAgent: MarkdownPillAgent
    ) -> LaunchContext? {
        guard let helperPath = installHelperScript() else { return nil }
        let selectedVault = standardizedExistingDirectoryPath(selectedVaultPath)
        let launchDirectory = selectedVault ?? onboardingWorkDirectoryPath()
        let allowTrustedAutomation = selectedVault != nil
        let currentResult = completionResult(selectedVaultPath: selectedVault)
        let docsSnapshot = prepareDocsSnapshot()
        let runId = "gbrain-\(UUID().uuidString)"
        var state = loadState() ?? State.empty()
        let previousProgress = state.progress
        let previousDocsFingerprint = Self.docsManifestFingerprint(state.docsManifest)
        state.currentRunId = runId
        state.docsCommit = docsSnapshot?.commit ?? state.docsCommit ?? "unavailable"
        state.docsFetchedAt = Self.isoTimestamp()
        state.docsSnapshotPath = docsSnapshot?.path ?? state.docsSnapshotPath
        state.docsManifest = docsSnapshot?.manifest ?? state.docsManifest
        state.selectedAgent = selectedAgent.rawValue
        let currentDocsFingerprint = Self.docsManifestFingerprint(state.docsManifest)
        let resolvedTargetKey = selectedVault.map(Self.targetKey(for:))
            ?? previousProgress?.resolvedTargetKey
        let canReuseProgress = previousProgress != nil
            && previousProgress?.resolvedTargetKey == resolvedTargetKey
            && previousDocsFingerprint == currentDocsFingerprint
        let completedSections = canReuseProgress ? previousProgress?.completedSections ?? [] : []
        let targetResolution = selectedVault != nil
            ? TargetResolution(
                status: "candidate",
                method: "selected_vault",
                confirmedAt: Self.isoTimestamp()
            )
            : previousProgress?.targetResolution ?? TargetResolution(
                status: "unresolved",
                method: nil,
                confirmedAt: nil
            )
        let waitingForUser = unresolvedInitialStep3Decision(
            selectedVault: selectedVault,
            resolvedTargetKey: resolvedTargetKey,
            previousWaitingForUser: previousProgress?.waitingForUser
        )
        let nextSection = nextSection(in: state, completedSections: completedSections)
        state.progress = Progress(
            launchDirectory: launchDirectory,
            selectedVaultPath: selectedVault,
            resolvedTargetKey: resolvedTargetKey,
            targetResolution: targetResolution,
            completedSections: completedSections,
            waitingForUser: waitingForUser,
            lastFailure: nil,
            nextSection: nextSection
        )
        writeState(state)

        let setupPacket = startupPrompt(
            selectedVaultPath: selectedVault,
            launchDirectory: launchDirectory,
            helperPath: helperPath.path,
            statePath: stateURL.path,
            state: state,
            completionResult: currentResult
        )
        guard let setupPacketURL = writeSetupPacket(setupPacket, runId: runId) else { return nil }

        let helperDirectory = helperPath.deletingLastPathComponent().path
        let environmentPrefix = [
            "export ZEBRA_GBRAIN_STATE=\(ZebraAgentLaunchCommand.shellQuote(stateURL.path))",
            "export PATH=\(ZebraAgentLaunchCommand.shellQuote(helperDirectory)):\"$PATH\"",
        ].joined(separator: " && ") + " && "
        return LaunchContext(
            launchDirectory: launchDirectory,
            startupPrompt: bootstrapPrompt(setupPacketPath: setupPacketURL.path),
            setupPacketPath: setupPacketURL.path,
            shellEnvironmentPrefix: environmentPrefix,
            allowTrustedAutomation: allowTrustedAutomation,
            allowLaunchDirectoryTrust: true
        )
    }

    private func bootstrapPrompt(setupPacketPath: String) -> String {
        """
        Your first visible response must be exactly:
        Zebra GBrain setup is starting. I am reading the setup packet now. Please wait.

        Do not run tools or read files before printing that line.
        After printing it, read the complete setup packet at:
        \(setupPacketPath)

        Then follow the setup packet exactly. The setup packet is authoritative for this GBrain setup run.
        """
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
            No Zebra vault is selected. You are starting from Zebra's onboarding work directory, not a brain repo target.
            Do not implicitly use the home directory as the GBrain source target.
            Before `gbrain init`, ask only for the topology decision. Do not ask for the brain repo target in the same prompt.
            After topology is chosen and `gbrain init`/doctor have run, ask separately for the brain repo target before import, sync, source registration, or receipt write.
            When asking for the brain repo target, present the numbered options in the target-resolution guard. Do not ask only as an open-ended sentence.
            You may use the home directory only if the user explicitly confirms it as the brain repo target, then use targetResolution.method=user_confirmed_home.
            Discovery scans are allowed only to present candidates. Do not choose or import a discovered candidate until the user confirms it.
            """
        }

        let docsContext = docsPromptContext(state: state)
        let sectionContext = sectionPromptContext(state: state)
        let decisionContext = decisionPromptContext(state: state)
        let targetResolutionGuard = targetResolutionGuardContext(state: state)
        let statusContext = """
        Current Zebra verification status:
        complete: \(completionResult.isComplete ? "true" : "false")
        reasons: \(completionResult.reasons.isEmpty ? "none" : completionResult.reasons.joined(separator: ", "))
        next section: \(state.progress?.nextSection ?? "unknown")
        waitingForUser: \(state.progress?.waitingForUser ?? "none")
        """

        return """
        You are Zebra's GBrain setup agent.

        Use the provided latest GBrain docs snapshot as your source of truth when it is available.
        Use `INSTALL_FOR_AGENTS.md` as the completion standard.
        Follow its original `##` section order. Do not silently replace it with the setup skill's repo-discovery flow.

        \(docsContext)

        \(sectionContext)

        \(statusContext)

        \(decisionContext)

        Launch directory:
        \(launchDirectory)

        \(targetContext)

        Zebra helper command:
        \(helperPath)

        State file:
        \(statePath)

        Zebra hard gates:
        - Zebra hard gates override INSTALL_FOR_AGENTS.md command order.
        - `waitingForUser` is a Zebra block reason, not an INSTALL_FOR_AGENTS.md section.
        - Continue to follow INSTALL_FOR_AGENTS.md `##` section order, but respect the current `waitingForUser` block reason first.
        - In Step 3, do not run `gbrain init`, `gbrain init --pglite`, or Supabase setup until the user has explicitly chosen topology.
        - In Step 3, do not import, sync, register a source, or write a completion receipt until the user has explicitly resolved the brain repo target.

        \(targetResolutionGuard)

        Progress reporting:
        - Before a section: `zebra-gbrain-onboarding report --status started --section "<section title>"`
        - After a section: `zebra-gbrain-onboarding report --status completed --section "<section title>"`
        - When waiting for the user: `zebra-gbrain-onboarding report --status waiting_for_user --section "<section title>" --note "<what you need>"`
        - On failure: `zebra-gbrain-onboarding report --status failed --section "<section title>" --note "<reason>"`
        - When Step 3 resolves a brain repo target, include `--target "<brain repo path>" --method "<targetResolution.method>"` on the completed report.
        - After the user chooses search mode, explicitly run `gbrain config set search.mode <mode>` even when it matches the auto-applied default, then verify with `gbrain search modes`.
        - If report rejects a section because the role is unknown, read the current section and report the role with `zebra-gbrain-onboarding report --status mapped_role --section "<section title>" --role "<install|credentials|create_brain|search_mode|import_index|verify>" --evidence "<why>"`, then retry the original report only after the missing prerequisite is satisfied.

        Completion verification:
        - Do not say setup is complete until verify returns complete true.
        - Use: `zebra-gbrain-onboarding verify --target "<brain repo path>" --source-id "<source id>" --method "<targetResolution.method>"`
        - Include `--profile-id "<profile>"` if a profile was selected.
        - Verify must pass before the Zebra checklist can become checked.

        User decision rule:
        - Ask only for decisions required by the current `next section` or current `waitingForUser` block.
        - Do not batch decisions from later sections into the current prompt.
        - If a later command reveals a new required decision, stop and ask then.
        """
    }

    private func prepareDocsSnapshot() -> DocsSnapshot? {
        if let repoURL = explicitDocsRepoURL() {
            return prepareLocalDocsSnapshot(repoURL: repoURL)
        }
        if environment["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED"] != "1",
           let remoteSnapshot = prepareRemoteDocsSnapshot() {
            return remoteSnapshot
        }
        return resolveFallbackDocsRepoURL().flatMap(prepareLocalDocsSnapshot(repoURL:))
    }

    private var docsPaths: [String] {
        [
            "INSTALL_FOR_AGENTS.md",
            "README.md",
            "AGENTS.md",
            "docs/GBRAIN_VERIFY.md",
            "skills/setup/SKILL.md",
        ]
    }

    private func prepareLocalDocsSnapshot(repoURL: URL) -> DocsSnapshot? {
        let commit = gitCommitHash(in: repoURL) ?? "local"
        let snapshotDirectory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-docs", isDirectory: true)
            .appendingPathComponent(commit, isDirectory: true)

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
            sourceKind: "local",
            sourceRef: commit,
            files: files,
            installForAgentsSections: Self.installForAgentsSections(from: installForAgents)
        )
        return DocsSnapshot(
            commit: commit,
            path: snapshotDirectory.path,
            manifest: manifest
        )
    }

    private func prepareRemoteDocsSnapshot() -> DocsSnapshot? {
        guard let ref = remoteDocsRef() else { return nil }
        let rawBase = environment["ZEBRA_GBRAIN_DOCS_RAW_BASE"]
            ?? "https://raw.githubusercontent.com/garrytan/gbrain"
        let snapshotDirectory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-docs", isDirectory: true)
            .appendingPathComponent(ref, isDirectory: true)

        var files: [DocsFile] = []
        var installForAgents = ""
        for relativePath in docsPaths {
            guard let url = URL(string: "\(rawBase)/\(ref)/\(relativePath)"),
                  let content = fetchRemoteText(url: url) else {
                continue
            }
            let destinationURL = snapshotDirectory.appendingPathComponent(relativePath, isDirectory: false)
            do {
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try content.write(to: destinationURL, atomically: true, encoding: .utf8)
                files.append(DocsFile(path: relativePath, hash: Self.stableHash(content)))
                if relativePath == "INSTALL_FOR_AGENTS.md" {
                    installForAgents = content
                }
            } catch {
                continue
            }
        }

        guard !files.isEmpty else { return nil }
        let manifest = DocsManifest(
            generatedAt: Self.isoTimestamp(),
            sourceRepoPath: rawBase,
            sourceKind: "remote",
            sourceRef: ref,
            files: files,
            installForAgentsSections: Self.installForAgentsSections(from: installForAgents)
        )
        return DocsSnapshot(
            commit: ref,
            path: snapshotDirectory.path,
            manifest: manifest
        )
    }

    private func explicitDocsRepoURL() -> URL? {
        if let gbrainDocsRepoURL {
            return gbrainDocsRepoURL
        }
        return environment["ZEBRA_GBRAIN_DOCS_REPO"].map(URL.init(fileURLWithPath:))
    }

    private func resolveFallbackDocsRepoURL() -> URL? {
        let candidates: [URL?] = [
            URL(fileURLWithPath: homeDirectoryPath).appendingPathComponent("gbrain", isDirectory: true),
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

    private func remoteDocsRef() -> String? {
        if let ref = nonEmpty(environment["ZEBRA_GBRAIN_DOCS_REF"]) {
            return ref
        }
        let commitURLString = environment["ZEBRA_GBRAIN_DOCS_COMMIT_URL"]
            ?? "https://api.github.com/repos/garrytan/gbrain/commits/main"
        guard let url = URL(string: commitURLString),
              let raw = fetchRemoteText(url: url),
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let sha = nonEmpty(object["sha"] as? String) {
            return sha
        }
        if let object = object["object"] as? [String: Any],
           let sha = nonEmpty(object["sha"] as? String) {
            return sha
        }
        return nil
    }

    private func fetchRemoteText(url: URL) -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("zebra-gbrain-onboarding", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var output: String?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data,
                  let text = String(data: data, encoding: .utf8) else {
                return
            }
            output = text
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            task.cancel()
            return nil
        }
        return output
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

    private func nextSection(in state: State, completedSections: [String]? = nil) -> String {
        let completed = Set(completedSections ?? state.progress?.completedSections ?? [])
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

    private func unresolvedInitialStep3Decision(
        selectedVault: String?,
        resolvedTargetKey: String?,
        previousWaitingForUser: String?
    ) -> String? {
        guard selectedVault == nil && resolvedTargetKey == nil else { return nil }
        if previousWaitingForUser == "brain_repo_target_resolution" {
            return previousWaitingForUser
        }
        return "topology_resolution"
    }

    private func decisionPromptContext(state: State) -> String {
        let nextSection = state.progress?.nextSection ?? ""
        let waitingForUser = state.progress?.waitingForUser
        if waitingForUser == "topology_resolution" {
            return """
            Current user-decision gate:
            Ask only for the Step 3 topology decision now: local PGLite or Supabase/Postgres.
            Do not ask for the brain repo target in this gate. Ask for that later, after topology is chosen and Step 3 init/doctor have run.
            Do not ask for Step 2 API keys in this gate. Ask for credentials later only if the current section or command actually requires them.
            """
        }
        if waitingForUser == "brain_repo_target_resolution" {
            return """
            Current user-decision gate:
            Ask only for the Step 3 brain repo target now. Present exactly these numbered options:
            1. Use an existing markdown/brain repo
            2. Create a new brain repo at ~/brain
            3. Create a new brain repo at a custom path
            If the user chooses 1, ask for the full existing repo path. If the user chooses 2, ask for yes/no confirmation before creating ~/brain. If the user chooses 3, ask for the full path to create.
            Do not ask for topology in this gate. Do not ask for Step 2 API keys unless the current Step 3 command refuses to continue without one.
            """
        }
        if nextSection.localizedCaseInsensitiveContains("Step 2") {
            return """
            Current user-decision gate:
            Ask only for Step 2 credential decisions needed by the current command.
            Do not ask for Step 3 topology or brain repo target until Step 3 is the current section.
            """
        }
        if nextSection.localizedCaseInsensitiveContains("Step 3") {
            return """
            Current user-decision gate:
            Ask only for Step 3 decisions that are not already resolved.
            Do not ask for Step 2 API keys unless a Step 3 command refuses to continue without one.
            """
        }
        return """
        Current user-decision gate:
        Ask only for decisions required by the current section.
        """
    }

    private func targetResolutionGuardContext(state: State) -> String {
        if state.progress?.waitingForUser == "topology_resolution" {
            return """
            Target-resolution timing:
            - Do not ask for the brain repo target in the topology prompt.
            - After topology is chosen and Step 3 init/doctor have run, ask separately for the brain repo target before import, sync, source registration, or receipt write.
            """
        }
        return """
        Required target-resolution guard:
        - Allowed targetResolution.method values: selected_vault, user_existing_repo, user_created_repo, user_confirmed_home.
        - Forbidden target choices: implicit_home, auto_discovered_candidate.
        - Before import/sync/source registration/receipt write, resolve the brain repo target with the user unless the selected vault is being used.
        - When resolving the brain repo target in terminal, present exactly these numbered options:
          1. Use an existing markdown/brain repo
          2. Create a new brain repo at ~/brain
          3. Create a new brain repo at a custom path
        - If the user chooses 1, ask for the full existing repo path. If the user chooses 2, ask for yes/no confirmation before creating ~/brain. If the user chooses 3, ask for the full path to create.
        - Do not ask only as an open-ended "give a path or create new" sentence.
        - If using an existing repo the user names, use method=user_existing_repo.
        - If creating a new repo, ask for the path first, create it, git init there if needed, then use method=user_created_repo.
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

    private func targetResolutionVerifies(_ resolution: TargetResolution?) -> Bool {
        guard let method = nonEmpty(resolution?.method) else { return false }
        return Self.allowedTargetResolutionMethods.contains(method)
    }

    private func liveVerificationResult(
        target: Target,
        vaultPath: String,
        sourceId: String
    ) -> LiveVerificationResult {
        var reasons: [String] = []
        var updatedTarget = target
        let executable = resolveGBrainExecutable(readiness: nil, target: target)

        guard let executable else {
            reasons.append("missing_gbrain_executable")
            updatedTarget.complete = false
            updatedTarget.reasons = reasons
            return LiveVerificationResult(
                complete: false,
                reasons: reasons,
                globalReadiness: GlobalReadiness(
                    complete: false,
                    gbrainExecutablePath: nil,
                    wrapperPath: nil,
                    doctorOk: false,
                    verifiedAt: Self.isoTimestamp()
                ),
                target: updatedTarget
            )
        }

        let doctor = runProcess(executable: executable, arguments: ["doctor", "--json"], cwd: vaultPath, timeout: 20)
        let doctorOk = doctor.exitCode == 0 && !doctor.timedOut
        if !doctorOk {
            reasons.append("doctor_failed")
        }

        let current = runProcess(executable: executable, arguments: ["sources", "current", "--json"], cwd: vaultPath, timeout: 12)
        let currentObject = Self.jsonObject(from: current.stdout)
        let currentSourceId = currentObject?["source_id"] as? String
        let currentOk = current.exitCode == 0
            && !current.timedOut
            && currentSourceId == sourceId

        let list = runProcess(executable: executable, arguments: ["sources", "list", "--json"], cwd: vaultPath, timeout: 12)
        let listedLocalPath = Self.sourceLocalPath(sourceId: sourceId, fromSourcesListJSON: list.stdout)
        let listOk = list.exitCode == 0
            && !list.timedOut
            && listedLocalPath.map(Self.standardizedPath) == vaultPath

        if !currentOk || !listOk {
            reasons.append("source_not_registered")
        }

        let complete = reasons.isEmpty
        updatedTarget.gbrainExecutablePath = executable
        updatedTarget.doctorStatus = ProbeResult(ok: doctorOk, status: doctorOk ? "ok" : "failed")
        updatedTarget.sourcesCurrentResult = SourceProbeResult(
            ok: currentOk && listOk,
            sourceId: currentSourceId ?? sourceId,
            localPath: listedLocalPath
        )
        updatedTarget.searchProbeResult = ProbeResult(ok: complete, status: complete ? "not_run" : "blocked")
        updatedTarget.verifiedAt = Self.isoTimestamp()
        updatedTarget.complete = complete
        updatedTarget.reasons = reasons

        return LiveVerificationResult(
            complete: complete,
            reasons: reasons,
            globalReadiness: GlobalReadiness(
                complete: doctorOk,
                gbrainExecutablePath: executable,
                wrapperPath: target.wrapperPath,
                doctorOk: doctorOk,
                verifiedAt: Self.isoTimestamp()
            ),
            target: updatedTarget
        )
    }

    private func updateReceipt(with live: LiveVerificationResult, targetKey: String) {
        guard var state = loadState() else { return }
        var receipt = state.receipt ?? Receipt(globalReadiness: nil, primaryTargetKey: nil, targets: nil)
        if receiptMateriallyMatches(receipt, live: live, targetKey: targetKey) {
            return
        }
        receipt.globalReadiness = live.globalReadiness
        var targets = receipt.targets ?? [:]
        targets[targetKey] = live.target
        receipt.targets = targets
        state.receipt = receipt
        writeState(state)
    }

    private func receiptMateriallyMatches(
        _ receipt: Receipt,
        live: LiveVerificationResult,
        targetKey: String
    ) -> Bool {
        var existingReadiness = receipt.globalReadiness
        var nextReadiness = live.globalReadiness
        existingReadiness?.verifiedAt = nil
        nextReadiness.verifiedAt = nil

        var existingTarget = receipt.targets?[targetKey]
        var nextTarget = live.target
        existingTarget?.verifiedAt = nil
        nextTarget.verifiedAt = nil

        return existingReadiness == nextReadiness && existingTarget == nextTarget
    }

    private func resolveGBrainExecutable(readiness: GlobalReadiness?, target: Target?) -> String? {
        if let path = executablePath(target?.gbrainExecutablePath),
           fileManager.isExecutableFile(atPath: path) {
            return path
        }
        if let path = executablePath(target?.wrapperPath),
           fileManager.isExecutableFile(atPath: path) {
            return path
        }
        if let path = executablePath(readiness?.gbrainExecutablePath),
           fileManager.isExecutableFile(atPath: path) {
            return path
        }
        if let path = executablePath(readiness?.wrapperPath),
           fileManager.isExecutableFile(atPath: path) {
            return path
        }
        return findExecutableOnPATH(named: "gbrain")
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        cwd: String?,
        timeout: TimeInterval
    ) -> ProcessRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = processEnvironment()
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return ProcessRunResult(exitCode: 127, stdout: "", stderr: "\(error)", timedOut: false)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        var timedOut = false
        if process.isRunning {
            timedOut = true
            process.terminate()
        }
        process.waitUntilExit()
        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessRunResult(
            exitCode: timedOut ? 124 : process.terminationStatus,
            stdout: stdoutText,
            stderr: stderrText,
            timedOut: timedOut
        )
    }

    private static func jsonObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func sourceLocalPath(sourceId: String, fromSourcesListJSON text: String) -> String? {
        guard let object = jsonObject(from: text),
              let sources = object["sources"] as? [[String: Any]] else {
            return nil
        }
        for source in sources {
            guard source["id"] as? String == sourceId else { continue }
            return source["local_path"] as? String
        }
        return nil
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

    private func writeSetupPacket(_ content: String, runId: String) -> URL? {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-setup-packets", isDirectory: true)
        let url = directory.appendingPathComponent("\(runId).md", isDirectory: false)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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

    private func onboardingWorkDirectoryPath() -> String {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-work", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return Self.standardizedPath(directory.path)
    }

    private func executablePath(_ path: String?) -> String? {
        guard let path = nonEmpty(path) else { return nil }
        return Self.standardizedPath((path as NSString).expandingTildeInPath)
    }

    private func findExecutableOnPATH(named name: String) -> String? {
        let path = toolSearchPath()
        for directory in path.split(separator: ":") {
            let candidate = (String(directory) as NSString).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func processEnvironment() -> [String: String] {
        var output = environment
        output["PATH"] = toolSearchPath()
        if output["HOME"] == nil {
            output["HOME"] = homeDirectoryPath
        }
        if output["BUN_INSTALL"] == nil {
            output["BUN_INSTALL"] = (homeDirectoryPath as NSString).appendingPathComponent(".bun")
        }
        return output
    }

    private func toolSearchPath() -> String {
        let home = homeDirectoryPath
        let fallbackDirectories = [
            (home as NSString).appendingPathComponent(".bun/bin"),
            (home as NSString).appendingPathComponent(".local/bin"),
            (home as NSString).appendingPathComponent("gbrain/bin"),
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        var seen = Set<String>()
        var directories: [String] = []
        for directory in ((environment["PATH"] ?? "").split(separator: ":").map(String.init) + fallbackDirectories) {
            let standardized = Self.standardizedPath((directory as NSString).expandingTildeInPath)
            guard !standardized.isEmpty,
                  !seen.contains(standardized) else {
                continue
            }
            seen.insert(standardized)
            directories.append(standardized)
        }
        return directories.joined(separator: ":")
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

    private static func docsManifestFingerprint(_ manifest: DocsManifest?) -> String? {
        guard let manifest else { return nil }
        let files = manifest.files
            .map { "\($0.path)=\($0.hash)" }
            .sorted()
            .joined(separator: "|")
        let sections = manifest.installForAgentsSections
            .map { "\($0.title)=\($0.hash)" }
            .joined(separator: "|")
        return stableHash("\(manifest.sourceRef ?? "")|\(files)|\(sections)")
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
    allowed_roles = {
        "install",
        "credentials",
        "create_brain",
        "search_mode",
        "import_index",
        "verify",
    }
    known_roles = allowed_roles | {"non_role"}
    allowed_search_modes = {"conservative", "balanced", "tokenmax"}

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

    def run_json(argv, cwd=None, timeout=30):
        try:
            result = subprocess.run(
                argv,
                cwd=cwd,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
            )
        except Exception as exc:
            return False, {}, str(exc)
        if result.returncode != 0:
            return False, {}, result.stderr.strip() or result.stdout.strip()
        try:
            return True, json.loads(result.stdout or "{}"), ""
        except Exception as exc:
            return False, {}, str(exc)

    def source_list_local_path(payload, source_id):
        for source in payload.get("sources") or []:
            if source.get("id") == source_id:
                return source.get("local_path")
        return None

    def stable_hash(value):
        hash_value = 0xcbf29ce484222325
        for byte in value.encode("utf-8"):
            hash_value ^= byte
            hash_value = (hash_value * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
        return f"{hash_value:016x}"

    def normalize_title(value):
        without_parenthetical = []
        depth = 0
        for char in (value or "").lower():
            if char == "(":
                depth += 1
                without_parenthetical.append(" ")
                continue
            if char == ")":
                depth = max(0, depth - 1)
                without_parenthetical.append(" ")
                continue
            if depth == 0:
                without_parenthetical.append(char)
        normalized = []
        for char in "".join(without_parenthetical):
            if char.isalnum():
                normalized.append(char)
            else:
                normalized.append(" ")
        return " ".join("".join(normalized).split())

    def docs_manifest_sections(state):
        manifest = state.get("docsManifest") or {}
        sections = manifest.get("installForAgentsSections") or []
        out = []
        for index, section in enumerate(sections):
            title = section.get("title") or ""
            out.append({
                "title": title,
                "hash": section.get("hash"),
                "body": "",
                "orderIndex": index,
            })
        return out

    def parse_install_sections(state):
        snapshot = state.get("docsSnapshotPath")
        path = os.path.join(snapshot, "INSTALL_FOR_AGENTS.md") if snapshot else None
        if not path or not os.path.exists(path):
            return docs_manifest_sections(state)
        try:
            with open(path, "r", encoding="utf-8") as handle:
                text = handle.read()
        except Exception:
            return docs_manifest_sections(state)

        sections = []
        current_title = None
        current_lines = []

        def finish():
            if current_title is None:
                return
            body = "\\n".join(current_lines)
            sections.append({
                "title": current_title,
                "hash": stable_hash(body),
                "body": body,
                "orderIndex": len(sections),
            })

        for line in text.splitlines():
            if line.startswith("## "):
                finish()
                current_title = line[3:].strip()
                current_lines = [line]
            elif current_title is not None:
                current_lines.append(line)
        finish()
        return sections or docs_manifest_sections(state)

    def section_entry(state, section_title):
        sections = parse_install_sections(state)
        normalized = normalize_title(section_title)
        for section in sections:
            if section.get("title") == section_title:
                return section, sections
        for section in sections:
            if normalize_title(section.get("title")) == normalized:
                return section, sections
        return {
            "title": section_title,
            "hash": None,
            "body": section_title or "",
            "orderIndex": len(sections),
        }, sections

    def role_key(entry, section_title):
        section_hash = entry.get("hash")
        if section_hash:
            return "hash:" + section_hash
        return "title:" + normalize_title(section_title or entry.get("title") or "")

    def known_title_role(title):
        normalized = normalize_title(title)
        if "step 1" in normalized and ("install gbrain" in normalized or "install cli" in normalized):
            return "install"
        if "step 2" in normalized and ("api key" in normalized or "credential" in normalized):
            return "credentials"
        if ("step 3 5" in normalized or "search mode" in normalized) and "confirm" in normalized:
            return "search_mode"
        if "step 3" in normalized and ("create the brain" in normalized or "initialize brain" in normalized):
            return "create_brain"
        if "step 4" in normalized and "import" in normalized and "index" in normalized:
            return "import_index"
        if "step 9" in normalized and "verify" in normalized:
            return "verify"
        return None

    def non_role_title(title):
        normalized = normalize_title(title)
        return (
            normalized.startswith("step 0 ")
            or normalized.startswith("step 4 5 ")
            or normalized.startswith("step 5 ")
            or normalized.startswith("step 6 ")
            or normalized.startswith("step 7 ")
            or normalized.startswith("step 8 ")
            or normalized == "upgrade"
            or normalized.startswith("upgrade ")
            or normalized.startswith("v0 42 0 onboard surface")
        )

    def signature_role(body):
        text = (body or "").lower()
        if "gbrain --version" in text and ("bun install -g github:garrytan/gbrain" in text or "install gbrain" in text):
            return "install"
        if "zeroentropy_api_key" in text or "openai_api_key" in text or "anthropic_api_key" in text:
            return "credentials"
        if (
            "gbrain init" in text
            and "gbrain doctor --json" in text
            and ("brain repo" in text or "markdown files" in text)
            and ("ask the user where their files are" in text or "create a new brain repo" in text)
        ):
            return "create_brain"
        if (
            "conservative" in text
            and "balanced" in text
            and "tokenmax" in text
            and "gbrain config set search.mode" in text
            and "gbrain search modes" in text
        ):
            return "search_mode"
        if "gbrain import" in text and "gbrain embed --stale" in text:
            return "import_index"
        if "docs/gbrain_verify.md" in text or "verification checks" in text:
            return "verify"
        return None

    def role_order_is_sane(role, entry, sections):
        if len(sections) <= 1:
            return True
        index = entry.get("orderIndex", len(sections))
        previous_roles = set()
        for section in sections:
            if section.get("orderIndex", 0) >= index:
                continue
            previous_roles.add(known_title_role(section.get("title")) or signature_role(section.get("body")) or "")
        if role == "search_mode":
            return "create_brain" in previous_roles
        if role == "import_index":
            return "create_brain" in previous_roles
        return True

    def section_role(state, section_title, record=False):
        entry, sections = section_entry(state, section_title)
        key = role_key(entry, section_title)
        roles = state.setdefault("sectionRoles", {}) if record else state.get("sectionRoles", {})
        existing = roles.get(key) if isinstance(roles, dict) else None
        if existing and existing.get("role") in known_roles:
            if not entry.get("hash") or existing.get("sectionHash") == entry.get("hash"):
                return existing.get("role"), existing.get("roleSource") or "known_hash", entry

        if non_role_title(entry.get("title")):
            role = "non_role"
            source = "non_role_title"
        else:
            role = known_title_role(entry.get("title"))
            source = "exact_title" if role else None
            if not role:
                role = signature_role(entry.get("body"))
                source = "signature" if role else None
        if role and not role_order_is_sane(role, entry, sections):
            role = None
            source = None
        if role and record:
            roles[key] = {
                "section": entry.get("title") or section_title,
                "sectionHash": entry.get("hash"),
                "role": role,
                "roleSource": source,
                "roleConfidence": "deterministic",
                "roleEvidence": [source],
                "updatedAt": now(),
            }
        return role or "unknown", source or "unknown", entry

    def record_agent_role(state, section_title, role, evidence):
        if role not in allowed_roles:
            return False
        entry, _ = section_entry(state, section_title)
        if not entry.get("hash") or non_role_title(entry.get("title")):
            return False
        key = role_key(entry, section_title)
        state.setdefault("sectionRoles", {})[key] = {
            "section": entry.get("title") or section_title,
            "sectionHash": entry.get("hash"),
            "role": role,
            "roleSource": "agent_judgment",
            "roleConfidence": "agent_asserted",
            "roleEvidence": evidence,
            "updatedAt": now(),
        }
        return True

    def completed_roles(state):
        progress = state.get("progress") or {}
        roles = set()
        for section in progress.get("completedSections") or []:
            role, _, _ = section_role(state, section, record=False)
            if role in allowed_roles:
                roles.add(role)
        return roles

    def apply_target_flags(state, flags):
        target = flags.get("target") or flags.get("target_path")
        method = flags.get("method")
        source_id = flags.get("source_id")
        profile_id = flags.get("profile_id")
        if not target and not method and not source_id and not profile_id:
            return None
        if not target:
            return "target_not_resolved"
        if method not in allowed_methods:
            return "target_confirmation_missing"

        target = os.path.abspath(os.path.expanduser(target))
        key = target_key(target)
        progress = state.setdefault("progress", {})
        progress["resolvedTargetKey"] = key
        progress["targetResolution"] = {
            "status": "resolved",
            "method": method,
            "confirmedAt": now(),
        }
        receipt = state.setdefault("receipt", {})
        targets = receipt.setdefault("targets", {})
        target_entry = targets.setdefault(key, {})
        target_entry["vaultPath"] = target
        target_entry["targetResolution"] = {
            "method": method,
            "confirmedAt": now(),
        }
        if source_id:
            target_entry["sourceId"] = source_id
        if profile_id:
            target_entry["profileId"] = profile_id
        if not progress.get("selectedVaultPath"):
            receipt["primaryTargetKey"] = key
        return None

    def resolved_target(state):
        progress = state.get("progress") or {}
        receipt = state.get("receipt") or {}
        key = progress.get("resolvedTargetKey") or receipt.get("primaryTargetKey")
        targets = receipt.get("targets") or {}
        target_entry = targets.get(key) if key else None
        target_path = target_entry.get("vaultPath") if target_entry else None
        if not target_path and key and key.startswith("vault:"):
            target_path = key[6:]
        resolution = progress.get("targetResolution") or {}
        method = resolution.get("method")
        if not method and target_entry:
            method = (target_entry.get("targetResolution") or {}).get("method")
        return key, target_path, method, target_entry or {}

    def target_is_tool_repo(path):
        return (
            path
            and os.path.isfile(os.path.join(path, "INSTALL_FOR_AGENTS.md"))
            and os.path.isdir(os.path.join(path, "skills"))
            and os.path.isfile(os.path.join(path, "package.json"))
        )

    def target_guard_reasons(state):
        _, target_path, method, _ = resolved_target(state)
        reasons = []
        if not target_path:
            reasons.append("brain_repo_target_unresolved")
            return reasons
        target_path = os.path.abspath(os.path.expanduser(target_path))
        if method not in allowed_methods:
            reasons.append("target_confirmation_missing")
        if target_path == os.path.abspath(os.path.expanduser("~")) and method != "user_confirmed_home":
            reasons.append("implicit_home_target")
        if target_is_tool_repo(target_path):
            reasons.append("gbrain_tool_repo_target")
        if not os.path.isdir(target_path):
            reasons.append("brain_repo_target_missing")
        return reasons

    def gbrain_version_ok():
        executable = gbrain_executable()
        if not executable:
            return False
        try:
            result = subprocess.run(
                [executable, "--version"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            return result.returncode == 0
        except Exception:
            return False

    def doctor_ok(state):
        executable = gbrain_executable()
        if not executable:
            return False
        _, target_path, _, _ = resolved_target(state)
        cwd = target_path if target_path and os.path.isdir(target_path) else None
        try:
            result = subprocess.run(
                [executable, "doctor", "--json"],
                cwd=cwd,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=45,
            )
            return result.returncode == 0
        except Exception:
            return False

    def source_registered(state, flags):
        executable = gbrain_executable()
        if not executable:
            return False
        _, target_path, _, target_entry = resolved_target(state)
        source_id = flags.get("source_id") or target_entry.get("sourceId")
        if not target_path or not os.path.isdir(target_path) or not source_id:
            return False
        current_ok, current_payload, _ = run_json(
            [executable, "sources", "current", "--json"],
            cwd=target_path,
            timeout=12,
        )
        current_ok = current_ok and current_payload.get("source_id") == source_id
        list_ok, list_payload, _ = run_json(
            [executable, "sources", "list", "--json"],
            cwd=target_path,
            timeout=12,
        )
        listed_local_path = source_list_local_path(list_payload, source_id)
        list_ok = (
            list_ok
            and listed_local_path
            and os.path.abspath(os.path.expanduser(listed_local_path)) == os.path.abspath(target_path)
        )
        return bool(current_ok and list_ok)

    def search_mode_configured(state):
        executable = gbrain_executable()
        if not executable:
            return False
        _, target_path, _, _ = resolved_target(state)
        cwd = target_path if target_path and os.path.isdir(target_path) else None
        try:
            result = subprocess.run(
                [executable, "config", "get", "search.mode"],
                cwd=cwd,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=12,
            )
        except Exception:
            return False
        if result.returncode != 0:
            return False
        for line in reversed((result.stdout + "\\n" + result.stderr).splitlines()):
            tokens = []
            for chunk in line.lower().replace("=", " ").replace(":", " ").split():
                token = "".join(char for char in chunk if char.isalnum())
                if token:
                    tokens.append(token)
            if any(token in allowed_search_modes for token in tokens):
                return True
        return False

    def receipt_verify_complete(state):
        receipt = state.get("receipt") or {}
        global_readiness = receipt.get("globalReadiness") or {}
        if not global_readiness.get("complete"):
            return False
        key, _, _, target_entry = resolved_target(state)
        if key and target_entry:
            return bool(target_entry.get("complete"))
        for target in (receipt.get("targets") or {}).values():
            if target.get("complete"):
                return True
        return False

    def reject_report(state, reason, section, status, next_action=None):
        progress = state.setdefault("progress", {})
        progress["lastFailure"] = reason
        progress["lastStatus"] = "rejected"
        progress["updatedAt"] = now()
        if reason in {
            "brain_repo_target_unresolved",
            "target_confirmation_missing",
            "implicit_home_target",
            "gbrain_tool_repo_target",
            "brain_repo_target_missing",
        }:
            progress["waitingForUser"] = "brain_repo_target_resolution"
        elif reason == "section_role_unknown":
            progress["waitingForUser"] = "section_role_mapping_resolution"
        save_state(state)
        payload = {
            "ok": False,
            "reason": reason,
            "section": section,
            "status": status,
        }
        if next_action:
            payload["nextAction"] = next_action
        print(json.dumps(payload, sort_keys=True))
        sys.exit(1)

    def report_guard_reason(state, status, role, flags):
        if status not in {"started", "completed"}:
            return None
        roles = completed_roles(state)
        target_reasons = target_guard_reasons(state)
        if role == "unknown" and status == "completed":
            return "section_role_unknown"
        if role == "install" and status == "completed" and not gbrain_version_ok():
            return "gbrain_version_failed"
        if role == "create_brain" and status == "completed":
            if target_reasons:
                return target_reasons[0]
            if not doctor_ok(state):
                return "doctor_failed"
        if role == "search_mode":
            if "create_brain" not in roles:
                return "create_brain_not_completed"
            if target_reasons:
                return target_reasons[0]
            if status == "completed" and not search_mode_configured(state):
                return "search_mode_not_configured"
        if role == "import_index":
            if "create_brain" not in roles:
                return "create_brain_not_completed"
            if "search_mode" not in roles:
                return "search_mode_not_completed"
            if target_reasons:
                return target_reasons[0]
            if status == "completed" and not source_registered(state, flags):
                return "source_not_registered"
        if role == "verify" and status == "completed" and not receipt_verify_complete(state):
            return "verify_incomplete"
        return None

    def target_confirmation_flags_present(flags):
        return bool(flags.get("target") or flags.get("target_path") or flags.get("method") or flags.get("profile_id"))

    def should_clear_waiting_for_user(progress, status, role, flags):
        waiting = progress.get("waitingForUser")
        if not waiting:
            return False
        if waiting == "topology_resolution":
            return role == "create_brain" and status in {"started", "completed"}
        if waiting == "brain_repo_target_resolution":
            return (
                role == "create_brain"
                and status == "completed"
                and bool(flags.get("target") or flags.get("target_path"))
                and flags.get("method") in allowed_methods
            )
        return False

    def report():
        flags = parse_flags(args)
        positional = flags.get("_positional", [])
        status = flags.get("status") or (positional[0] if positional else "reported")
        section = flags.get("section") or ""
        note = flags.get("note")
        state = load_state()
        if status == "mapped_role":
            role = flags.get("role")
            evidence = []
            if flags.get("evidence"):
                evidence.append(flags.get("evidence"))
            if note:
                evidence.append(note)
            if not section or not record_agent_role(state, section, role, evidence):
                reject_report(state, "invalid_section_role_mapping", section, status)
            progress = state.setdefault("progress", {})
            if progress.get("waitingForUser") == "section_role_mapping_resolution":
                progress.pop("waitingForUser", None)
            progress["updatedAt"] = now()
            save_state(state)
            print(json.dumps({"ok": True, "status": status, "section": section, "role": role}, sort_keys=True))
            return

        candidate_state = json.loads(json.dumps(state))
        role, _, _ = section_role(candidate_state, section, record=True)
        if target_confirmation_flags_present(flags):
            if not (role == "create_brain" and status == "completed"):
                reject_report(state, "target_flags_not_allowed", section, status)
            target_error = apply_target_flags(candidate_state, flags)
            if target_error:
                reject_report(state, target_error, section, status)
        guard_reason = report_guard_reason(candidate_state, status, role, flags)
        if guard_reason:
            next_action = None
            if guard_reason == "section_role_unknown":
                next_action = "report mapped_role with role and evidence, or report waiting_for_user"
            elif guard_reason in {"brain_repo_target_unresolved", "target_confirmation_missing"}:
                next_action = "report waiting_for_user for brain_repo_target_resolution"
            reject_report(state, guard_reason, section, status, next_action=next_action)

        state = candidate_state
        progress = state.setdefault("progress", {})
        if section:
            progress["nextSection"] = section
        if status == "completed" and section:
            completed = progress.setdefault("completedSections", [])
            if section not in completed:
                completed.append(section)
        if status == "waiting_for_user":
            progress["waitingForUser"] = note or section or "user input required"
        elif should_clear_waiting_for_user(progress, status, role, flags):
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

        current_ok = False
        current_source_id = None
        list_ok = False
        listed_local_path = None
        if executable and target and os.path.isdir(target) and source_id:
            current_ok, current_payload, _ = run_json(
                [executable, "sources", "current", "--json"],
                cwd=target,
                timeout=12,
            )
            current_source_id = current_payload.get("source_id")
            current_ok = current_ok and current_source_id == source_id

            list_ok, list_payload, _ = run_json(
                [executable, "sources", "list", "--json"],
                cwd=target,
                timeout=12,
            )
            listed_local_path = source_list_local_path(list_payload, source_id)
            list_ok = (
                list_ok
                and listed_local_path
                and os.path.abspath(os.path.expanduser(listed_local_path)) == target
            )
            if not current_ok or not list_ok:
                reasons.append("source_not_registered")

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
                    "ok": current_ok and list_ok,
                    "sourceId": current_source_id or source_id,
                    "localPath": listed_local_path,
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
