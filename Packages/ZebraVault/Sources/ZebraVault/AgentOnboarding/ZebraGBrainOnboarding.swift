import Foundation

struct ZebraOnboardingChecklistSubstepSnapshot: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String?
    let isCompleted: Bool
    let isActive: Bool
    let isWaitingForUser: Bool
    let isRunning: Bool
    let showsStart: Bool
    let wasStartedBefore: Bool
    let isAttention: Bool
    let isSkipped: Bool

    init(
        id: String,
        title: String,
        detail: String? = nil,
        isCompleted: Bool,
        isActive: Bool,
        isWaitingForUser: Bool,
        isRunning: Bool,
        showsStart: Bool,
        wasStartedBefore: Bool,
        isAttention: Bool = false,
        isSkipped: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isCompleted = isCompleted
        self.isActive = isActive
        self.isWaitingForUser = isWaitingForUser
        self.isRunning = isRunning
        self.showsStart = showsStart
        self.wasStartedBefore = wasStartedBefore
        self.isAttention = isAttention
        self.isSkipped = isSkipped
    }
}

public struct ZebraGBrainOnboardingStore {
    public struct LaunchContext {
        public let launchDirectory: String
        public let startupPrompt: String
        public let runId: String
        public let shellEnvironmentPrefix: String
        public let allowTrustedAutomation: Bool
        public let allowLaunchDirectoryTrust: Bool
        public let existingInstallVerificationMode: Bool

        public init(
            launchDirectory: String,
            startupPrompt: String,
            runId: String,
            shellEnvironmentPrefix: String,
            allowTrustedAutomation: Bool,
            allowLaunchDirectoryTrust: Bool,
            existingInstallVerificationMode: Bool = false
        ) {
            self.launchDirectory = launchDirectory
            self.startupPrompt = startupPrompt
            self.runId = runId
            self.shellEnvironmentPrefix = shellEnvironmentPrefix
            self.allowTrustedAutomation = allowTrustedAutomation
            self.allowLaunchDirectoryTrust = allowLaunchDirectoryTrust
            self.existingInstallVerificationMode = existingInstallVerificationMode
        }
    }

    struct CompletionResult: Equatable {
        let isComplete: Bool
        let reasons: [String]
    }

    public struct ActiveGBrainBinding: Codable, Equatable {
        public let sourceRepoPath: String
        public let sourceRepoStatus: String
        public let gbrainHomePath: String
        public let confirmedAt: String

        public init(
            sourceRepoPath: String,
            sourceRepoStatus: String,
            gbrainHomePath: String,
            confirmedAt: String
        ) {
            self.sourceRepoPath = sourceRepoPath
            self.sourceRepoStatus = sourceRepoStatus
            self.gbrainHomePath = gbrainHomePath
            self.confirmedAt = confirmedAt
        }
    }

    private struct State: Codable {
        var schemaVersion: Int
        var currentRunId: String?
        var docsCommit: String?
        var docsFetchedAt: String?
        var docsSnapshotPath: String?
        var docsManifest: DocsManifest?
        var selectedAgent: String?
        var activeGBrainBinding: ActiveGBrainBinding?
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
                activeGBrainBinding: nil,
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
        var gbrainSetupMode: String?
        var freshInstallConfirmedAt: String?
        var existingInstallVerification: ExistingInstallVerification?
    }

    private struct ExistingInstallVerification: Codable, Equatable {
        var status: String?
        var verifiedAt: String?
        var gbrainExecutablePath: String?
        var gbrainVersion: String?
        var doctorOk: Bool?
        var readProbeOk: Bool?
        var sourceProbeOk: Bool?
        var sourceId: String?
        var reasons: [String]?
        var preservedReceipt: Bool?
        var transientFailure: Bool?
    }

    private struct EmbeddingDecision: Codable {
        var decision: String?
        var provider: String?
        var keyEnvName: String?
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
        var doctorEffectiveOk: Bool? = nil
        var verifiedAt: String?
    }

    private struct Target: Codable, Equatable {
        var vaultPath: String?
        var sourceId: String?
        var profileId: String?
        var remoteMCPURL: String?
        var gbrainExecutablePath: String?
        var wrapperPath: String?
        var doctorStatus: ProbeResult?
        var sourcesCurrentResult: SourceProbeResult?
        var syncProbeResult: ProbeResult?
        var statsProbeResult: ProbeResult?
        var embeddingProbeResult: ProbeResult?
        var searchProbeResult: ProbeResult?
        var sourceVerification: SourceVerification?
        var verifiedAt: String?
        var complete: Bool?
        var status: String?
        var warnings: [String]?
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
        var failedChecks: [String]? = nil
    }

    private struct SourceProbeResult: Codable, Equatable {
        var ok: Bool?
        var sourceId: String?
        var localPath: String?
        var status: String?
        var reason: String?
    }

    private struct SourceVerification: Codable, Equatable {
        var sourceId: String?
        var targetPath: String?
        var remoteMCPURL: String?
        var verifiedAt: String?
        var method: String?
        var gbrainExecutablePath: String?
        var gbrainVersion: String?
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
        var hasTransientProbeFailure: Bool
    }

    private struct DoctorResult {
        var ok: Bool
        var failedChecks: [String]
        var effectiveOk: Bool
        var maintenancePending: Bool
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
        case error(reason: String)
    }

    private static let pgliteBusyReason = "pglite_busy"
    private static let pgliteWasmRuntimeErrorReason = "pglite_wasm_runtime_error"
    private static let sourceProbeRuntimeErrorReason = "source_probe_runtime_error"
    private static let prepareSourceRepoSectionID = "zebra-gbrain-prepare-source"
    private static let existingInstallVerificationMode = "existing_install_verification"
    private static let freshInstallMode = "fresh_install"

    private static let allowedTargetResolutionMethods: Set<String> = [
        "selected_vault",
        "user_existing_repo",
        "user_created_repo",
        "user_confirmed_home",
        "thin_client_remote",
    ]

    private let stateURL: URL
    private let fileManager: FileManager
    private let homeDirectoryPath: String
    private let gbrainDocsRepoURL: URL?
    private let environment: [String: String]
    private let onboardingLanguage: ZebraOnboardingLanguage

    public init(
        stateURL: URL = ZebraGBrainOnboardingStore.defaultStateURL(),
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory(),
        gbrainDocsRepoURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        appPreferredLocalizations: [String] = Bundle.main.preferredLocalizations,
        preferredLanguages: [String] = Locale.preferredLanguages,
        currentLocaleIdentifier: String = Locale.current.identifier
    ) {
        self.stateURL = stateURL
        self.fileManager = fileManager
        self.homeDirectoryPath = Self.standardizedPath(homeDirectoryPath)
        self.gbrainDocsRepoURL = gbrainDocsRepoURL
        self.environment = environment
        self.onboardingLanguage = ZebraOnboardingLanguage.current(
            appPreferredLocalizations: appPreferredLocalizations,
            preferredLanguages: preferredLanguages,
            currentLocaleIdentifier: currentLocaleIdentifier
        )
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

    public func activeSourceRepoPathFromCachedState() -> String? {
        guard let sourceRepoPath = loadState()?.activeGBrainBinding?.sourceRepoPath else {
            return nil
        }
        return validGBrainSourceRepoPath(sourceRepoPath)
    }

    public func nextSectionIsImportIndexFromCachedState() -> Bool {
        guard let state = loadState(),
              let nextSection = nonEmpty(state.progress?.nextSection) else {
            return false
        }
        let normalized = Self.normalizedSectionTitle(nextSection)
        return normalized.contains("step 4")
            && normalized.contains("import")
            && normalized.contains("index")
    }

    func recurringJobsCompletedFromCachedState() -> Bool {
        guard let state = loadState(),
              let completedSections = state.progress?.completedSections,
              !completedSections.isEmpty else {
            return false
        }
        return completedSections.contains { completedSection in
            completedSectionHasRole("recurring_jobs", title: completedSection, in: state)
                || Self.isRecurringJobsSectionTitle(completedSection)
        }
    }

    func sectionSnapshotsFromCachedState(
        isParentRunning: Bool,
        showsStartForActiveSection: Bool,
        wasStartedBefore: Bool
    ) -> [ZebraOnboardingChecklistSubstepSnapshot] {
        guard let state = loadState() else {
            return []
        }
        if isExistingInstallVerificationMode(state) {
            return existingInstallVerificationSnapshots(
                state: state,
                isParentRunning: isParentRunning,
                showsStartForActiveSection: showsStartForActiveSection,
                wasStartedBefore: wasStartedBefore
            )
        }
        let sourcePrepared = state.activeGBrainBinding != nil || state.docsManifest != nil
        let manifestSections = state.docsManifest?.installForAgentsSections ?? []
        let sections = manifestSections.isEmpty
            ? fallbackInstallForAgentsSectionsForPendingSourcePrepare(state: state)
            : Self.enabledInstallForAgentsSections(manifestSections)
        guard !sections.isEmpty else { return [] }

        let completedSections = state.progress?.completedSections ?? []
        let completedTitles = Set(completedSections)
        let completedNormalizedTitles = Set(completedSections.map(Self.normalizedSectionTitle))
        let waitingSection = nonEmpty(state.progress?.waitingForUser?.section)
        let waitingNormalizedTitle = waitingSection.map(Self.normalizedSectionTitle)
        let activeTitle = sourcePrepared
            ? (waitingSection ?? nonEmpty(state.progress?.nextSection))
            : nil
        let activeNormalizedTitle = activeTitle.map(Self.normalizedSectionTitle)
        let sourceIsActive = !sourcePrepared

        let prepareSourceSnapshot = ZebraOnboardingChecklistSubstepSnapshot(
            id: Self.prepareSourceRepoSectionID,
            title: Self.prepareSourceRepoSectionTitle(),
            isCompleted: sourcePrepared,
            isActive: sourceIsActive,
            isWaitingForUser: false,
            isRunning: isParentRunning && sourceIsActive,
            showsStart: showsStartForActiveSection && sourceIsActive,
            wasStartedBefore: wasStartedBefore
        )

        return [prepareSourceSnapshot] + sections.map { section in
            let normalizedTitle = Self.normalizedSectionTitle(section.title)
            let isCompleted = completedTitles.contains(section.title)
                || completedNormalizedTitles.contains(normalizedTitle)
            let isActive = activeTitle == section.title
                || (activeNormalizedTitle != nil && activeNormalizedTitle == normalizedTitle)
            let isWaitingForUser = waitingSection == section.title
                || (waitingNormalizedTitle != nil && waitingNormalizedTitle == normalizedTitle)

            return ZebraOnboardingChecklistSubstepSnapshot(
                id: section.hash.isEmpty ? section.title : section.hash,
                title: section.title,
                isCompleted: isCompleted,
                isActive: isActive,
                isWaitingForUser: isWaitingForUser,
                isRunning: isParentRunning && isActive,
                showsStart: sourcePrepared && showsStartForActiveSection && isActive,
                wasStartedBefore: wasStartedBefore
            )
        }
    }

    private func fallbackInstallForAgentsSectionsForPendingSourcePrepare(state: State) -> [DocsSection] {
        guard !isExistingInstallVerificationMode(state) else {
            return []
        }
        guard let sourceRepoPath = sourceRepoPathForPendingSourcePrepareProjection(state: state) else {
            return []
        }
        let installForAgentsURL = URL(fileURLWithPath: sourceRepoPath, isDirectory: true)
            .appendingPathComponent("INSTALL_FOR_AGENTS.md", isDirectory: false)
        guard let markdown = try? String(contentsOf: installForAgentsURL, encoding: .utf8) else {
            return []
        }
        return Self.installForAgentsSections(from: markdown)
    }

    private func sourceRepoPathForPendingSourcePrepareProjection(state: State) -> String? {
        if let sourceRepoPath = state.activeGBrainBinding?.sourceRepoPath,
           let validPath = validGBrainSourceRepoPath(sourceRepoPath) {
            return validPath
        }
        if let defaultPath = nonEmpty(environment["ZEBRA_GBRAIN_SOURCE_REPO_DEFAULT"]),
           let validPath = validGBrainSourceRepoPath(defaultPath) {
            return validPath
        }
        let recommendedPath = (homeDirectoryPath as NSString).appendingPathComponent("gbrain")
        return validGBrainSourceRepoPath(recommendedPath)
    }

    private func isExistingInstallVerificationMode(_ state: State) -> Bool {
        state.progress?.gbrainSetupMode == Self.existingInstallVerificationMode
    }

    private func existingInstallVerificationSnapshots(
        state: State,
        isParentRunning: Bool,
        showsStartForActiveSection: Bool,
        wasStartedBefore: Bool
    ) -> [ZebraOnboardingChecklistSubstepSnapshot] {
        let verification = state.progress?.existingInstallVerification
        let status = verification?.status
        let reasons = verification?.reasons ?? []
        let diagnosisNeeded = status == "diagnosis_needed" || status == "existing_install_failed"

        guard diagnosisNeeded else {
            return []
        }

        return [
            ZebraOnboardingChecklistSubstepSnapshot(
                id: "zebra-gbrain-existing-install-diagnosis",
                title: Self.existingInstallDiagnosisTitle(),
                detail: existingInstallVerificationDetail(status: status, reasons: reasons),
                isCompleted: false,
                isActive: true,
                isWaitingForUser: false,
                isRunning: isParentRunning,
                showsStart: showsStartForActiveSection,
                wasStartedBefore: wasStartedBefore,
                isAttention: true
            ),
        ]
    }

    private func existingInstallVerificationDetail(status: String?, reasons: [String]) -> String? {
        if status == "transient_retry_preserved" {
            return String(
                localized: "brain.onboarding.gbrain.substep.existingInstall.transient.detail",
                defaultValue: "Previous verification is preserved; retry after the transient failure clears."
            )
        }
        guard !reasons.isEmpty else { return nil }
        let joined = reasons.joined(separator: ", ")
        let format = String(
            localized: "brain.onboarding.gbrain.substep.existingInstall.reasons.detail",
            defaultValue: "Diagnosis evidence: %@"
        )
        return String(format: format, joined)
    }

    private func validGBrainSourceRepoPath(_ sourceRepoPath: String) -> String? {
        let standardized = Self.standardizedPath((sourceRepoPath as NSString).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.fileExists(
                atPath: URL(fileURLWithPath: standardized, isDirectory: true)
                    .appendingPathComponent("package.json", isDirectory: false)
                    .path
              ),
              fileManager.fileExists(
                atPath: URL(fileURLWithPath: standardized, isDirectory: true)
                    .appendingPathComponent("INSTALL_FOR_AGENTS.md", isDirectory: false)
                    .path
              ),
              fileManager.fileExists(
                atPath: URL(fileURLWithPath: standardized, isDirectory: true)
                    .appendingPathComponent("skills", isDirectory: true)
                    .path,
                isDirectory: &isDirectory
              ),
              isDirectory.boolValue else {
            return nil
        }
        return standardized
    }

    private static func prepareSourceRepoSectionTitle() -> String {
        String(
            localized: "brain.onboarding.gbrain.substep.prepareSource",
            defaultValue: "Check and clone GBrain repo"
        )
    }

    private static func existingInstallDiagnosisTitle() -> String {
        String(
            localized: "brain.onboarding.gbrain.substep.existingInstall.diagnose",
            defaultValue: "Diagnose existing GBrain install"
        )
    }

    @discardableResult
    public func prefetchDocsSnapshotIfNeeded() -> Bool {
        false
    }

    func hasSourceRepoPrepareAbortMarker() -> Bool {
        loadState()?.progress?.lastFailure == "source_repo_prepare_aborted"
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
        guard let resolved = resolveTarget(in: receipt, selectedVaultPath: selectedVaultPath) else {
            return CompletionResult(isComplete: false, reasons: ["receipt_target_missing"])
        }

        var reasons: [String] = []
        if !targetResolutionVerifies(resolved.target.targetResolution) {
            reasons.append("target_confirmation_missing")
        }
        if targetHasThinClientRemoteVerification(resolved.target),
           receiptIsComplete(receipt, selectedVaultPath: selectedVaultPath),
           reasons.isEmpty {
            return CompletionResult(isComplete: true, reasons: [])
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
        if targetHasThinClientReadVerification(resolved.target),
           receiptIsComplete(receipt, selectedVaultPath: selectedVaultPath),
           reasons.isEmpty {
            return CompletionResult(isComplete: true, reasons: [])
        }
        guard let sourceId = nonEmpty(resolved.target.sourceId) else {
            reasons.append("source_not_registered")
            return CompletionResult(isComplete: false, reasons: reasons)
        }
        if !reasons.isEmpty {
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
        guard let resolved = resolveTarget(in: receipt, selectedVaultPath: selectedVaultPath) else {
            return CompletionResult(isComplete: false, reasons: ["receipt_target_missing"])
        }

        var reasons: [String] = []
        if !targetResolutionVerifies(resolved.target.targetResolution) {
            reasons.append("target_confirmation_missing")
        }
        if targetHasThinClientRemoteVerification(resolved.target) {
            guard receiptIsComplete(receipt, selectedVaultPath: selectedVaultPath) else {
                reasons.append("receipt_incomplete")
                return CompletionResult(isComplete: false, reasons: reasons)
            }
            return CompletionResult(isComplete: reasons.isEmpty, reasons: reasons)
        } else {
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
        }
        guard nonEmpty(resolved.target.sourceId) != nil || targetHasThinClientReadVerification(resolved.target) else {
            reasons.append("source_not_registered")
            return CompletionResult(isComplete: false, reasons: reasons)
        }
        guard receiptIsComplete(receipt, selectedVaultPath: selectedVaultPath) else {
            reasons.append("receipt_incomplete")
            return CompletionResult(isComplete: false, reasons: reasons)
        }
        return CompletionResult(isComplete: true, reasons: [])
    }

    private func targetHasThinClientReadVerification(_ target: Target) -> Bool {
        target.sourceVerification?.method == "existing_install_thin_client_read_probe"
            && target.complete == true
    }

    private func targetHasThinClientRemoteVerification(_ target: Target) -> Bool {
        target.targetResolution?.method == "thin_client_remote"
            && target.sourceVerification?.method == "existing_install_thin_client_read_probe"
            && nonEmpty(target.remoteMCPURL) != nil
            && target.complete == true
    }

    public func resolvedBrainRepoTargetPath() -> String? {
        guard let state = loadState(),
              let receipt = state.receipt,
              let targets = receipt.targets,
              !targets.isEmpty else {
            return nil
        }
        let key = state.progress?.resolvedTargetKey ?? receipt.primaryTargetKey
        guard let key,
              let target = targets[key],
              let vaultPath = standardizedExistingDirectoryPath(target.vaultPath) else {
            return nil
        }
        return vaultPath
    }

    private func completedSectionHasRole(
        _ role: String,
        title completedTitle: String,
        in state: State
    ) -> Bool {
        guard let sectionRoles = state.sectionRoles, !sectionRoles.isEmpty else {
            return false
        }
        let manifestSection = matchingManifestSection(title: completedTitle, in: state)
        var candidateKeys = Set<String>()
        if let hash = nonEmpty(manifestSection?.hash) {
            candidateKeys.insert("hash:\(hash)")
        }
        candidateKeys.insert("title:\(Self.normalizedSectionTitle(completedTitle))")
        if let manifestTitle = nonEmpty(manifestSection?.title) {
            candidateKeys.insert("title:\(Self.normalizedSectionTitle(manifestTitle))")
        }
        if candidateKeys.contains(where: { sectionRoles[$0]?.role == role }) {
            return true
        }

        let completedNormalizedTitle = Self.normalizedSectionTitle(completedTitle)
        let manifestNormalizedTitle = manifestSection.map { Self.normalizedSectionTitle($0.title) }
        return sectionRoles.values.contains { record in
            guard record.role == role else { return false }
            if let sectionHash = nonEmpty(record.sectionHash),
               sectionHash == nonEmpty(manifestSection?.hash) {
                return true
            }
            guard let recordedSection = nonEmpty(record.section) else {
                return false
            }
            let recordedNormalizedTitle = Self.normalizedSectionTitle(recordedSection)
            return recordedNormalizedTitle == completedNormalizedTitle
                || recordedNormalizedTitle == manifestNormalizedTitle
        }
    }

    private func matchingManifestSection(title: String, in state: State) -> DocsSection? {
        guard let sections = state.docsManifest?.installForAgentsSections else {
            return nil
        }
        if let exact = sections.first(where: { $0.title == title }) {
            return exact
        }
        let normalized = Self.normalizedSectionTitle(title)
        return sections.first { Self.normalizedSectionTitle($0.title) == normalized }
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

    private static func isRecurringJobsSectionTitle(_ title: String) -> Bool {
        let normalized = normalizedSectionTitle(title)
        return normalized.contains("recurring job")
            || normalized.contains("recurring jobs")
            || normalized.contains("scheduler")
            || normalized.contains("autopilot")
            || normalized.contains("background sync")
            || normalized.contains("background job")
            || normalized.contains("background service")
            || normalized.contains("daemon")
    }

    private static func isInstallSectionTitle(_ title: String) -> Bool {
        let normalized = normalizedSectionTitle(title)
        return normalized.contains("step 1")
            && normalized.contains("install")
            && (normalized.contains("gbrain") || normalized.contains("cli"))
    }

    private static func isCredentialsSectionTitle(_ title: String) -> Bool {
        let normalized = normalizedSectionTitle(title)
        return normalized.contains("step 2")
            && (normalized.contains("api key") || normalized.contains("credential"))
    }

    private static func isCreateBrainSectionTitle(_ title: String) -> Bool {
        let normalized = normalizedSectionTitle(title)
        return normalized.contains("step 3")
            && (normalized.contains("create the brain") || normalized.contains("initialize brain"))
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
        selectedAgent: MarkdownPillAgent? = nil
    ) -> LaunchContext? {
        guard let helperPath = installHelperScript() else { return nil }
        let selectedVault = standardizedExistingDirectoryPath(selectedVaultPath)
        let launchDirectory = onboardingWorkDirectoryPath()
        let allowTrustedAutomation = true
        let runId = "gbrain-\(UUID().uuidString)"
        var state = loadState() ?? State.empty()
        let previousProgress = state.progress
        let previousMode = previousProgress?.gbrainSetupMode
        let hasExplicitFreshInstallChoice = previousMode == Self.freshInstallMode
            && previousProgress?.freshInstallConfirmedAt != nil
        let existingInstallVerificationMode = !hasExplicitFreshInstallChoice
        let gbrainSetupMode = existingInstallVerificationMode
            ? Self.existingInstallVerificationMode
            : Self.freshInstallMode
        let docsSnapshot = prepareDocsSnapshot(includeInstallForAgentsSections: !existingInstallVerificationMode)
        let previousDocsFingerprint = Self.docsManifestFingerprint(state.docsManifest)
        state.currentRunId = runId
        state.docsCommit = docsSnapshot?.commit ?? state.docsCommit ?? "unavailable"
        state.docsFetchedAt = Self.isoTimestamp()
        state.docsSnapshotPath = docsSnapshot?.path ?? state.docsSnapshotPath
        state.docsManifest = docsSnapshot?.manifest ?? state.docsManifest
        state.selectedAgent = selectedAgent?.rawValue
        let currentDocsFingerprint = Self.docsManifestFingerprint(state.docsManifest)
        let resolvedTargetKey = selectedVault.map(Self.targetKey(for:))
            ?? (existingInstallVerificationMode ? nil : previousProgress?.resolvedTargetKey)
        let canReuseProgress = previousProgress != nil
            && previousProgress?.resolvedTargetKey == resolvedTargetKey
            && previousDocsFingerprint == currentDocsFingerprint
            && !existingInstallVerificationMode
        let completedSections = canReuseProgress ? previousProgress?.completedSections ?? [] : []
        let targetResolution = selectedVault != nil
            ? TargetResolution(
                status: "candidate",
                method: "selected_vault",
                confirmedAt: Self.isoTimestamp()
            )
            : (existingInstallVerificationMode ? nil : previousProgress?.targetResolution) ?? TargetResolution(
                status: "unresolved",
                method: nil,
                confirmedAt: nil
            )
        let nextSection = nextSection(in: state, completedSections: completedSections)
        let waitingForUser = unresolvedInitialStep3Decision(
            selectedVault: selectedVault,
            resolvedTargetKey: resolvedTargetKey,
            nextSection: nextSection,
            completedSections: completedSections,
            previousWaitingForUser: previousProgress?.waitingForUser
        )
        state.progress = Progress(
            launchDirectory: launchDirectory,
            selectedVaultPath: selectedVault,
            resolvedTargetKey: resolvedTargetKey,
            targetResolution: targetResolution,
            embeddingDecision: canReuseProgress ? previousProgress?.embeddingDecision : nil,
            completedSections: completedSections,
            waitingForUser: waitingForUser,
            lastFailure: nil,
            nextSection: existingInstallVerificationMode ? nil : nextSection,
            gbrainSetupMode: gbrainSetupMode,
            freshInstallConfirmedAt: hasExplicitFreshInstallChoice
                ? previousProgress?.freshInstallConfirmedAt
                : nil,
            existingInstallVerification: existingInstallVerificationMode
                && previousProgress?.resolvedTargetKey == resolvedTargetKey
                ? previousProgress?.existingInstallVerification
                : nil
        )
        writeState(state)

        let helperDirectory = helperPath.deletingLastPathComponent().path
        let environmentPrefixParts = [
            "export ZEBRA_GBRAIN_STATE=\(ZebraAgentLaunchCommand.shellQuote(stateURL.path))",
            "export ZEBRA_GBRAIN_HOME=\(ZebraAgentLaunchCommand.shellQuote(homeDirectoryPath))",
            "export ZEBRA_ONBOARDING_LANGUAGE=\(ZebraAgentLaunchCommand.shellQuote(onboardingLanguage.code))",
            "export PATH=\(ZebraAgentLaunchCommand.shellQuote(helperDirectory)):\"$PATH\"",
        ]
        let environmentPrefix = environmentPrefixParts.joined(separator: " && ") + " && "
        return LaunchContext(
            launchDirectory: launchDirectory,
            startupPrompt: bootstrapPrompt(),
            runId: runId,
            shellEnvironmentPrefix: environmentPrefix,
            allowTrustedAutomation: allowTrustedAutomation,
            allowLaunchDirectoryTrust: false,
            existingInstallVerificationMode: existingInstallVerificationMode
        )
    }

    private func bootstrapPrompt() -> String {
        if let state = loadState(),
           state.progress?.gbrainSetupMode == Self.existingInstallVerificationMode {
            return existingInstallBootstrapPrompt(selectedVault: state.progress?.selectedVaultPath)
        }
        var instructions = [
            onboardingLanguage.firstVisibleGBrainSetupInstruction,
            "Do not run tools or read files before printing that line.",
            "After printing it, follow the current section prompt generated by Zebra.",
            "Work only the current INSTALL_FOR_AGENTS.md section. When that section is complete, run the report command shown in the section prompt and continue from the `nextPrompt` printed by that command.",
            "Do not edit gbrain-setup-state.json directly. Zebra-owned helper commands are the only authority allowed to write onboarding completion receipts.",
        ]
        if let selectedVault = loadState()?.progress?.selectedVaultPath {
            instructions.append(
                "Before starting INSTALL_FOR_AGENTS.md Step 1, check whether the selected vault already has a working GBrain by running `zebra-gbrain-onboarding verify-existing-install --target \(ZebraAgentLaunchCommand.shellQuote(selectedVault)) --method selected_vault`. If it returns `complete: true`, stop the GBrain install work. If it fails, run the printed `nextAction.command` before choosing a repair path. The diagnosis output is read-only context: use the installed `gbrain` CLI help/doctor/status/remediation output as the primary authority, use any local GBrain repo docs only as fallback, do not edit `gbrain-setup-state.json` directly, ask the user before changing source bindings, remote topology, credentials, or abandoning recovery for a new home-directory GBrain setup, and rerun `verify-existing-install` after repair."
            )
        }
        return instructions.joined(separator: " ")
    }

    private func existingInstallBootstrapPrompt(selectedVault: String?) -> String {
        var instructions = [
            onboardingLanguage.firstVisibleGBrainSetupInstruction,
            "Do not run tools or read files before printing that line.",
            "This is Zebra GBrain preflight mode. Do not start INSTALL_FOR_AGENTS.md Step 1 and do not create a GBrain setup checklist unless `discover-existing-install-target` returns `kind: fresh_install`, or the user explicitly confirms abandoning existing-install recovery for a new GBrain/brain setup.",
        ]
        if let selectedVault {
            instructions.append(
                "First run `zebra-gbrain-onboarding verify-existing-install --target \(ZebraAgentLaunchCommand.shellQuote(selectedVault)) --method selected_vault`."
            )
        } else {
            instructions.append(
                "No selected local brain repo target is confirmed yet. First run `zebra-gbrain-onboarding discover-existing-install-target`. If it returns `kind: remote_thin_client`, treat the remote MCP URL as a remote-only target, do not ask for a local brain repo path, and run the printed `nextAction.command`. If it returns `kind: local_vault`, run the printed `nextAction.command`. If it returns `kind: fresh_install`, run the printed `nextAction.command` and continue the fresh GBrain setup flow. Only ask the user for a local brain/vault repo path when it returns `kind: unresolved` with `askUserFor: brain_repo_path`."
            )
        }
        instructions.append(contentsOf: [
            "When you run `verify-existing-install`, if it returns `complete: true` with status `verified` or `transient_retry_preserved`, stop new GBrain setup work and summarize the result.",
            "If `verify-existing-install` fails with `diagnosis_needed`, run the printed `nextAction.command` before choosing a repair path.",
            "Treat `failure.reasons` as probe evidence labels, not root-cause taxonomy and not a fixed repair-command mapping.",
            "Use installed `gbrain` CLI output as the primary authority. Use a local GBrain source repo only as docs/tool fallback when needed.",
            "If `discover-existing-install-target` returns `kind: fresh_install`, that is Zebra's decision that no existing install evidence is present. Do not ask the user to confirm a new setup again; run the printed `nextAction.command` and continue the fresh GBrain setup flow.",
            "Only when existing-install recovery is not practical and you ask the user to abandon that recovery, put the new setup option first and label it as installing GBrain in the home directory, for example Korean `홈 디렉토리에 GBrain 설치` or English `Install GBrain in my home directory`. Do not use that fallback confirmation for `kind: fresh_install`. Do not use the phrase `fresh install` in user-facing text.",
            "If the user explicitly chooses that new home-directory GBrain setup, run `zebra-gbrain-onboarding prepare-source-repo --fresh-install`, then follow the returned setup section flow.",
            "Do not edit gbrain-setup-state.json directly. Zebra-owned helper commands are the only authority allowed to write onboarding completion receipts.",
        ])
        return instructions.joined(separator: " ")
    }

    private func prepareDocsSnapshot(includeInstallForAgentsSections: Bool = true) -> DocsSnapshot? {
        if let repoURL = explicitDocsRepoURL() {
            return prepareLocalDocsSnapshot(
                repoURL: repoURL,
                includeInstallForAgentsSections: includeInstallForAgentsSections
            )
        }
        return nil
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

    private func prepareLocalDocsSnapshot(
        repoURL: URL,
        includeInstallForAgentsSections: Bool = true
    ) -> DocsSnapshot? {
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
            installForAgentsSections: includeInstallForAgentsSections
                ? Self.installForAgentsSections(from: installForAgents)
                : []
        )
        return DocsSnapshot(
            commit: commit,
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
            guard isInstallForAgentsChecklistSectionTitle(title) else { return }
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

    private static func isInstallForAgentsChecklistSectionTitle(_ title: String) -> Bool {
        title.range(
            of: #"^Step\s+[1-9](?:\.\d+)?\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func enabledInstallForAgentsSections(_ sections: [DocsSection]) -> [DocsSection] {
        sections
    }

    private func nextSection(in state: State, completedSections: [String]? = nil) -> String {
        let completed = Set(completedSections ?? state.progress?.completedSections ?? [])
        guard let sections = state.docsManifest?.installForAgentsSections,
              !sections.isEmpty else {
            return "Step 1: Install GBrain"
        }
        return Self.enabledInstallForAgentsSections(sections)
            .first { !completed.contains($0.title) }?.title ?? "verify"
    }

    private func unresolvedInitialStep3Decision(
        selectedVault: String?,
        resolvedTargetKey: String?,
        nextSection: String,
        completedSections: [String],
        previousWaitingForUser: PendingUserDecision?
    ) -> PendingUserDecision? {
        guard selectedVault == nil && resolvedTargetKey == nil else { return nil }
        guard Self.isCreateBrainSectionTitle(nextSection),
              completedSections.contains(where: Self.isInstallSectionTitle),
              completedSections.contains(where: Self.isCredentialsSectionTitle) else {
            return nil
        }
        let previousReason = waitingForUserDisplay(previousWaitingForUser)
        if previousReason == "brain_repo_target_resolution" || previousReason == "topology_resolution" {
            return previousWaitingForUser
        }
        return PendingUserDecision(
            section: "Step 3: Create the Brain",
            reason: "topology_resolution",
            note: onboardingLanguage.topologyDecisionNote,
            createdAt: Self.isoTimestamp()
        )
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
                    doctorEffectiveOk: false,
                    verifiedAt: Self.isoTimestamp()
                ),
                target: updatedTarget,
                hasTransientProbeFailure: false
            )
        }

        let doctor = runProcess(executable: executable, arguments: ["doctor", "--json"], cwd: vaultPath, timeout: 20)
        let doctorResult = Self.strictDoctorResult(doctor)
        let doctorOk = doctorResult.ok
        var doctorEffectiveOk = doctorResult.effectiveOk
        let doctorTransientFailure = !doctorOk && Self.isTransientGBrainProbeFailure(doctor)
        if doctorTransientFailure {
            reasons.append(Self.pgliteBusyReason)
        } else if !doctorEffectiveOk && !doctorResult.maintenancePending {
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
        if case .error(let reason) = sourceProbe.status,
           !reasons.contains(reason) {
            reasons.append(reason)
        }

        let hasTransientProbeFailure: Bool
        if case .transientFailure = sourceProbe.status {
            hasTransientProbeFailure = true
        } else {
            hasTransientProbeFailure = doctorTransientFailure
        }
        var warnings: [String] = []
        var syncProbe = ProbeResult(ok: nil, status: "not_run")
        var statsProbe = ProbeResult(ok: nil, status: "not_run")
        var embeddingProbe = ProbeResult(ok: nil, status: "not_run")
        var searchProbe = ProbeResult(ok: nil, status: "not_run")
        if doctorResult.maintenancePending, sourceProbe.status == .verified {
            let probes = installProbeResults(executable: executable, vaultPath: vaultPath)
            syncProbe = probes.sync
            statsProbe = probes.stats
            embeddingProbe = probes.embedding
            searchProbe = probes.search
            for reason in probes.reasons where !reasons.contains(reason) {
                reasons.append(reason)
            }
            doctorEffectiveOk = probes.reasons.isEmpty
            if doctorEffectiveOk {
                warnings.append("maintenance_pending:cycle_freshness")
            }
        }

        let verified = reasons.isEmpty && doctorEffectiveOk && sourceProbe.status == .verified
        let complete = verified
        let now = Self.isoTimestamp()
        updatedTarget.gbrainExecutablePath = executable
        updatedTarget.doctorStatus = ProbeResult(
            ok: doctorOk,
            status: doctorOk ? "ok" : "failed",
            failedChecks: doctorResult.failedChecks
        )
        updatedTarget.sourcesCurrentResult = SourceProbeResult(
            ok: sourceProbe.status == .verified,
            sourceId: sourceProbe.currentSourceId ?? sourceId,
            localPath: sourceProbe.listedLocalPath,
            status: Self.sourceProbeStatusLabel(sourceProbe.status),
            reason: Self.sourceProbeStatusReason(sourceProbe.status)
        )
        updatedTarget.syncProbeResult = syncProbe
        updatedTarget.statsProbeResult = statsProbe
        updatedTarget.embeddingProbeResult = embeddingProbe
        if sourceProbe.status == .verified {
            updatedTarget.sourceVerification = SourceVerification(
                sourceId: sourceId,
                targetPath: vaultPath,
                verifiedAt: now,
                method: "sources_current_and_list",
                gbrainExecutablePath: executable,
                gbrainVersion: nil
            )
        }
        updatedTarget.searchProbeResult = doctorResult.maintenancePending ? searchProbe : ProbeResult(ok: complete, status: complete ? "not_run" : "blocked")
        updatedTarget.verifiedAt = now
        updatedTarget.complete = complete
        updatedTarget.status = complete
            ? (doctorResult.maintenancePending ? "verified_with_maintenance_pending" : "verified")
            : "failed"
        updatedTarget.warnings = warnings
        updatedTarget.reasons = reasons

        return LiveVerificationResult(
            complete: complete,
            reasons: reasons,
            globalReadiness: GlobalReadiness(
                complete: doctorEffectiveOk,
                gbrainExecutablePath: executable,
                wrapperPath: target.wrapperPath,
                doctorOk: doctorOk,
                doctorEffectiveOk: doctorEffectiveOk,
                verifiedAt: now
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
            if Self.sourceMissingProbeFailure(current) {
                return (.mismatch, nil, nil)
            }
            return (.error(reason: Self.gbrainProbeFailureReason(current)), nil, nil)
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
            if Self.sourceMissingProbeFailure(list) {
                return (.mismatch, currentSourceId, nil)
            }
            return (.error(reason: Self.gbrainProbeFailureReason(list)), currentSourceId, nil)
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

    private static func gbrainProbeFailureReason(_ result: ProcessRunResult) -> String {
        if let transientReason = transientGBrainProbeReason(result) {
            return transientReason
        }
        let output = "\(result.stderr)\n\(result.stdout)".lowercased()
        if output.contains("pglite failed to initialize its wasm runtime")
            || (output.contains("aborted()") && output.contains("pglite")) {
            return pgliteWasmRuntimeErrorReason
        }
        return sourceProbeRuntimeErrorReason
    }

    private static func sourceMissingProbeFailure(_ result: ProcessRunResult) -> Bool {
        let output = "\(result.stderr)\n\(result.stdout)".lowercased()
        return output.contains("source_not_registered")
            || output.contains("source not registered")
            || output.contains("source not found")
            || output.contains("no current source")
            || output.contains("no source")
    }

    private static func sourceProbeStatusLabel(_ status: SourceProbeStatus) -> String {
        switch status {
        case .verified:
            return "verified"
        case .mismatch:
            return "mismatch"
        case .transientFailure:
            return "transient"
        case .error:
            return "error"
        }
    }

    private static func sourceProbeStatusReason(_ status: SourceProbeStatus) -> String? {
        switch status {
        case .verified, .mismatch:
            return nil
        case .transientFailure(let reason), .error(let reason):
            return reason
        }
    }

    private func sourceVerificationMatches(
        _ verification: SourceVerification?,
        vaultPath: String,
        sourceId: String
    ) -> Bool {
        guard let method = verification?.method,
              [
                "sources_current_and_list",
                "existing_install_sources_current_and_list",
                "existing_install_remote_sources_list",
              ].contains(method),
              verification?.sourceId == sourceId,
              let targetPath = verification?.targetPath else {
            return false
        }
        return Self.standardizedPath(targetPath) == vaultPath
    }

    private static func containsOnlyTransientProbeReasons(_ reasons: [String]) -> Bool {
        reasons.allSatisfy { $0 == pgliteBusyReason }
    }

    private static func strictDoctorResult(_ result: ProcessRunResult) -> DoctorResult {
        if result.exitCode == 0, !result.timedOut {
            return DoctorResult(ok: true, failedChecks: [], effectiveOk: true, maintenancePending: false)
        }
        let failedChecks = doctorFailedCheckNames(from: result.stdout)
        let maintenancePending = failedChecks == ["cycle_freshness"]
        return DoctorResult(
            ok: false,
            failedChecks: failedChecks,
            effectiveOk: false,
            maintenancePending: maintenancePending
        )
    }

    private static func doctorFailedCheckNames(from stdout: String) -> [String] {
        guard let data = stdout.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let checks = payload["checks"] as? [[String: Any]]
        else {
            return []
        }
        return checks.compactMap { check -> String? in
            let status = (check["status"] as? String ?? "").lowercased()
            guard ["fail", "failed", "error"].contains(status) else { return nil }
            return check["name"] as? String ?? "unknown"
        }
    }

    private func installProbeResults(
        executable: String,
        vaultPath: String
    ) -> (sync: ProbeResult, stats: ProbeResult, embedding: ProbeResult, search: ProbeResult, reasons: [String]) {
        var reasons: [String] = []

        let sync = runProcess(
            executable: executable,
            arguments: ["config", "get", "sync.last_run"],
            cwd: vaultPath,
            timeout: 20
        )
        let syncValue = sync.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let syncOk = sync.exitCode == 0 && !sync.timedOut && !syncValue.isEmpty
        if !syncOk {
            reasons.append("sync_not_verified")
        }
        let syncProbe = ProbeResult(ok: syncOk, status: syncOk ? "ok" : "missing_sync_last_run")

        let stats = runProcess(
            executable: executable,
            arguments: ["stats"],
            cwd: vaultPath,
            timeout: 20
        )
        let parsedStats = Self.parseGBrainStats(stats.stdout)
        let statsOk = stats.exitCode == 0 && !stats.timedOut && !parsedStats.isEmpty
        if !statsOk {
            reasons.append("stats_not_verified")
        }
        let statsProbe = ProbeResult(ok: statsOk, status: statsOk ? "ok" : "stats_probe_failed")

        let chunks = parsedStats["chunks"]
        let embedded = parsedStats["embedded"]
        let embeddingOk = statsOk && chunks != nil && embedded != nil && (chunks == 0 || (embedded ?? -1) >= (chunks ?? 0))
        if !embeddingOk {
            reasons.append("embedding_not_verified")
        }
        let embeddingProbe = ProbeResult(ok: embeddingOk, status: embeddingOk ? "ok" : "embedding_backlog")

        guard let sample = Self.syncableMarkdownSample(in: vaultPath) else {
            return (
                syncProbe,
                statsProbe,
                embeddingProbe,
                ProbeResult(ok: true, status: "skipped_no_content"),
                reasons
            )
        }

        let search = runProcess(
            executable: executable,
            arguments: ["search", sample],
            cwd: vaultPath,
            timeout: 30
        )
        let searchOutput = search.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchOk = search.exitCode == 0
            && !search.timedOut
            && !searchOutput.isEmpty
            && searchOutput.lowercased() != "no results."
        if !searchOk {
            reasons.append("search_not_verified")
        }
        return (
            syncProbe,
            statsProbe,
            embeddingProbe,
            ProbeResult(ok: searchOk, status: searchOk ? "ok" : "no_results"),
            reasons
        )
    }

    private static func parseGBrainStats(_ stdout: String) -> [String: Int] {
        var stats: [String: Int] = [:]
        for line in stdout.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let digits = parts[1].filter(\.isNumber)
            guard let value = Int(String(digits)) else { continue }
            stats[key] = value
        }
        return stats
    }

    private static func syncableMarkdownSample(in vaultPath: String) -> String? {
        let excludedNames: Set<String> = ["README.md", "index.md", "schema.md", "log.md"]
        let rootURL = URL(fileURLWithPath: vaultPath, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let fileURL as URL in enumerator {
            let relative = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            let parts = relative.split(separator: "/").map(String.init)
            if parts.contains(".raw") || parts.contains("ops") {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard fileURL.pathExtension == "md",
                  !excludedNames.contains(fileURL.lastPathComponent),
                  let contents = try? String(contentsOf: fileURL, encoding: .utf8)
            else {
                continue
            }
            for line in contents.components(separatedBy: .newlines) {
                let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if text.count >= 12 && !text.hasPrefix("---") {
                    return String(text.prefix(80))
                }
            }
        }
        return nil
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
        existingTarget?.sourceVerification?.verifiedAt = nil
        nextTarget.sourceVerification?.verifiedAt = nil

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
        if let repoLocal = repoLocalGBrainExecutablePath(),
           fileManager.isExecutableFile(atPath: repoLocal) {
            return repoLocal
        }
        return findExecutableOnPATH(named: "gbrain")
    }

    private func repoLocalGBrainExecutablePath() -> String? {
        guard let sourceRepoPath = loadState()?.activeGBrainBinding?.sourceRepoPath else {
            return nil
        }
        return URL(fileURLWithPath: sourceRepoPath, isDirectory: true)
            .appendingPathComponent("node_modules", isDirectory: true)
            .appendingPathComponent(".bin", isDirectory: true)
            .appendingPathComponent("gbrain", isDirectory: false)
            .path
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
        let launchctlWrapperURL = directory.appendingPathComponent("launchctl", isDirectory: false)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.helperScript.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try Self.launchctlWrapperScript.write(to: launchctlWrapperURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launchctlWrapperURL.path)
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
        if let binding = loadState()?.activeGBrainBinding {
            if output["GBRAIN_HOME"] == nil {
                output["GBRAIN_HOME"] = binding.gbrainHomePath
            }
        }
        for (key, value) in gbrainDotenvValues(homePath: output["GBRAIN_HOME"] ?? homeDirectoryPath) {
            if output[key] == nil && !value.isEmpty {
                output[key] = value
            }
        }
        return output
    }

    private func gbrainDotenvValues(homePath: String) -> [String: String] {
        let envPath = URL(fileURLWithPath: homePath, isDirectory: true)
            .appendingPathComponent(".gbrain", isDirectory: true)
            .appendingPathComponent(".env", isDirectory: false)
        guard let text = try? String(contentsOf: envPath, encoding: .utf8) else {
            return [:]
        }
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                continue
            }
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "'" || first == "\""),
               first == last {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values
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

    if [ -n "${ZEBRA_GBRAIN_STATE:-}" ]; then
      STATE="$ZEBRA_GBRAIN_STATE"
    elif [ -n "${HOME:-}" ]; then
      STATE="$HOME/Library/Application Support/zebra/onboarding/gbrain-setup-state.json"
    else
      echo "ZEBRA_GBRAIN_STATE or HOME is required for zebra-gbrain-onboarding" >&2
      exit 1
    fi
    COMMAND="${1:-}"
    if [ -n "$COMMAND" ]; then
      shift
    fi
    export ZEBRA_GBRAIN_HELPER_PATH="$0"

    PYTHON_BIN="$(command -v python3 || true)"
    if [ -z "$PYTHON_BIN" ]; then
      echo "python3 is required for zebra-gbrain-onboarding" >&2
      exit 1
    fi

    zebra_has_path_arg() {
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --path|--path=*)
            return 0
            ;;
        esac
        shift
      done
      return 1
    }

    if [ "$COMMAND" = "prepare-source-repo" ] && [ -z "${ZEBRA_GBRAIN_SOURCE_REPO:-}" ] && ! zebra_has_path_arg "$@"; then
      LANGUAGE_CODE="$(printf '%s' "${ZEBRA_ONBOARDING_LANGUAGE:-en}" | tr '[:upper:]' '[:lower:]')"
      case "$LANGUAGE_CODE" in
        ko|ko-*)
          PROMPT_UNAVAILABLE="GBrain source repo path를 입력할 수 있는 terminal stdin이 없습니다."
          NEED_SOURCE="Zebra가 Step 3을 실행하기 전에 local GBrain source repo가 필요합니다."
          HOME_MISSING="HOME을 확인할 수 없어 ~/gbrain 추천 경로를 만들 수 없습니다. custom path를 입력하세요."
          VALID_HOME_1="valid GBrain source repo를 찾았습니다:"
          VALID_HOME_2="이 repo를 Step 3 source repo로 사용할까요?"
          MISSING_HOME_1="valid GBrain source repo가 없습니다:"
          MISSING_HOME_2="이 경로에 GBrain repo를 clone할까요?"
          INVALID_REPO_SUFFIX="는 GBrain source repo가 아닙니다."
          INVALID_EXISTING_NOTE="이 경로는 이미 존재하므로 Zebra가 자동으로 삭제하거나 덮어쓰지 않습니다."
          ACTION_PROMPT="작업을 선택하세요"
          OPTION_USE_REPO="이 repo를 사용합니다."
          OPTION_CLONE_RECOMMENDED="이 경로에 clone 합니다."
          OPTION_RETRY_SAME_PATH="이 path를 비우거나 백업한 뒤 같은 path를 재확인합니다"
          OPTION_OTHER_PATH="다른 path를 선택합니다."
          OPTION_SUBDIR_CLONE_PREFIX="이 하위 경로에 clone 합니다: "
          OPTION_SUBDIR_CLONE_SUFFIX=""
          OPTION_CUSTOM_RETRY="이 path를 비우거나 백업한 뒤 같은 path를 재확인합니다"
          OPTION_CUSTOM_OTHER="다른 path를 선택합니다."
          OPTION_ABORT="중단합니다."
          MENU_HINT="위/아래 방향키 또는 j/k로 이동하고 Enter로 선택하세요. q로 중단합니다."
          FALLBACK_CHOICE_PROMPT="선택 번호: "
          CUSTOM_REQUIRED="다른 GBrain source repo path가 필요합니다. 절대 경로를 입력하세요. 예: /path/to/gbrain-source 또는 ~/gbrain-source"
          CUSTOM_PROMPT="GBrain source repo custom path: "
          CUSTOM_PATH_FORMAT_ERROR="custom path는 / 또는 ~로 시작해야 합니다. 예: /path/to/gbrain-source 또는 ~/gbrain-source"
          INVALID_SUBDIR="선택한 하위 디렉토리도 사용할 수 없습니다:"
          UNAVAILABLE_MESSAGE="GBrain source repo path를 입력할 수 있는 terminal stdin이 없습니다."
          EMPTY_CUSTOM_PATH="custom path가 비어 있습니다."
          ABORTED_MESSAGE="GBrain source repo 준비를 중단했습니다."
          USING_SOURCE_PREFIX="GBrain source repo를 사용합니다: "
          PREPARING_SOURCE_PREFIX="GBrain source repo를 준비합니다: "
          RECHECKING_SOURCE_PREFIX="GBrain source repo path를 다시 확인합니다: "
          WAITING_CUSTOM_MESSAGE="custom GBrain source repo path 입력을 기다립니다..."
          ;;
        *)
          PROMPT_UNAVAILABLE="No terminal stdin is available for the GBrain source repo path prompt."
          NEED_SOURCE="Zebra needs the local GBrain source repo before Step 3 can run."
          HOME_MISSING="HOME is unavailable, so Zebra cannot recommend ~/gbrain. Enter a custom path."
          VALID_HOME_1="Found a valid GBrain source repo at:"
          VALID_HOME_2="Use this repo for Step 3?"
          MISSING_HOME_1="No valid GBrain source repo was found at:"
          MISSING_HOME_2="Clone the GBrain repo into this path?"
          INVALID_REPO_SUFFIX=" is not a GBrain source repo."
          INVALID_EXISTING_NOTE="This path already exists, so Zebra will not delete or overwrite it automatically."
          ACTION_PROMPT="Choose an action"
          OPTION_USE_REPO="Use this repo"
          OPTION_CLONE_RECOMMENDED="Clone into this path"
          OPTION_RETRY_SAME_PATH="Retry this same path after you clear or back it up"
          OPTION_OTHER_PATH="Choose another path"
          OPTION_SUBDIR_CLONE_PREFIX="Clone into "
          OPTION_SUBDIR_CLONE_SUFFIX=""
          OPTION_CUSTOM_RETRY="Retry this same path after you clear or back it up"
          OPTION_CUSTOM_OTHER="Choose another path"
          OPTION_ABORT="Abort"
          MENU_HINT="Use Up/Down or j/k, then Enter. Press q to abort."
          FALLBACK_CHOICE_PROMPT="Selection: "
          CUSTOM_REQUIRED="A different GBrain source repo path is required. Enter an absolute path, for example /path/to/gbrain-source or ~/gbrain-source."
          CUSTOM_PROMPT="Custom GBrain source repo path: "
          CUSTOM_PATH_FORMAT_ERROR="Custom path must start with / or ~, for example /path/to/gbrain-source or ~/gbrain-source."
          INVALID_SUBDIR="The selected subdirectory is also unavailable:"
          UNAVAILABLE_MESSAGE="No terminal stdin is available for the GBrain source repo path prompt."
          EMPTY_CUSTOM_PATH="Custom path is empty."
          ABORTED_MESSAGE="GBrain source repo preparation was aborted."
          USING_SOURCE_PREFIX="Using GBrain source repo: "
          PREPARING_SOURCE_PREFIX="Preparing GBrain source repo at: "
          RECHECKING_SOURCE_PREFIX="Rechecking GBrain source repo path: "
          WAITING_CUSTOM_MESSAGE="Waiting for a custom GBrain source repo path..."
          ;;
      esac
      if [ ! -t 0 ]; then
        echo "$UNAVAILABLE_MESSAGE" >&2
        exit 1
      fi

      zebra_expand_path() {
        "$PYTHON_BIN" -c 'import os, sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$1"
      }

      zebra_trim_input() {
        "$PYTHON_BIN" -c 'import sys; print(sys.argv[1].strip())' "$1"
      }

      zebra_custom_path_has_valid_format() {
        case "$1" in
          /*)
            return 0
            ;;
          "~"|"~/"*)
            return 0
            ;;
        esac
        return 1
      }

      zebra_classify_source_repo() {
        CHECK_PATH="$(zebra_expand_path "$1")"
        if [ ! -e "$CHECK_PATH" ]; then
          echo "missing"
          return
        fi
        if [ -d "$CHECK_PATH" ] && [ -z "$(find "$CHECK_PATH" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
          echo "empty"
          return
        fi
        if [ -d "$CHECK_PATH" ] && [ -f "$CHECK_PATH/package.json" ] && [ -f "$CHECK_PATH/INSTALL_FOR_AGENTS.md" ] && [ -d "$CHECK_PATH/skills" ]; then
          echo "valid"
          return
        fi
        echo "occupied_invalid"
      }

            zebra_read_reply() {
              "$PYTHON_BIN" -c 'import sys
    sys.stderr.write(sys.argv[1])
    sys.stderr.flush()
    try:
        with open("/dev/tty", "r", encoding="utf-8", errors="replace") as tty:
            value = tty.readline()
    except (OSError, KeyboardInterrupt, UnicodeDecodeError):
        sys.exit(1)
    if value == "":
        sys.exit(1)
    value = value.rstrip("\\r\\n")
    print(value)
    ' "$1" || {
          echo "$UNAVAILABLE_MESSAGE" >&2
          exit 1
              }
            }

            zebra_select_menu() {
              MENU_OUTPUT="$("$PYTHON_BIN" - "$MENU_HINT" "$FALLBACK_CHOICE_PROMPT" "$@" <<'PY_MENU'
    import os
    import select
    import sys
    import termios

    hint = sys.argv[1]
    fallback_prompt = sys.argv[2]
    prompt = sys.argv[3]
    options = sys.argv[4:]

    if not options:
        sys.exit(1)

    try:
        tty_fd = os.open("/dev/tty", os.O_RDONLY)
    except OSError:
        sys.exit(1)
    tty_file = os.fdopen(os.dup(tty_fd), "r", encoding="utf-8", errors="replace", buffering=1)

    def print_fallback():
        print("", file=sys.stderr)
        print(prompt, file=sys.stderr)
        for offset, label in enumerate(options, start=1):
            print(f"  {offset}. {label}", file=sys.stderr)

    def fallback():
        print_fallback()
        while True:
            try:
                sys.stderr.write(fallback_prompt)
                sys.stderr.flush()
                reply = tty_file.readline()
            except (KeyboardInterrupt, UnicodeDecodeError):
                sys.exit(1)
            if reply == "":
                sys.exit(1)
            reply = reply.strip().lower()
            if reply in {"q", "quit", "abort"}:
                print("abort")
                return
            if reply.isdigit():
                index = int(reply)
                if 1 <= index <= len(options):
                    print(index)
                    return
            print(f"Enter a number from 1 to {len(options)}, or q to abort.", file=sys.stderr)

    if os.environ.get("TERM", "").lower() == "dumb":
        fallback()
        sys.exit(0)

    stdin_fd = tty_fd
    if not os.isatty(stdin_fd):
        sys.exit(1)

    selected = 0
    line_count = len(options) + 4

    def render(first=False):
        if not first:
            sys.stderr.write(f"\\x1b[{line_count}F")
        sys.stderr.write("\\x1b[J")
        sys.stderr.write("\\n")
        sys.stderr.write(prompt + "\\n")
        sys.stderr.write(hint + "\\n\\n")
        for index, label in enumerate(options):
            marker = "> " if index == selected else "  "
            sys.stderr.write(f"{marker}{label}\\n")
        sys.stderr.flush()

    try:
        old_settings = termios.tcgetattr(stdin_fd)
    except termios.error:
        fallback()
        sys.exit(0)

    try:
        new_settings = old_settings[:]
        new_settings[3] = new_settings[3] & ~(termios.ECHO | termios.ICANON)
        new_settings[6][termios.VMIN] = 1
        new_settings[6][termios.VTIME] = 0
        termios.tcsetattr(stdin_fd, termios.TCSADRAIN, new_settings)
        sys.stderr.write("\\x1b[?25l")
        sys.stderr.flush()
        render(first=True)
        while True:
            ch = os.read(stdin_fd, 1).decode("utf-8", errors="ignore")
            if ch in {"\\r", "\\n"}:
                sys.stderr.write("\\n")
                sys.stderr.flush()
                print(selected + 1)
                break
            if ch in {"q", "Q"}:
                sys.stderr.write("\\n")
                sys.stderr.flush()
                print("abort")
                break
            if ch == "\\x03":
                raise KeyboardInterrupt
            if ch == "\\x1b":
                sequence = ""
                ready, _, _ = select.select([stdin_fd], [], [], 0.02)
                while ready and len(sequence) < 2:
                    sequence += os.read(stdin_fd, 1).decode("utf-8", errors="ignore")
                    ready, _, _ = select.select([stdin_fd], [], [], 0.02)
                if sequence == "[A":
                    selected = (selected - 1) % len(options)
                    render()
                    continue
                if sequence == "[B":
                    selected = (selected + 1) % len(options)
                    render()
                    continue
                sys.stderr.write("\\n")
                sys.stderr.flush()
                print("abort")
                break
            if ch in {"k", "K"}:
                selected = (selected - 1) % len(options)
                render()
                continue
            if ch in {"j", "J"}:
                selected = (selected + 1) % len(options)
                render()
                continue
            if ch.isdigit():
                index = int(ch)
                if 1 <= index <= len(options):
                    selected = index - 1
                    render()
                    continue
    finally:
        sys.stderr.write("\\x1b[?25h")
        sys.stderr.flush()
        try:
            termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_settings)
        except Exception:
            pass
    PY_MENU
              )" || {
                echo "$UNAVAILABLE_MESSAGE" >&2
                exit 1
              }
              printf '%s\\n' "$MENU_OUTPUT"
            }

            zebra_menu_or_abort() {
              MENU_SELECTION="$(zebra_select_menu "$@")"
              case "$MENU_SELECTION" in
                abort)
                  zebra_abort
                  ;;
              esac
              LAST_OPTION=""
              for MENU_OPTION in "$@"; do
                LAST_OPTION="$MENU_OPTION"
              done
              if [ "$LAST_OPTION" = "$OPTION_ABORT" ] && [ "$MENU_SELECTION" = "$(($# - 1))" ]; then
                zebra_abort
              fi
              printf '%s\\n' "$MENU_SELECTION"
            }

            zebra_note_using_source() {
              printf '%s%s\\n' "$USING_SOURCE_PREFIX" "$1" >&2
            }

            zebra_note_preparing_source() {
              printf '%s%s\\n' "$PREPARING_SOURCE_PREFIX" "$1" >&2
            }

            zebra_note_rechecking_source() {
              printf '%s%s\\n' "$RECHECKING_SOURCE_PREFIX" "$1" >&2
            }

            zebra_note_waiting_custom_source() {
              printf '%s\\n' "$WAITING_CUSTOM_MESSAGE" >&2
            }

      zebra_record_prepare_aborted() {
        "$PYTHON_BIN" - "$STATE" <<'PY_ABORT' || true
    import json
    import os
    import sys
    from datetime import datetime, timezone

    state_path = sys.argv[1]
    try:
        with open(state_path, "r", encoding="utf-8") as handle:
            state = json.load(handle)
    except Exception:
        state = {"schemaVersion": 1}
    state["schemaVersion"] = 1
    progress = state.setdefault("progress", {})
    progress["lastFailure"] = "source_repo_prepare_aborted"
    progress["updatedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    tmp = state_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
        handle.write("\\n")
    os.replace(tmp, state_path)
    PY_ABORT
      }

      zebra_abort() {
        zebra_record_prepare_aborted
        echo "$ABORTED_MESSAGE" >&2
        exit 1
      }

            zebra_choose_custom_source() {
              while :; do
                CUSTOM_INPUT="$(zebra_trim_input "$(zebra_read_reply "$CUSTOM_PROMPT")")"
          if [ -z "$CUSTOM_INPUT" ]; then
            echo "$EMPTY_CUSTOM_PATH" >&2
            continue
          fi
          case "$(printf '%s' "$CUSTOM_INPUT" | tr '[:upper:]' '[:lower:]')" in
            q|quit|abort)
              zebra_abort
              ;;
          esac
          if ! zebra_custom_path_has_valid_format "$CUSTOM_INPUT"; then
            echo "$CUSTOM_PATH_FORMAT_ERROR" >&2
            continue
          fi
          CUSTOM_PATH="$(zebra_expand_path "$CUSTOM_INPUT")"
                CUSTOM_STATUS="$(zebra_classify_source_repo "$CUSTOM_PATH")"
                case "$CUSTOM_STATUS" in
                  valid)
                    zebra_note_using_source "$CUSTOM_PATH"
                    SELECTED_SOURCE="$CUSTOM_PATH"
                    return
                    ;;
                  missing|empty)
                    zebra_note_preparing_source "$CUSTOM_PATH"
                    SELECTED_SOURCE="$CUSTOM_PATH"
                    return
                    ;;
                  occupied_invalid)
                    while :; do
                      SUBDIR_PATH="$(zebra_expand_path "$CUSTOM_PATH/gbrain")"
                      printf '\\n%s%s\\n%s\\n' \
                        "$CUSTOM_PATH" "$INVALID_REPO_SUFFIX" \
                        "$INVALID_EXISTING_NOTE" >&2
                      CUSTOM_CHOICE="$(zebra_menu_or_abort "$ACTION_PROMPT" \
                        "$OPTION_SUBDIR_CLONE_PREFIX$SUBDIR_PATH$OPTION_SUBDIR_CLONE_SUFFIX" \
                        "$OPTION_CUSTOM_RETRY" \
                        "$OPTION_CUSTOM_OTHER" \
                        "$OPTION_ABORT")"
                      case "$CUSTOM_CHOICE" in
                        1)
                          SUBDIR_STATUS="$(zebra_classify_source_repo "$SUBDIR_PATH")"
                          case "$SUBDIR_STATUS" in
                            missing|empty|valid)
                              zebra_note_preparing_source "$SUBDIR_PATH"
                              SELECTED_SOURCE="$SUBDIR_PATH"
                              return
                              ;;
                      *)
                        printf '%s\\n%s\\n' "$INVALID_SUBDIR" "$SUBDIR_PATH" >&2
                        ;;
                    esac
                          ;;
                        2)
                          zebra_note_rechecking_source "$CUSTOM_PATH"
                          CUSTOM_STATUS="$(zebra_classify_source_repo "$CUSTOM_PATH")"
                          case "$CUSTOM_STATUS" in
                            valid)
                              zebra_note_using_source "$CUSTOM_PATH"
                              SELECTED_SOURCE="$CUSTOM_PATH"
                              return
                              ;;
                            missing|empty)
                              zebra_note_preparing_source "$CUSTOM_PATH"
                              SELECTED_SOURCE="$CUSTOM_PATH"
                              return
                              ;;
                          esac
                          ;;
                        3)
                          zebra_note_waiting_custom_source
                          break
                          ;;
                      esac
                    done
                    ;;
          esac
        done
      }

      zebra_choose_from_home() {
        if [ -n "${ZEBRA_GBRAIN_SOURCE_REPO_DEFAULT:-}" ]; then
          RECOMMENDED_SOURCE="$(zebra_expand_path "$ZEBRA_GBRAIN_SOURCE_REPO_DEFAULT")"
        elif [ -n "${HOME:-}" ]; then
          RECOMMENDED_SOURCE="$(zebra_expand_path "$HOME/gbrain")"
        else
          printf '\\n%s\\n%s\\n' "$NEED_SOURCE" "$HOME_MISSING" >&2
          zebra_choose_custom_source
          return
        fi

        while :; do
          RECOMMENDED_STATUS="$(zebra_classify_source_repo "$RECOMMENDED_SOURCE")"
                case "$RECOMMENDED_STATUS" in
                  valid)
                    printf '\\n%s\\n%s\\n' "$VALID_HOME_1" "$RECOMMENDED_SOURCE" >&2
                    HOME_REPLY="$(zebra_menu_or_abort "$VALID_HOME_2" "$OPTION_USE_REPO" "$OPTION_OTHER_PATH" "$OPTION_ABORT")"
                    case "$HOME_REPLY" in
                      1)
                        zebra_note_using_source "$RECOMMENDED_SOURCE"
                        SELECTED_SOURCE="$RECOMMENDED_SOURCE"
                        return
                        ;;
                      2)
                        zebra_note_waiting_custom_source
                        printf '%s\\n' "$CUSTOM_REQUIRED" >&2
                        zebra_choose_custom_source
                        return
                        ;;
                    esac
                    ;;
                  missing|empty)
                    printf '\\n%s\\n%s\\n' "$MISSING_HOME_1" "$RECOMMENDED_SOURCE" >&2
                    HOME_REPLY="$(zebra_menu_or_abort "$MISSING_HOME_2" "$OPTION_CLONE_RECOMMENDED" "$OPTION_OTHER_PATH" "$OPTION_ABORT")"
                    case "$HOME_REPLY" in
                      1)
                        zebra_note_preparing_source "$RECOMMENDED_SOURCE"
                        SELECTED_SOURCE="$RECOMMENDED_SOURCE"
                        return
                        ;;
                      2)
                        zebra_note_waiting_custom_source
                        printf '%s\\n' "$CUSTOM_REQUIRED" >&2
                        zebra_choose_custom_source
                        return
                        ;;
                    esac
                    ;;
                  occupied_invalid)
                    while :; do
                      printf '\\n%s%s\\n%s\\n' \
                        "$RECOMMENDED_SOURCE" "$INVALID_REPO_SUFFIX" \
                        "$INVALID_EXISTING_NOTE" >&2
                      HOME_CHOICE="$(zebra_menu_or_abort "$ACTION_PROMPT" "$OPTION_RETRY_SAME_PATH" "$OPTION_OTHER_PATH" "$OPTION_ABORT")"
                      case "$HOME_CHOICE" in
                        1)
                          zebra_note_rechecking_source "$RECOMMENDED_SOURCE"
                          RECOMMENDED_STATUS="$(zebra_classify_source_repo "$RECOMMENDED_SOURCE")"
                          case "$RECOMMENDED_STATUS" in
                            valid)
                              zebra_note_using_source "$RECOMMENDED_SOURCE"
                              SELECTED_SOURCE="$RECOMMENDED_SOURCE"
                              return
                              ;;
                            missing|empty)
                              zebra_note_preparing_source "$RECOMMENDED_SOURCE"
                              SELECTED_SOURCE="$RECOMMENDED_SOURCE"
                              return
                              ;;
                          esac
                          ;;
                        2)
                          zebra_note_waiting_custom_source
                          zebra_choose_custom_source
                          return
                          ;;
                      esac
                    done
                    ;;
          esac
        done
      }

      SELECTED_SOURCE=""
      zebra_choose_from_home
      if [ -z "$SELECTED_SOURCE" ]; then
        echo "$UNAVAILABLE_MESSAGE" >&2
        exit 1
      fi
      set -- --path "$SELECTED_SOURCE" "$@"
    fi

    "$PYTHON_BIN" - "$STATE" "$COMMAND" "$@" <<'PY'
    import glob
    import json
    import os
    import re
    import shutil
    import subprocess
    import sys
    import time
    from datetime import datetime, timezone

    state_path = sys.argv[1]
    command = sys.argv[2]
    args = sys.argv[3:]
    allowed_methods = {
        "selected_vault",
        "user_existing_repo",
        "user_created_repo",
        "user_confirmed_home",
        "thin_client_remote",
    }
    allowed_roles = {
        "install",
        "credentials",
        "create_brain",
        "search_mode",
        "import_index",
        "recurring_jobs",
        "verify",
    }
    known_roles = allowed_roles | {"non_role"}
    allowed_search_modes = {"conservative", "balanced", "tokenmax"}
    allowed_embedding_decisions = {"provider_key", "defer_embeddings"}
    embedding_provider_env_names = {
        "zeroentropy": "ZEROENTROPY_API_KEY",
        "openai": "OPENAI_API_KEY",
        "voyage": "VOYAGE_API_KEY",
    }
    allowed_topology_decisions = {"pglite", "postgres", "supabase"}
    allowed_recurring_jobs_decisions = {
        "defer",
        "manual_scheduler",
        "platform_scheduler_install",
        "autopilot_install",
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
                if "=" in key:
                    key, value = key.split("=", 1)
                    out[key] = value
                    i += 1
                elif i + 1 < len(argv) and not argv[i + 1].startswith("--"):
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

    def gbrain_home_directory():
        return os.path.abspath(os.path.expanduser(os.environ.get("ZEBRA_GBRAIN_HOME") or "~"))

    def default_source_repo_path():
        explicit = os.environ.get("ZEBRA_GBRAIN_SOURCE_REPO_DEFAULT")
        if explicit:
            return os.path.abspath(os.path.expanduser(explicit))
        return os.path.join(gbrain_home_directory(), "gbrain")

    def is_recommended_source_repo_path(path):
        return os.path.realpath(os.path.abspath(os.path.expanduser(path))) == os.path.realpath(default_source_repo_path())

    def source_remote():
        return os.environ.get("ZEBRA_GBRAIN_SOURCE_REMOTE") or "https://github.com/garrytan/gbrain.git"

    def is_empty_directory(path):
        try:
            return os.path.isdir(path) and len(os.listdir(path)) == 0
        except Exception:
            return False

    def is_valid_gbrain_source_repo(path):
        return (
            os.path.isdir(path)
            and os.path.isfile(os.path.join(path, "package.json"))
            and os.path.isfile(os.path.join(path, "INSTALL_FOR_AGENTS.md"))
            and os.path.isdir(os.path.join(path, "skills"))
        )

    def classify_source_repo(path):
        if not os.path.exists(path):
            return "missing"
        if is_empty_directory(path):
            return "empty"
        if is_valid_gbrain_source_repo(path):
            return "valid"
        return "occupied_invalid"

    def existing_active_source_repo_path():
        binding = (load_state().get("activeGBrainBinding") or {})
        path = binding.get("sourceRepoPath")
        if path and is_valid_gbrain_source_repo(os.path.abspath(os.path.expanduser(path))):
            return os.path.abspath(os.path.expanduser(path))
        return None

    def selected_source_repo_path(flags):
        explicit = flags.get("path") or os.environ.get("ZEBRA_GBRAIN_SOURCE_REPO")
        if explicit:
            return os.path.abspath(os.path.expanduser(explicit))
        raise RuntimeError("source_repo_path_missing")

    def clone_source_repo(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        result = subprocess.run(
            ["git", "clone", "--progress", source_remote(), path],
            text=True,
            timeout=1200,
        )
        if result.returncode != 0:
            raise RuntimeError("gbrain_source_repo_clone_failed")

    def docs_paths():
        return [
            "INSTALL_FOR_AGENTS.md",
            "README.md",
            "AGENTS.md",
            "docs/GBRAIN_VERIFY.md",
            "skills/setup/SKILL.md",
        ]

    def git_commit(path):
        try:
            result = subprocess.run(
                ["git", "-C", path, "rev-parse", "HEAD"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
        except Exception:
            return "local"
        if result.returncode != 0:
            return "local"
        return (result.stdout or "").strip() or "local"

    def install_for_agents_sections(markdown):
        sections = []
        current_title = None
        current_lines = []

        def finish():
            if current_title is None:
                return
            if not re.match(r"^Step\\s+[1-9](?:\\.\\d+)?\\b", current_title, re.IGNORECASE):
                return
            body = "\\n".join(current_lines)
            sections.append({"title": current_title, "hash": stable_hash(body)})

        for line in markdown.splitlines():
            if line.startswith("## "):
                finish()
                current_title = line[3:].strip()
                current_lines = [line]
            elif current_title is not None:
                current_lines.append(line)
        finish()
        return sections

    def docs_manifest_fingerprint(manifest):
        if not manifest:
            return None
        files = "|".join(sorted(
            f"{entry.get('path') or ''}={entry.get('hash') or ''}"
            for entry in manifest.get("files") or []
        ))
        sections = "|".join(
            f"{entry.get('title') or ''}={entry.get('hash') or ''}"
            for entry in manifest.get("installForAgentsSections") or []
        )
        return stable_hash(f"{manifest.get('sourceRef') or ''}|{files}|{sections}")

    def first_install_section_title(manifest):
        sections = manifest.get("installForAgentsSections") or []
        if sections:
            return sections[0].get("title") or "Step 1: Install GBrain"
        return "Step 1: Install GBrain"

    def reset_progress_for_docs_change(state, manifest, source_repo_path):
        progress = state.setdefault("progress", {})
        progress["launchDirectory"] = source_repo_path
        progress["completedSections"] = []
        progress["nextSection"] = first_install_section_title(manifest)
        progress["updatedAt"] = now()
        progress.pop("waitingForUser", None)
        progress.pop("lastFailure", None)
        state["sectionRoles"] = {}

    def existing_install_verification_mode(state):
        return ((state.get("progress") or {}).get("gbrainSetupMode") == "existing_install_verification")

    def write_local_docs_snapshot(state, source_repo_path, include_install_sections=True):
        previous_fingerprint = docs_manifest_fingerprint(state.get("docsManifest"))
        commit = git_commit(source_repo_path)
        snapshot_dir = os.path.join(os.path.dirname(state_path), "gbrain-docs", commit)
        files = []
        install_for_agents = ""
        for relative_path in docs_paths():
            src = os.path.join(source_repo_path, relative_path)
            if not os.path.isfile(src):
                continue
            dest = os.path.join(snapshot_dir, relative_path)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copy2(src, dest)
            try:
                with open(src, "r", encoding="utf-8") as handle:
                    content = handle.read()
            except Exception:
                content = ""
            files.append({"path": relative_path, "hash": stable_hash(content)})
            if relative_path == "INSTALL_FOR_AGENTS.md":
                install_for_agents = content
        if not files:
            return None
        manifest = {
            "generatedAt": now(),
            "sourceRepoPath": source_repo_path,
            "sourceKind": "local",
            "sourceRef": commit,
            "files": files,
            "installForAgentsSections": install_for_agents_sections(install_for_agents) if include_install_sections else [],
        }
        state["docsCommit"] = commit
        state["docsFetchedAt"] = now()
        state["docsSnapshotPath"] = snapshot_dir
        state["docsManifest"] = manifest
        if include_install_sections and docs_manifest_fingerprint(manifest) != previous_fingerprint:
            reset_progress_for_docs_change(state, manifest, source_repo_path)
        return {"commit": commit, "path": snapshot_dir, "manifest": manifest}

    def persist_active_binding(path, status, include_install_sections=True):
        state = load_state()
        binding = {
            "sourceRepoPath": path,
            "sourceRepoStatus": status,
            "gbrainHomePath": gbrain_home_directory(),
            "sourceRepoIsRecommended": is_recommended_source_repo_path(path),
            "confirmedAt": now(),
        }
        state["schemaVersion"] = 1
        state["activeGBrainBinding"] = binding
        if include_install_sections:
            progress = state.setdefault("progress", {})
            progress["gbrainSetupMode"] = "fresh_install"
            progress["freshInstallConfirmedAt"] = now()
        write_local_docs_snapshot(state, path, include_install_sections=include_install_sections)
        save_state(state)
        return binding

    def prepare_source_repo():
        flags = parse_flags(args)
        state = load_state()
        fresh_install_requested = bool(flags.get("fresh_install"))
        include_install_sections = fresh_install_requested or not existing_install_verification_mode(state)
        path = selected_source_repo_path(flags)
        status = classify_source_repo(path)
        if status in {"missing", "empty"}:
            clone_source_repo(path)
            prepared_status = "cloned"
        elif status == "valid":
            prepared_status = "reused"
        else:
            raise RuntimeError("gbrain_source_repo_occupied_invalid")
        if not is_valid_gbrain_source_repo(path):
            raise RuntimeError("gbrain_source_repo_invalid")
        binding = persist_active_binding(
            os.path.abspath(path),
            prepared_status,
            include_install_sections=include_install_sections,
        )
        print(json.dumps({
            "ok": True,
            "activeGBrainBinding": binding,
            "freshInstallSectionsPrepared": include_install_sections,
        }, sort_keys=True))

    def active_source_repo_path():
        path = existing_active_source_repo_path()
        if not path:
            print("active GBrain source repo binding is missing or invalid", file=sys.stderr)
            sys.exit(1)
        print(path)

    def shell_quote(value):
        return "'" + str(value).replace("'", "'\\''") + "'"

    def helper_directory():
        helper_path = os.environ.get("ZEBRA_GBRAIN_HELPER_PATH")
        if helper_path:
            return os.path.dirname(os.path.abspath(helper_path))
        return os.path.dirname(state_path)

    def gbrain_wrapper_path():
        return os.path.join(helper_directory(), "gbrain")

    def path_gbrain_executable():
        wrapper = os.path.realpath(gbrain_wrapper_path())
        for directory in os.environ.get("PATH", "").split(os.pathsep):
            candidate = os.path.join(directory or ".", "gbrain")
            if os.access(candidate, os.X_OK) and os.path.realpath(candidate) != wrapper:
                return candidate
        return None

    def recommended_source_repo_active(state):
        binding = state.get("activeGBrainBinding") or {}
        source_repo = binding.get("sourceRepoPath")
        return bool(binding.get("sourceRepoIsRecommended")) or (
            source_repo and is_recommended_source_repo_path(source_repo)
        )

    def source_repo_local_gbrain_paths(state):
        binding = state.get("activeGBrainBinding") or {}
        source_repo = binding.get("sourceRepoPath")
        if not source_repo:
            return set()
        source_repo = os.path.abspath(os.path.expanduser(source_repo))
        return {
            os.path.abspath(os.path.join(source_repo, "node_modules", ".bin", "gbrain")),
            os.path.abspath(os.path.join(source_repo, "bin", "gbrain")),
        }

    def global_gbrain_executable(state):
        wrapper = os.path.realpath(gbrain_wrapper_path())
        source_local = source_repo_local_gbrain_paths(state)
        for directory in os.environ.get("PATH", "").split(os.pathsep):
            candidate = os.path.abspath(os.path.join(directory or ".", "gbrain"))
            if candidate in source_local:
                continue
            if os.access(candidate, os.X_OK) and os.path.realpath(candidate) != wrapper:
                return candidate
        return None

    def active_source_env():
        state = load_state()
        binding = state.get("activeGBrainBinding") or {}
        path = existing_active_source_repo_path()
        if not path:
            print("active GBrain source repo binding is missing or invalid", file=sys.stderr)
            sys.exit(1)
        print(f"export ZEBRA_GBRAIN_SOURCE_REPO={shell_quote(path)}")
        print(f"export ZEBRA_GBRAIN_SOURCE_REPO_IS_RECOMMENDED={shell_quote('1' if is_recommended_source_repo_path(path) else '0')}")
        print("export PATH=" + shell_quote(helper_directory()) + ':"$PATH"')
        print('if [ -z "${GBRAIN_DATABASE_URL:-}" ] && [ -n "${DATABASE_URL:-}" ]; then export GBRAIN_DATABASE_URL="$DATABASE_URL"; fi')
        print(f'if [ -z "${{GBRAIN_DATABASE_URL:-}}" ]; then export GBRAIN_HOME={shell_quote(binding.get("gbrainHomePath") or gbrain_home_directory())}; fi')

    def docs_prompt_context(state):
        snapshot_path = state.get("docsSnapshotPath")
        manifest = state.get("docsManifest") or {}
        files = manifest.get("files") or []
        if not snapshot_path or not files:
            return "GBrain docs snapshot:\\npending. Read INSTALL_FOR_AGENTS.md from activeGBrainBinding.sourceRepoPath before making installation decisions."
        file_lines = "\\n".join(
            f"- {entry.get('path') or 'unknown'} [hash: {entry.get('hash') or 'unknown'}]"
            for entry in files
        )
        return f"GBrain docs snapshot:\\npath: {snapshot_path}\\ncommit: {state.get('docsCommit') or 'unknown'}\\nfiles:\\n{file_lines or '- none'}"

    def section_prompt_context(state):
        sections = ((state.get("docsManifest") or {}).get("installForAgentsSections") or [])
        if not sections:
            return "INSTALL_FOR_AGENTS.md section manifest:\\nunavailable. Read local INSTALL_FOR_AGENTS.md from activeGBrainBinding.sourceRepoPath."
        lines = "\\n".join(
            f"- {entry.get('title') or 'unknown'} [hash: {entry.get('hash') or 'unknown'}]"
            for entry in sections
        )
        return f"INSTALL_FOR_AGENTS.md `##` section manifest:\\n{lines}"

    def prompt_file_safe_name(value):
        safe = "".join(
            character if character.isalnum() or character in "-_" else "-"
            for character in str(value or "section")
        ).strip("-_")
        return safe[:96] or "section"

    def next_prompt_directory(state):
        run_id = state.get("currentRunId") or "gbrain-setup"
        return os.path.join(
            os.path.dirname(state_path),
            "gbrain-step-prompts",
            prompt_file_safe_name(run_id),
        )

    def write_next_prompt_file(state, section_title, prompt):
        directory = next_prompt_directory(state)
        os.makedirs(directory, exist_ok=True)
        safe = prompt_file_safe_name(section_title)
        path = os.path.join(directory, safe + ".md")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(prompt.rstrip() + "\\n")
        os.chmod(path, 0o600)
        return path

    def manifest_install_sections(state):
        manifest = state.get("docsManifest") or {}
        sections = manifest.get("installForAgentsSections") or []
        bodies = snapshot_section_bodies(state)
        out = []
        for index, section in enumerate(sections):
            title = section.get("title") or ""
            if not title:
                continue
            body = bodies.get(title)
            if body is None:
                normalized = normalize_title(title)
                for candidate_title, candidate_body in bodies.items():
                    if normalize_title(candidate_title) == normalized:
                        body = candidate_body
                        break
            out.append({
                "title": title,
                "hash": section.get("hash"),
                "body": body or "",
                "orderIndex": index,
            })
        return out

    def next_section_title(state):
        progress = state.get("progress") or {}
        completed = set(progress.get("completedSections") or [])
        completed_normalized = {normalize_title(title) for title in completed}
        for section in manifest_install_sections(state):
            title = section.get("title") or ""
            if title in completed or normalize_title(title) in completed_normalized:
                continue
            return title
        return "complete" if verify_section_completed(state) else "verify"

    def verify_section_completed(state):
        progress = state.get("progress") or {}
        completed = progress.get("completedSections") or []
        for title in completed:
            normalized = normalize_title(title)
            if normalized == "verify":
                return True
            if "step 9" in normalized and "verify" in normalized:
                return True
        return False

    def section_body_for_prompt(state, section_title):
        entry, _ = section_entry(state, section_title)
        return (entry.get("body") or section_title or "").strip()

    def language_policy_prompt():
        language = onboarding_language()
        display = "Korean" if language == "ko" else "Japanese" if language == "ja" else "English"
        return (
            "Language policy:\\n"
            f"Use Zebra's app language ({display}) for user-facing prose. Preserve technical terms, domain terminology, product names, commands, identifiers, file paths, environment variables, API names, CLI flags, JSON keys, error codes, and quoted/source text in their original English spelling."
        )

    def embedding_provider_decision_options():
        language = onboarding_language()
        if language == "ko":
            return "\\n".join([
                "When an embedding provider decision is required, show only these four numbered options in Korean. Preserve `ZEROENTROPY_API_KEY`, `OPENAI_API_KEY`, `VOYAGE_API_KEY`, `defer embeddings`, `gbrain init --pglite --no-embedding`, `embeddings`, URLs, and `**무료**` exactly:",
                "GBrain이 문서를 검색할 수 있게 하려면 embeddings provider가 필요합니다.",
                "처음 설치라면 ZeroEntropy를 추천합니다. **무료**로 시작하기 쉽고 GBrain embeddings 용도에 맞습니다.",
                "",
                "  1. ZEROENTROPY_API_KEY (recommended) — ZeroEntropy embeddings를 사용합니다.",
                "     키 만들기: https://dashboard.zeroentropy.dev",
                "  2. OPENAI_API_KEY — OpenAI embeddings를 사용합니다.",
                "     키 만들기: https://platform.openai.com/api-keys",
                "  3. VOYAGE_API_KEY — Voyage embeddings를 사용합니다.",
                "     키 만들기: https://dashboard.voyageai.com",
                "  4. defer embeddings — 지금은 `gbrain init --pglite --no-embedding`으로 설치만 진행합니다.",
                "     검색용 embeddings는 나중에 설정할 수 있습니다.",
            ])
        if language == "ja":
            return "\\n".join([
                "When an embedding provider decision is required, show only these four numbered options in Japanese. Preserve `ZEROENTROPY_API_KEY`, `OPENAI_API_KEY`, `VOYAGE_API_KEY`, `defer embeddings`, `gbrain init --pglite --no-embedding`, `embeddings`, URLs, and `**無料**` exactly:",
                "GBrainで文書を検索できるようにするにはembeddings providerが必要です。",
                "初回セットアップならZeroEntropyをおすすめします。**無料**で始めやすく、GBrain embeddingsの用途に合っています。",
                "",
                "  1. ZEROENTROPY_API_KEY (recommended) — ZeroEntropy embeddingsを使用します。",
                "     キー作成: https://dashboard.zeroentropy.dev",
                "  2. OPENAI_API_KEY — OpenAI embeddingsを使用します。",
                "     キー作成: https://platform.openai.com/api-keys",
                "  3. VOYAGE_API_KEY — Voyage embeddingsを使用します。",
                "     キー作成: https://dashboard.voyageai.com",
                "  4. defer embeddings — 今は`gbrain init --pglite --no-embedding`でインストールだけ進めます。",
                "     検索用embeddingsは後で設定できます。",
            ])
        return "\\n".join([
            "When an embedding provider decision is required, show only these four numbered options:",
            "GBrain needs an embeddings provider so it can search documents.",
            "For a first install, ZeroEntropy is recommended. It is easy to start for free and fits GBrain embeddings usage.",
            "",
            "  1. ZEROENTROPY_API_KEY (recommended) — use ZeroEntropy embeddings.",
            "     Create a key: https://dashboard.zeroentropy.dev",
            "  2. OPENAI_API_KEY — use OpenAI embeddings.",
            "     Create a key: https://platform.openai.com/api-keys",
            "  3. VOYAGE_API_KEY — use Voyage embeddings.",
            "     Create a key: https://dashboard.voyageai.com",
            "  4. defer embeddings — install now with `gbrain init --pglite --no-embedding`.",
            "     Search embeddings can be configured later.",
        ])

    def embedding_key_prompt(provider):
        env_name = embedding_provider_env_names.get(provider) or "ZEROENTROPY_API_KEY"
        url = {
            "zeroentropy": "https://dashboard.zeroentropy.dev",
            "openai": "https://platform.openai.com/api-keys",
            "voyage": "https://dashboard.voyageai.com",
        }.get(provider, "https://dashboard.zeroentropy.dev")
        language = onboarding_language()
        if language == "ko":
            return "\\n".join([
                f"{env_name}를 입력해 주세요.",
                "",
                "키가 아직 없으면 여기에서 만든 뒤 붙여넣어 주세요:",
                url,
            ])
        if language == "ja":
            return "\\n".join([
                f"{env_name}を入力してください。",
                "",
                "キーがまだない場合は、ここで作成してから貼り付けてください:",
                url,
            ])
        return "\\n".join([
            f"Enter {env_name}.",
            "",
            "If you do not have a key yet, create one here and paste it:",
            url,
        ])

    def brain_repo_target_options_text():
        recommended = recommended_brain_repo_path()
        descriptions = target_option_descriptions(recommended)
        return "\\n".join([
            f"1. {descriptions[0]}",
            f"2. {descriptions[1]}",
            f"3. {descriptions[2]}",
        ])

    def brain_repo_target_prompt_text():
        language = onboarding_language()
        options = brain_repo_target_options_text()
        if language == "ko":
            return "\\n".join([
                "brain repo target을 아래 번호 중 하나로 선택해 주세요.",
                options,
            ])
        if language == "ja":
            return "\\n".join([
                "brain repo targetは次の番号から選んでください。",
                options,
            ])
        return "\\n".join([
            "Choose the brain repo target using one of these numbered options.",
            options,
        ])

    def topology_decision_options_text():
        language = onboarding_language()
        if language == "ko":
            return "\\n".join([
                "1. PGLite (recommended) — 로컬 embedded Postgres입니다. 서버가 필요 없고 첫 설치에 가장 적합합니다.",
                "2. Postgres — 기존 Postgres database를 사용합니다.",
                "3. Supabase — hosted 또는 큰 brain을 위한 managed Postgres입니다.",
            ])
        if language == "ja":
            return "\\n".join([
                "1. PGLite (recommended) — ローカルembedded Postgresです。サーバー不要で初回セットアップに最適です。",
                "2. Postgres — 既存のPostgres databaseを使用します。",
                "3. Supabase — hostedまたは大きなbrain向けのmanaged Postgresです。",
            ])
        return "\\n".join([
            "1. PGLite (recommended) — local embedded Postgres, no server, best first install.",
            "2. Postgres — use an existing Postgres database.",
            "3. Supabase — managed Postgres for hosted or larger brains.",
        ])

    def topology_decision_prompt_text():
        language = onboarding_language()
        if language == "ko":
            return "\\n".join([
                "Step 3 database topology를 아래 번호 중 하나로 선택해 주세요:",
                topology_decision_options_text(),
            ])
        if language == "ja":
            return "\\n".join([
                "Step 3 database topologyは次の番号から選んでください:",
                topology_decision_options_text(),
            ])
        return "\\n".join([
            "Choose the Step 3 database topology using exactly these numbered options:",
            topology_decision_options_text(),
        ])

    def recurring_jobs_intro_text():
        language = onboarding_language()
        if language == "ko":
            return "\\n".join([
                "이 단계는 brain을 최신 상태로 유지하기 위한 정기 자동 작업을 설정하는 단계입니다.",
                "설정하면 Zebra가 주기적으로 새 변경사항을 가져오고, 검색용 데이터를 갱신하고, 상태를 점검합니다.",
                "지금 설정하지 않아도 Zebra는 계속 사용할 수 있고, 나중에 다시 켤 수 있습니다.",
            ])
        if language == "ja":
            return "\\n".join([
                "この段階はbrainを最新の状態に保つための定期自動作業を設定します。",
                "設定すると、Zebraが定期的に新しい変更を取り込み、検索用データを更新し、状態を確認します。",
                "今設定しなくてもZebraは使い続けられ、後から有効にできます。",
            ])
        return "\\n".join([
            "This section sets up scheduled automatic work that keeps the brain up to date.",
            "When enabled, Zebra periodically pulls new changes, refreshes search data, and checks health.",
            "You can keep using Zebra if you skip it now, and turn it on later.",
        ])

    def recurring_jobs_choice_prompt_text():
        language = onboarding_language()
        if language == "ko":
            return "brain을 최신 상태로 유지할 방식을 선택해 주세요:"
        if language == "ja":
            return "brainを最新の状態に保つ方法を選んでください:"
        return "Choose how to keep the brain up to date:"

    def recurring_jobs_topology_recommendation_text(state):
        language = onboarding_language()
        topology = topology_decision_value(state)
        if language == "ko":
            if topology == "pglite":
                return "Step 3에서 PGLite를 선택했기 때문에 Platform scheduler를 추천합니다."
            if topology == "postgres":
                return "Step 3에서 Postgres를 선택했기 때문에 GBrain autopilot을 추천합니다."
            if topology == "supabase":
                return "Step 3에서 Supabase를 선택했기 때문에 GBrain autopilot을 추천합니다."
            return "Step 3 database 선택을 확인할 수 없어 추천 없이 옵션을 보여줍니다."
        if language == "ja":
            if topology == "pglite":
                return "Step 3でPGLiteを選んだため、Platform schedulerをおすすめします。"
            if topology == "postgres":
                return "Step 3でPostgresを選んだため、GBrain autopilotをおすすめします。"
            if topology == "supabase":
                return "Step 3でSupabaseを選んだため、GBrain autopilotをおすすめします。"
            return "Step 3のdatabase選択を確認できないため、推奨なしで選択肢を表示します。"
        if topology == "pglite":
            return "Because Step 3 used PGLite, Zebra recommends Platform scheduler."
        if topology == "postgres":
            return "Because Step 3 used Postgres, Zebra recommends GBrain autopilot."
        if topology == "supabase":
            return "Because Step 3 used Supabase, Zebra recommends GBrain autopilot."
        return "Zebra could not confirm the Step 3 database choice, so these options have no recommendation."

    def recurring_jobs_option_records(state):
        language = onboarding_language()
        topology = topology_decision_value(state)
        def record(label, decision, description):
            return {
                "label": label,
                "decision": decision,
                "description": description,
            }
        if topology == "pglite":
            if language == "ko":
                return [
                    record("Platform scheduler (recommended)", "platform_scheduler_install", "선택한 agent가 로컬 brain의 정기 작업을 실행합니다."),
                    record("GBrain autopilot", "autopilot_install", "agent scheduler를 쓰기 어려울 때 GBrain이 정기 작업을 실행합니다."),
                    record("직접 설정", "manual_scheduler", "launchd, crontab, 외부 cron 등을 직접 구성합니다."),
                    record("나중에 하기", "defer", "지금은 정기 자동 작업을 설정하지 않습니다."),
                ]
            if language == "ja":
                return [
                    record("Platform scheduler (recommended)", "platform_scheduler_install", "選択したagentがローカルbrainの定期作業を実行します。"),
                    record("GBrain autopilot", "autopilot_install", "agent schedulerを使いにくい場合にGBrainが定期作業を実行します。"),
                    record("直接設定", "manual_scheduler", "launchd、crontab、外部cronなどを自分で構成します。"),
                    record("後で行う", "defer", "今は定期自動作業を設定しません。"),
                ]
            return [
                record("Platform scheduler (recommended)", "platform_scheduler_install", "the selected agent runs scheduled work for the local brain."),
                record("GBrain autopilot", "autopilot_install", "GBrain runs scheduled work when an agent scheduler is hard to use."),
                record("Manual setup", "manual_scheduler", "configure launchd, crontab, or external cron yourself."),
                record("Do later", "defer", "do not set up scheduled automatic work now."),
            ]
        if topology in {"postgres", "supabase"}:
            if language == "ko":
                return [
                    record("GBrain autopilot (recommended)", "autopilot_install", "durable database setup에 맞게 GBrain이 정기 작업을 실행합니다."),
                    record("Platform scheduler", "platform_scheduler_install", "이미 agent scheduler를 운영 기준으로 쓰고 있을 때 선택합니다."),
                    record("직접 설정", "manual_scheduler", "launchd, crontab, Railway cron 등 외부 scheduler를 직접 구성합니다."),
                    record("나중에 하기", "defer", "지금은 정기 자동 작업을 설정하지 않습니다."),
                ]
            if language == "ja":
                return [
                    record("GBrain autopilot (recommended)", "autopilot_install", "durable database setupに合わせてGBrainが定期作業を実行します。"),
                    record("Platform scheduler", "platform_scheduler_install", "すでにagent schedulerを運用基準として使っている場合に選びます。"),
                    record("直接設定", "manual_scheduler", "launchd、crontab、Railway cronなど外部schedulerを自分で構成します。"),
                    record("後で行う", "defer", "今は定期自動作業を設定しません。"),
                ]
            return [
                record("GBrain autopilot (recommended)", "autopilot_install", "GBrain runs scheduled work for durable database setups."),
                record("Platform scheduler", "platform_scheduler_install", "choose this when an agent scheduler is already the operating standard."),
                record("Manual setup", "manual_scheduler", "configure launchd, crontab, Railway cron, or another external scheduler yourself."),
                record("Do later", "defer", "do not set up scheduled automatic work now."),
            ]
        if language == "ko":
            return [
                record("Platform scheduler", "platform_scheduler_install", "선택한 agent가 brain의 정기 작업을 실행합니다."),
                record("GBrain autopilot", "autopilot_install", "GBrain이 정기 작업을 실행합니다."),
                record("직접 설정", "manual_scheduler", "launchd, crontab, 외부 cron 등을 직접 구성합니다."),
                record("나중에 하기", "defer", "지금은 정기 자동 작업을 설정하지 않습니다."),
            ]
        if language == "ja":
            return [
                record("Platform scheduler", "platform_scheduler_install", "選択したagentがbrainの定期作業を実行します。"),
                record("GBrain autopilot", "autopilot_install", "GBrainが定期作業を実行します。"),
                record("直接設定", "manual_scheduler", "launchd、crontab、外部cronなどを自分で構成します。"),
                record("後で行う", "defer", "今は定期自動作業を設定しません。"),
            ]
        return [
            record("Platform scheduler", "platform_scheduler_install", "the selected agent runs scheduled work for the brain."),
            record("GBrain autopilot", "autopilot_install", "GBrain runs scheduled work."),
            record("Manual setup", "manual_scheduler", "configure launchd, crontab, or external cron yourself."),
            record("Do later", "defer", "do not set up scheduled automatic work now."),
        ]

    def recurring_jobs_options_text(state):
        records = recurring_jobs_option_records(state)
        lines = [
            recurring_jobs_intro_text(),
            recurring_jobs_topology_recommendation_text(state),
            recurring_jobs_choice_prompt_text(),
        ]
        lines.extend([
            f"{index}. {record['label']} — {record['description']}"
            for index, record in enumerate(records, start=1)
        ])
        return "\\n".join(lines)

    def recurring_jobs_decision_mapping_text(state):
        records = recurring_jobs_option_records(state)
        return "\\n".join([
            f"  {index}. {record['label']} -> `--recurring-jobs-decision {record['decision']}`"
            for index, record in enumerate(records, start=1)
        ])

    def user_decision_gate_prompt(state, section_title):
        progress = state.get("progress") or {}
        waiting = progress.get("waitingForUser")
        reason = waiting_reason(waiting)
        normalized = normalize_title(section_title)
        if reason == "topology_resolution":
            return "\\n".join([
                "Current user-decision gate:",
                "Ask only for the Step 3 topology decision now. Present exactly this numbered prompt to the user:",
                topology_decision_prompt_text(),
                "Do not ask for the brain repo target in this gate. Ask for that later, after topology is chosen and Step 3 init/doctor have run.",
                "Do not ask for Step 2 API keys in the topology prompt. However, if a Step 3 command needs an embedding provider or offers `--no-embedding`/deferred embeddings, stop and show only the embedding provider decision options from Zebra hard gates.",
            ])
        if reason == "brain_repo_target_resolution":
            return "\\n".join([
                "Current user-decision gate:",
                "Ask only for the Step 3 brain repo target now. Present exactly this numbered prompt to the user:",
                brain_repo_target_prompt_text(),
                "If the user chooses 1, create the recommended path without asking for another yes/no confirmation. If the user chooses 2, ask for the full existing repo path. If the user chooses 3, ask for the full path to create, then create it without asking for another yes/no confirmation.",
                "Do not present Zebra's onboarding work directory, launch directory, or any path under it as a brain repo target option.",
                "Do not ask for topology in this gate. Do not ask for Step 2 API keys unless the current Step 3 command refuses to continue without one. Do not silently choose `--no-embedding`; show only the embedding provider decision options from Zebra hard gates and record `--embedding-decision` first.",
            ])
        if "step 2" in normalized:
            return "\\n".join([
                "Current user-decision gate:",
                "Ask only for Step 2 credential decisions needed by the current command.",
                "If no embedding provider is configured, show only the embedding provider decision options from Zebra hard gates. Do not choose deferred/no-embedding mode without explicit user confirmation.",
                "Do not ask for Step 3 topology or brain repo target until Step 3 is the current section.",
            ])
        if ("step 3 5" in normalized or "search mode" in normalized) and "confirm" in normalized:
            return "\\n".join([
                "Current user-decision gate:",
                "Ask only for the search mode decision required by this section.",
                "If Zebra hard gates say the user already chose a mode earlier, do not ask again.",
            ])
        if "step 3" in normalized:
            return "\\n".join([
                "Current user-decision gate:",
                "Ask only for Step 3 decisions that are not already resolved.",
                "Do not ask for Step 2 API keys unless a Step 3 command refuses to continue without one. If it offers `--no-embedding` or embedding deferral, show only the embedding provider decision options from Zebra hard gates before using that path and record the decision.",
            ])
        return "\\n".join([
            "Current user-decision gate:",
            "Ask only for decisions required by the current section.",
        ])

    def hard_gate_prompt_for_section(state, section_title):
        role, _, _ = section_role(state, section_title, record=False)
        completion_command = (
            "`zebra-gbrain-onboarding report --status completed --section "
            + json.dumps(section_title)
            + " --recurring-jobs-decision <defer|manual_scheduler|platform_scheduler_install|autopilot_install>`"
            if role == "recurring_jobs" else
            "`zebra-gbrain-onboarding report --status completed --section "
            + json.dumps(section_title)
            + "`"
        )
        common = [
            "Zebra section boundary rules:",
            "- Work only this section. Do not start later INSTALL_FOR_AGENTS.md sections until Zebra prints their nextPrompt.",
            "- Keep using the active GBrain source repo from `activeGBrainBinding.sourceRepoPath` for GBrain installation work.",
            "- When this section is complete, run: " + completion_command + ".",
            "- If Zebra rejects the report, fix the reported reason and do not continue to the next section.",
        ]
        if role == "install":
            binding = state.get("activeGBrainBinding") or {}
            source_repo = binding.get("sourceRepoPath") or "unknown"
            recommended = bool(binding.get("sourceRepoIsRecommended")) or (
                source_repo != "unknown" and is_recommended_source_repo_path(source_repo)
            )
            install_rule = (
                "- Because the active source repo is Zebra's recommended `~/gbrain` path, run `bun install`, then `bun install -g .`, then verify `gbrain --version`."
                if recommended else
                "- Because the active source repo is not Zebra's recommended `~/gbrain` path, run `bun install`, then `bun link`, then verify `gbrain --version`."
            )
            common.extend([
                "",
                "Install hard gates:",
                f"- Active GBrain source repo: {source_repo}.",
                "- Run GBrain installation from the active GBrain source repo.",
                install_rule,
                "- Do not use `zebra-gbrain-onboarding run-gbrain -- --version` or `bun src/cli.ts --version` as the completion verification; Step 1 must expose the active source repo through the user-visible `gbrain` command first.",
                "- Do not run `bun upgrade` during Zebra onboarding.",
            ])
        elif role == "credentials":
            common.extend([
                "",
                "Credential and embedding decision hard gates:",
                "- Do not choose deferred/no-embedding mode unless the user explicitly chooses that path.",
                "- " + embedding_provider_decision_options().replace("\\n", "\\n- "),
                "- If the user chooses 1, use provider=zeroentropy and key env `ZEROENTROPY_API_KEY`. Show this exact key prompt next, before reporting the section:\\n" + embedding_key_prompt("zeroentropy") + "\\nAfter the user provides the key, configure it using the saving instructions already present in this prompt's `INSTALL_FOR_AGENTS.md section body`. Do not reread files or open separate docs for those instructions. Then report this section with `--embedding-decision provider_key --embedding-provider zeroentropy --embedding-key-env ZEROENTROPY_API_KEY`.",
                "- If the user chooses 2, use provider=openai and key env `OPENAI_API_KEY`. Show this exact key prompt next, before reporting the section:\\n" + embedding_key_prompt("openai") + "\\nAfter the user provides the key, configure it using the saving instructions already present in this prompt's `INSTALL_FOR_AGENTS.md section body`. Do not reread files or open separate docs for those instructions. Then report this section with `--embedding-decision provider_key --embedding-provider openai --embedding-key-env OPENAI_API_KEY`.",
                "- If the user chooses 3, use provider=voyage and key env `VOYAGE_API_KEY`. Show this exact key prompt next, before reporting the section:\\n" + embedding_key_prompt("voyage") + "\\nAfter the user provides the key, configure it using the saving instructions already present in this prompt's `INSTALL_FOR_AGENTS.md section body`. Do not reread files or open separate docs for those instructions. Then report this section with `--embedding-decision provider_key --embedding-provider voyage --embedding-key-env VOYAGE_API_KEY`.",
                "- If the user chooses 4, report this section with `--embedding-decision defer_embeddings`.",
                "- Never write API key values to Zebra state, progress, report flags, logs, or summaries. Zebra state records only provider metadata.",
            ])
        elif role == "create_brain":
            common.extend([
                "",
                "Step 3 topology / PGLite / target hard gates:",
                "- In Step 3, do not run `gbrain init`, `gbrain init --pglite`, or Supabase/Postgres setup until the user has explicitly chosen topology.",
                "- Ask the user to choose database topology before initialization. Present exactly this numbered prompt to the user:",
                topology_decision_prompt_text(),
                "- Interpret user choice 1 as topology=pglite and run `gbrain init --pglite`.",
                "- Interpret user choice 2 as topology=postgres and configure the existing Postgres database before `gbrain doctor --json`.",
                "- Interpret user choice 3 as topology=supabase and configure Supabase before `gbrain doctor --json`.",
                "- Do not run `gbrain init --pglite --no-embedding`, accept deferred embeddings, or otherwise disable embeddings until the user explicitly chooses that path.",
                "- Ask for the brain repo target separately after topology is chosen and Step 3 init/doctor have run.",
                "- When asking for the brain repo target, present exactly this numbered prompt to the user:",
                brain_repo_target_prompt_text(),
                "- Interpret user choice 1 as the recommended path with targetResolution.method=user_created_repo.",
                "- Interpret user choice 2 as an existing repo path with targetResolution.method=user_existing_repo; ask for the path if the user provides only the number.",
                "- Interpret user choice 3 as a new custom repo path with targetResolution.method=user_created_repo; ask for the path if the user provides only the number.",
                "- Do not ask only as an open-ended path question.",
                "- Do not implicitly use the home directory or Zebra's onboarding work directory as the brain repo target.",
                "- When Step 3 resolves a brain repo target, include `--topology <pglite|postgres|supabase> --target <brain repo path> --method <targetResolution.method>` on the completed report.",
                "- If a Step 3 command asks the user to choose search mode before Step 3.5, include `--search-mode <mode>` on the Step 3 completed report so Zebra will not ask the same question again in Step 3.5.",
                "- If the Step 3 completed report returns `doctor_failed`, inspect the report's `doctorFailedChecks`, `doctorCwd`, and `doctorExitCode`. Do not treat Step 9 `verify` output as the Step 3 report contract.",
                "- `cycle_freshness` alone should not block Step 3. Any other doctor failed check must be fixed before reporting Step 3 completed again.",
            ])
        elif role == "search_mode":
            decision = search_mode_decision(state)
            mode = decision.get("mode")
            if mode:
                source_section = decision.get("sourceSection") or "an earlier section"
                common.extend([
                    "",
                    "Search mode hard gates:",
                    f"- The user already chose search mode `{mode}` during `{source_section}`. Do not ask the user to choose search mode again.",
                    f"- Run `gbrain config set search.mode {mode}` even when it matches the default.",
                    "- Verify with `gbrain search modes` before reporting completion.",
                ])
            else:
                common.extend([
                    "",
                    "Search mode hard gates:",
                    "- When asking for search mode, extract the available option labels and descriptions from this INSTALL_FOR_AGENTS.md section body and present them to the user as a numbered list.",
                    "- If the section body expresses options inline, such as comma-separated labels or an `A, B, or C` phrase, rewrite those labels into separate `1.`, `2.`, `3.` lines before asking the user.",
                    "- Preserve the section body's option labels, descriptions, and order. Do not hardcode, add, remove, or rename search mode options if the section body changes.",
                    "- Do not ask with an unnumbered comma-separated sentence.",
                    "- Map the user's chosen number back to the exact selected mode label from the section body before running the config command.",
                    "- After the user chooses search mode, explicitly run `gbrain config set search.mode <mode>` even when it matches the default.",
                    "- Verify with `gbrain search modes` before reporting completion.",
                ])
        elif role == "import_index":
            common.extend([
                "",
                "Import/index hard gates:",
                "- Before import/embed/sync, verify the resolved brain repo target has an initial git commit.",
                "- If Zebra rejects completion with `brain_repo_initial_commit_missing`, run `zebra-gbrain-onboarding create-initial-brain-commit --target <brain repo path>`.",
                "- Then rerun import/sync and report completion again.",
                "- Before import/embed/sync, ensure the resolved brain repo target is registered as a GBrain source.",
                "- Verify `gbrain sources current --json` and `gbrain sources list --json` identify the same source id for the target path.",
                "- Do not import the target into the implicit `default` source.",
                "- Include `--source-id <source id>` on the completed report after the source probe verifies that source id for the target path.",
            ])
        elif role == "recurring_jobs":
            recurring_target_key, recurring_target_path, _, _ = resolved_target(state)
            recurring_repo = recurring_target_path or "<brain repo path>"
            recurring_repo_arg = shell_quote(recurring_repo) if recurring_target_path else "<brain repo path>"
            common.extend([
                "",
                "Recurring jobs hard gates:",
                "- This section installs or defers scheduled automatic work that keeps the brain up to date; it is not a prerequisite for import/index or final verify.",
                f"- Step 3 topology is `{topology_decision_value(state) or 'unknown'}`.",
                f"- Recurring jobs target key is `{recurring_target_key or '__unresolved__'}`.",
                f"- Recurring jobs target path is `{recurring_repo}`.",
                "- Ask the user how to keep the brain up to date using exactly these numbered options:",
                recurring_jobs_options_text(state),
                "- Map the user's selected number exactly as follows:",
                recurring_jobs_decision_mapping_text(state),
                "- Do not run `gbrain autopilot --install`, `gbrain autopilot install`, `launchctl`, `cron`, `crontab`, `systemd`, or scheduler installation/start commands until the user explicitly chooses that path.",
                "- First run `zebra-gbrain-onboarding report --status waiting_for_user --section " + json.dumps(section_title) + " --reason recurring_jobs_decision --note \\\"Choose defer, manual_scheduler, platform_scheduler_install, or autopilot_install\\\"` and ask the user to choose.",
                "- If the user chooses `defer`, do not install or start any background service; report completed with `--recurring-jobs-decision defer`.",
                "- If the user chooses `manual_scheduler`, do not run scheduler commands; report completed with `--recurring-jobs-decision manual_scheduler`.",
                "- If the user chooses `autopilot_install`, first record approval with `zebra-gbrain-onboarding report --status started --section " + json.dumps(section_title) + " --recurring-jobs-decision autopilot_install`, then run `zebra-gbrain-onboarding check-launchd-bun-path` before running `zebra-gbrain-onboarding run-gbrain -- autopilot --install --repo " + recurring_repo_arg + "`.",
                "- If `check-launchd-bun-path` reports `bun_missing_for_launchd_autopilot`, run `zebra-gbrain-onboarding repair-launchd-bun-path`, then rerun `zebra-gbrain-onboarding check-launchd-bun-path`.",
                "- Only after `check-launchd-bun-path` returns ok, run `zebra-gbrain-onboarding run-gbrain -- autopilot --install --repo " + recurring_repo_arg + "`, then report completed with `--recurring-jobs-decision autopilot_install`.",
                "- If the user chooses `platform_scheduler_install`, first record approval with `zebra-gbrain-onboarding report --status started --section " + json.dumps(section_title) + " --recurring-jobs-decision platform_scheduler_install`, then run `zebra-gbrain-onboarding prepare-platform-scheduler` to install/start only the selected runtime's scheduler service.",
                "- Do not run `openclaw gateway install`, `openclaw gateway start`, `hermes gateway install`, or `hermes gateway start` directly; use `zebra-gbrain-onboarding prepare-platform-scheduler` so Zebra can verify recurring jobs approval first.",
                "- After `prepare-platform-scheduler` returns ok, create the GBrain core recurring jobs using the selected runtime scheduler only. Do not create the old single `GBrain save` job.",
                "- Create exactly these four core jobs for the selected runtime: Live sync every 15 minutes, Auto-update daily, Dream cycle nightly, and Weekly health weekly.",
                "- Footer save status uses only the Live sync job; auto-update, dream cycle, and weekly health must not be treated as footer save status jobs.",
                "- For OpenClaw, keep `--no-deliver --json` on all four jobs and use these command shapes:",
                "  1. `openclaw cron create --name \\\"GBrain live sync\\\" --every 15m --session isolated --message \\\"Run: gbrain sync --repo " + recurring_repo_arg + " --yes && gbrain embed --stale, then run: gbrain status. If sync reports thin-client/not-routable, run: gbrain remote ping. Do not send any chat message.\\\" --no-deliver --json`",
                "  2. `openclaw cron create --name \\\"GBrain auto-update\\\" --cron \\\"0 9 * * *\\\" --session isolated --message \\\"Run: gbrain check-update --json. Tell the user only if an update is available; never auto-install. Do not send any chat message unless an update is available.\\\" --no-deliver --json`",
                "  3. `openclaw cron create --name \\\"GBrain dream cycle\\\" --cron \\\"0 2 * * *\\\" --session isolated --message \\\"Run: gbrain dream --dir " + recurring_repo_arg + ". Do not send any chat message unless the dream cycle fails.\\\" --no-deliver --json`",
                "  4. `openclaw cron create --name \\\"GBrain weekly health\\\" --cron \\\"0 6 * * 1\\\" --session isolated --message \\\"Run: gbrain doctor --json && gbrain embed --stale. Do not send any chat message unless the health check reports failure or warnings requiring user action.\\\" --no-deliver --json`",
                "- For Hermes, omit `--deliver` so Hermes uses its default local delivery and use these command shapes:",
                "  1. `hermes cron create \\\"every 15m\\\" \\\"Run: gbrain sync --repo " + recurring_repo_arg + " --yes && gbrain embed --stale, then run: gbrain status. If sync reports thin-client/not-routable, run: gbrain remote ping. Do not send any chat message.\\\" --name \\\"GBrain live sync\\\" --workdir \\\"" + recurring_repo + "\\\"`",
                "  2. `hermes cron create \\\"0 9 * * *\\\" \\\"Run: gbrain check-update --json. Tell the user only if an update is available; never auto-install. Do not send any chat message unless an update is available.\\\" --name \\\"GBrain auto-update\\\"`",
                "  3. `hermes cron create \\\"0 2 * * *\\\" \\\"Run: gbrain dream --dir " + recurring_repo_arg + ". Do not send any chat message unless the dream cycle fails.\\\" --name \\\"GBrain dream cycle\\\" --workdir \\\"" + recurring_repo + "\\\"`",
                "  4. `hermes cron create \\\"0 6 * * 1\\\" \\\"Run: gbrain doctor --json && gbrain embed --stale. Do not send any chat message unless the health check reports failure or warnings requiring user action.\\\" --name \\\"GBrain weekly health\\\"`",
                "- After all four runtime cron jobs are created, report completed with `--recurring-jobs-decision platform_scheduler_install`.",
            ])
        elif role == "verify":
            common.extend([
                "",
                "Verify hard gates:",
                "- Do not say setup is complete until `zebra-gbrain-onboarding verify` returns `complete: true`.",
                "- Use `zebra-gbrain-onboarding verify --target <brain repo path> --source-id <source id> --method <targetResolution.method>`.",
                "- `verify` may complete with `status=verified_with_maintenance_pending` only when `cycle_freshness` is the sole doctor failure and source/sync/embed/search probes pass.",
                "- Do not run `gbrain dream` implicitly during verify. If the user explicitly wants immediate warm-up, run `zebra-gbrain-onboarding recover-cycle-freshness --target <path> --source-id <id>`.",
                "- If `verify` returns `complete: false`, inspect `reasons` and `doctorFailedChecks` and fix the named blockers before retrying verify.",
            ])
        return "\\n".join(common)

    def build_section_prompt(state, section_title):
        if section_title == "verify":
            return build_verify_prompt(state)
        if section_title == "complete":
            return build_complete_prompt(state)
        body = section_body_for_prompt(state, section_title)
        return "\\n\\n".join([
            f"Zebra GBrain setup: current section is `{section_title}`.",
            language_policy_prompt(),
            "Follow only the INSTALL_FOR_AGENTS.md section below. Do not continue to later sections until Zebra prints the next prompt.",
            "INSTALL_FOR_AGENTS.md section body:",
            body,
            user_decision_gate_prompt(state, section_title),
            hard_gate_prompt_for_section(state, section_title),
        ]).strip()

    def build_verify_prompt(state):
        receipt = state.get("receipt") or {}
        progress = state.get("progress") or {}
        targets = receipt.get("targets") or {}
        target_key = progress.get("resolvedTargetKey") or receipt.get("primaryTargetKey")
        target = targets.get(target_key) if target_key else None
        target_path = (target or {}).get("vaultPath") or "<brain repo path>"
        source_id = (target or {}).get("sourceId") or "<source id>"
        method = ((target or {}).get("targetResolution") or progress.get("targetResolution") or {}).get("method") or "<targetResolution.method>"
        if receipt_verify_complete(state):
            return "\\n".join([
                "Zebra GBrain setup: final verification already passed.",
                "",
                "Do not run `zebra-gbrain-onboarding verify` again.",
                "Finish the Zebra UI completion state now by running:",
                "`zebra-gbrain-onboarding report --status completed --section \\\"verify\\\"`",
                "After the report succeeds, follow the returned `nextPrompt`.",
            ])
        return "\\n".join([
            "Zebra GBrain setup: INSTALL_FOR_AGENTS.md sections are complete. Run final verification now.",
            "",
            "Do not say setup is complete until verify returns `complete: true`.",
            f"Run: zebra-gbrain-onboarding verify --target {shell_quote(target_path)} --source-id {shell_quote(source_id)} --method {shell_quote(method)}",
            "If a profile was selected, include `--profile-id <profile>`.",
            "Only after verify returns `complete: true`, immediately run `zebra-gbrain-onboarding report --status completed --section \\\"verify\\\"` so Zebra marks the UI complete.",
            "If verify fails, repair the reported reasons and rerun verify.",
        ])

    def build_complete_prompt(state):
        if receipt_verify_complete(state) and not verify_section_completed(state):
            return "\\n".join([
                "Zebra GBrain setup verification is complete, but Zebra still needs the final UI completion report.",
                "",
                "Do not run `zebra-gbrain-onboarding verify` again.",
                "Run exactly:",
                "`zebra-gbrain-onboarding report --status completed --section \\\"verify\\\"`",
                "Then follow the returned `nextPrompt`.",
            ])
        return "\\n".join([
            "Zebra GBrain setup is complete.",
            "",
            "Do not run `zebra-gbrain-onboarding verify` again.",
            "Do not run any more onboarding commands.",
            "Briefly tell the user that Zebra GBrain setup is complete, then stop.",
        ])

    def next_prompt_payload(state):
        section = next_section_title(state)
        prompt = build_section_prompt(state, section)
        path = write_next_prompt_file(state, section, prompt)
        return {
            "nextSection": section,
            "nextPrompt": prompt,
            "nextPromptPath": path,
        }

    def waiting_display(progress):
        waiting = progress.get("waitingForUser") if progress else None
        if isinstance(waiting, dict):
            reason = waiting.get("reason")
            note = waiting.get("note")
            if reason == "user_input_required" and note:
                return note
            return reason or note or waiting.get("section")
        if isinstance(waiting, str):
            return waiting
        return "none"

    def terminal_argument_prompt(prompt):
        return " ".join(
            line.strip()
            for line in prompt.replace("\\r", "\\n").split("\\n")
            if line.strip()
        )

    def bootstrap_prompt():
        state = load_state()
        progress = state.get("progress") or {}
        if existing_install_verification_mode(state):
            return terminal_argument_prompt(existing_install_bootstrap_prompt(state))
        section = progress.get("nextSection") or next_section_title(state)
        section_prompt = build_section_prompt(state, section)
        language = (os.environ.get("ZEBRA_ONBOARDING_LANGUAGE") or "en").lower()
        if language == "ko" or language.startswith("ko-"):
            first_visible = "Your first visible response must be a brief Korean sentence telling the user that Zebra GBrain setup is starting, you are reading the current section prompt now, and they should wait. Preserve `Zebra GBrain setup` and `section prompt` exactly."
        elif language == "ja" or language.startswith("ja-"):
            first_visible = "Your first visible response must be a brief Japanese sentence telling the user that Zebra GBrain setup is starting, you are reading the current section prompt now, and they should wait. Preserve `Zebra GBrain setup` and `section prompt` exactly."
        else:
            first_visible = "Your first visible response must be exactly:\\nZebra GBrain setup is starting. I am reading the current section prompt now. Please wait."
        return terminal_argument_prompt("\\n".join([
            first_visible,
            "Do not run tools or read files before printing that line.",
            "After printing it, follow this current section prompt exactly:",
            section_prompt,
            "When this section is complete, run the report command shown in the section prompt and continue from its `nextPrompt` stdout.",
        ]))

    def existing_install_bootstrap_prompt(state):
        progress = state.get("progress") or {}
        selected_vault = progress.get("selectedVaultPath")
        verify_command = None
        if selected_vault:
            verify_command = (
                "zebra-gbrain-onboarding verify-existing-install --target "
                + shell_quote(selected_vault)
                + " --method selected_vault"
            )
        language = (os.environ.get("ZEBRA_ONBOARDING_LANGUAGE") or "en").lower()
        if language == "ko" or language.startswith("ko-"):
            first_visible = "Your first visible response must be a brief Korean sentence telling the user that Zebra is checking their existing GBrain install and they should wait. Preserve `Zebra` and `GBrain` exactly."
        elif language == "ja" or language.startswith("ja-"):
            first_visible = "Your first visible response must be a brief Japanese sentence telling the user that Zebra is checking their existing GBrain install and they should wait. Preserve `Zebra` and `GBrain` exactly."
        else:
            first_visible = "Your first visible response must be exactly:\\nZebra is checking your existing GBrain install. Please wait."
        return "\\n".join([
            first_visible,
            "Do not run tools or read files before printing that line.",
            "This is Zebra GBrain preflight mode. Do not start INSTALL_FOR_AGENTS.md Step 1 and do not create a GBrain setup checklist unless `discover-existing-install-target` returns `kind: fresh_install`, or the user explicitly confirms abandoning existing-install recovery for a new GBrain/brain setup.",
            ("First run: " + verify_command) if verify_command else "No selected local brain repo target is confirmed yet. First run: zebra-gbrain-onboarding discover-existing-install-target. If it returns `kind: remote_thin_client`, treat the remote MCP URL as a remote-only target, do not ask for a local brain repo path, and run its `nextAction.command`. If it returns `kind: local_vault`, run its `nextAction.command`. If it returns `kind: fresh_install`, run its `nextAction.command` and continue the fresh GBrain setup flow. Only ask the user for a local brain/vault repo path when it returns `kind: unresolved` with `askUserFor: brain_repo_path`.",
            "When you run `verify-existing-install`, if it returns `complete: true` with status `verified` or `transient_retry_preserved`, stop new GBrain setup work and summarize the result. Do not edit `gbrain-setup-state.json` directly.",
            "If `verify-existing-install` fails with `diagnosis_needed`, run the printed `nextAction.command` before choosing a repair path.",
            "Treat `failure.reasons` as probe evidence labels, not root-cause taxonomy and not a fixed repair-command mapping.",
            "Use installed `gbrain` CLI help/doctor/status/remediation output as the primary authority. Use a local GBrain source repo only as docs/tool fallback when needed; to prepare that fallback without starting a new setup, run `zebra-gbrain-onboarding prepare-source-repo`.",
            "Ask the user before changing source bindings, remote topology, credentials, destructive data state, or abandoning recovery for a new home-directory GBrain setup.",
            "If `discover-existing-install-target` returns `kind: fresh_install`, that is Zebra's decision that no existing install evidence is present. Do not ask the user to confirm a new setup again; run its `nextAction.command` and continue the fresh GBrain setup flow.",
            "Only when existing-install recovery is not practical and you ask the user to abandon that recovery, put the new setup option first and label it as installing GBrain in the home directory, for example Korean `홈 디렉토리에 GBrain 설치` or English `Install GBrain in my home directory`. Do not use that fallback confirmation for `kind: fresh_install`. Do not use the phrase `fresh install` in user-facing text.",
            "If the user explicitly chooses that new home-directory GBrain setup, run `zebra-gbrain-onboarding prepare-source-repo --fresh-install`, then follow the returned setup section flow.",
            "After any repair, rerun the verify command. Completion is valid only when `verify-existing-install` succeeds.",
        ])

    def launcher_safe_run_id(run_id):
        safe = "".join(
            character if character.isalnum() or character in "-_" else "-"
            for character in str(run_id or "gbrain-setup")
        ).strip("-_") or "gbrain-setup"
        return safe

    def launcher_script_path(run_id):
        safe = launcher_safe_run_id(run_id)
        directory = os.path.join(os.path.dirname(state_path), "gbrain-runtime-launchers")
        return os.path.join(directory, safe + ".sh")

    def launcher_prompt_path(run_id):
        safe = launcher_safe_run_id(run_id)
        directory = os.path.join(os.path.dirname(state_path), "gbrain-runtime-launchers")
        return os.path.join(directory, safe + ".prompt.txt")

    def write_runtime_launcher():
        flags = parse_flags(args)
        runtime = flags.get("runtime")
        executable = flags.get("executable")
        run_id = flags.get("run_id") or (load_state().get("currentRunId") or "gbrain-setup")
        if not runtime:
            raise RuntimeError("runtime_missing")
        if not executable:
            raise RuntimeError("runtime_executable_missing")
        state = load_state()
        source_repo = existing_active_source_repo_path()
        existing_mode = existing_install_verification_mode(state)
        if not source_repo and not existing_mode:
            raise RuntimeError("active_source_repo_missing")
        prompt = bootstrap_prompt()
        path = launcher_script_path(run_id)
        prompt_path = launcher_prompt_path(run_id)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(prompt_path, "w", encoding="utf-8") as handle:
            handle.write(prompt.rstrip() + "\\n")
        os.chmod(prompt_path, 0o600)
        lines = [
            "#!/bin/sh",
            "set -eu",
            f"ZEBRA_GBRAIN_BOOTSTRAP_PROMPT_PATH={shell_quote(prompt_path)}",
            'ZEBRA_GBRAIN_BOOTSTRAP_PROMPT=$(cat "$ZEBRA_GBRAIN_BOOTSTRAP_PROMPT_PATH")',
        ]
        if source_repo:
            lines[2:2] = [
                'if [ -z "${ZEBRA_GBRAIN_SOURCE_REPO:-}" ]; then',
                '  eval "$(zebra-gbrain-onboarding active-source-env)"',
                "fi",
            ]
            workspace = '"$ZEBRA_GBRAIN_SOURCE_REPO"'
        else:
            workspace = shell_quote((state.get("progress") or {}).get("launchDirectory") or os.path.dirname(state_path))
        if runtime == "openclaw":
            agent_id = flags.get("agent_id") or "zebra-gbrain-setup"
            session = flags.get("session") or f"agent:{agent_id}:{run_id}"
            if source_repo:
                lines.append(f"zebra-gbrain-onboarding prepare-openclaw-agent --executable {shell_quote(executable)} --agent-id {shell_quote(agent_id)}")
            lines.extend([
                f"cd {workspace}",
                f"exec {shell_quote(executable)} tui --local --session {shell_quote(session)} --message \\\"$ZEBRA_GBRAIN_BOOTSTRAP_PROMPT\\\"",
            ])
        elif runtime == "hermes":
            lines.extend([
                f"cd {workspace}",
                f"exec {shell_quote(executable)} chat --tui --source zebra-gbrain-onboarding --query \\\"$ZEBRA_GBRAIN_BOOTSTRAP_PROMPT\\\"",
            ])
        else:
            raise RuntimeError(f"unsupported_runtime:{runtime}")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("\\n".join(lines) + "\\n")
        os.chmod(path, 0o700)
        print(f"export ZEBRA_GBRAIN_RUNTIME_LAUNCHER={shell_quote(path)}")

    def prepare_openclaw_agent():
        flags = parse_flags(args)
        executable = flags.get("executable") or shutil.which("openclaw")
        if not executable:
            raise RuntimeError("openclaw_executable_missing")
        source_repo = existing_active_source_repo_path()
        if not source_repo:
            raise RuntimeError("active_source_repo_missing")
        agent_id = flags.get("agent_id") or "zebra-gbrain-setup"
        expected_workspace = os.path.realpath(os.path.abspath(os.path.expanduser(source_repo)))
        list_result = subprocess.run(
            [executable, "agents", "list", "--json"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        if list_result.returncode != 0:
            if list_result.stderr:
                print(list_result.stderr, file=sys.stderr)
            raise RuntimeError("openclaw_agents_list_failed")
        try:
            agents = json.loads(list_result.stdout or "[]")
        except Exception:
            raise RuntimeError("openclaw_agents_list_invalid_json")
        existing = next((agent for agent in agents if agent.get("id") == agent_id), None)
        if existing:
            workspace = os.path.realpath(os.path.abspath(os.path.expanduser(str(existing.get("workspace") or ""))))
            if workspace != expected_workspace:
                raise RuntimeError(f"openclaw_agent_workspace_mismatch:{workspace}")
            print(json.dumps({
                "ok": True,
                "status": "ready",
                "agentId": agent_id,
                "workspace": source_repo,
            }, sort_keys=True))
            return
        add_result = subprocess.run(
            [executable, "agents", "add", agent_id, "--workspace", source_repo, "--non-interactive"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        if add_result.returncode != 0:
            if add_result.stderr:
                print(add_result.stderr, file=sys.stderr)
            raise RuntimeError("openclaw_agent_add_failed")
        print(json.dumps({
            "ok": True,
            "status": "created",
            "agentId": agent_id,
            "workspace": source_repo,
        }, sort_keys=True))

    def target_key(path):
        return "vault:" + os.path.abspath(os.path.expanduser(path))

    def remote_target_key(remote_mcp_url):
        return "remote:" + (remote_mcp_url or "thin-client")

    def gbrain_executable():
        state = load_state()
        binding = state.get("activeGBrainBinding") or {}
        source_repo = binding.get("sourceRepoPath")
        if source_repo:
            for candidate in [
                os.path.join(os.path.abspath(os.path.expanduser(source_repo)), "node_modules", ".bin", "gbrain"),
                os.path.join(os.path.abspath(os.path.expanduser(source_repo)), "bin", "gbrain"),
            ]:
                if os.access(candidate, os.X_OK):
                    return candidate
        found = path_gbrain_executable()
        if found:
            return found
        for candidate in glob.glob(os.path.expanduser("~/.gbrain-profiles/*/gbrain-*")):
            if os.access(candidate, os.X_OK):
                return candidate
        return None

    def run_gbrain():
        forwarded_args = list(args)
        if forwarded_args and forwarded_args[0] == "--":
            forwarded_args = forwarded_args[1:]

        state = load_state()
        source_repo = (state.get("activeGBrainBinding") or {}).get("sourceRepoPath")
        if not source_repo:
            print("active GBrain source repo binding is missing", file=sys.stderr)
            sys.exit(127)
        source_repo = os.path.abspath(os.path.expanduser(source_repo))
        if not os.path.isdir(source_repo):
            print("active GBrain source repo is missing: " + source_repo, file=sys.stderr)
            sys.exit(127)

        if (
            forwarded_args
            and forwarded_args[0] == "autopilot"
            and any(arg in {"--install", "install"} for arg in forwarded_args[1:])
        ):
            decision = recurring_jobs_decision_value(state)
            if os.environ.get("ZEBRA_GBRAIN_ALLOW_RECURRING_JOBS_INSTALL") != "1" and decision != "autopilot_install":
                print("Zebra blocked 'gbrain autopilot --install': recurring_jobs_decision=autopilot_install is required before installing persistent background jobs.", file=sys.stderr)
                print("Run: zebra-gbrain-onboarding report --status waiting_for_user --section \\\"<section title>\\\" --reason recurring_jobs_decision", file=sys.stderr)
                sys.exit(78)

        candidates = [
            [os.path.join(source_repo, "node_modules", ".bin", "gbrain")],
            [os.path.join(source_repo, "bin", "gbrain")],
        ]
        bun = shutil.which("bun")
        if bun and os.path.isfile(os.path.join(source_repo, "src", "cli.ts")):
            candidates.append([bun, os.path.join(source_repo, "src", "cli.ts")])

        for prefix in candidates:
            executable = prefix[0]
            if len(prefix) == 1 and not os.access(executable, os.X_OK):
                continue
            if len(prefix) > 1 and not os.path.isfile(prefix[1]):
                continue
            try:
                result = subprocess.run(prefix + forwarded_args, cwd=source_repo, env=process_env_with_gbrain_env())
            except FileNotFoundError:
                continue
            except Exception as exc:
                print("failed to run active GBrain source CLI: " + str(exc), file=sys.stderr)
                sys.exit(1)
            sys.exit(result.returncode)

        print("active GBrain source CLI is unavailable; run bun install from the active GBrain source repo first", file=sys.stderr)
        sys.exit(127)

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
    PGLITE_WASM_RUNTIME_ERROR_REASON = "pglite_wasm_runtime_error"
    SOURCE_PROBE_RUNTIME_ERROR_REASON = "source_probe_runtime_error"
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

    def source_missing_probe_failure(message):
        text = (message or "").lower()
        return (
            "source_not_registered" in text
            or "source not registered" in text
            or "source not found" in text
            or "no current source" in text
            or "no source" in text
        )

    def probe_failure_reason(message):
        reason = transient_probe_reason(message)
        if reason:
            return reason
        text = (message or "").lower()
        if "pglite failed to initialize its wasm runtime" in text:
            return PGLITE_WASM_RUNTIME_ERROR_REASON
        if "aborted()" in text and "pglite" in text:
            return PGLITE_WASM_RUNTIME_ERROR_REASON
        return SOURCE_PROBE_RUNTIME_ERROR_REASON

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
            if source_missing_probe_failure(current_error):
                return "mismatch", None, None, None
            return "error", None, None, probe_failure_reason(current_error)
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
            if source_missing_probe_failure(list_error):
                return "mismatch", current_source_id, None, None
            return "error", current_source_id, None, probe_failure_reason(list_error)
        listed_local_path = source_list_local_path(list_payload, source_id)
        if not listed_local_path or os.path.abspath(os.path.expanduser(listed_local_path)) != os.path.abspath(target_path):
            return "mismatch", current_source_id, listed_local_path, None
        return "verified", current_source_id, listed_local_path, None

    def live_sync_job_matches_target_payload(payload, target_path):
        text = json.dumps(payload or {}, sort_keys=True)
        lower = text.lower()
        if "gbrain live sync" not in lower:
            return False
        if "gbrain sync" not in lower or "gbrain embed --stale" not in lower:
            return False
        if target_path and target_path not in text:
            return False
        excluded = ["auto-update", "auto update", "dream cycle", "weekly health"]
        return not any(value in lower for value in excluded)

    def selected_runtime_live_sync_job_exists(runtime, runtime_executable, target_path):
        try:
            if runtime == "openclaw":
                result = subprocess.run(
                    [runtime_executable, "cron", "list", "--json"],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=20,
                )
                if result.returncode != 0:
                    return False, "live_sync_job_list_failed"
                payload = json.loads(result.stdout or "{}")
                if isinstance(payload, list):
                    jobs = payload
                elif isinstance(payload, dict):
                    if live_sync_job_matches_target_payload(payload, target_path):
                        jobs = [payload]
                    else:
                        jobs = payload.get("jobs") or []
                else:
                    jobs = []
                return any(live_sync_job_matches_target_payload(job, target_path) for job in jobs), "live_sync_job_missing"
            if runtime == "hermes":
                path = os.path.join(zebra_home_directory(), ".hermes", "cron", "jobs.json")
                with open(path, "r", encoding="utf-8") as handle:
                    payload = json.load(handle)
                jobs = payload.get("jobs") if isinstance(payload, dict) else []
                return any(live_sync_job_matches_target_payload(job, target_path) for job in jobs), "live_sync_job_missing"
        except Exception:
            return False, "live_sync_job_check_failed"
        return False, "live_sync_job_runtime_missing"

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

    def snapshot_section_bodies(state):
        snapshot = state.get("docsSnapshotPath")
        path = os.path.join(snapshot, "INSTALL_FOR_AGENTS.md") if snapshot else None
        if not path or not os.path.exists(path):
            return {}
        try:
            with open(path, "r", encoding="utf-8") as handle:
                text = handle.read()
        except Exception:
            return {}

        sections = {}
        current_title = None
        current_lines = []

        def finish():
            if current_title is None:
                return
            body = "\\n".join(current_lines)
            sections[current_title] = body

        for line in text.splitlines():
            if line.startswith("## "):
                finish()
                current_title = line[3:].strip()
                current_lines = [line]
            elif current_title is not None:
                current_lines.append(line)
        finish()
        return sections

    def section_entry(state, section_title):
        sections = manifest_install_sections(state)
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
        if normalized == "verify":
            return "verify"
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

    def recurring_jobs_title(title):
        normalized = normalize_title(title)
        return (
            "recurring job" in normalized
            or "recurring jobs" in normalized
            or "scheduler" in normalized
            or "autopilot" in normalized
            or "background sync" in normalized
            or "background job" in normalized
            or "background service" in normalized
            or "daemon" in normalized
        )

    def recurring_jobs_signature(body):
        text = (body or "").lower()
        return (
            "gbrain autopilot --install" in text
            or "autopilot --install" in text
            or "gbrain autopilot install" in text
            or "launchctl" in text
            or "crontab" in text
            or " cron " in (" " + text + " ")
            or "systemd" in text
            or " timer" in text
            or "scheduler" in text
            or "background service" in text
            or "background job" in text
            or "daemon" in text
        )

    def non_role_title(title):
        normalized = normalize_title(title)
        return (
            normalized.startswith("step 0 ")
            or normalized.startswith("step 4 5 ")
            or normalized.startswith("step 5 ")
            or normalized.startswith("step 6 ")
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
        if recurring_jobs_signature(body):
            return "recurring_jobs"
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
            if recurring_jobs_title(section.get("title")) or recurring_jobs_signature(section.get("body")):
                previous_roles.add("recurring_jobs")
            elif non_role_title(section.get("title")):
                previous_roles.add("")
            else:
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

        if recurring_jobs_title(entry.get("title")) or recurring_jobs_signature(entry.get("body")):
            role = "recurring_jobs"
            source = "recurring_jobs_title" if recurring_jobs_title(entry.get("title")) else "recurring_jobs_signature"
        elif non_role_title(entry.get("title")):
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
        if not entry.get("hash") or (non_role_title(entry.get("title")) and role != "recurring_jobs"):
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
        return bool(flags.get("embedding_decision") or flags.get("embedding_provider") or flags.get("embedding_key_env"))

    def apply_embedding_decision(state, flags):
        decision = flags.get("embedding_decision")
        if not decision:
            return None
        if decision not in allowed_embedding_decisions:
            return "invalid_embedding_decision"
        entry = {
            "decision": decision,
            "confirmedAt": now(),
        }
        if decision == "provider_key":
            provider = normalize_embedding_provider(flags.get("embedding_provider"))
            key_env_name = (flags.get("embedding_key_env") or "").strip()
            if not provider and key_env_name:
                provider = embedding_provider_for_env(key_env_name) or ""
            if not provider or provider not in embedding_provider_env_names:
                return "embedding_provider_required"
            expected_env_name = embedding_provider_env_names[provider]
            if key_env_name and key_env_name != expected_env_name:
                return "invalid_embedding_key_env"
            key_env_name = expected_env_name
            entry.update({
                "provider": provider,
                "keyEnvName": key_env_name,
            })
        progress = state.setdefault("progress", {})
        progress["embeddingDecision"] = entry
        return None

    def embedding_decision_recorded(state):
        progress = state.get("progress") or {}
        decision = progress.get("embeddingDecision") or {}
        value = decision.get("decision")
        if value == "defer_embeddings":
            return True
        if value == "provider_key":
            provider = normalize_embedding_provider(decision.get("provider"))
            key_env_name = decision.get("keyEnvName")
            return provider in embedding_provider_env_names and key_env_name == embedding_provider_env_names.get(provider)
        return False

    def topology_decision_flags_present(flags):
        return bool(flags.get("topology"))

    def apply_topology_decision(state, flags):
        topology = (flags.get("topology") or "").strip().lower()
        if not topology:
            return None
        if topology not in allowed_topology_decisions:
            return "invalid_topology_decision"
        progress = state.setdefault("progress", {})
        progress["topologyDecision"] = {
            "topology": topology,
            "confirmedAt": now(),
        }
        return None

    def topology_decision_value(state):
        progress = state.get("progress") or {}
        decision = progress.get("topologyDecision") or {}
        topology = decision.get("topology")
        return topology if topology in allowed_topology_decisions else None

    def search_mode_decision_flags_present(flags):
        return bool(flags.get("search_mode"))

    def apply_search_mode_decision(state, flags, section):
        mode = (flags.get("search_mode") or "").strip().lower()
        if not mode:
            return None
        if mode not in allowed_search_modes:
            return "invalid_search_mode"
        progress = state.setdefault("progress", {})
        progress["searchModeDecision"] = {
            "mode": mode,
            "sourceSection": section or None,
            "confirmedAt": now(),
        }
        return None

    def search_mode_decision(state):
        progress = state.get("progress") or {}
        decision = progress.get("searchModeDecision") or {}
        mode = decision.get("mode")
        if mode in allowed_search_modes:
            return decision
        return {}

    def recurring_jobs_decision_flags_present(flags):
        return bool(flags.get("recurring_jobs_decision"))

    def recurring_jobs_target_key(state):
        key, _, _, _ = resolved_target(state)
        return key or "__unresolved__"

    def apply_recurring_jobs_decision(state, flags):
        decision = flags.get("recurring_jobs_decision")
        if not decision:
            return None
        if decision not in allowed_recurring_jobs_decisions:
            return "invalid_recurring_jobs_decision"
        progress = state.setdefault("progress", {})
        key = recurring_jobs_target_key(state)
        decisions = progress.setdefault("recurringJobsDecisionByTarget", {})
        decisions[key] = {
            "decision": decision,
            "confirmedAt": now(),
            "targetKey": key,
        }
        return None

    def recurring_jobs_decision_value(state):
        progress = state.get("progress") or {}
        key = recurring_jobs_target_key(state)
        decisions = progress.get("recurringJobsDecisionByTarget") or {}
        decision = decisions.get(key) or {}
        value = decision.get("decision")
        return value if value in allowed_recurring_jobs_decisions else None

    def gbrain_runtime_state_path():
        explicit = os.environ.get("ZEBRA_GBRAIN_RUNTIME_STATE")
        if explicit:
            return os.path.abspath(os.path.expanduser(explicit))
        return os.path.join(os.path.dirname(state_path), "gbrain-runtime-state.json")

    def selected_runtime_receipt():
        runtime_state_path = gbrain_runtime_state_path()
        try:
            with open(runtime_state_path, "r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except Exception:
            raise RuntimeError("selected_runtime_receipt_missing")
        receipt = payload.get("receipt") or {}
        if receipt.get("complete") is not True:
            raise RuntimeError("selected_runtime_receipt_incomplete")
        runtime = receipt.get("runtime")
        if runtime not in {"openclaw", "hermes"}:
            raise RuntimeError("selected_runtime_missing")
        executable = receipt.get("executablePath")
        if not executable:
            raise RuntimeError("selected_runtime_executable_missing")
        executable = os.path.abspath(os.path.expanduser(executable))
        if not os.access(executable, os.X_OK):
            raise RuntimeError("selected_runtime_executable_missing")
        return {
            "runtime": runtime,
            "executablePath": executable,
            "statePath": runtime_state_path,
        }

    def run_platform_scheduler_command(argv, timeout=120):
        try:
            result = subprocess.run(
                argv,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout,
            )
            return {
                "ok": result.returncode == 0,
                "code": result.returncode,
                "stdoutTail": (result.stdout or "")[-2000:],
                "stderrTail": (result.stderr or "")[-2000:],
            }
        except subprocess.TimeoutExpired as exc:
            return {
                "ok": False,
                "code": 124,
                "stdoutTail": (exc.stdout or "")[-2000:] if isinstance(exc.stdout, str) else "",
                "stderrTail": (exc.stderr or "")[-2000:] if isinstance(exc.stderr, str) else "timeout",
            }
        except Exception as exc:
            return {
                "ok": False,
                "code": 1,
                "stdoutTail": "",
                "stderrTail": str(exc),
            }

    def platform_scheduler_status(runtime, executable):
        if runtime == "openclaw":
            return run_platform_scheduler_command(
                [executable, "gateway", "status", "--json", "--require-rpc", "--timeout", "5000"],
                timeout=20,
            )
        return run_platform_scheduler_command([executable, "gateway", "status"], timeout=20)

    def hermes_python_for_executable(executable):
        candidates = []
        for base in (executable, os.path.realpath(executable or "")):
            if not base:
                continue
            bin_dir = os.path.dirname(base)
            for name in ("python", "python3"):
                candidate = os.path.join(bin_dir, name)
                if candidate not in candidates:
                    candidates.append(candidate)
        hermes_home = os.path.abspath(os.path.expanduser(os.environ.get("ZEBRA_GBRAIN_HOME") or "~"))
        for name in ("python", "python3"):
            candidate = os.path.join(hermes_home, ".hermes", "hermes-agent", "venv", "bin", name)
            if candidate not in candidates:
                candidates.append(candidate)
        for candidate in candidates:
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                return candidate
        return None

    def hermes_gateway_liveness(executable):
        python = hermes_python_for_executable(executable)
        if not python:
            return {
                "ok": False,
                "code": 127,
                "stdoutTail": "",
                "stderrTail": "Hermes venv python not found next to executable",
            }
        return run_platform_scheduler_command(
            [
                python,
                "-c",
                "import json\\nfrom gateway.status import get_running_pid\\npid = get_running_pid()\\nprint(json.dumps({'running': pid is not None, 'pid': pid}))",
            ],
            timeout=20,
        )

    def platform_scheduler_ready(runtime, status_result):
        if runtime == "hermes":
            try:
                payload = json.loads(status_result.get("stdoutTail") or "{}")
            except Exception:
                return False
            if isinstance(payload, dict):
                return bool(payload.get("running"))
            return False
        return bool(status_result.get("ok"))

    def recorded_platform_scheduler_ready(state):
        progress = state.get("progress") or {}
        platform_scheduler = progress.get("platformScheduler") or {}
        if platform_scheduler.get("ready") is not True:
            return False
        try:
            runtime_receipt = selected_runtime_receipt()
        except Exception:
            return False
        return (
            platform_scheduler.get("runtime") == runtime_receipt.get("runtime")
            and platform_scheduler.get("executablePath") == runtime_receipt.get("executablePath")
        )

    def recurring_jobs_platform_completion_guard_reason(state):
        try:
            runtime_receipt = selected_runtime_receipt()
        except Exception:
            return "selected_runtime_receipt_missing"
        runtime = runtime_receipt.get("runtime")
        runtime_executable = runtime_receipt.get("executablePath")
        executable = gbrain_executable()
        target_key_value, target_path, _, target_entry = resolved_target(state)
        source_id = (target_entry or {}).get("sourceId")
        if not executable:
            return "missing_gbrain_executable"
        if not target_path or not os.path.isdir(os.path.abspath(os.path.expanduser(target_path))):
            return "receipt_target_missing"
        target_path = os.path.abspath(os.path.expanduser(target_path))
        if not source_id:
            return "source_not_registered"
        status_result = hermes_gateway_liveness(runtime_executable) if runtime == "hermes" else platform_scheduler_status(runtime, runtime_executable)
        if not platform_scheduler_ready(runtime, status_result):
            return "platform_scheduler_prepare_required"
        job_exists, job_reason = selected_runtime_live_sync_job_exists(runtime, runtime_executable, target_path)
        if not job_exists:
            return job_reason
        source_probe, current_source_id, listed_local_path, source_probe_reason = source_probe_status(executable, target_path, source_id)
        if source_probe != "verified":
            if source_probe == "mismatch":
                return "source_not_registered"
            return source_probe_reason or "source_probe_not_verified"
        return None

    def prepare_platform_scheduler():
        state = load_state()
        decision = recurring_jobs_decision_value(state)
        if os.environ.get("ZEBRA_GBRAIN_ALLOW_RECURRING_JOBS_INSTALL") != "1" and decision != "platform_scheduler_install":
            print("Zebra blocked platform scheduler preparation: recurring_jobs_decision=platform_scheduler_install is required before installing or starting runtime scheduler services.", file=sys.stderr)
            print("Run: zebra-gbrain-onboarding report --status waiting_for_user --section \\\"<section title>\\\" --reason recurring_jobs_decision", file=sys.stderr)
            sys.exit(78)

        runtime_receipt = selected_runtime_receipt()
        runtime = runtime_receipt["runtime"]
        executable = runtime_receipt["executablePath"]
        status_before = hermes_gateway_liveness(executable) if runtime == "hermes" else platform_scheduler_status(runtime, executable)
        install_result = None
        start_result = None
        status_after = status_before
        ready_before = platform_scheduler_ready(runtime, status_before)
        if not ready_before:
            if runtime == "openclaw":
                install_result = run_platform_scheduler_command([executable, "gateway", "install", "--json"], timeout=180)
                if install_result["ok"]:
                    start_result = run_platform_scheduler_command([executable, "gateway", "start"], timeout=60)
            else:
                install_result = run_platform_scheduler_command([executable, "gateway", "install"], timeout=180)
                if install_result["ok"]:
                    start_result = run_platform_scheduler_command([executable, "gateway", "start"], timeout=60)
            status_after = hermes_gateway_liveness(executable) if runtime == "hermes" else platform_scheduler_status(runtime, executable)

        ready_after = platform_scheduler_ready(runtime, status_after)
        ready = bool(ready_before or ready_after)
        state = load_state()
        progress = state.setdefault("progress", {})
        progress["platformScheduler"] = {
            "runtime": runtime,
            "executablePath": executable,
            "ready": ready,
            "alreadyRunning": bool(ready_before),
            "preparedAt": now(),
        }
        if ready:
            progress.pop("lastFailure", None)
        else:
            progress["lastFailure"] = "platform_scheduler_prepare_failed"
        save_state(state)

        print(json.dumps({
            "ok": ready,
            "runtime": runtime,
            "executablePath": executable,
            "statusBefore": status_before,
            "install": install_result,
            "start": start_result,
            "statusAfter": status_after,
            "nextRecommendedAction": "create runtime cron job" if ready else "inspect runtime gateway install/start output",
        }, sort_keys=True))
        if not ready:
            sys.exit(1)

    def launchd_clean_path():
        return "/usr/bin:/bin:/usr/sbin:/sbin"

    def launchd_style_bun_guard_reason():
        home = zebra_home_directory()
        env = {
            "HOME": home,
            "PATH": launchd_clean_path(),
        }
        try:
            result = subprocess.run(
                ["/bin/zsh", "-c", "bun --version"],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
        except FileNotFoundError:
            return "bun_unusable_for_launchd_autopilot"
        except Exception:
            return "bun_unusable_for_launchd_autopilot"
        if result.returncode == 0:
            return None
        combined = ((result.stdout or "") + "\\n" + (result.stderr or "")).lower()
        if "command not found" in combined or "no such file" in combined or "not found" in combined:
            return "bun_missing_for_launchd_autopilot"
        return "bun_unusable_for_launchd_autopilot"

    def launchd_bun_repair_payload(reason=None):
        payload = {
            "nextAction": "repair_launchd_bun_path",
            "suggestedCommand": "zebra-gbrain-onboarding repair-launchd-bun-path",
        }
        if reason:
            payload["repairReason"] = reason
        return payload

    def check_launchd_bun_path():
        reason = launchd_style_bun_guard_reason()
        if reason:
            payload = {
                "ok": False,
                "reason": reason,
                "status": "failed",
            }
            if reason == "bun_missing_for_launchd_autopilot":
                payload.update(launchd_bun_repair_payload(reason))
            print(json.dumps(payload, sort_keys=True))
            sys.exit(1)
        print(json.dumps({
            "ok": True,
            "status": "ready",
            "bunVersionOk": True,
        }, sort_keys=True))

    def repair_launchd_bun_path():
        home = zebra_home_directory()
        bun_path = os.path.join(home, ".bun", "bin", "bun")
        zshenv_path = os.path.join(home, ".zshenv")
        block = "\\n".join([
            "# >>> Zebra GBrain launchd bun PATH >>>",
            'if [ -d "$HOME/.bun/bin" ]; then',
            '  export PATH="$HOME/.bun/bin:$PATH"',
            "fi",
            "# <<< Zebra GBrain launchd bun PATH <<<",
            "",
        ])
        if not os.path.isfile(bun_path) or not os.access(bun_path, os.X_OK):
            print(json.dumps({
                "ok": False,
                "reason": "bun_missing",
                "bunPath": bun_path,
                "zshenvUpdated": False,
                "bunVersionOk": False,
            }, sort_keys=True))
            sys.exit(1)
        existing = ""
        if os.path.exists(zshenv_path):
            try:
                with open(zshenv_path, "r", encoding="utf-8") as handle:
                    existing = handle.read()
            except Exception as exc:
                print(json.dumps({
                    "ok": False,
                    "reason": "zshenv_read_failed",
                    "error": str(exc),
                    "zshenvPath": zshenv_path,
                }, sort_keys=True))
                sys.exit(1)
        zshenv_updated = False
        initial_bun_reason = launchd_style_bun_guard_reason()
        if initial_bun_reason and "# >>> Zebra GBrain launchd bun PATH >>>" not in existing:
            try:
                os.makedirs(os.path.dirname(zshenv_path), exist_ok=True)
                with open(zshenv_path, "a", encoding="utf-8") as handle:
                    if existing and not existing.endswith("\\n"):
                        handle.write("\\n")
                    handle.write(block)
                zshenv_updated = True
            except Exception as exc:
                print(json.dumps({
                    "ok": False,
                    "reason": "zshenv_write_failed",
                    "error": str(exc),
                    "zshenvPath": zshenv_path,
                    "zshenvUpdated": False,
                }, sort_keys=True))
                sys.exit(1)
        bun_reason = launchd_style_bun_guard_reason()
        if bun_reason:
            print(json.dumps({
                "ok": False,
                "reason": bun_reason,
                "bunPath": bun_path,
                "zshenvPath": zshenv_path,
                "zshenvUpdated": zshenv_updated,
                "bunVersionOk": False,
            }, sort_keys=True))
            sys.exit(1)
        print(json.dumps({
            "ok": True,
            "status": "repaired" if zshenv_updated else "already_configured",
            "bunPath": bun_path,
            "zshenvPath": zshenv_path,
            "zshenvUpdated": zshenv_updated,
            "bunVersionOk": True,
        }, sort_keys=True))

    def is_git_repo_root(path):
        try:
            result = subprocess.run(
                ["git", "-C", path, "rev-parse", "--show-toplevel"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
        except Exception:
            return False
        if result.returncode != 0:
            return False
        root = (result.stdout or "").strip()
        return bool(root) and os.path.realpath(root) == os.path.realpath(path)

    def git_has_status_entries(path):
        try:
            result = subprocess.run(
                ["git", "-C", path, "status", "--porcelain", "--untracked-files=all"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
        except Exception:
            return False
        return result.returncode == 0 and bool((result.stdout or "").strip())

    def create_initial_brain_commit():
        flags = parse_flags(args)
        target = flags.get("target") or flags.get("target_path")
        if not target:
            print(json.dumps({
                "ok": False,
                "reason": "brain_repo_target_missing",
                "target": "",
            }, sort_keys=True))
            sys.exit(1)
        target = os.path.abspath(os.path.expanduser(target))
        if not os.path.isdir(target):
            print(json.dumps({
                "ok": False,
                "reason": "brain_repo_target_missing",
                "target": target,
            }, sort_keys=True))
            sys.exit(1)
        if not is_git_repo_root(target):
            print(json.dumps({
                "ok": False,
                "reason": "brain_repo_not_git_repo",
                "target": target,
            }, sort_keys=True))
            sys.exit(1)
        existing_commit = git_head_commit(target)
        if existing_commit:
            print(json.dumps({
                "ok": True,
                "status": "already_committed",
                "target": target,
                "commit": existing_commit,
                "createdMarker": False,
                "identityMode": "none",
            }, sort_keys=True))
            return

        created_marker = False
        if not git_has_status_entries(target):
            marker_path = os.path.join(target, ".zebra-initialized")
            with open(marker_path, "w", encoding="utf-8") as handle:
                handle.write("Zebra initialized this brain repository so GBrain can sync from an initial git commit.\\n")
            created_marker = True

        add_result = subprocess.run(
            ["git", "-C", target, "add", "."],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        if add_result.returncode != 0:
            print(json.dumps({
                "ok": False,
                "reason": "brain_repo_initial_commit_add_failed",
                "target": target,
                "stderr": (add_result.stderr or "").strip(),
            }, sort_keys=True))
            sys.exit(1)

        commit_result = subprocess.run(
            [
                "git", "-C", target,
                "-c", "user.name=Zebra Onboarding",
                "-c", "user.email=zebra-onboarding@offlight.local",
                "commit",
                "-m", "Initialize brain repo for GBrain sync",
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        if commit_result.returncode != 0:
            print(json.dumps({
                "ok": False,
                "reason": "brain_repo_initial_commit_failed",
                "target": target,
                "createdMarker": created_marker,
                "identityMode": "inline_zebra",
                "stderr": (commit_result.stderr or "").strip(),
            }, sort_keys=True))
            sys.exit(1)

        commit = git_head_commit(target)
        if not commit:
            print(json.dumps({
                "ok": False,
                "reason": "brain_repo_initial_commit_verify_failed",
                "target": target,
                "createdMarker": created_marker,
                "identityMode": "inline_zebra",
            }, sort_keys=True))
            sys.exit(1)
        print(json.dumps({
            "ok": True,
            "status": "created",
            "target": target,
            "commit": commit,
            "createdMarker": created_marker,
            "identityMode": "inline_zebra",
        }, sort_keys=True))

    def record_verified_source_id(state, flags):
        key, target_path, _, target_entry = resolved_target(state)
        if not key or not target_path or not target_entry:
            return "brain_repo_target_unresolved"
        source_id = flags.get("source_id") or target_entry.get("sourceId")
        if not source_id:
            return "source_not_registered"
        receipt = state.setdefault("receipt", {})
        targets = receipt.setdefault("targets", {})
        target_entry = targets.setdefault(key, target_entry)
        target_entry["vaultPath"] = target_path
        target_entry["sourceId"] = source_id
        profile_id = flags.get("profile_id")
        if profile_id:
            target_entry["profileId"] = profile_id
        executable = gbrain_executable()
        target_entry["sourceVerification"] = {
            "sourceId": source_id,
            "targetPath": target_path,
            "verifiedAt": now(),
            "method": "sources_current_and_list",
            "gbrainExecutablePath": executable,
            "gbrainVersion": gbrain_version_string(executable),
        }
        if not receipt.get("primaryTargetKey"):
            receipt["primaryTargetKey"] = key
        return None

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
        if role == "credentials":
            return ["embedding_provider_required"]
        if role == "create_brain":
            return ["topology_resolution", "brain_repo_target_resolution"]
        if role == "recurring_jobs":
            return ["recurring_jobs_decision"]
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

    def onboarding_language():
        raw = (os.environ.get("ZEBRA_ONBOARDING_LANGUAGE") or "en").lower().replace("_", "-")
        if raw == "ko" or raw.startswith("ko-"):
            return "ko"
        if raw == "ja" or raw.startswith("ja-"):
            return "ja"
        return "en"

    def target_option_descriptions(recommended):
        language = onboarding_language()
        if language == "ko":
            return [
                f"{recommended}에 새 brain repo를 만듭니다 (recommended)",
                "사용자가 제공하는 기존 markdown/brain repo path를 사용합니다",
                "custom path에 새 brain repo를 만듭니다",
            ]
        if language == "ja":
            return [
                f"{recommended}に新しいbrain repoを作成します (recommended)",
                "ユーザーが指定する既存のmarkdown/brain repo pathを使用します",
                "custom pathに新しいbrain repoを作成します",
            ]
        return [
            f"Create a new brain repo at {recommended} (recommended)",
            "Use an existing markdown/brain repo path that the user provides",
            "Create a new brain repo at a custom path",
        ]

    def target_resolution_next_action():
        recommended = recommended_brain_repo_path()
        descriptions = target_option_descriptions(recommended)
        return {
            "nextAction": "ask_user_for_brain_repo_target",
            "nextPrompt": brain_repo_target_prompt_text(),
            "targetPrompt": brain_repo_target_prompt_text(),
            "targetOptions": [
                {
                    "reply": "1",
                    "description": descriptions[0],
                    "path": recommended,
                    "method": "user_created_repo",
                },
                {
                    "reply": "2 <path>",
                    "description": descriptions[1],
                    "method": "user_existing_repo",
                },
                {
                    "reply": "3 <path>",
                    "description": descriptions[2],
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

    def git_head_commit(path):
        if not path or not os.path.isdir(path):
            return None
        try:
            result = subprocess.run(
                ["git", "-C", path, "rev-parse", "--verify", "HEAD"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
        except Exception:
            return None
        if result.returncode != 0:
            return None
        return (result.stdout or "").strip() or None

    def user_created_brain_repo_initial_commit_guard_reason(state):
        _, target_path, method, _ = resolved_target(state)
        if method != "user_created_repo":
            return None
        if not target_path or not os.path.isdir(target_path):
            return None
        target_path = os.path.abspath(os.path.expanduser(target_path))
        if not is_git_repo_root(target_path):
            return None
        if git_head_commit(target_path):
            return None
        return "brain_repo_initial_commit_missing"

    def create_initial_brain_commit_payload(target):
        return {
            "nextAction": "create_initial_brain_commit",
            "suggestedCommand": "zebra-gbrain-onboarding create-initial-brain-commit --target " + shell_quote(target),
        }

    def gbrain_version_ok():
        state = load_state()
        binding = state.get("activeGBrainBinding") or {}
        executable = global_gbrain_executable(state) if binding.get("sourceRepoPath") else gbrain_executable()
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

    def gbrain_version_string(executable):
        if not executable:
            return None
        try:
            result = subprocess.run(
                [executable, "--version"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            if result.returncode == 0:
                return (result.stdout or result.stderr or "").strip() or None
        except Exception:
            return None
        return None

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

    def bounded_text(value, limit=2000):
        text = (value or "").strip()
        if len(text) <= limit:
            return text
        return text[-limit:]

    def create_brain_doctor_diagnostics(state):
        executable = gbrain_executable()
        if not executable:
            return {
                "doctorEffectiveOk": False,
                "doctorFailedChecks": ["missing_gbrain_executable"],
                "doctorCwd": None,
                "doctorExitCode": None,
                "doctorError": "missing_gbrain_executable",
            }
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
            ok, maintenance_pending = doctor_allows_create_or_import_progress(result)
            diagnostics = {
                "doctorEffectiveOk": ok,
                "doctorMaintenancePending": maintenance_pending,
                "doctorFailedChecks": doctor_failed_checks(result),
                "doctorCwd": cwd,
                "doctorExitCode": result.returncode,
            }
            stderr = bounded_text(result.stderr)
            if stderr:
                diagnostics["doctorStderrTail"] = stderr
            return diagnostics
        except subprocess.TimeoutExpired as exc:
            return {
                "doctorEffectiveOk": False,
                "doctorFailedChecks": ["doctor_timeout"],
                "doctorCwd": cwd,
                "doctorExitCode": None,
                "doctorError": "doctor_timeout",
                "doctorStderrTail": bounded_text(exc.stderr if isinstance(exc.stderr, str) else ""),
            }
        except Exception:
            return {
                "doctorEffectiveOk": False,
                "doctorFailedChecks": ["doctor_failed"],
                "doctorCwd": cwd,
                "doctorExitCode": None,
                "doctorError": "doctor_failed",
            }

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
        if status == "mismatch":
            return "source_not_registered"
        return transient_reason or SOURCE_PROBE_RUNTIME_ERROR_REASON

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
        if extra_payload and reason == "doctor_failed":
            progress["lastFailureDetails"] = extra_payload
        else:
            progress.pop("lastFailureDetails", None)
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
        elif reason == "recurring_jobs_decision_required":
            set_waiting_for_user(progress, section, "recurring_jobs_decision", "Choose defer, manual_scheduler, platform_scheduler_install, or autopilot_install.")
        elif reason == "embedding_provider_required":
            set_waiting_for_user(progress, section, "embedding_provider_required", "Choose ZEROENTROPY_API_KEY, OPENAI_API_KEY, VOYAGE_API_KEY, or defer embeddings.")
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
        elif reason == "embedding_provider_required":
            payload.update({
                "nextAction": "choose_embedding_provider",
                "embeddingProviderPrompt": embedding_provider_decision_options(),
            })
        elif reason == "bun_missing_for_launchd_autopilot":
            payload.update(launchd_bun_repair_payload(reason))
        elif reason == "brain_repo_initial_commit_missing":
            _, target_path, _, _ = resolved_target(state)
            payload.update(create_initial_brain_commit_payload(target_path or "<brain repo path>"))
        elif next_action:
            payload["nextAction"] = next_action
        print(json.dumps(payload, sort_keys=True))
        sys.exit(1)

    def report_guard_reason(state, status, role, flags, guard_context=None):
        if status not in {"started", "completed"}:
            return None
        roles = completed_roles(state)
        target_reasons = target_guard_reasons(state)
        if role == "unknown" and status == "completed":
            return "section_role_unknown"
        if role == "install" and status == "completed" and not gbrain_version_ok():
            return "gbrain_version_failed"
        if role == "credentials" and status == "completed" and not embedding_decision_recorded(state):
            return "embedding_provider_required"
        if role == "create_brain" and status == "completed":
            if not topology_decision_value(state):
                return "topology_decision_required"
            if target_reasons:
                return target_reasons[0]
            if not embedding_decision_recorded(state):
                return "embedding_provider_required"
            doctor_diagnostics = create_brain_doctor_diagnostics(state)
            if guard_context is not None:
                guard_context["doctor_diagnostics"] = doctor_diagnostics
            if doctor_diagnostics.get("doctorEffectiveOk") is not True:
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
                initial_commit_reason = user_created_brain_repo_initial_commit_guard_reason(state)
                if initial_commit_reason:
                    return initial_commit_reason
                source_reason = source_registration_guard_reason(state, flags)
                if source_reason:
                    return source_reason
        if role == "recurring_jobs" and status == "completed":
            recurring_jobs_decision = recurring_jobs_decision_value(state)
            if not recurring_jobs_decision:
                return "recurring_jobs_decision_required"
            if recurring_jobs_decision == "autopilot_install":
                bun_reason = launchd_style_bun_guard_reason()
                if bun_reason:
                    return bun_reason
            if recurring_jobs_decision == "platform_scheduler_install" and not recorded_platform_scheduler_ready(state):
                return "platform_scheduler_prepare_required"
            if recurring_jobs_decision == "platform_scheduler_install":
                platform_completion_reason = recurring_jobs_platform_completion_guard_reason(state)
                if platform_completion_reason:
                    return platform_completion_reason
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
        if reason == "embedding_provider_required":
            return role == "credentials" and status == "completed" and embedding_decision_recorded(state)
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
        if topology_decision_flags_present(flags):
            if not (role == "create_brain" and status == "completed"):
                reject_report(state, "topology_decision_flags_not_allowed", section, status)
            topology_error = apply_topology_decision(candidate_state, flags)
            if topology_error:
                reject_report(state, topology_error, section, status)
        if search_mode_decision_flags_present(flags):
            if not (role in {"create_brain", "search_mode"} and status == "completed"):
                reject_report(state, "search_mode_flags_not_allowed", section, status)
            search_mode_error = apply_search_mode_decision(candidate_state, flags, section)
            if search_mode_error:
                reject_report(state, search_mode_error, section, status)
        if recurring_jobs_decision_flags_present(flags):
            if not (role == "recurring_jobs" and status in {"started", "completed"}):
                reject_report(state, "recurring_jobs_decision_flags_not_allowed", section, status)
            recurring_jobs_error = apply_recurring_jobs_decision(candidate_state, flags)
            if recurring_jobs_error:
                reject_report(state, recurring_jobs_error, section, status)
        guard_context = {}
        guard_reason = report_guard_reason(candidate_state, status, role, flags, guard_context)
        if guard_reason:
            next_action = None
            extra_payload = None
            if guard_reason == "section_role_unknown":
                next_action = "report mapped_role with role and evidence, or report waiting_for_user"
            elif guard_reason in {
                "brain_repo_target_unresolved",
                "target_confirmation_missing",
                "implicit_home_target",
                "onboarding_work_directory_target",
            }:
                next_action = "report waiting_for_user for brain_repo_target_resolution"
            elif guard_reason == "recurring_jobs_decision_required":
                next_action = "report waiting_for_user for recurring_jobs_decision"
            elif guard_reason == "doctor_failed" and role == "create_brain" and status == "completed":
                extra_payload = guard_context.get("doctor_diagnostics")
            reject_report(state, guard_reason, section, status, next_action=next_action, extra_payload=extra_payload)
        if role == "import_index" and status == "completed":
            source_record_error = record_verified_source_id(candidate_state, flags)
            if source_record_error:
                reject_report(state, source_record_error, section, status)

        state = candidate_state
        progress = state.setdefault("progress", {})
        if section and status != "completed":
            progress["nextSection"] = section
        if status == "completed" and section:
            completed = progress.setdefault("completedSections", [])
            if section not in completed:
                completed.append(section)
            progress["nextSection"] = next_section_title(state)
        waiting_reason_value = None
        if status == "waiting_for_user":
            waiting_reason_value = flags.get("reason") or "user_input_required"
            set_waiting_for_user(progress, section, waiting_reason_value, note)
        elif should_clear_waiting_for_user(state, progress, status, role, flags, section):
            progress.pop("waitingForUser", None)
        if status == "failed":
            progress["lastFailure"] = note or section or "failed"
            progress.pop("lastFailureDetails", None)
        elif status in ("started", "completed", "skipped", "deferred"):
            progress.pop("lastFailure", None)
            progress.pop("lastFailureDetails", None)
        progress["lastStatus"] = status
        progress["updatedAt"] = now()
        payload = {"ok": True, "status": status, "section": section}
        if status == "completed":
            payload.update(next_prompt_payload(state))
        save_state(state)
        if waiting_reason_value == "brain_repo_target_resolution":
            payload.update(target_resolution_next_action())
        print(json.dumps(payload, sort_keys=True))

    def status():
        print(json.dumps(load_state(), indent=2, sort_keys=True))

    def source_verification_matches(target_entry, target, source_id):
        verification = (target_entry or {}).get("sourceVerification") or {}
        if verification.get("method") not in {
            "sources_current_and_list",
            "existing_install_sources_current_and_list",
            "existing_install_remote_sources_list",
        }:
            return False
        if verification.get("sourceId") != source_id:
            return False
        verified_path = verification.get("targetPath")
        if not verified_path or not target:
            return False
        return os.path.abspath(os.path.expanduser(verified_path)) == os.path.abspath(os.path.expanduser(target))

    def gbrain_config_dir():
        home_override = os.environ.get("GBRAIN_HOME")
        if home_override and home_override.strip():
            return os.path.join(os.path.abspath(os.path.expanduser(home_override)), ".gbrain")
        home = os.environ.get("HOME") or os.path.expanduser("~")
        return os.path.join(os.path.abspath(os.path.expanduser(home)), ".gbrain")

    def gbrain_config_path():
        return os.path.join(gbrain_config_dir(), "config.json")

    def gbrain_config_file():
        try:
            with open(gbrain_config_path(), "r", encoding="utf-8") as handle:
                payload = json.load(handle)
            return payload if isinstance(payload, dict) else {}
        except Exception:
            return {}

    def gbrain_env_path():
        return os.path.join(gbrain_home_directory(), ".gbrain", ".env")

    def parse_env_file(path):
        values = {}
        try:
            with open(path, "r", encoding="utf-8") as handle:
                for raw_line in handle:
                    line = raw_line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    key, value = line.split("=", 1)
                    key = key.strip()
                    value = value.strip()
                    if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", key):
                        continue
                    if (
                        len(value) >= 2
                        and ((value[0] == value[-1] == "'") or (value[0] == value[-1] == '"'))
                    ):
                        value = value[1:-1]
                    values[key] = value
        except FileNotFoundError:
            pass
        except Exception:
            pass
        return values

    def gbrain_env_values():
        return parse_env_file(gbrain_env_path())

    def process_env_with_gbrain_env():
        env = os.environ.copy()
        for key, value in gbrain_env_values().items():
            if value and not env.get(key):
                env[key] = value
        return env

    def normalize_embedding_provider(provider):
        raw = (provider or "").strip().lower()
        if raw in {"zeroentropy", "zero-entropy", "zero_entropy", "ze", "zeroentropy_api_key", "zeroentropy-api-key"}:
            return "zeroentropy"
        if raw in {"openai", "openai_api_key", "openai-api-key"}:
            return "openai"
        if raw in {"voyage", "voyageai", "voyage_ai", "voyage_api_key", "voyage-api-key"}:
            return "voyage"
        return raw

    def embedding_provider_for_env(env_name):
        for provider, candidate_env_name in embedding_provider_env_names.items():
            if candidate_env_name == env_name:
                return provider
        return None

    def doctor_failed_checks(result):
        if result.returncode == 0:
            return []
        try:
            payload = json.loads(result.stdout or "{}")
        except Exception:
            return ["doctor_failed"]
        checks = payload.get("checks") or []
        failed = []
        for check in checks:
            status = str(check.get("status") or "").lower()
            if status in {"fail", "failed", "error"}:
                failed.append(check.get("name") or "unknown")
        return failed or ["doctor_failed"]

    def syncable_markdown_sample(target):
        if not target or not os.path.isdir(target):
            return None
        excluded_names = {"README.md", "index.md", "schema.md", "log.md"}
        for root_dir, dirs, files in os.walk(target):
            rel_root = os.path.relpath(root_dir, target)
            parts = [] if rel_root == "." else rel_root.split(os.sep)
            if any(part.startswith(".") for part in parts):
                dirs[:] = []
                continue
            dirs[:] = [
                d for d in dirs
                if not d.startswith(".") and d not in {".raw", "ops"}
            ]
            if ".raw" in parts or "ops" in parts:
                continue
            for name in sorted(files):
                if not name.endswith(".md") or name in excluded_names:
                    continue
                path = os.path.join(root_dir, name)
                try:
                    with open(path, "r", encoding="utf-8") as handle:
                        for line in handle:
                            text = " ".join((line or "").strip().split())
                            if len(text) >= 12 and not text.startswith("---"):
                                return text[:80]
                except Exception:
                    continue
        return None

    def parse_gbrain_stats(stdout):
        stats = {}
        for line in (stdout or "").splitlines():
            if ":" not in line:
                continue
            key, raw_value = line.split(":", 1)
            normalized = key.strip().lower()
            digits = "".join(ch for ch in raw_value if ch.isdigit())
            if digits:
                stats[normalized] = int(digits)
        return stats

    def run_install_probes(executable, target):
        probes = {
            "sync": {"ok": False, "status": "not_run"},
            "stats": {"ok": False, "status": "not_run"},
            "embedding": {"ok": False, "status": "not_run"},
            "search": {"ok": False, "status": "not_run"},
        }
        reasons = []

        try:
            sync_result = subprocess.run(
                [executable, "config", "get", "sync.last_run"],
                cwd=target if target and os.path.isdir(target) else None,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
            sync_value = (sync_result.stdout or "").strip()
            sync_ok = sync_result.returncode == 0 and bool(sync_value)
            probes["sync"] = {"ok": sync_ok, "status": "ok" if sync_ok else "missing_sync_last_run"}
            if not sync_ok:
                reasons.append("sync_not_verified")
        except Exception:
            probes["sync"] = {"ok": False, "status": "sync_probe_failed"}
            reasons.append("sync_not_verified")

        stats_payload = {}
        try:
            stats_result = subprocess.run(
                [executable, "stats"],
                cwd=target if target and os.path.isdir(target) else None,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
            stats_payload = parse_gbrain_stats(stats_result.stdout)
            stats_ok = stats_result.returncode == 0 and bool(stats_payload)
            probes["stats"] = {"ok": stats_ok, "status": "ok" if stats_ok else "stats_probe_failed", "stats": stats_payload}
            chunks = stats_payload.get("chunks")
            embedded = stats_payload.get("embedded")
            if stats_ok and chunks is not None and embedded is not None and (chunks == 0 or embedded >= chunks):
                probes["embedding"] = {"ok": True, "status": "ok", "chunks": chunks, "embedded": embedded}
            else:
                probes["embedding"] = {"ok": False, "status": "embedding_backlog", "chunks": chunks, "embedded": embedded}
                reasons.append("embedding_not_verified")
            if not stats_ok:
                reasons.append("stats_not_verified")
        except Exception:
            probes["stats"] = {"ok": False, "status": "stats_probe_failed"}
            probes["embedding"] = {"ok": False, "status": "stats_probe_failed"}
            reasons.extend(["stats_not_verified", "embedding_not_verified"])

        sample = syncable_markdown_sample(target)
        if not sample:
            probes["search"] = {"ok": True, "status": "skipped_no_content"}
        else:
            try:
                search_result = subprocess.run(
                    [executable, "search", sample],
                    cwd=target if target and os.path.isdir(target) else None,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=30,
                )
                output = (search_result.stdout or "").strip()
                search_ok = search_result.returncode == 0 and bool(output) and output.lower() != "no results."
                probes["search"] = {"ok": search_ok, "status": "ok" if search_ok else "no_results", "sample": sample}
                if not search_ok:
                    reasons.append("search_not_verified")
            except Exception:
                probes["search"] = {"ok": False, "status": "search_probe_failed", "sample": sample}
                reasons.append("search_not_verified")

        return probes, reasons

    def search_output_has_hit(output):
        text = (output or "").strip()
        if not text:
            return False
        if text.lower() in {"no results", "no results."}:
            return False
        try:
            payload = json.loads(text)
        except Exception:
            return True
        if isinstance(payload, list):
            return len(payload) > 0
        if isinstance(payload, dict):
            for key in ["results", "hits", "matches", "items"]:
                if key in payload:
                    value = payload.get(key)
                    if isinstance(value, list):
                        return len(value) > 0
                    return bool(value)
            for key in ["count", "total", "totalResults"]:
                if key not in payload:
                    continue
                count = payload.get(key)
                if isinstance(count, (int, float)):
                    return count > 0
                if isinstance(count, str) and count.strip().isdigit():
                    return int(count.strip()) > 0
                return bool(count)
        return bool(payload)

    def existing_install_has_only_transient_reasons(reasons):
        return bool(reasons) and all(reason == PGLITE_BUSY_REASON for reason in reasons)

    def existing_install_admin_diagnostic_unavailable(text):
        lower = (text or "").lower()
        return (
            "remote snapshot failed" in lower
            or ("insufficient_scope" in lower and "admin" in lower)
            or ("requires 'admin' scope" in lower)
            or ("requires admin scope" in lower)
            or ("admin scope" in lower and "required" in lower)
        )

    def existing_install_remote_mcp_url(payload):
        found = []
        def visit(value, key_hint=""):
            if isinstance(value, dict):
                for key, child in value.items():
                    visit(child, str(key))
            elif isinstance(value, list):
                for child in value:
                    visit(child, key_hint)
            elif isinstance(value, str):
                text = value.strip()
                lower_key = (key_hint or "").lower()
                if text.startswith("http") and ("/mcp" in text or "mcp" in lower_key):
                    found.append(text)
        visit(payload)
        return found[0] if found else None

    def existing_install_remote_has_read_write(payload):
        scopes = set()
        def visit(value, key_hint=""):
            lower_key = (key_hint or "").lower()
            if isinstance(value, dict):
                for key, child in value.items():
                    normalized_key = "".join(ch for ch in str(key).lower() if ch.isalnum())
                    if child is True and normalized_key in {"read", "canread", "readaccess", "readpermission"}:
                        scopes.add("read")
                    if child is True and normalized_key in {"write", "canwrite", "writeaccess", "writepermission"}:
                        scopes.add("write")
                    visit(child, str(key))
            elif isinstance(value, list):
                for child in value:
                    visit(child, key_hint)
            elif isinstance(value, str):
                lower_value = value.strip().lower()
                if lower_value in {"read", "write"} and any(token in lower_key for token in ["scope", "capabilit", "permission", "access"]):
                    scopes.add(lower_value)
        visit(payload)
        if {"read", "write"}.issubset(scopes):
            return True
        text = json.dumps(payload).lower()
        return '"read"' in text and '"write"' in text and any(token in text for token in ["scope", "capabilit", "permission", "access"])

    def existing_install_remote_target_probe(executable, target):
        try:
            result = subprocess.run(
                [executable, "status", "--json"],
                cwd=target if target and os.path.isdir(target) else None,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
        except subprocess.TimeoutExpired:
            return {"ok": False, "adapter": "remote", "status": "transient", "reason": PGLITE_BUSY_REASON}
        except Exception:
            return {"ok": False, "adapter": "remote", "status": "error", "reason": "remote_status_failed"}
        if result.returncode != 0:
            reason = transient_probe_reason((result.stderr or "") + "\\n" + (result.stdout or "")) or "remote_status_failed"
            return {"ok": False, "adapter": "remote", "status": "error", "reason": reason}
        try:
            payload = json.loads(result.stdout or "{}")
        except Exception:
            return {"ok": False, "adapter": "remote", "status": "error", "reason": "remote_status_invalid_json"}
        remote_mcp_url = existing_install_remote_mcp_url(payload)
        read_write_ok = existing_install_remote_has_read_write(payload)
        warnings = []
        warning_text = json.dumps(payload.get("warnings") if isinstance(payload, dict) else []) + "\\n" + (result.stderr or "")
        if existing_install_admin_diagnostic_unavailable(warning_text):
            warnings.append("remote_admin_diagnostic_unavailable")
        reasons = []
        if not remote_mcp_url:
            reasons.append("remote_mcp_target_missing")
        if not read_write_ok:
            reasons.append("remote_read_write_not_verified")
        return {
            "ok": not reasons,
            "adapter": "remote",
            "status": "verified" if not reasons else "mismatch",
            "method": "existing_install_thin_client_status",
            "remoteMCPURL": remote_mcp_url,
            "readWriteOk": read_write_ok,
            "warnings": warnings,
            "reasons": reasons,
            "reason": reasons[0] if reasons else None,
        }

    def existing_install_has_thin_client_source_refusal(source_probe_attempts):
        return any(
            attempt.get("reason") == "sources_cli_not_routable"
            for attempt in (source_probe_attempts or [])
        )

    def existing_install_source_probe_admin_diagnostic_unavailable(source_probe):
        return (source_probe or {}).get("reason") in {
            "remote_status_snapshot_failed",
            "remote_admin_diagnostic_unavailable",
        }

    def existing_install_as_thin_client_read_verified(source_probe, source_probe_attempts, source_id):
        return {
            "ok": True,
            "adapter": "remote",
            "status": "verified_with_admin_diagnostic_unavailable",
            "method": "existing_install_thin_client_read_probe",
            "sourceId": source_id,
            "warning": "remote_admin_diagnostic_unavailable",
            "diagnosticSourceProbe": source_probe,
            "sourceProbeAttempts": source_probe_attempts,
        }

    def existing_install_read_probe(executable, target):
        sample = syncable_markdown_sample(target) or "zebra gbrain existing install verification"
        try:
            result = subprocess.run(
                [executable, "search", sample],
                cwd=target if target and os.path.isdir(target) else None,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            output = (result.stdout or "").strip()
            ok = result.returncode == 0 and search_output_has_hit(output)
            reason = None if ok else (transient_probe_reason((result.stderr or "") + "\\n" + (result.stdout or "")) or "read_probe_failed")
            return {
                "ok": ok,
                "status": "ok" if ok else reason,
                "sample": sample,
            }, reason
        except subprocess.TimeoutExpired:
            return {"ok": False, "status": PGLITE_BUSY_REASON, "sample": sample}, PGLITE_BUSY_REASON
        except Exception:
            return {"ok": False, "status": "read_probe_failed", "sample": sample}, "read_probe_failed"

    def existing_install_direct_source_probe(executable, target, source_id):
        current_ok, current_payload, current_error = run_json(
            [executable, "sources", "current", "--json"],
            cwd=target,
            timeout=12,
        )
        if not current_ok:
            lower_error = (current_error or "").lower()
            if "not routable" in lower_error or "remote_mcp" in lower_error or "remote mcp" in lower_error:
                return {
                    "ok": False,
                    "adapter": "direct",
                    "status": "unsupported",
                    "reason": "sources_cli_not_routable",
                }
            reason = transient_probe_reason(current_error)
            if reason:
                return {"ok": False, "adapter": "direct", "status": "transient", "reason": reason}
            if source_missing_probe_failure(current_error):
                return {"ok": False, "adapter": "direct", "status": "mismatch", "reason": "source_not_registered"}
            return {"ok": False, "adapter": "direct", "status": "error", "reason": probe_failure_reason(current_error)}

        current_source_id = current_payload.get("source_id")
        expected_source_id = source_id or current_source_id
        if not expected_source_id:
            return {
                "ok": False,
                "adapter": "direct",
                "status": "mismatch",
                "reason": "source_not_registered",
                "currentSourceId": current_source_id,
            }
        if current_source_id != expected_source_id:
            return {
                "ok": False,
                "adapter": "direct",
                "status": "mismatch",
                "reason": "source_not_registered",
                "currentSourceId": current_source_id,
                "sourceId": expected_source_id,
            }

        list_ok, list_payload, list_error = run_json(
            [executable, "sources", "list", "--json"],
            cwd=target,
            timeout=12,
        )
        if not list_ok:
            reason = transient_probe_reason(list_error)
            if reason:
                return {"ok": False, "adapter": "direct", "status": "transient", "reason": reason, "sourceId": expected_source_id}
            if source_missing_probe_failure(list_error):
                return {"ok": False, "adapter": "direct", "status": "mismatch", "reason": "source_not_registered", "sourceId": expected_source_id}
            return {"ok": False, "adapter": "direct", "status": "error", "reason": probe_failure_reason(list_error), "sourceId": expected_source_id}
        listed_local_path = source_list_local_path(list_payload, expected_source_id)
        if not listed_local_path or os.path.abspath(os.path.expanduser(listed_local_path)) != os.path.abspath(target):
            return {
                "ok": False,
                "adapter": "direct",
                "status": "mismatch",
                "reason": "source_not_registered",
                "sourceId": expected_source_id,
                "currentSourceId": current_source_id,
                "localPath": listed_local_path,
            }
        return {
            "ok": True,
            "adapter": "direct",
            "status": "verified",
            "method": "existing_install_sources_current_and_list",
            "sourceId": expected_source_id,
            "currentSourceId": current_source_id,
            "localPath": listed_local_path,
        }

    def collect_source_entries(payload):
        entries = []
        def visit(value):
            if isinstance(value, dict):
                has_source_shape = (
                    ("id" in value or "source_id" in value)
                    and ("local_path" in value or "localPath" in value or "path" in value)
                )
                if has_source_shape:
                    entries.append(value)
                for child in value.values():
                    visit(child)
            elif isinstance(value, list):
                for child in value:
                    visit(child)
        visit(payload)
        return entries

    def existing_install_remote_source_probe(executable, target, source_id):
        try:
            result = subprocess.run(
                [executable, "status", "--json"],
                cwd=target if target and os.path.isdir(target) else None,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
        except subprocess.TimeoutExpired:
            return {"ok": False, "adapter": "remote", "status": "transient", "reason": PGLITE_BUSY_REASON}
        except Exception:
            return {"ok": False, "adapter": "remote", "status": "error", "reason": "remote_status_failed"}
        if result.returncode != 0:
            reason = transient_probe_reason((result.stderr or "") + "\\n" + (result.stdout or "")) or "remote_status_failed"
            return {"ok": False, "adapter": "remote", "status": "error", "reason": reason}
        try:
            payload = json.loads(result.stdout or "{}")
        except Exception:
            return {"ok": False, "adapter": "remote", "status": "error", "reason": "remote_status_invalid_json"}
        warnings = payload.get("warnings") if isinstance(payload, dict) else None
        warning_text = json.dumps(warnings or []) + "\\n" + (result.stderr or "")
        if existing_install_admin_diagnostic_unavailable(warning_text):
            return {"ok": False, "adapter": "remote", "status": "error", "reason": "remote_status_snapshot_failed"}
        target_abs = os.path.abspath(os.path.expanduser(target))
        for entry in collect_source_entries(payload):
            entry_source_id = entry.get("id") or entry.get("source_id")
            local_path = entry.get("local_path") or entry.get("localPath") or entry.get("path")
            if not local_path:
                continue
            if os.path.abspath(os.path.expanduser(local_path)) != target_abs:
                continue
            if source_id and entry_source_id and entry_source_id != source_id:
                continue
            resolved_source_id = source_id or entry_source_id
            if not resolved_source_id:
                continue
            return {
                "ok": True,
                "adapter": "remote",
                "status": "verified",
                "method": "existing_install_remote_sources_list",
                "sourceId": resolved_source_id,
                "localPath": local_path,
            }
        return {
            "ok": False,
            "adapter": "remote",
            "status": "mismatch",
            "reason": "source_binding_not_verified",
            "sourceId": source_id,
        }

    def existing_install_source_probe(executable, target, source_id):
        direct = existing_install_direct_source_probe(executable, target, source_id)
        if direct.get("ok"):
            return direct, [direct]
        attempts = [direct]
        if direct.get("reason") == "sources_cli_not_routable":
            remote = existing_install_remote_source_probe(executable, target, source_id)
            attempts.append(remote)
            if remote.get("ok"):
                return remote, attempts
            return remote, attempts
        return direct, attempts

    def existing_install_verify_command(target, method, source_id=None):
        command = "zebra-gbrain-onboarding verify-existing-install"
        if target:
            command += " --target " + shell_quote(target)
        command += " --method " + shell_quote(method or ("selected_vault" if target else "thin_client_remote"))
        if source_id:
            command += " --source-id " + shell_quote(source_id)
        return command

    def existing_install_diagnose_command(target, method, source_id=None):
        command = "zebra-gbrain-onboarding diagnose-existing-install-failure"
        if target:
            command += " --target " + shell_quote(target)
        command += " --method " + shell_quote(method or ("selected_vault" if target else "thin_client_remote"))
        if source_id:
            command += " --source-id " + shell_quote(source_id)
        return command

    def existing_install_next_action(target, method, source_id=None):
        return {
            "kind": "diagnose_existing_install_failure",
            "command": existing_install_diagnose_command(target, method, source_id),
            "instruction": "Run this command before choosing a repair path. Treat the installed gbrain CLI output as the primary authority, then rerun verify-existing-install after repair.",
        }

    def existing_install_verify_next_action(target, method, source_id=None):
        return {
            "kind": "verify_existing_install",
            "command": existing_install_verify_command(target, method, source_id),
            "instruction": "Run this command before asking for a new local brain repo path or starting a new GBrain setup.",
        }

    def fresh_install_next_action():
        return {
            "kind": "start_fresh_install",
            "command": "zebra-gbrain-onboarding prepare-source-repo --fresh-install",
            "instruction": "Run this command to prepare the GBrain source repo and continue the fresh setup flow. The brain/vault repo target is chosen later in Step 3.",
        }

    def discover_local_path_from_entries(payload, preferred_source_id=None):
        entries = collect_source_entries(payload)
        preferred = []
        fallback = []
        for entry in entries:
            local_path = entry.get("local_path") or entry.get("localPath") or entry.get("path")
            if not local_path:
                continue
            expanded = os.path.abspath(os.path.expanduser(local_path))
            if not os.path.isdir(expanded):
                continue
            entry_source_id = entry.get("id") or entry.get("source_id") or entry.get("sourceId")
            candidate = {
                "targetPath": expanded,
                "sourceId": entry_source_id,
            }
            if preferred_source_id and entry_source_id == preferred_source_id:
                preferred.append(candidate)
            else:
                fallback.append(candidate)
        return (preferred or fallback or [None])[0]

    def discover_current_source_id(payload):
        if not isinstance(payload, dict):
            return None
        direct = payload.get("source_id") or payload.get("sourceId") or payload.get("id")
        if direct:
            return direct
        current = payload.get("current") or payload.get("source")
        if isinstance(current, dict):
            return current.get("source_id") or current.get("sourceId") or current.get("id")
        return None

    def discovered_local_vault_payload(target_path, source_id=None, method="user_existing_repo", source="unknown"):
        target_path = os.path.abspath(os.path.expanduser(target_path))
        payload = {
            "kind": "local_vault",
            "targetPath": target_path,
            "targetKey": target_key(target_path),
            "method": method,
            "source": source,
            "nextAction": existing_install_verify_next_action(target_path, method, source_id),
        }
        if source_id:
            payload["sourceId"] = source_id
        return payload

    def discovered_remote_thin_client_payload(remote_probe, source="gbrain_status"):
        remote_mcp_url = remote_probe.get("remoteMCPURL")
        return {
            "kind": "remote_thin_client",
            "remoteMCPURL": remote_mcp_url,
            "targetKey": remote_target_key(remote_mcp_url),
            "readWriteOk": bool(remote_probe.get("readWriteOk")),
            "method": "thin_client_remote",
            "source": source,
            "warnings": remote_probe.get("warnings") or [],
            "nextAction": existing_install_verify_next_action(None, "thin_client_remote"),
        }

    def discover_existing_install_target():
        state = load_state()
        progress = state.get("progress") or {}
        receipt = state.get("receipt") or {}
        targets = receipt.get("targets") or {}

        selected_vault = progress.get("selectedVaultPath")
        has_existing_install_evidence = bool(selected_vault or receipt.get("primaryTargetKey") or progress.get("resolvedTargetKey") or targets)
        if selected_vault and os.path.isdir(os.path.abspath(os.path.expanduser(selected_vault))):
            print(json.dumps(
                discovered_local_vault_payload(
                    selected_vault,
                    method="selected_vault",
                    source="selected_vault",
                ),
                sort_keys=True,
            ))
            sys.exit(0)

        primary_key = receipt.get("primaryTargetKey") or progress.get("resolvedTargetKey")
        primary_target = targets.get(primary_key) if primary_key else None
        if primary_target:
            remote_mcp_url = primary_target.get("remoteMCPURL")
            target_method = (primary_target.get("targetResolution") or {}).get("method")
            if target_method == "thin_client_remote" and remote_mcp_url:
                print(json.dumps({
                    "kind": "remote_thin_client",
                    "remoteMCPURL": remote_mcp_url,
                    "targetKey": remote_target_key(remote_mcp_url),
                    "readWriteOk": True,
                    "method": "thin_client_remote",
                    "source": "cached_receipt",
                    "warnings": primary_target.get("warnings") or [],
                    "nextAction": existing_install_verify_next_action(None, "thin_client_remote"),
                }, sort_keys=True))
                sys.exit(0)
            target_path = primary_target.get("vaultPath")
            if target_path and os.path.isdir(os.path.abspath(os.path.expanduser(target_path))):
                print(json.dumps(
                    discovered_local_vault_payload(
                        target_path,
                        source_id=primary_target.get("sourceId"),
                        method=target_method or "user_existing_repo",
                        source="cached_receipt",
                    ),
                    sort_keys=True,
                ))
                sys.exit(0)

        executable = gbrain_executable()
        probes = []
        if executable:
            remote_probe = existing_install_remote_target_probe(executable, None)
            probes.append({
                "name": "gbrain_status_remote",
                "ok": bool(remote_probe.get("ok")),
                "reason": remote_probe.get("reason"),
                "reasons": remote_probe.get("reasons") or [],
            })
            if remote_probe.get("ok") and remote_probe.get("remoteMCPURL"):
                print(json.dumps(discovered_remote_thin_client_payload(remote_probe), sort_keys=True))
                sys.exit(0)

            status_ok, status_payload, status_error = run_json(
                [executable, "status", "--json"],
                timeout=12,
            )
            probes.append({
                "name": "gbrain_status",
                "ok": bool(status_ok),
                "reason": None if status_ok else probe_failure_reason(status_error),
            })
            if status_ok:
                status_candidate = discover_local_path_from_entries(status_payload)
                if status_candidate:
                    print(json.dumps(
                        discovered_local_vault_payload(
                            status_candidate["targetPath"],
                            source_id=status_candidate.get("sourceId"),
                            source="gbrain_status",
                        ),
                        sort_keys=True,
                    ))
                    sys.exit(0)

            current_ok, current_payload, current_error = run_json(
                [executable, "sources", "current", "--json"],
                timeout=8,
            )
            probes.append({
                "name": "gbrain_sources_current",
                "ok": bool(current_ok),
                "reason": None if current_ok else probe_failure_reason(current_error),
            })
            current_source_id = discover_current_source_id(current_payload) if current_ok else None
            current_candidate = discover_local_path_from_entries(current_payload, current_source_id) if current_ok else None
            if current_candidate:
                print(json.dumps(
                    discovered_local_vault_payload(
                        current_candidate["targetPath"],
                        source_id=current_candidate.get("sourceId") or current_source_id,
                        source="gbrain_sources_current",
                    ),
                    sort_keys=True,
                ))
                sys.exit(0)

            list_ok, list_payload, list_error = run_json(
                [executable, "sources", "list", "--json"],
                timeout=8,
            )
            probes.append({
                "name": "gbrain_sources_list",
                "ok": bool(list_ok),
                "reason": None if list_ok else probe_failure_reason(list_error),
            })
            list_candidate = discover_local_path_from_entries(list_payload, current_source_id) if list_ok else None
            if list_candidate:
                print(json.dumps(
                    discovered_local_vault_payload(
                        list_candidate["targetPath"],
                        source_id=list_candidate.get("sourceId") or current_source_id,
                        source="gbrain_sources_list",
                    ),
                    sort_keys=True,
                ))
                sys.exit(0)
        else:
            probes.append({
                "name": "gbrain_executable",
                "ok": False,
                "reason": "missing_gbrain_executable",
            })
            if not has_existing_install_evidence:
                print(json.dumps({
                    "kind": "fresh_install",
                    "reason": "missing_gbrain_executable",
                    "probes": probes,
                    "nextAction": fresh_install_next_action(),
                    "instruction": "No selected vault, cached receipt, remote thin-client evidence, or gbrain executable was found. Start fresh GBrain setup; do not ask for a brain/vault repo path until Step 3.",
                }, sort_keys=True))
                sys.exit(0)

        print(json.dumps({
            "kind": "unresolved",
            "askUserFor": "brain_repo_path",
            "reason": "existing_install_target_not_discovered",
            "probes": probes,
            "instruction": "Ask whether to continue remote-only if the user knows they use thin-client remote MCP, or ask for an optional local brain/vault repo path. Do not run broad filesystem scans.",
        }, sort_keys=True))
        sys.exit(0)

    def existing_install_guardrails():
        return [
            "Do not edit gbrain-setup-state.json directly.",
            "Do not run source registration, default-source, attach, detach, credential, remote topology, VPN, Tailscale, host, or destructive data commands without explicit user confirmation.",
            "Do not abandon existing-install recovery for a new home-directory GBrain setup unless the user explicitly confirms that fallback.",
            "Use the installed gbrain CLI help, doctor, status, and remediation output as the primary authority.",
            "Use local GBrain repo/docs only as fallback context when discovered.",
            "Only a successful verify-existing-install run may mark the existing install complete.",
        ]

    def existing_install_local_gbrain_docs():
        roots = []
        for candidate in [
            os.environ.get("ZEBRA_GBRAIN_SOURCE_REPO"),
            os.environ.get("ZEBRA_GBRAIN_SOURCE_REPO_DEFAULT"),
            default_source_repo_path(),
        ]:
            if candidate:
                expanded = os.path.abspath(os.path.expanduser(candidate))
                if expanded not in roots:
                    roots.append(expanded)
        relative_paths = [
            "AGENTS.md",
            "INSTALL_FOR_AGENTS.md",
            "README.md",
            "docs/GBRAIN_VERIFY.md",
            "docs/help.md",
            "llms.txt",
            "llms-full.txt",
        ]
        for root in roots:
            paths = []
            for relative_path in relative_paths:
                path = os.path.join(root, relative_path)
                if os.path.isfile(path):
                    paths.append({"path": path, "relativePath": relative_path})
            if paths:
                return {
                    "found": True,
                    "root": root,
                    "priority": "fallback_after_installed_cli",
                    "paths": paths,
                }
        return {
            "found": False,
            "priority": "fallback_after_installed_cli",
            "paths": [],
        }

    def existing_install_has_remote_probe(source_probe_attempts):
        for attempt in source_probe_attempts or []:
            if attempt.get("adapter") == "remote":
                return True
            if attempt.get("reason") == "sources_cli_not_routable":
                return True
            if str(attempt.get("reason") or "").startswith("remote_"):
                return True
        return False

    def existing_install_recommended_references(reasons, source_probe_attempts):
        commands = [
            {
                "priority": 1,
                "source": "installed_gbrain_cli",
                "command": "gbrain --help",
                "purpose": "Discover the installed CLI surface before choosing commands.",
            },
            {
                "priority": 1,
                "source": "installed_gbrain_cli",
                "command": "gbrain doctor --json",
                "purpose": "Read the current health checks exactly as this installation reports them.",
            },
            {
                "priority": 1,
                "source": "installed_gbrain_cli",
                "command": "gbrain status --json",
                "purpose": "Inspect current sync/source/index status without mutating state.",
            },
            {
                "priority": 1,
                "source": "installed_gbrain_cli",
                "command": "gbrain doctor --remediation-plan --json",
                "purpose": "Ask the installed CLI for its own repair plan when supported.",
            },
            {
                "priority": 1,
                "source": "installed_gbrain_cli",
                "command": "gbrain sources current --json",
                "purpose": "Check the currently selected source when this CLI surface is routable.",
            },
            {
                "priority": 1,
                "source": "installed_gbrain_cli",
                "command": "gbrain sources list --json",
                "purpose": "Check whether the selected vault is registered as a source.",
            },
        ]
        if "read_probe_failed" in (reasons or []):
            commands.extend([
                {
                    "priority": 1,
                    "source": "installed_gbrain_cli",
                    "command": "gbrain sync --help",
                    "purpose": "Learn the installed CLI's read/index sync command before repair.",
                },
                {
                    "priority": 1,
                    "source": "installed_gbrain_cli",
                    "command": "gbrain embed --help",
                    "purpose": "Learn the installed CLI's embedding/indexing command before repair.",
                },
                {
                    "priority": 1,
                    "source": "installed_gbrain_cli",
                    "command": "gbrain search --help",
                    "purpose": "Confirm the installed CLI search syntax and expected output.",
                },
            ])
        if existing_install_has_remote_probe(source_probe_attempts):
            commands.extend([
                {
                    "priority": 1,
                    "source": "installed_gbrain_cli",
                    "command": "gbrain remote ping --timeout 15m --json",
                    "purpose": "Check the remote runtime path without assuming a local source repair.",
                },
                {
                    "priority": 1,
                    "source": "installed_gbrain_cli",
                    "command": "gbrain remote doctor --json",
                    "purpose": "Read remote health checks when the sources CLI is a thin client.",
                },
            ])
        return commands

    def existing_install_safe_helper_options(target, method, source_id, doctor_failed_checks):
        if source_id and doctor_failed_checks == [CYCLE_FRESHNESS_CHECK_NAME]:
            return [
                {
                    "kind": "recover_cycle_freshness",
                    "command": "zebra-gbrain-onboarding recover-cycle-freshness --target "
                        + shell_quote(target or "")
                        + " --source-id " + shell_quote(source_id)
                        + " --method " + shell_quote(method or "selected_vault"),
                    "scope": "Zebra helper-owned narrow recovery for a single cycle_freshness doctor failure.",
                    "requiresUserConfirmation": False,
                }
            ]
        return []

    def diagnose_existing_install_failure():
        flags = parse_flags(args)
        target = flags.get("target")
        method = flags.get("method") or "selected_vault"
        source_id = flags.get("source_id")
        if target:
            target = os.path.abspath(os.path.expanduser(target))
        state = load_state()
        progress = state.get("progress") or {}
        existing = progress.get("existingInstallVerification") or {}
        key = target_key(target) if target and os.path.isdir(target) else progress.get("resolvedTargetKey")
        target_payload = (((state.get("receipt") or {}).get("targets") or {}).get(key) or {}) if key else {}

        source_probe = existing.get("sourceProbe") or target_payload.get("sourcesCurrentResult") or {}
        source_probe_attempts = existing.get("sourceProbeAttempts") or []
        read_probe = existing.get("readProbe") or target_payload.get("searchProbeResult") or {}
        reasons = existing.get("reasons") or target_payload.get("reasons") or []
        doctor_failed_check_names = (
            existing.get("doctorFailedChecks")
            or ((target_payload.get("doctorStatus") or {}).get("failedChecks") or [])
        )
        source_id = source_id or existing.get("sourceId") or source_probe.get("sourceId") or target_payload.get("sourceId")

        retry_command = existing_install_verify_command(target, method, source_id)
        payload = {
            "status": "diagnosis_ready",
            "target": target,
            "method": method,
            "sourceId": source_id,
            "failure": {
                "reasons": reasons,
                "doctorFailedChecks": doctor_failed_check_names,
                "doctorStatus": target_payload.get("doctorStatus") or {
                    "ok": existing.get("doctorOk"),
                    "failedChecks": doctor_failed_check_names,
                },
                "readProbe": read_probe,
                "sourceProbe": source_probe,
                "sourceProbeAttempts": source_probe_attempts,
            },
            "authorityOrder": [
                "installed_gbrain_cli",
                "local_gbrain_repo_or_docs_when_discovered",
            ],
            "recommendedReferences": existing_install_recommended_references(reasons, source_probe_attempts),
            "localGBrainDocs": existing_install_local_gbrain_docs(),
            "guardrails": existing_install_guardrails(),
            "safeHelperOptions": existing_install_safe_helper_options(target, method, source_id, doctor_failed_check_names),
            "retryCommand": retry_command,
            "completionRule": "After repair, rerun retryCommand. Only verify-existing-install success may mark the existing GBrain install complete; do not edit gbrain-setup-state.json directly.",
        }
        print(json.dumps(payload, sort_keys=True))
        sys.exit(0)

    def verify_existing_install():
        flags = parse_flags(args)
        target = flags.get("target")
        source_id = flags.get("source_id")
        method = flags.get("method") or "selected_vault"
        profile_id = flags.get("profile_id")
        remote_mcp_url = None
        is_thin_client_remote = method == "thin_client_remote"
        reasons = []
        if not target and not is_thin_client_remote:
            reasons.append("target_not_resolved")
        elif target:
            target = os.path.abspath(os.path.expanduser(target))
            forbidden_reason = forbidden_target_reason(target, method)
            if forbidden_reason:
                reasons.append(forbidden_reason)
            if not os.path.isdir(target):
                reasons.append("receipt_target_missing")
        if method not in allowed_methods:
            reasons.append("target_confirmation_missing")

        executable = gbrain_executable()
        if not executable:
            reasons.append("missing_gbrain_executable")
        version = gbrain_version_string(executable)
        version_ok = bool(version)

        doctor_ok = False
        doctor_failed_check_names = []
        doctor_reason = None
        if executable:
            try:
                doctor = subprocess.run(
                    [executable, "doctor", "--json"],
                    cwd=target if target and os.path.isdir(target) else None,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=45,
                )
                doctor_ok, _ = strict_doctor_result(doctor)
                doctor_failed_check_names = doctor_failed_checks(doctor)
                if not doctor_ok:
                    doctor_reason = transient_probe_reason((doctor.stderr or "") + "\\n" + (doctor.stdout or "")) or "doctor_failed"
            except subprocess.TimeoutExpired:
                doctor_reason = PGLITE_BUSY_REASON
                doctor_failed_check_names = ["doctor_timeout"]
            except Exception:
                doctor_reason = "doctor_failed"
                doctor_failed_check_names = ["doctor_failed"]

        read_probe = {"ok": False, "status": "not_run"}
        read_reason = None
        if executable and (is_thin_client_remote or (target and os.path.isdir(target))):
            read_probe, read_reason = existing_install_read_probe(executable, target)
            if read_reason:
                reasons.append(read_reason)

        source_probe = {"ok": False, "status": "not_run", "reason": "source_probe_not_run"}
        source_probe_attempts = []
        warnings = []
        if executable and is_thin_client_remote:
            remote_probe = existing_install_remote_target_probe(executable, target)
            source_probe_attempts = [remote_probe]
            remote_mcp_url = remote_probe.get("remoteMCPURL")
            warnings.extend(remote_probe.get("warnings") or [])
            if remote_probe.get("ok") and read_probe.get("ok"):
                source_probe = existing_install_as_thin_client_read_verified(
                    remote_probe,
                    source_probe_attempts,
                    source_id,
                )
            else:
                source_probe = remote_probe
                for reason in remote_probe.get("reasons") or [remote_probe.get("reason") or "remote_target_not_verified"]:
                    reasons.append(reason)
        elif executable and target and os.path.isdir(target):
            source_probe, source_probe_attempts = existing_install_source_probe(executable, target, source_id)
            if source_probe.get("sourceId"):
                source_id = source_probe.get("sourceId")

            thin_client_admin_diagnostic_unavailable = bool(
                read_probe.get("ok")
                and existing_install_has_thin_client_source_refusal(source_probe_attempts)
                and existing_install_source_probe_admin_diagnostic_unavailable(source_probe)
            )
            if thin_client_admin_diagnostic_unavailable:
                warnings.append("remote_admin_diagnostic_unavailable")
                source_probe = existing_install_as_thin_client_read_verified(
                    source_probe,
                    source_probe_attempts,
                    source_id,
                )
            elif not source_probe.get("ok"):
                reasons.append(source_probe.get("reason") or "source_binding_not_verified")

        doctor_admin_diagnostic_unavailable = bool(
            doctor_reason
            and existing_install_admin_diagnostic_unavailable(doctor_reason + "\\n" + "\\n".join(doctor_failed_check_names))
            and read_probe.get("ok")
            and (is_thin_client_remote or existing_install_has_thin_client_source_refusal(source_probe_attempts))
        )
        if doctor_admin_diagnostic_unavailable:
            warnings.append("remote_admin_diagnostic_unavailable")
        elif doctor_reason:
            reasons.append(doctor_reason)

        reasons = list(dict.fromkeys([reason for reason in reasons if reason]))
        warnings = list(dict.fromkeys([warning for warning in warnings if warning]))
        doctor_effective_ok = bool(doctor_ok or doctor_admin_diagnostic_unavailable)
        global_complete = bool(executable and version_ok and doctor_effective_ok and read_probe.get("ok"))
        source_identity_satisfied = bool(source_id or source_probe.get("method") == "existing_install_thin_client_read_probe")
        complete = bool(global_complete and source_probe.get("ok") and source_identity_satisfied and not reasons)
        verified_at = now()
        key = remote_target_key(remote_mcp_url) if is_thin_client_remote and remote_mcp_url else (target_key(target) if target and os.path.isdir(target) else None)

        state = load_state()
        receipt = state.setdefault("receipt", {})
        targets = receipt.setdefault("targets", {})
        existing_target_payload = dict((targets or {}).get(key) or {}) if key else {}
        preserve_completed_receipt = bool(
            (not complete)
            and key
            and (receipt.get("globalReadiness") or {}).get("complete") is True
            and existing_target_payload.get("complete") is True
            and existing_install_has_only_transient_reasons(reasons)
        )
        effective_complete = bool(complete or preserve_completed_receipt)
        status_value = (
            "verified"
            if complete
            else ("transient_retry_preserved" if preserve_completed_receipt else "diagnosis_needed")
        )
        next_action = None if complete else existing_install_next_action(target, method, source_id)

        if not preserve_completed_receipt:
            receipt["globalReadiness"] = {
                "complete": global_complete,
                "gbrainExecutablePath": executable,
                "doctorOk": doctor_ok,
                "doctorEffectiveOk": doctor_effective_ok,
                "verifiedAt": verified_at,
            }
        if key:
            receipt["primaryTargetKey"] = key
            target_payload = dict((targets or {}).get(key) or {})
            if not preserve_completed_receipt:
                target_payload.update({
                    "vaultPath": target,
                    "remoteMCPURL": remote_mcp_url,
                    "sourceId": source_id,
                    "profileId": profile_id,
                    "gbrainExecutablePath": executable,
                    "doctorStatus": {
                        "ok": doctor_ok,
                        "effectiveOk": doctor_effective_ok,
                        "status": "ok" if doctor_ok else "failed",
                        "failedChecks": doctor_failed_check_names,
                    },
                    "sourcesCurrentResult": {
                        "ok": bool(source_probe.get("ok")),
                        "sourceId": source_id,
                        "localPath": source_probe.get("localPath"),
                        "status": source_probe.get("status"),
                        "reason": source_probe.get("reason"),
                    },
                    "searchProbeResult": read_probe,
                    "verifiedAt": verified_at,
                    "complete": complete,
                    "status": status_value,
                    "warnings": warnings,
                    "targetResolution": {
                        "method": method,
                        "confirmedAt": verified_at,
                    },
                    "reasons": reasons,
                })
                if source_probe.get("ok"):
                    target_payload["sourceVerification"] = {
                        "sourceId": source_id,
                        "targetPath": target,
                        "remoteMCPURL": remote_mcp_url,
                        "verifiedAt": verified_at,
                        "method": source_probe.get("method") or "existing_install_sources_current_and_list",
                        "gbrainExecutablePath": executable,
                        "gbrainVersion": version,
                    }
                else:
                    target_payload.pop("sourceVerification", None)
                targets[key] = target_payload
            progress = state.setdefault("progress", {})
            if target:
                progress.setdefault("selectedVaultPath", target)
            progress["resolvedTargetKey"] = key
            progress["targetResolution"] = {
                "status": status_value,
                "method": method,
                "confirmedAt": verified_at,
            }
            progress["existingInstallVerification"] = {
                "status": status_value,
                "verifiedAt": verified_at,
                "gbrainExecutablePath": executable,
                "gbrainVersion": version,
                "doctorOk": doctor_ok,
                "doctorEffectiveOk": doctor_effective_ok,
                "doctorFailedChecks": doctor_failed_check_names,
                "readProbe": read_probe,
                "sourceProbe": source_probe,
                "sourceProbeAttempts": source_probe_attempts,
                "sourceId": source_id,
                "reasons": reasons,
                "warnings": warnings,
                "nextAction": next_action,
                "preservedReceipt": preserve_completed_receipt,
                "transientFailure": preserve_completed_receipt,
            }
        progress = state.setdefault("progress", {})
        progress["lastStatus"] = status_value
        progress["updatedAt"] = verified_at
        if reasons:
            progress["lastFailure"] = ",".join(reasons)
        else:
            progress.pop("lastFailure", None)
        save_state(state)
        print(json.dumps({
            "complete": effective_complete,
            "status": status_value,
            "reasons": reasons,
            "globalReadinessComplete": global_complete,
            "gbrainExecutablePath": executable,
            "gbrainVersion": version,
            "doctorOk": doctor_ok,
            "doctorEffectiveOk": doctor_effective_ok,
            "doctorFailedChecks": doctor_failed_check_names,
            "readProbe": read_probe,
            "sourceProbe": source_probe,
            "sourceProbeAttempts": source_probe_attempts,
            "warnings": warnings,
            "nextAction": next_action,
            "preservedReceipt": preserve_completed_receipt,
            "transientFailure": preserve_completed_receipt,
        }, sort_keys=True))
        sys.exit(0 if effective_complete else 1)

    def recover_cycle_freshness():
        flags = parse_flags(args)
        target = flags.get("target")
        source_id = flags.get("source_id")
        reasons = []
        warnings = []
        status_value = "failed"
        doctor_before_failed_checks = []
        doctor_after_failed_checks = None
        source_probe = "not_run"
        source_probe_reason = None
        dream_ran = False
        dream_ok = False
        executable = gbrain_executable()
        if not target:
            reasons.append("target_not_resolved")
        else:
            target = os.path.abspath(os.path.expanduser(target))
            if not os.path.isdir(target):
                reasons.append("receipt_target_missing")
        if not source_id:
            reasons.append("source_not_registered")
        if not executable:
            reasons.append("missing_gbrain_executable")
        if reasons:
            print(json.dumps({
                "ok": False,
                "status": status_value,
                "reasons": reasons,
                "warnings": warnings,
            }, sort_keys=True))
            sys.exit(1)

        try:
            doctor_before = subprocess.run(
                [executable, "doctor", "--json"],
                cwd=target,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=45,
            )
            doctor_before_failed_checks = doctor_failed_checks(doctor_before)
            if not doctor_before_failed_checks:
                status_value = "already_fresh"
            elif doctor_before_failed_checks == [CYCLE_FRESHNESS_CHECK_NAME]:
                source_probe, _, _, source_probe_reason = source_probe_status(executable, target, source_id)
                if source_probe != "verified":
                    if source_probe == "mismatch":
                        reasons.append("source_not_registered")
                    elif source_probe_reason:
                        reasons.append(source_probe_reason)
                    else:
                        reasons.append("source_probe_not_verified")
                    status_value = "source_probe_not_verified"
                else:
                    dream_ran = True
                    try:
                        dream_result = subprocess.run(
                            [executable, "dream", "--source", source_id],
                            cwd=target,
                            text=True,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            timeout=1800,
                        )
                        dream_ok = dream_result.returncode == 0
                        if not dream_ok:
                            reasons.append("dream_failed")
                            status_value = "dream_failed"
                    except subprocess.TimeoutExpired:
                        reasons.append("dream_timeout")
                        status_value = "dream_timeout"
                    if dream_ok:
                        doctor_after = subprocess.run(
                            [executable, "doctor", "--json"],
                            cwd=target,
                            text=True,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            timeout=45,
                        )
                        doctor_after_failed_checks = doctor_failed_checks(doctor_after)
                        if not doctor_after_failed_checks:
                            status_value = "recovered"
                        else:
                            reasons.append("doctor_failed")
                            status_value = "doctor_still_failed"
            else:
                reasons.append("unexpected_doctor_blockers")
                status_value = "unexpected_doctor_blockers"
        except subprocess.TimeoutExpired:
            reasons.append("doctor_timeout")
            status_value = "doctor_timeout"
        except Exception:
            reasons.append("cycle_recovery_failed")
            status_value = "failed"

        ok = len(reasons) == 0
        print(json.dumps({
            "ok": ok,
            "status": status_value,
            "reasons": reasons,
            "warnings": warnings,
            "doctorBefore": {
                "failedChecks": doctor_before_failed_checks,
            },
            "doctorAfter": {
                "failedChecks": doctor_after_failed_checks,
            } if doctor_after_failed_checks is not None else None,
            "sourceProbe": {
                "status": source_probe,
                "reason": source_probe_reason,
            },
            "dream": {
                "ran": dream_ran,
                "ok": dream_ok,
                "sourceId": source_id,
            },
        }, sort_keys=True))
        sys.exit(0 if ok else 1)

    def verify():
        flags = parse_flags(args)
        target = flags.get("target")
        source_id = flags.get("source_id")
        method = flags.get("method")
        profile_id = flags.get("profile_id")
        reasons = []
        warnings = []
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
        doctor_failed_check_names = []
        doctor_transient = False
        source_probe = "transient"
        current_ok = False
        current_source_id = None
        list_ok = False
        listed_local_path = None
        source_probe_reason = None
        source_probe_reasons = []
        doctor_effective_ok = False
        maintenance_pending = False
        install_probes = {
            "sync": {"ok": False, "status": "not_run"},
            "stats": {"ok": False, "status": "not_run"},
            "embedding": {"ok": False, "status": "not_run"},
            "search": {"ok": False, "status": "not_run"},
        }
        auto_recovery = {
            "ran": False,
            "command": "recover-cycle-freshness",
            "status": "not_needed",
        }

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
                doctor_failed_check_names = [] if doctor_ok or doctor_transient else doctor_failed_checks(result)
                if doctor_transient_reason and doctor_transient_reason not in reasons:
                    reasons.append(doctor_transient_reason)
                elif not doctor_ok:
                    reasons.append("doctor_failed")
            except Exception as exc:
                doctor_transient_reason = transient_probe_reason(str(exc))
                doctor_transient = doctor_transient_reason is not None
                doctor_failed_check_names = [] if doctor_transient else ["doctor_failed"]
                if doctor_transient_reason and doctor_transient_reason not in reasons:
                    reasons.append(doctor_transient_reason)
                elif not doctor_transient:
                    reasons.append("doctor_failed")

            if target and os.path.isdir(target) and source_id:
                source_probe, current_source_id, listed_local_path, source_probe_reason = source_probe_status(executable, target, source_id)
                current_ok = source_probe == "verified"
                list_ok = source_probe == "verified"
                if source_probe == "mismatch":
                    source_probe_reasons.append("source_not_registered")
                elif source_probe_reason:
                    source_probe_reasons.append(source_probe_reason)
                for reason in source_probe_reasons:
                    if reason not in reasons:
                        reasons.append(reason)
            if (
                (not doctor_ok)
                and (not doctor_transient)
                and doctor_failed_check_names == [CYCLE_FRESHNESS_CHECK_NAME]
            ):
                non_doctor_reasons = [reason for reason in reasons if reason != "doctor_failed"]
                has_invocation_blocker = any(reason not in source_probe_reasons for reason in non_doctor_reasons)
                if has_invocation_blocker:
                    auto_recovery = {
                        "ran": False,
                        "command": "recover-cycle-freshness",
                        "status": "unsupported_doctor_failed_checks",
                        "reason": "unsupported_doctor_failed_checks",
                    }
                elif source_probe != "verified":
                    auto_recovery = {
                        "ran": False,
                        "command": "recover-cycle-freshness",
                        "status": "source_probe_not_verified",
                        "reason": source_probe_reason or ("source_not_registered" if source_probe == "mismatch" else "source_probe_not_verified"),
                    }
                else:
                    install_probes, probe_reasons = run_install_probes(executable, target)
                    if probe_reasons:
                        for reason in probe_reasons:
                            if reason not in reasons:
                                reasons.append(reason)
                        auto_recovery = {
                            "ran": False,
                            "command": "recover-cycle-freshness",
                            "status": "maintenance_probe_failed",
                            "reason": ",".join(probe_reasons),
                        }
                    else:
                        reasons = [reason for reason in reasons if reason != "doctor_failed"]
                        maintenance_pending = True
                        doctor_effective_ok = True
                        warnings.append("maintenance_pending:cycle_freshness")
                        auto_recovery = {
                            "ran": False,
                            "command": "recover-cycle-freshness",
                            "status": "maintenance_pending",
                        }
            elif (not doctor_ok) and (not doctor_transient) and doctor_failed_check_names:
                auto_recovery = {
                    "ran": False,
                    "command": "recover-cycle-freshness",
                    "status": "unsupported_doctor_failed_checks",
                    "reason": "unsupported_doctor_failed_checks",
                }

        state = load_state()
        receipt = state.setdefault("receipt", {})
        key = target_key(target) if target and os.path.isdir(target) else None
        existing_target = (receipt.get("targets") or {}).get(key) if key else None
        if doctor_ok:
            doctor_effective_ok = True
        verified = len(reasons) == 0 and doctor_effective_ok and source_probe == "verified"
        complete = verified
        status_value = "verified_with_maintenance_pending" if complete and maintenance_pending else ("verified" if complete else "failed")
        receipt["globalReadiness"] = {
            "complete": bool(executable and doctor_effective_ok),
            "gbrainExecutablePath": executable,
            "doctorOk": doctor_ok,
            "doctorEffectiveOk": doctor_effective_ok,
            "verifiedAt": now(),
        }
        if key:
            targets = receipt.setdefault("targets", {})
            target_payload = dict(existing_target or {})
            target_payload.update({
                "vaultPath": target,
                "sourceId": source_id,
                "profileId": profile_id,
                "gbrainExecutablePath": executable,
                "doctorStatus": {
                    "ok": doctor_ok,
                    "status": "ok" if doctor_ok else "failed",
                    "failedChecks": doctor_failed_check_names,
                },
                "sourcesCurrentResult": {
                    "ok": current_ok and list_ok,
                    "sourceId": current_source_id or source_id,
                    "localPath": listed_local_path,
                    "status": source_probe,
                    "reason": source_probe_reason,
                },
                "syncProbeResult": install_probes.get("sync"),
                "statsProbeResult": install_probes.get("stats"),
                "embeddingProbeResult": install_probes.get("embedding"),
                "searchProbeResult": install_probes.get("search") if maintenance_pending else {"ok": complete},
                "verifiedAt": now(),
                "complete": complete,
                "status": status_value,
                "warnings": warnings,
                "doctorFailedChecks": doctor_failed_check_names,
                "autoRecovery": auto_recovery,
                "targetResolution": {
                    "method": method,
                    "confirmedAt": now(),
                },
                "reasons": reasons,
            })
            if source_probe == "verified":
                target_payload["sourceVerification"] = {
                    "sourceId": source_id,
                    "targetPath": target,
                    "verifiedAt": now(),
                    "method": "sources_current_and_list",
                    "gbrainExecutablePath": executable,
                    "gbrainVersion": gbrain_version_string(executable),
                }
            targets[key] = target_payload
            progress = state.setdefault("progress", {})
            progress["resolvedTargetKey"] = key
            progress["targetResolution"] = {
                "status": status_value,
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
        print(json.dumps({
            "complete": complete,
            "status": status_value,
            "reasons": reasons,
            "warnings": warnings,
            "doctorOk": doctor_ok,
            "doctorEffectiveOk": doctor_effective_ok,
            "doctorFailedChecks": doctor_failed_check_names,
            "autoRecovery": auto_recovery,
            "maintenancePending": maintenance_pending,
            "probes": install_probes,
            "sourceProbe": {
                "ok": source_probe == "verified",
                "status": source_probe,
                "reason": source_probe_reason,
            },
        }, sort_keys=True))
        sys.exit(0 if complete else 1)

    if command == "prepare-source-repo":
        try:
            prepare_source_repo()
        except Exception as exc:
            print(json.dumps({"ok": False, "reason": str(exc)}, sort_keys=True))
            sys.exit(1)
    elif command == "active-source-repo-path":
        active_source_repo_path()
    elif command == "active-source-env":
        active_source_env()
    elif command == "write-runtime-launcher":
        try:
            write_runtime_launcher()
        except Exception as exc:
            print(json.dumps({"ok": False, "reason": str(exc)}, sort_keys=True))
            sys.exit(1)
    elif command == "prepare-openclaw-agent":
        try:
            prepare_openclaw_agent()
        except Exception as exc:
            print(json.dumps({"ok": False, "reason": str(exc)}, sort_keys=True))
            sys.exit(1)
    elif command == "run-gbrain":
        run_gbrain()
    elif command == "report":
        report()
    elif command == "status":
        status()
    elif command == "verify":
        verify()
    elif command == "discover-existing-install-target":
        discover_existing_install_target()
    elif command == "verify-existing-install":
        verify_existing_install()
    elif command == "diagnose-existing-install-failure":
        diagnose_existing_install_failure()
    elif command == "recover-cycle-freshness":
        recover_cycle_freshness()
    elif command == "prepare-platform-scheduler":
        try:
            prepare_platform_scheduler()
        except Exception as exc:
            print(json.dumps({"ok": False, "reason": str(exc)}, sort_keys=True))
            sys.exit(1)
    elif command == "check-launchd-bun-path":
        check_launchd_bun_path()
    elif command == "repair-launchd-bun-path":
        repair_launchd_bun_path()
    elif command == "create-initial-brain-commit":
        create_initial_brain_commit()
    else:
        print("usage: zebra-gbrain-onboarding <prepare-source-repo|active-source-repo-path|active-source-env|write-runtime-launcher|prepare-openclaw-agent|run-gbrain|report|status|verify|discover-existing-install-target|verify-existing-install|diagnose-existing-install-failure|recover-cycle-freshness|prepare-platform-scheduler|check-launchd-bun-path|repair-launchd-bun-path|create-initial-brain-commit> [options]", file=sys.stderr)
        sys.exit(2)
    PY
    """

    private static let launchctlWrapperScript = """
    #!/bin/sh
    set -eu

    if [ -n "${ZEBRA_GBRAIN_STATE:-}" ]; then
      STATE="$ZEBRA_GBRAIN_STATE"
    elif [ -n "${HOME:-}" ]; then
      STATE="$HOME/Library/Application Support/zebra/onboarding/gbrain-setup-state.json"
    else
      echo "ZEBRA_GBRAIN_STATE or HOME is required for launchctl wrapper" >&2
      exit 1
    fi

    zebra_recurring_jobs_decision() {
      PYTHON_BIN="$(command -v python3 || true)"
      if [ -z "$PYTHON_BIN" ]; then
        return 0
      fi
      "$PYTHON_BIN" -c 'import json, os, sys
    path = sys.argv[1]
    try:
        with open(path, "r", encoding="utf-8") as handle:
            state = json.load(handle)
    except Exception:
        state = {}
    progress = state.get("progress") or {}
    receipt = state.get("receipt") or {}
    key = progress.get("resolvedTargetKey") or receipt.get("primaryTargetKey") or "__unresolved__"
    decision = (progress.get("recurringJobsDecisionByTarget") or {}).get(key) or {}
    print(decision.get("decision") or "")' "$STATE" 2>/dev/null || true
    }

    zebra_launchctl_requires_approval() {
      case "${1:-}" in
        load|bootstrap|enable|start)
          return 0
          ;;
        *)
          return 1
          ;;
      esac
    }

    if zebra_launchctl_requires_approval "$@"; then
      DECISION="$(zebra_recurring_jobs_decision)"
      if [ "${ZEBRA_GBRAIN_ALLOW_RECURRING_JOBS_INSTALL:-}" != "1" ] && [ "$DECISION" != "autopilot_install" ] && [ "$DECISION" != "platform_scheduler_install" ]; then
        echo "Zebra blocked 'launchctl ${1:-}': recurring_jobs_decision=platform_scheduler_install or autopilot_install is required before installing persistent background jobs." >&2
        echo "Run: zebra-gbrain-onboarding report --status waiting_for_user --section \"<section title>\" --reason recurring_jobs_decision" >&2
        exit 78
      fi
    fi

    SELF_DIR="$(cd "$(dirname "$0")" && pwd -P)"
    OLD_IFS="$IFS"
    IFS=:
    for dir in $PATH; do
      IFS="$OLD_IFS"
      [ -z "$dir" ] && dir=.
      resolved_dir="$(cd "$dir" 2>/dev/null && pwd -P || true)"
      if [ "$resolved_dir" = "$SELF_DIR" ]; then
        IFS=:
        continue
      fi
      if [ -x "$dir/launchctl" ]; then
        exec "$dir/launchctl" "$@"
      fi
      IFS=:
    done
    IFS="$OLD_IFS"

    if [ -x /bin/launchctl ]; then
      exec /bin/launchctl "$@"
    fi
    if [ -x /usr/bin/launchctl ]; then
      exec /usr/bin/launchctl "$@"
    fi
    echo "launchctl executable is unavailable" >&2
    exit 127
    """
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
