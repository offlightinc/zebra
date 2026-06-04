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
        var embeddingDecision: EmbeddingDecision?
        var completedSections: [String]?
        var waitingForUser: PendingUserDecision?
        var lastFailure: String?
        var nextSection: String?
    }

    private struct EmbeddingDecision: Codable {
        var decision: String?
        var confirmedAt: String?
    }

    private struct PendingUserDecision: Codable, Equatable {
        var section: String?
        var reason: String?
        var note: String?
        var createdAt: String?
        var legacyString: Bool?

        init(
            section: String?,
            reason: String?,
            note: String?,
            createdAt: String? = nil,
            legacyString: Bool? = nil
        ) {
            self.section = section
            self.reason = reason
            self.note = note
            self.createdAt = createdAt
            self.legacyString = legacyString
        }

        init(from decoder: Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(String.self) {
                self.section = nil
                self.reason = value
                self.note = value
                self.createdAt = nil
                self.legacyString = true
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.section = try container.decodeIfPresent(String.self, forKey: .section)
            self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
            self.note = try container.decodeIfPresent(String.self, forKey: .note)
            self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
            self.legacyString = try container.decodeIfPresent(Bool.self, forKey: .legacyString)
        }
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

    private struct DocsSnapshotRecord: Codable {
        var commit: String
        var path: String
        var manifest: DocsManifest
        var storedAt: String
    }

    private struct LiveVerificationResult {
        var complete: Bool
        var reasons: [String]
        var globalReadiness: GlobalReadiness
        var target: Target
        var hasTransientProbeFailure: Bool
    }

    private struct DoctorResult {
        var ok: Bool
    }

    private struct ProcessRunResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
        var timedOut: Bool
    }

    private enum SourceProbeStatus: Equatable {
        case verified
        case mismatch
        case transientFailure(reason: String)
    }

    private static let pgliteBusyReason = "pglite_busy"

    private static let allowedTargetResolutionMethods: Set<String> = [
        "selected_vault",
        "user_existing_repo",
        "user_created_repo",
        "user_confirmed_home",
    ]
    private static let launchPrefetchWaitSeconds: TimeInterval = 0.6
    private static let docsPrefetchCoordinator = GBrainDocsPrefetchCoordinator()

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

    public func isSetupCompletedFromCachedReceipt(selectedVaultPath: String?) -> Bool {
        cachedCompletionResult(selectedVaultPath: selectedVaultPath).isComplete
    }

    @discardableResult
    public func prefetchDocsSnapshotIfNeeded() -> Bool {
        guard explicitDocsRepoURL() == nil,
              environment["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED"] != "1" else {
            return false
        }
        return Self.docsPrefetchCoordinator.prefetchIfNeeded(store: self)
    }

    fileprivate var docsPrefetchKey: String {
        stateURL.path
    }

    fileprivate func hasCachedDocsSnapshot() -> Bool {
        cachedDocsSnapshot() != nil
    }

    fileprivate func fetchAndCacheRemoteDocsSnapshot() -> Bool {
        let hasUsableCache = cachedDocsSnapshot() != nil
        guard let snapshot = prepareRemoteDocsSnapshot() else {
            return hasUsableCache
        }
        writeDocsSnapshotCache(snapshot)
        return true
    }

    func completionResult(selectedVaultPath: String?) -> CompletionResult {
        guard var state = loadState() else {
            return CompletionResult(isComplete: false, reasons: ["missing_receipt"])
        }
        guard let receipt = state.receipt else {
            return CompletionResult(isComplete: false, reasons: ["missing_receipt"])
        }
        if clearStaleLegacyWaitingForUserIfNeeded(in: &state, receipt: receipt, selectedVaultPath: selectedVaultPath) {
            writeState(state)
        }
        if let waitingForUser = blockingWaitingForUser(in: state, receipt: receipt, selectedVaultPath: selectedVaultPath) {
            return CompletionResult(isComplete: false, reasons: ["waiting_for_user:\(waitingForUser)"])
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
        if let forbiddenReason = forbiddenBrainRepoTargetReason(
            vaultPath,
            method: resolved.target.targetResolution?.method
        ) {
            reasons.append(forbiddenReason)
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
        if preservesCompletedReceiptOnTransientFailure(receipt: receipt, live: live, targetKey: resolved.key) {
            return CompletionResult(isComplete: true, reasons: [])
        }
        updateReceipt(with: live, targetKey: resolved.key)
        return CompletionResult(isComplete: live.complete, reasons: live.reasons)
    }

    func cachedCompletionResult(selectedVaultPath: String?) -> CompletionResult {
        guard var state = loadState() else {
            return CompletionResult(isComplete: false, reasons: ["missing_receipt"])
        }
        guard let receipt = state.receipt else {
            return CompletionResult(isComplete: false, reasons: ["missing_receipt"])
        }
        if clearStaleLegacyWaitingForUserIfNeeded(in: &state, receipt: receipt, selectedVaultPath: selectedVaultPath) {
            writeState(state)
        }
        if let waitingForUser = blockingWaitingForUser(in: state, receipt: receipt, selectedVaultPath: selectedVaultPath) {
            return CompletionResult(isComplete: false, reasons: ["waiting_for_user:\(waitingForUser)"])
        }
        guard let resolved = resolveTarget(in: receipt, selectedVaultPath: selectedVaultPath) else {
            return CompletionResult(isComplete: false, reasons: ["receipt_target_missing"])
        }

        var reasons: [String] = []
        if !targetResolutionVerifies(resolved.target.targetResolution) {
            reasons.append("target_confirmation_missing")
        }
        guard standardizedExistingDirectoryPath(resolved.target.vaultPath) != nil else {
            reasons.append("receipt_target_missing")
            return CompletionResult(isComplete: false, reasons: reasons)
        }
        if let vaultPath = standardizedExistingDirectoryPath(resolved.target.vaultPath),
           let forbiddenReason = forbiddenBrainRepoTargetReason(
            vaultPath,
            method: resolved.target.targetResolution?.method
           ) {
            reasons.append(forbiddenReason)
            return CompletionResult(isComplete: false, reasons: reasons)
        }
        guard nonEmpty(resolved.target.sourceId) != nil else {
            reasons.append("source_not_registered")
            return CompletionResult(isComplete: false, reasons: reasons)
        }
        if activeRunRequiresImportIndexCompletion(in: state),
           !hasCompletedImportIndex(in: state) {
            reasons.append("import_index_not_completed")
            return CompletionResult(isComplete: false, reasons: reasons)
        }
        guard receiptIsComplete(receipt, selectedVaultPath: selectedVaultPath) else {
            reasons.append("receipt_incomplete")
            return CompletionResult(isComplete: false, reasons: reasons)
        }
        return CompletionResult(isComplete: true, reasons: [])
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

    private func blockingWaitingForUser(
        in state: State,
        receipt: Receipt,
        selectedVaultPath: String?
    ) -> String? {
        guard let waitingForUser = state.progress?.waitingForUser,
              let reason = waitingForUserDisplay(waitingForUser) else {
            return nil
        }
        if isStaleLegacyWaitingForUser(waitingForUser, in: state, receipt: receipt, selectedVaultPath: selectedVaultPath) {
            return nil
        }
        return reason
    }

    private func clearStaleLegacyWaitingForUserIfNeeded(
        in state: inout State,
        receipt: Receipt,
        selectedVaultPath: String?
    ) -> Bool {
        guard let waitingForUser = state.progress?.waitingForUser,
              isStaleLegacyWaitingForUser(waitingForUser, in: state, receipt: receipt, selectedVaultPath: selectedVaultPath) else {
            return false
        }
        state.progress?.waitingForUser = nil
        return true
    }

    private func isStaleLegacyWaitingForUser(
        _ waitingForUser: PendingUserDecision,
        in state: State,
        receipt: Receipt,
        selectedVaultPath: String?
    ) -> Bool {
        guard waitingForUser.legacyString == true,
              hasCompletedVerify(in: state),
              receiptIsComplete(receipt, selectedVaultPath: selectedVaultPath) else {
            return false
        }
        return true
    }

    private func hasCompletedVerify(in state: State) -> Bool {
        guard let completedSections = state.progress?.completedSections else { return false }
        return completedSections.contains { title in
            let normalized = Self.normalizedSectionTitle(title)
            return normalized.contains("step 9") && normalized.contains("verify")
        }
    }

    private func receiptIsComplete(_ receipt: Receipt, selectedVaultPath: String?) -> Bool {
        guard receipt.globalReadiness?.complete == true else { return false }
        if let resolved = resolveTarget(in: receipt, selectedVaultPath: selectedVaultPath) {
            return resolved.target.complete == true
        }
        return receipt.targets?.values.contains { $0.complete == true } == true
    }

    private func waitingForUserDisplay(_ waitingForUser: PendingUserDecision?) -> String? {
        let reason = nonEmpty(waitingForUser?.reason)
        let note = nonEmpty(waitingForUser?.note)
        if reason == "user_input_required", note != nil {
            return note
        }
        return reason
            ?? note
            ?? nonEmpty(waitingForUser?.section)
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
            embeddingDecision: canReuseProgress ? previousProgress?.embeddingDecision : nil,
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
            "export ZEBRA_GBRAIN_HOME=\(ZebraAgentLaunchCommand.shellQuote(homeDirectoryPath))",
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
            Do not present or use the home directory itself as the brain repo target.
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
        waitingForUser: \(waitingForUserDisplay(state.progress?.waitingForUser) ?? "none")
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
        - Do not run `gbrain init --pglite --no-embedding`, accept deferred embeddings, or otherwise disable embeddings until the user explicitly chooses that path.
        - Do not install/start autopilot, recurring jobs, or run a foreground dream only to satisfy `cycle_freshness`. A lone `cycle_freshness` doctor failure means the source has not completed a full cycle yet; it is not a Step 3/4 blocker.
        - Step 7 recurring jobs are maintenance, not a prerequisite for Step 4 import/index.
        - When an embedding provider decision is required, show only these two numbered options:
          1. provider key provided: set one of `OPENAI_API_KEY`, `ZEROENTROPY_API_KEY`, or `VOYAGE_API_KEY` in the environment, then continue.
          2. defer embeddings: initialize with `gbrain init --pglite --no-embedding` now; embeddings can be configured later.
        - Record the user's Step 2 embedding decision with `zebra-gbrain-onboarding report --status completed --section "Step 2: API Keys" --embedding-decision "<provider_key|defer_embeddings>"`. This records the decision only; never write API key values to Zebra state.
        - In Step 3, do not import, sync, register a source, or write a completion receipt until the user has explicitly resolved the brain repo target.

        \(targetResolutionGuard)

        Progress reporting:
        - Before a section: `zebra-gbrain-onboarding report --status started --section "<section title>"`
        - After a section: `zebra-gbrain-onboarding report --status completed --section "<section title>"`
        - When waiting for the user: `zebra-gbrain-onboarding report --status waiting_for_user --section "<section title>" --note "<what you need>"`
        - On failure: `zebra-gbrain-onboarding report --status failed --section "<section title>" --note "<reason>"`
        - When Step 3 resolves a brain repo target, include `--target "<brain repo path>" --method "<targetResolution.method>"` on the completed report.
        - After the user chooses search mode, explicitly run `gbrain config set search.mode <mode>` even when it matches the auto-applied default, then verify with `gbrain search modes`.
        - After the user chooses provider keys or deferred/no-embedding mode, report Step 2 with `--embedding-decision "provider_key"` or `--embedding-decision "defer_embeddings"` before continuing.
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
        if let cachedSnapshot = cachedDocsSnapshot() {
            return cachedSnapshot
        }
        if environment["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED"] != "1",
           Self.docsPrefetchCoordinator.waitForRunningPrefetch(
            stateURL: stateURL,
            timeout: Self.launchPrefetchWaitSeconds
           ),
           let cachedSnapshot = cachedDocsSnapshot() {
            return cachedSnapshot
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
        let remoteURLs = docsPaths.compactMap { relativePath -> (path: String, url: URL)? in
            guard let url = URL(string: "\(rawBase)/\(ref)/\(relativePath)") else { return nil }
            return (relativePath, url)
        }
        let remoteContents = fetchRemoteTexts(urlsByPath: remoteURLs)
        for relativePath in docsPaths {
            guard let content = remoteContents[relativePath] else {
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

        guard !installForAgents.isEmpty else { return nil }
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

    private func cachedDocsSnapshot() -> DocsSnapshot? {
        if let record = readDocsSnapshotCache(),
           isValidDocsSnapshot(path: record.path, manifest: record.manifest) {
            return DocsSnapshot(
                commit: record.commit,
                path: record.path,
                manifest: record.manifest
            )
        }

        guard let state = loadState(),
              let path = state.docsSnapshotPath,
              let manifest = state.docsManifest,
              isValidDocsSnapshot(path: path, manifest: manifest) else {
            return nil
        }
        return DocsSnapshot(
            commit: state.docsCommit ?? manifest.sourceRef ?? "cached",
            path: path,
            manifest: manifest
        )
    }

    private func readDocsSnapshotCache() -> DocsSnapshotRecord? {
        guard let data = try? Data(contentsOf: docsSnapshotRecordURL()) else { return nil }
        return try? JSONDecoder().decode(DocsSnapshotRecord.self, from: data)
    }

    private func writeDocsSnapshotCache(_ snapshot: DocsSnapshot) {
        let record = DocsSnapshotRecord(
            commit: snapshot.commit,
            path: snapshot.path,
            manifest: snapshot.manifest,
            storedAt: Self.isoTimestamp()
        )
        do {
            try fileManager.createDirectory(
                at: docsSnapshotRecordURL().deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(record)
            try data.write(to: docsSnapshotRecordURL(), options: .atomic)
        } catch {
            return
        }
    }

    private func docsSnapshotRecordURL() -> URL {
        stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-docs", isDirectory: true)
            .appendingPathComponent("latest-snapshot.json", isDirectory: false)
    }

    private func isValidDocsSnapshot(path: String, manifest: DocsManifest) -> Bool {
        guard !manifest.files.isEmpty else { return false }
        guard manifest.files.contains(where: { $0.path == "INSTALL_FOR_AGENTS.md" }),
              !manifest.installForAgentsSections.isEmpty else {
            return false
        }
        let snapshotURL = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: snapshotURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        return manifest.files.allSatisfy { file in
            let filePath = snapshotURL
                .appendingPathComponent(file.path, isDirectory: false)
                .path
            return fileManager.fileExists(atPath: filePath)
        }
    }

    private func remoteDocsRef() -> String? {
        if let ref = nonEmpty(environment["ZEBRA_GBRAIN_DOCS_REF"]) {
            return ref
        }
        return "main"
    }

    private func fetchRemoteTexts(urlsByPath: [(path: String, url: URL)]) -> [String: String] {
        guard !urlsByPath.isEmpty else { return [:] }
        let group = DispatchGroup()
        let lock = NSLock()
        var output: [String: String] = [:]
        var tasks: [URLSessionDataTask] = []

        for entry in urlsByPath {
            group.enter()
            let task = URLSession.shared.dataTask(with: remoteTextRequest(url: entry.url)) { data, response, _ in
                defer { group.leave() }
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let data,
                      let text = String(data: data, encoding: .utf8) else {
                    return
                }
                lock.lock()
                output[entry.path] = text
                lock.unlock()
            }
            tasks.append(task)
        }

        tasks.forEach { $0.resume() }
        if group.wait(timeout: .now() + 10) == .timedOut {
            tasks.forEach { $0.cancel() }
        }
        lock.lock()
        let result = output
        lock.unlock()
        return result
    }

    private func remoteTextRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("zebra-gbrain-onboarding", forHTTPHeaderField: "User-Agent")
        return request
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
        previousWaitingForUser: PendingUserDecision?
    ) -> PendingUserDecision? {
        guard selectedVault == nil && resolvedTargetKey == nil else { return nil }
        if waitingForUserDisplay(previousWaitingForUser) == "brain_repo_target_resolution" {
            return previousWaitingForUser
        }
        return PendingUserDecision(
            section: "Step 3: Create the Brain",
            reason: "topology_resolution",
            note: "Choose local PGLite or Supabase/Postgres.",
            createdAt: Self.isoTimestamp()
        )
    }

    private func decisionPromptContext(state: State) -> String {
        let nextSection = state.progress?.nextSection ?? ""
        let waitingForUser = waitingForUserDisplay(state.progress?.waitingForUser)
        let recommendedBrainRepoPath = recommendedBrainRepoPath()
        if waitingForUser == "topology_resolution" {
            return """
            Current user-decision gate:
            Ask only for the Step 3 topology decision now: local PGLite or Supabase/Postgres.
            Do not ask for the brain repo target in this gate. Ask for that later, after topology is chosen and Step 3 init/doctor have run.
            Do not ask for Step 2 API keys in the topology prompt. However, if a Step 3 command needs an embedding provider or offers `--no-embedding`/deferred embeddings, stop and show only the two embedding provider decision options from Zebra hard gates.
            """
        }
        if waitingForUser == "brain_repo_target_resolution" {
            return """
            Current user-decision gate:
            Ask only for the Step 3 brain repo target now. Present exactly these numbered options:
            1. Create a new brain repo at \(recommendedBrainRepoPath) (recommended)
            2. Use an existing markdown/brain repo path that the user provides
            3. Create a new brain repo at a custom path
            If the user chooses 1, ask for yes/no confirmation before creating \(recommendedBrainRepoPath). If the user chooses 2, ask for the full existing repo path. If the user chooses 3, ask for the full path to create.
            Do not present Zebra's onboarding work directory, launch directory, or any path under it as a brain repo target option.
            Do not ask for topology in this gate. Do not ask for Step 2 API keys unless the current Step 3 command refuses to continue without one. Do not silently choose `--no-embedding`; show only the two embedding provider decision options from Zebra hard gates and record `--embedding-decision` first.
            """
        }
        if nextSection.localizedCaseInsensitiveContains("Step 2") {
            return """
            Current user-decision gate:
            Ask only for Step 2 credential decisions needed by the current command.
            If no embedding provider is configured, show only the two embedding provider decision options from Zebra hard gates. Do not choose deferred/no-embedding mode without explicit user confirmation.
            Do not ask for Step 3 topology or brain repo target until Step 3 is the current section.
            """
        }
        if nextSection.localizedCaseInsensitiveContains("Step 3") {
            return """
            Current user-decision gate:
            Ask only for Step 3 decisions that are not already resolved.
            Do not ask for Step 2 API keys unless a Step 3 command refuses to continue without one. If it offers `--no-embedding` or embedding deferral, show only the two embedding provider decision options from Zebra hard gates before using that path and record the decision.
            """
        }
        return """
        Current user-decision gate:
        Ask only for decisions required by the current section.
        """
    }

    private func targetResolutionGuardContext(state: State) -> String {
        let recommendedBrainRepoPath = recommendedBrainRepoPath()
        if waitingForUserDisplay(state.progress?.waitingForUser) == "topology_resolution" {
            return """
            Target-resolution timing:
            - Do not ask for the brain repo target in the topology prompt.
            - After topology is chosen and Step 3 init/doctor have run, ask separately for the brain repo target before import, sync, source registration, or receipt write.
            """
        }
        return """
        Required target-resolution guard:
        - Allowed targetResolution.method values: selected_vault, user_existing_repo, user_created_repo, user_confirmed_home.
        - Forbidden target choices: implicit_home, onboarding_work_directory_target, auto_discovered_candidate.
        - Before import/sync/source registration/receipt write, resolve the brain repo target with the user unless the selected vault is being used.
        - When resolving the brain repo target in terminal, present exactly these numbered options:
          1. Create a new brain repo at \(recommendedBrainRepoPath) (recommended)
          2. Use an existing markdown/brain repo path that the user provides
          3. Create a new brain repo at a custom path
        - If the user chooses 1, ask for yes/no confirmation before creating \(recommendedBrainRepoPath). If the user chooses 2, ask for the full existing repo path. If the user chooses 3, ask for the full path to create.
        - Do not present Zebra's onboarding work directory, launch directory, or any path under it as a brain repo target option.
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

    private func forbiddenBrainRepoTargetReason(_ path: String, method: String?) -> String? {
        let target = Self.standardizedPath((path as NSString).expandingTildeInPath)
        if target == homeDirectoryPath,
           method != "user_confirmed_home" {
            return "implicit_home_target"
        }
        let workDirectory = Self.standardizedPath(
            stateURL
                .deletingLastPathComponent()
                .appendingPathComponent("gbrain-work", isDirectory: true)
                .path
        )
        if Self.path(target, isEqualToOrInside: workDirectory) {
            return "onboarding_work_directory_target"
        }
        return nil
    }

    private static func path(_ path: String, isEqualToOrInside directory: String) -> Bool {
        path == directory || path.hasPrefix(directory + "/")
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
                target: updatedTarget,
                hasTransientProbeFailure: false
            )
        }

        let doctor = runProcess(executable: executable, arguments: ["doctor", "--json"], cwd: vaultPath, timeout: 20)
        let doctorResult = Self.strictDoctorResult(doctor)
        let doctorOk = doctorResult.ok
        let doctorTransientFailure = !doctorOk && Self.isTransientGBrainProbeFailure(doctor)
        if doctorTransientFailure {
            reasons.append(Self.pgliteBusyReason)
        } else if !doctorOk {
            reasons.append("doctor_failed")
        }

        let sourceProbe = sourceProbeResult(
            executable: executable,
            vaultPath: vaultPath,
            sourceId: sourceId
        )

        if case .mismatch = sourceProbe.status {
            reasons.append("source_not_registered")
        }
        if case .transientFailure(let reason) = sourceProbe.status,
           !reasons.contains(reason) {
            reasons.append(reason)
        }

        let hasTransientProbeFailure: Bool
        if case .transientFailure = sourceProbe.status {
            hasTransientProbeFailure = true
        } else {
            hasTransientProbeFailure = doctorTransientFailure
        }
        let complete = reasons.isEmpty && doctorOk && sourceProbe.status == .verified
        updatedTarget.gbrainExecutablePath = executable
        updatedTarget.doctorStatus = ProbeResult(
            ok: doctorOk,
            status: doctorOk ? "ok" : "failed"
        )
        updatedTarget.sourcesCurrentResult = SourceProbeResult(
            ok: sourceProbe.status == .verified,
            sourceId: sourceProbe.currentSourceId ?? sourceId,
            localPath: sourceProbe.listedLocalPath
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
            target: updatedTarget,
            hasTransientProbeFailure: hasTransientProbeFailure
        )
    }

    private func sourceProbeResult(
        executable: String,
        vaultPath: String,
        sourceId: String
    ) -> (status: SourceProbeStatus, currentSourceId: String?, listedLocalPath: String?) {
        let current = runProcess(executable: executable, arguments: ["sources", "current", "--json"], cwd: vaultPath, timeout: 12)
        guard current.exitCode == 0,
              !current.timedOut,
              let currentObject = Self.jsonObject(from: current.stdout) else {
            if let reason = Self.transientGBrainProbeReason(current) {
                return (.transientFailure(reason: reason), nil, nil)
            }
            return (.mismatch, nil, nil)
        }
        let currentSourceId = currentObject["source_id"] as? String
        guard currentSourceId == sourceId else {
            return (.mismatch, currentSourceId, nil)
        }

        let list = runProcess(executable: executable, arguments: ["sources", "list", "--json"], cwd: vaultPath, timeout: 12)
        guard list.exitCode == 0,
              !list.timedOut,
              Self.jsonObject(from: list.stdout) != nil else {
            if let reason = Self.transientGBrainProbeReason(list) {
                return (.transientFailure(reason: reason), currentSourceId, nil)
            }
            return (.mismatch, currentSourceId, nil)
        }
        let listedLocalPath = Self.sourceLocalPath(sourceId: sourceId, fromSourcesListJSON: list.stdout)
        guard listedLocalPath.map(Self.standardizedPath) == vaultPath else {
            return (.mismatch, currentSourceId, listedLocalPath)
        }

        return (.verified, currentSourceId, listedLocalPath)
    }

    private func updateReceipt(with live: LiveVerificationResult, targetKey: String) {
        guard var state = loadState() else { return }
        var receipt = state.receipt ?? Receipt(globalReadiness: nil, primaryTargetKey: nil, targets: nil)
        if preservesCompletedReceiptOnTransientFailure(receipt: receipt, live: live, targetKey: targetKey) {
            return
        }
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

    private func preservesCompletedReceiptOnTransientFailure(
        receipt: Receipt,
        live: LiveVerificationResult,
        targetKey: String
    ) -> Bool {
        guard receipt.globalReadiness?.complete == true,
              receipt.targets?[targetKey]?.complete == true,
              live.target.complete == false,
              Self.containsOnlyTransientProbeReasons(live.target.reasons ?? []),
              live.hasTransientProbeFailure else {
            return false
        }
        return true
    }

    private static func isTransientGBrainProbeFailure(_ result: ProcessRunResult) -> Bool {
        transientGBrainProbeReason(result) != nil
    }

    private static func transientGBrainProbeReason(_ result: ProcessRunResult) -> String? {
        if result.timedOut { return pgliteBusyReason }
        let output = "\(result.stderr)\n\(result.stdout)".lowercased()
        if output.contains("timed out waiting for pglite lock")
            || output.contains("connect timed out")
            || output.contains("connection timed out") {
            return pgliteBusyReason
        }
        return nil
    }

    private static func containsOnlyTransientProbeReasons(_ reasons: [String]) -> Bool {
        reasons.allSatisfy { $0 == pgliteBusyReason }
    }

    private static func strictDoctorResult(_ result: ProcessRunResult) -> DoctorResult {
        if result.exitCode == 0, !result.timedOut {
            return DoctorResult(ok: true)
        }
        return DoctorResult(ok: false)
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

    private func recommendedBrainRepoPath() -> String {
        Self.standardizedPath((homeDirectoryPath as NSString).appendingPathComponent("brain"))
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
    allowed_embedding_decisions = {"provider_key", "defer_embeddings"}

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

    PGLITE_BUSY_REASON = "pglite_busy"
    CYCLE_FRESHNESS_CHECK_NAME = "cycle_freshness"

    def transient_probe_reason(message):
        text = (message or "").lower()
        if (
            "timed out waiting for pglite lock" in text
            or "connect timed out" in text
            or "connection timed out" in text
            or "timed out" in text
        ):
            return PGLITE_BUSY_REASON
        return None

    def transient_probe_failure(message):
        return transient_probe_reason(message) is not None

    def strict_doctor_result(result):
        return result.returncode == 0, False

    def doctor_allows_create_or_import_progress(result):
        if result.returncode == 0:
            return True, False
        try:
            payload = json.loads(result.stdout or "{}")
        except Exception:
            return False, False
        checks = payload.get("checks") or []
        if not checks:
            return False, False
        blocking = []
        ignored_cycle_freshness = False
        for check in checks:
            status = str(check.get("status") or "").lower()
            if status not in {"fail", "failed", "error"}:
                continue
            if check.get("name") == CYCLE_FRESHNESS_CHECK_NAME:
                ignored_cycle_freshness = True
            else:
                blocking.append(check.get("name") or "unknown")
        ok = len(blocking) == 0 and ignored_cycle_freshness
        return ok, ok

    def strict_doctor_ok(result):
        ok, _ = strict_doctor_result(result)
        return ok

    def doctor_allows_create_or_import_progress_ok(result):
        ok, _ = doctor_allows_create_or_import_progress(result)
        return ok

    def source_list_local_path(payload, source_id):
        for source in payload.get("sources") or []:
            if source.get("id") == source_id:
                return source.get("local_path")
        return None

    def source_probe_status(executable, target_path, source_id):
        current_ok, current_payload, current_error = run_json(
            [executable, "sources", "current", "--json"],
            cwd=target_path,
            timeout=12,
        )
        if not current_ok:
            reason = transient_probe_reason(current_error)
            if reason:
                return "transient", None, None, reason
            return "mismatch", None, None, None
        current_source_id = current_payload.get("source_id")
        if current_source_id != source_id:
            return "mismatch", current_source_id, None, None

        list_ok, list_payload, list_error = run_json(
            [executable, "sources", "list", "--json"],
            cwd=target_path,
            timeout=12,
        )
        if not list_ok:
            reason = transient_probe_reason(list_error)
            if reason:
                return "transient", current_source_id, None, reason
            return "mismatch", current_source_id, None, None
        listed_local_path = source_list_local_path(list_payload, source_id)
        if not listed_local_path or os.path.abspath(os.path.expanduser(listed_local_path)) != os.path.abspath(target_path):
            return "mismatch", current_source_id, listed_local_path, None
        return "verified", current_source_id, listed_local_path, None

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
        target = os.path.abspath(os.path.expanduser(target))
        forbidden_reason = forbidden_target_reason(target, method)
        if forbidden_reason:
            return forbidden_reason
        if method not in allowed_methods:
            return "target_confirmation_missing"
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

    def embedding_decision_flags_present(flags):
        return bool(flags.get("embedding_decision"))

    def apply_embedding_decision(state, flags):
        decision = flags.get("embedding_decision")
        if not decision:
            return None
        if decision not in allowed_embedding_decisions:
            return "invalid_embedding_decision"
        progress = state.setdefault("progress", {})
        progress["embeddingDecision"] = {
            "decision": decision,
            "confirmedAt": now(),
        }
        return None

    def embedding_decision_recorded(state):
        progress = state.get("progress") or {}
        decision = progress.get("embeddingDecision") or {}
        return decision.get("decision") in allowed_embedding_decisions

    def waiting_reason(waiting):
        if isinstance(waiting, dict):
            return waiting.get("reason") or waiting.get("note") or waiting.get("section")
        if isinstance(waiting, str):
            return waiting
        return None

    def waiting_section(waiting):
        if isinstance(waiting, dict):
            return waiting.get("section")
        return None

    def set_waiting_for_user(progress, section, reason, note=None):
        progress["waitingForUser"] = {
            "section": section or None,
            "reason": reason or "user_input_required",
            "note": note or section or reason or "user input required",
            "createdAt": now(),
        }

    def allowed_waiting_reasons(role):
        if role == "create_brain":
            return ["topology_resolution", "brain_repo_target_resolution"]
        return []

    def waiting_reason_guard_reason(role, requested_reason):
        allowed = allowed_waiting_reasons(role)
        if not allowed:
            return None
        if not requested_reason:
            return "missing_waiting_reason"
        if requested_reason not in allowed:
            return "unsupported_waiting_reason"
        return None

    def recommended_brain_repo_path():
        return os.path.abspath(os.path.join(zebra_home_directory(), "brain"))

    def target_resolution_next_action():
        recommended = recommended_brain_repo_path()
        return {
            "nextAction": "ask_user_for_brain_repo_target",
            "targetOptions": [
                {
                    "reply": "1",
                    "description": f"Create a new brain repo at {recommended} (recommended)",
                    "path": recommended,
                    "method": "user_created_repo",
                },
                {
                    "reply": "2 <path>",
                    "description": "Use an existing markdown/brain repo path that the user provides",
                    "method": "user_existing_repo",
                },
                {
                    "reply": "3 <path>",
                    "description": "Create a new brain repo at a custom path",
                    "method": "user_created_repo",
                },
            ],
        }

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

    def path_equal_or_inside(path, directory):
        if not path or not directory:
            return False
        path = os.path.abspath(os.path.expanduser(path))
        directory = os.path.abspath(os.path.expanduser(directory))
        return path == directory or path.startswith(directory + os.sep)

    def zebra_home_directory():
        return os.path.abspath(os.path.expanduser(os.environ.get("ZEBRA_GBRAIN_HOME") or "~"))

    def onboarding_work_directory():
        return os.path.join(os.path.dirname(state_path), "gbrain-work")

    def forbidden_target_reason(path, method=None):
        if not path:
            return None
        target = os.path.abspath(os.path.expanduser(path))
        if target == zebra_home_directory() and method != "user_confirmed_home":
            return "implicit_home_target"
        if path_equal_or_inside(target, onboarding_work_directory()):
            return "onboarding_work_directory_target"
        return None

    def target_guard_reasons(state):
        _, target_path, method, _ = resolved_target(state)
        reasons = []
        if not target_path:
            reasons.append("brain_repo_target_unresolved")
            return reasons
        target_path = os.path.abspath(os.path.expanduser(target_path))
        forbidden_reason = forbidden_target_reason(target_path, method)
        if forbidden_reason:
            reasons.append(forbidden_reason)
        if method not in allowed_methods:
            reasons.append("target_confirmation_missing")
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
            return strict_doctor_ok(result)
        except Exception:
            return False

    def doctor_allows_create_brain_progress(state):
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
            return doctor_allows_create_or_import_progress_ok(result)
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
        status, _, _, _ = source_probe_status(executable, target_path, source_id)
        return status == "verified"

    def source_registration_guard_reason(state, flags):
        executable = gbrain_executable()
        if not executable:
            return "source_not_registered"
        _, target_path, _, target_entry = resolved_target(state)
        source_id = flags.get("source_id") or target_entry.get("sourceId")
        if not target_path or not os.path.isdir(target_path) or not source_id:
            return "source_not_registered"
        status, _, _, transient_reason = source_probe_status(executable, target_path, source_id)
        if status == "verified":
            return None
        return transient_reason or "source_not_registered"

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

    def reject_report(state, reason, section, status, next_action=None, extra_payload=None):
        progress = state.setdefault("progress", {})
        progress["lastFailure"] = reason
        progress["lastStatus"] = "rejected"
        progress["updatedAt"] = now()
        if reason in {
            "brain_repo_target_unresolved",
            "target_confirmation_missing",
            "implicit_home_target",
            "onboarding_work_directory_target",
            "gbrain_tool_repo_target",
            "brain_repo_target_missing",
        }:
            set_waiting_for_user(progress, section, "brain_repo_target_resolution", "Resolve the GBrain brain repo target.")
        elif reason == "section_role_unknown":
            set_waiting_for_user(progress, section, "section_role_mapping_resolution", "Map this INSTALL_FOR_AGENTS section to a known Zebra role.")
        save_state(state)
        payload = {
            "ok": False,
            "reason": reason,
            "section": section,
            "status": status,
        }
        if extra_payload:
            payload.update(extra_payload)
        if waiting_reason(progress.get("waitingForUser")) == "brain_repo_target_resolution":
            payload.update(target_resolution_next_action())
        elif next_action:
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
        if role == "credentials" and status == "completed" and not embedding_decision_recorded(state):
            return "embedding_decision_required"
        if role == "create_brain" and status == "completed":
            if target_reasons:
                return target_reasons[0]
            if not embedding_decision_recorded(state):
                return "embedding_decision_required"
            if not doctor_allows_create_brain_progress(state):
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
            if status == "completed":
                source_reason = source_registration_guard_reason(state, flags)
                if source_reason:
                    return source_reason
        if role == "verify" and status == "completed" and not receipt_verify_complete(state):
            return "verify_incomplete"
        return None

    def target_confirmation_flags_present(flags):
        return bool(flags.get("target") or flags.get("target_path") or flags.get("method") or flags.get("profile_id"))

    def should_clear_waiting_for_user(state, progress, status, role, flags, section):
        waiting = progress.get("waitingForUser")
        if not waiting:
            return False
        reason = waiting_reason(waiting)
        if reason == "topology_resolution":
            return role == "create_brain" and status in {"started", "completed"}
        if reason == "brain_repo_target_resolution":
            return (
                role == "create_brain"
                and status == "completed"
                and bool(flags.get("target") or flags.get("target_path"))
                and flags.get("method") in allowed_methods
            )
        waited_section = waiting_section(waiting)
        if (
            waited_section
            and section
            and normalize_title(waited_section) == normalize_title(section)
            and status in {"completed", "skipped", "deferred"}
        ):
            return True
        if (
            status == "completed"
            and role == "verify"
            and receipt_verify_complete(state)
            and reason not in {"topology_resolution", "brain_repo_target_resolution", "section_role_mapping_resolution"}
        ):
            return True
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
            if waiting_reason(progress.get("waitingForUser")) == "section_role_mapping_resolution":
                progress.pop("waitingForUser", None)
            progress["updatedAt"] = now()
            save_state(state)
            print(json.dumps({"ok": True, "status": status, "section": section, "role": role}, sort_keys=True))
            return

        candidate_state = json.loads(json.dumps(state))
        role, _, _ = section_role(candidate_state, section, record=True)
        if status == "waiting_for_user":
            waiting_error = waiting_reason_guard_reason(role, flags.get("reason"))
            if waiting_error:
                reject_report(
                    state,
                    waiting_error,
                    section,
                    status,
                    extra_payload={"allowedReasons": allowed_waiting_reasons(role)},
                )
        if target_confirmation_flags_present(flags):
            if not (role == "create_brain" and status == "completed"):
                reject_report(state, "target_flags_not_allowed", section, status)
            target_error = apply_target_flags(candidate_state, flags)
            if target_error:
                reject_report(state, target_error, section, status)
        if embedding_decision_flags_present(flags):
            if not (role == "credentials" and status == "completed"):
                reject_report(state, "embedding_decision_flags_not_allowed", section, status)
            embedding_error = apply_embedding_decision(candidate_state, flags)
            if embedding_error:
                reject_report(state, embedding_error, section, status)
        guard_reason = report_guard_reason(candidate_state, status, role, flags)
        if guard_reason:
            next_action = None
            if guard_reason == "section_role_unknown":
                next_action = "report mapped_role with role and evidence, or report waiting_for_user"
            elif guard_reason in {
                "brain_repo_target_unresolved",
                "target_confirmation_missing",
                "implicit_home_target",
                "onboarding_work_directory_target",
            }:
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
        waiting_reason_value = None
        if status == "waiting_for_user":
            waiting_reason_value = flags.get("reason") or "user_input_required"
            set_waiting_for_user(progress, section, waiting_reason_value, note)
        elif should_clear_waiting_for_user(state, progress, status, role, flags, section):
            progress.pop("waitingForUser", None)
        if status == "failed":
            progress["lastFailure"] = note or section or "failed"
        elif status in ("started", "completed", "skipped", "deferred"):
            progress.pop("lastFailure", None)
        progress["lastStatus"] = status
        progress["updatedAt"] = now()
        save_state(state)
        payload = {"ok": True, "status": status, "section": section}
        if waiting_reason_value == "brain_repo_target_resolution":
            payload.update(target_resolution_next_action())
        print(json.dumps(payload, sort_keys=True))

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
            forbidden_reason = forbidden_target_reason(target, method)
            if forbidden_reason:
                reasons.append(forbidden_reason)
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
        doctor_transient = False
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
                doctor_ok, _ = strict_doctor_result(result)
                doctor_transient_reason = None if doctor_ok else transient_probe_reason((result.stderr or "") + "\\n" + (result.stdout or ""))
                doctor_transient = doctor_transient_reason is not None
                if doctor_transient_reason and doctor_transient_reason not in reasons:
                    reasons.append(doctor_transient_reason)
                elif not doctor_ok:
                    reasons.append("doctor_failed")
            except Exception as exc:
                doctor_transient_reason = transient_probe_reason(str(exc))
                doctor_transient = doctor_transient_reason is not None
                if doctor_transient_reason and doctor_transient_reason not in reasons:
                    reasons.append(doctor_transient_reason)
                elif not doctor_transient:
                    reasons.append("doctor_failed")

        source_probe = "transient"
        current_ok = False
        current_source_id = None
        list_ok = False
        listed_local_path = None
        source_transient_reason = None
        if executable and target and os.path.isdir(target) and source_id:
            source_probe, current_source_id, listed_local_path, source_transient_reason = source_probe_status(executable, target, source_id)
            current_ok = source_probe == "verified"
            list_ok = source_probe == "verified"
            if source_probe == "mismatch":
                reasons.append("source_not_registered")
            elif source_transient_reason and source_transient_reason not in reasons:
                reasons.append(source_transient_reason)

        state = load_state()
        receipt = state.setdefault("receipt", {})
        key = target_key(target) if target and os.path.isdir(target) else None
        existing_target = (receipt.get("targets") or {}).get(key) if key else None
        transient_source_probe = source_probe == "transient" and executable and target and os.path.isdir(target) and source_id
        transient_probe = doctor_transient or transient_source_probe
        preserve_complete = (
            transient_probe
            and all(reason == PGLITE_BUSY_REASON for reason in reasons)
            and bool(receipt.get("globalReadiness", {}).get("complete"))
            and bool((existing_target or {}).get("complete"))
            and bool(executable)
        )
        complete = preserve_complete or (len(reasons) == 0 and doctor_ok and source_probe == "verified")
        if preserve_complete:
            print(json.dumps({"complete": True, "reasons": []}, sort_keys=True))
            save_state(state)
            sys.exit(0)
        receipt["globalReadiness"] = {
            "complete": bool(executable and doctor_ok),
            "gbrainExecutablePath": executable,
            "doctorOk": doctor_ok,
            "verifiedAt": now(),
        }
        if key:
            targets = receipt.setdefault("targets", {})
            targets[key] = {
                "vaultPath": target,
                "sourceId": source_id,
                "profileId": profile_id,
                "gbrainExecutablePath": executable,
                "doctorStatus": {
                    "ok": doctor_ok,
                    "status": "ok" if doctor_ok else "failed",
                },
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

private final class GBrainDocsPrefetchCoordinator {
    private let lock = NSLock()
    private var startedKeys: Set<String> = []
    private var runningGroupsByKey: [String: DispatchGroup] = [:]

    func prefetchIfNeeded(store: ZebraGBrainOnboardingStore) -> Bool {
        let key = store.docsPrefetchKey
        let group = DispatchGroup()

        lock.lock()
        if runningGroupsByKey[key] != nil || startedKeys.contains(key) {
            lock.unlock()
            return store.hasCachedDocsSnapshot()
        }
        startedKeys.insert(key)
        group.enter()
        runningGroupsByKey[key] = group
        lock.unlock()

        let result = store.fetchAndCacheRemoteDocsSnapshot()

        lock.lock()
        runningGroupsByKey[key] = nil
        lock.unlock()
        group.leave()
        return result
    }

    func waitForRunningPrefetch(stateURL: URL, timeout: TimeInterval) -> Bool {
        lock.lock()
        let group = runningGroupsByKey[stateURL.path]
        lock.unlock()
        guard let group else { return false }
        return group.wait(timeout: .now() + timeout) == .success
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
