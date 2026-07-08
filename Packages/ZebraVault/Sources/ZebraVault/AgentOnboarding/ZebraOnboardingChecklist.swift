import Foundation
import SwiftUI
#if os(macOS)
import Darwin
#endif

public enum ZebraOnboardingChecklistStepID: String, CaseIterable, Identifiable, Sendable {
    case agent
    case gbrainRuntime
    case gbrain
    case sourceOnboarding
    case adapter
    case goals

    public var id: String { rawValue }
}

public struct ZebraOnboardingChecklistStepSnapshot: Identifiable, Equatable {
    public let id: ZebraOnboardingChecklistStepID
    public let number: Int
    public let isCompleted: Bool
    public let isDevelopmentCompleted: Bool
    public let isActive: Bool
    public let isRunning: Bool
    public let showsStart: Bool
    public let wasStartedBefore: Bool
    let substeps: [ZebraOnboardingChecklistSubstepSnapshot]
}

@MainActor
public final class ZebraOnboardingChecklistStore: ObservableObject {
    private struct StepCompletionResult {
        let isComplete: Bool
        let reasons: [String]
    }

    private struct StepDefinition {
        let id: ZebraOnboardingChecklistStepID
        let number: Int
        let staleTimeout: TimeInterval
    }

#if os(macOS)
    private struct WatchedCompletionFile {
        let url: URL
        let stepID: ZebraOnboardingChecklistStepID
    }

    private struct CompletionFileSignature: Equatable {
        let exists: Bool
        let modificationTime: TimeInterval?
        let size: UInt64?
    }
#endif

    private static let steps: [StepDefinition] = [
        StepDefinition(id: .agent,            number: 1, staleTimeout: 5 * 60),
        StepDefinition(id: .gbrainRuntime,    number: 2, staleTimeout: 10 * 60),
        StepDefinition(id: .gbrain,           number: 3, staleTimeout: 15 * 60),
        StepDefinition(id: .adapter,          number: 4, staleTimeout: 5 * 60),
        StepDefinition(id: .sourceOnboarding, number: 5, staleTimeout: 5 * 60),
        // StepDefinition(id: .goals,            number: 6, staleTimeout: 5 * 60),
    ]
    private static let enabledStepIDs = Set(steps.map(\.id))

    private let fileManager: FileManager
    private let homeDirectoryPath: String
    private let gbrainRuntimeOnboardingStore: ZebraGBrainRuntimeOnboardingStore
    private let gbrainOnboardingStore: ZebraGBrainOnboardingStore
    private let gbrainAdapterOnboardingStore: ZebraGBrainAdapterOnboardingStore
    private let agentOnboardingStateURL: URL
    private let agentPreferenceURL: URL
    private let agentEventsURL: URL
    private let gbrainRuntimeOnboardingStateURL: URL
    private let gbrainOnboardingStateURL: URL
    private let gbrainAdapterOnboardingStateURL: URL
    private let sourceOnboardingStateURL: URL
    private var selectedVaultPath: String?
    private var emailConnectionRepairState: ZebraEmailConnectionRepairState?
    private var emailConnectionVerified = false
    private var launchGeneration = 0
    private var startedStepIDs: Set<ZebraOnboardingChecklistStepID> = []
    private var gbrainDocsPrefetchTask: Task<Bool, Never>?
    private var didStartGBrainDocsPrefetch = false
    private var lastKnownGBrainRecurringJobsCompleted: Bool?
#if DEBUG
    private static let developmentIncompleteStepIDsDefaultsKey = "ZebraOnboardingChecklistStore.developmentIncompleteStepIDs"
    private var developmentIncompleteStepIDs: Set<ZebraOnboardingChecklistStepID> = []
#endif
#if os(macOS)
    private var completionWatchSources: [DispatchSourceFileSystemObject] = []
    private var isCompletionWatching = false
    private var watchedCompletionFileSignatures: [String: CompletionFileSignature] = [:]
    private var pendingCompletionRefreshStepIDs: Set<ZebraOnboardingChecklistStepID> = []
    private let completionWatchQueue = DispatchQueue(
        label: "com.cmux.zebra.onboarding-checklist-watcher",
        qos: .utility
    )
    private var completionRefreshWorkItem: DispatchWorkItem?
#endif

    @Published public private(set) var completedStepIDs: Set<ZebraOnboardingChecklistStepID> = []
    @Published public private(set) var activeStepID: ZebraOnboardingChecklistStepID?
    @Published public private(set) var runningStepID: ZebraOnboardingChecklistStepID?
    @Published public private(set) var pendingRuntimeInteractiveAuthRequest: ZebraGBrainRuntimeOnboardingStore.InteractiveAuthRequest?
    @Published public private(set) var substepSnapshotRevision = 0
    @Published public private(set) var gbrainRecurringJobsCompletionRevision = 0

    public init(
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory(),
        agentOnboardingStateURL: URL = ZebraAgentOnboardingStartup.defaultStateURL(),
        agentPreferenceURL: URL = ZebraAgentPreferenceStore.defaultPreferencesURL(),
        gbrainRuntimeOnboardingStateURL: URL = ZebraGBrainRuntimeOnboardingStore.defaultStateURL(),
        gbrainOnboardingStateURL: URL = ZebraGBrainOnboardingStore.defaultStateURL(),
        gbrainAdapterOnboardingStateURL: URL = ZebraGBrainAdapterOnboardingStore.defaultStateURL(),
        sourceOnboardingStateURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectoryPath = Self.standardizedPath(homeDirectoryPath)
        self.agentOnboardingStateURL = agentOnboardingStateURL
        self.agentPreferenceURL = agentPreferenceURL
        self.agentEventsURL = agentOnboardingStateURL
            .deletingLastPathComponent()
            .appendingPathComponent("agent-cli-events.jsonl", isDirectory: false)
        self.gbrainRuntimeOnboardingStateURL = gbrainRuntimeOnboardingStateURL
        self.gbrainOnboardingStateURL = gbrainOnboardingStateURL
        self.gbrainAdapterOnboardingStateURL = gbrainAdapterOnboardingStateURL
        self.sourceOnboardingStateURL = sourceOnboardingStateURL
            ?? ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: homeDirectoryPath)
        self.gbrainRuntimeOnboardingStore = ZebraGBrainRuntimeOnboardingStore(
            stateURL: gbrainRuntimeOnboardingStateURL,
            fileManager: fileManager,
            homeDirectoryPath: homeDirectoryPath
        )
        self.gbrainAdapterOnboardingStore = ZebraGBrainAdapterOnboardingStore(
            stateURL: gbrainAdapterOnboardingStateURL,
            gbrainOnboardingStateURL: gbrainOnboardingStateURL,
            fileManager: fileManager,
            homeDirectoryPath: homeDirectoryPath
        )
        self.gbrainOnboardingStore = ZebraGBrainOnboardingStore(
            stateURL: gbrainOnboardingStateURL,
            fileManager: fileManager,
            homeDirectoryPath: homeDirectoryPath
        )
#if DEBUG
        self.developmentIncompleteStepIDs = Self.loadDevelopmentIncompleteStepIDs()
#endif
        refreshDetectedCompletion()
        prefetchGBrainDocsIfNeeded()
    }

    deinit {
        gbrainDocsPrefetchTask?.cancel()
#if os(macOS)
        completionRefreshWorkItem?.cancel()
        completionWatchSources.forEach { $0.cancel() }
#endif
    }

    public var totalCount: Int {
        Self.steps.count
    }

    public var completedCount: Int {
        completedStepIDs.intersection(Self.enabledStepIDs).count
    }

    public var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    public var isVisible: Bool {
        completedCount < totalCount
    }

    public static func automaticStepToStart(
        previousCompletedStepIDs previous: Set<ZebraOnboardingChecklistStepID>,
        currentCompletedStepIDs current: Set<ZebraOnboardingChecklistStepID>,
        didStartAgentStepInCurrentSession: Bool
    ) -> ZebraOnboardingChecklistStepID? {
        guard didStartAgentStepInCurrentSession,
              !previous.contains(.agent),
              current.contains(.agent),
              !current.contains(.gbrainRuntime) else {
            return nil
        }
        return .gbrainRuntime
    }

    public static func shouldBeginChainedRuntimeHandoff(
        previousCompletedStepIDs previous: Set<ZebraOnboardingChecklistStepID>,
        currentCompletedStepIDs current: Set<ZebraOnboardingChecklistStepID>,
        didLaunchRuntimeInAgentTerminal: Bool
    ) -> Bool {
        guard didLaunchRuntimeInAgentTerminal,
              !previous.contains(.agent),
              current.contains(.agent),
              !current.contains(.gbrainRuntime) else {
            return false
        }
        return true
    }

    public func prefetchGBrainDocsIfNeeded() {
        didStartGBrainDocsPrefetch = true
    }

    public var snapshots: [ZebraOnboardingChecklistStepSnapshot] {
        _ = substepSnapshotRevision
        let firstIncomplete = Self.steps.first { !completedStepIDs.contains($0.id) }?.id
        return Self.steps.map { step in
            let showsStart = firstIncomplete == step.id && runningStepID != step.id
            let wasStartedBefore = startedStepIDs.contains(step.id)
            let shouldProjectGBrainSubsteps = step.id == .gbrain
                && (runningStepID == .gbrain || wasStartedBefore)
            let substeps: [ZebraOnboardingChecklistSubstepSnapshot]
            if shouldProjectGBrainSubsteps {
                substeps = gbrainOnboardingStore.sectionSnapshotsFromCachedState(
                    isParentRunning: runningStepID == .gbrain,
                    showsStartForActiveSection: showsStart,
                    wasStartedBefore: wasStartedBefore
                )
            } else if step.id == .sourceOnboarding {
                substeps = sourceOnboardingSubstepsFromCachedState(
                    isParentRunning: runningStepID == .sourceOnboarding,
                    showsStartForActiveSource: showsStart
                )
            } else {
                substeps = []
            }
            return ZebraOnboardingChecklistStepSnapshot(
                id: step.id,
                number: step.number,
                isCompleted: completedStepIDs.contains(step.id),
                isDevelopmentCompleted: isDevelopmentCompleted(step.id),
                isActive: firstIncomplete == step.id,
                isRunning: runningStepID == step.id,
                showsStart: showsStart,
                wasStartedBefore: wasStartedBefore,
                substeps: substeps
            )
        }
    }

    public func syncExternalState(
        selectedVaultPath: String?,
        emailConnectionRepairState: ZebraEmailConnectionRepairState? = nil,
        emailConnectionVerified: Bool = false
    ) {
        let validVaultPath = Self.validDirectoryPath(
            selectedVaultPath,
            fileManager: fileManager
        )
        if self.selectedVaultPath != validVaultPath
            || self.emailConnectionRepairState != emailConnectionRepairState
            || self.emailConnectionVerified != emailConnectionVerified {
            self.selectedVaultPath = validVaultPath
            self.emailConnectionRepairState = emailConnectionRepairState
            self.emailConnectionVerified = emailConnectionVerified
        }
        refreshDetectedCompletion()
        prefetchGBrainDocsIfNeeded()
    }

    public func beginLaunch(stepID: ZebraOnboardingChecklistStepID) {
        activeStepID = stepID
        runningStepID = stepID
        startedStepIDs.insert(stepID)
        scheduleStaleTimeout(for: stepID)
    }

    public func cancelRunning(stepID: ZebraOnboardingChecklistStepID) {
        guard runningStepID == stepID else { return }
        launchGeneration += 1
        runningStepID = nil
    }

    private func scheduleStaleTimeout(for stepID: ZebraOnboardingChecklistStepID) {
        launchGeneration += 1
        let generation = launchGeneration
        let timeout = Self.steps.first { $0.id == stepID }?.staleTimeout ?? 300
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await MainActor.run { [weak self] in
                guard let self,
                      self.launchGeneration == generation,
                      self.runningStepID == stepID else { return }
                self.runningStepID = nil
                self.refreshDetectedCompletion(for: stepID)
            }
        }
    }

    public func refreshDetectedCompletion() {
        let runtimeCompletion = runtimeCompletionResult()
        refreshRuntimeInteractiveAuthRequest()
        refreshGBrainRecurringJobsCompletionSignal()
        let cachedGBrainCompletion = gbrainCompletionResultFromCachedReceipt(
            selectedVaultPath: selectedVaultPath
        )
        let sourceOnboardingCompletion = sourceOnboardingCompletionResult()
        let adapterCompletion = adapterCompletionResult(
            selectedVaultPath: selectedVaultPath
        )
        applyAllDetectedCompletion(
            agentCompleted: agentCompletionResult().isComplete,
            gbrainRuntimeCompletion: runtimeCompletion,
            gbrainCompleted: cachedGBrainCompletion.isComplete,
            sourceOnboardingCompleted: sourceOnboardingCompletion.isComplete,
            gbrainAdapterCompleted: adapterCompletion.isComplete
        )
    }

    public func refreshDetectedCompletion(for stepID: ZebraOnboardingChecklistStepID) {
        switch stepID {
        case .agent:
            applyDetectedCompletion(for: .agent, result: agentCompletionResult())
        case .gbrainRuntime:
            refreshRuntimeInteractiveAuthRequest()
            applyDetectedCompletion(for: .gbrainRuntime, result: runtimeCompletionResult())
        case .gbrain:
            invalidateGBrainSubstepSnapshots()
            refreshGBrainRecurringJobsCompletionSignal()
            let cached = gbrainCompletionResultFromCachedReceipt(selectedVaultPath: selectedVaultPath)
            applyDetectedCompletion(
                for: .gbrain,
                result: StepCompletionResult(isComplete: cached.isComplete, reasons: cached.reasons)
            )
        case .adapter:
            applyDetectedCompletion(
                for: .adapter,
                result: adapterCompletionResult(selectedVaultPath: selectedVaultPath)
            )
        case .sourceOnboarding:
            applyDetectedCompletion(for: .sourceOnboarding, result: sourceOnboardingCompletionResult())
            invalidateSubstepSnapshots()
        case .goals:
            break
        }
    }

    public func resolvedGBrainTargetVaultPath() -> String? {
        gbrainOnboardingStore.resolvedBrainRepoTargetPath()
    }

    public func gBrainNextSectionIsImportIndex() -> Bool {
        gbrainOnboardingStore.nextSectionIsImportIndexFromCachedState()
    }

    private func applyAllDetectedCompletion(
        agentCompleted: Bool,
        gbrainRuntimeCompletion: StepCompletionResult,
        gbrainCompleted: Bool,
        sourceOnboardingCompleted: Bool,
        gbrainAdapterCompleted: Bool
    ) {
        var completed = Set<ZebraOnboardingChecklistStepID>()

        if agentCompleted {
            completed.insert(.agent)
        }
        if shouldMarkRuntimeCompleted(gbrainRuntimeCompletion) {
            completed.insert(.gbrainRuntime)
        }
        if gbrainCompleted {
            completed.insert(.gbrain)
        }
        if sourceOnboardingCompleted {
            completed.insert(.sourceOnboarding)
        }
        if gbrainAdapterCompleted {
            completed.insert(.adapter)
        }
#if DEBUG
        applyDevelopmentCompletionOverrides(to: &completed)
#endif

        applyCompletedStepIDs(completed)
    }

    private func applyDetectedCompletion(
        for stepID: ZebraOnboardingChecklistStepID,
        result: StepCompletionResult
    ) {
        var completed = completedStepIDs
        let shouldComplete: Bool
        switch stepID {
        case .gbrainRuntime:
            shouldComplete = shouldMarkRuntimeCompleted(result)
        default:
            shouldComplete = result.isComplete
        }
        if shouldComplete {
            completed.insert(stepID)
        } else {
            completed.remove(stepID)
        }
#if DEBUG
        applyDevelopmentCompletionOverrides(to: &completed)
#endif
        applyCompletedStepIDs(completed)
    }

    private func applyCompletedStepIDs(_ completed: Set<ZebraOnboardingChecklistStepID>) {
        let enabledCompleted = completed.intersection(Self.enabledStepIDs)
        if let runningStepID, enabledCompleted.contains(runningStepID) {
            self.runningStepID = nil
        }
        if runningStepID == .gbrain,
           gbrainOnboardingStore.hasSourceRepoPrepareAbortMarker() {
            self.runningStepID = nil
        }
        if completedStepIDs != enabledCompleted {
            completedStepIDs = enabledCompleted
        }
    }

    private func invalidateGBrainSubstepSnapshots() {
        invalidateSubstepSnapshots()
    }

    private func invalidateSubstepSnapshots() {
        substepSnapshotRevision &+= 1
    }

    private func refreshGBrainRecurringJobsCompletionSignal() {
        let isCompleted = gbrainOnboardingStore.recurringJobsCompletedFromCachedState()
        if lastKnownGBrainRecurringJobsCompleted == false && isCompleted {
            gbrainRecurringJobsCompletionRevision &+= 1
        }
        lastKnownGBrainRecurringJobsCompleted = isCompleted
    }

    private func shouldMarkRuntimeCompleted(_ result: StepCompletionResult) -> Bool {
        if result.isComplete {
            return true
        }
        guard completedStepIDs.contains(.gbrainRuntime) else {
            return false
        }
        return !isHardRuntimeIncomplete(reasons: result.reasons)
    }

    private func isHardRuntimeIncomplete(reasons: [String]) -> Bool {
        let softReasons: Set<String> = [
            "executable_missing",
            "credential_source_missing",
            "credentials_unverified",
            "runtime_config_unverified",
            "llm_call_unverified",
        ]
        guard !reasons.isEmpty else { return false }
        return !Set(reasons).isSubset(of: softReasons)
    }

    private func agentCompletionResult() -> StepCompletionResult {
        StepCompletionResult(
            isComplete: !ZebraAgentOnboardingStartup.shouldRunAutomaticWelcome(
                preferencesURL: agentPreferenceURL,
                stateURL: agentOnboardingStateURL
            ),
            reasons: []
        )
    }

    private func runtimeCompletionResult() -> StepCompletionResult {
        let result = gbrainRuntimeOnboardingStore.cachedCompletionResult()
        return StepCompletionResult(isComplete: result.isComplete, reasons: result.reasons)
    }

    private func refreshRuntimeInteractiveAuthRequest() {
        pendingRuntimeInteractiveAuthRequest = gbrainRuntimeOnboardingStore.pendingInteractiveAuthRequest()
    }

    private func gbrainCompletionResultFromCachedReceipt(
        selectedVaultPath: String?
    ) -> ZebraGBrainOnboardingStore.CompletionResult {
        gbrainOnboardingStore.cachedCompletionResult(selectedVaultPath: selectedVaultPath)
    }

    private func adapterCompletionResult(selectedVaultPath: String?) -> StepCompletionResult {
        let result = gbrainAdapterOnboardingStore.cachedCompletionResult(
            selectedVaultPath: selectedVaultPath
        )
        return StepCompletionResult(isComplete: result.isComplete, reasons: result.reasons)
    }

    func sourceOnboardingPreviewState(now: Date = Date()) -> ZebraSourceOnboardingState {
        let gbrainTargetPath = resolvedGBrainTargetVaultPath()
        let adapterCompletion = adapterCompletionResult(selectedVaultPath: selectedVaultPath)
        let missingReason: String?
        if gbrainTargetPath == nil {
            missingReason = "gbrain_target_missing"
        } else if !adapterCompletion.isComplete {
            missingReason = "gbrain_adapter_missing"
        } else {
            missingReason = nil
        }
        return ZebraSourceOnboardingState(
            status: missingReason == nil ? .ready : .attention,
            entryContext: ZebraSourceOnboardingState.EntryContext(
                onboardingLanguageCode: ZebraOnboardingLanguage.current().code,
                gbrainWriteTargetPath: selectedVaultPath,
                gbrainTargetPath: gbrainTargetPath,
                gbrainTargetKey: gbrainTargetPath.map { "vault:\($0)" },
                gbrainReceiptPath: gbrainOnboardingStateURL.path,
                gbrainTargetStatus: gbrainTargetPath == nil ? nil : "receipt_target_available",
                gbrainTargetMissingReason: gbrainTargetPath == nil ? "gbrain_target_missing" : nil,
                gbrainWarnings: [],
                liveProbe: ZebraSourceOnboardingState.LiveProbe(
                    ran: false,
                    status: nil,
                    reason: gbrainTargetPath == nil ? "gbrain_target_missing" : "step3_receipt_available"
                ),
                adapterReady: adapterCompletion.isComplete,
                adapterReadinessReasons: adapterCompletion.reasons
            ),
            sourceReadiness: ZebraSourceOnboardingState.SourceReadiness(
                gmail: gmailSourceReadiness()
            ),
            updatedAt: now
        )
    }

    func recordSourceOnboardingInput(
        _ rawSourceInput: String,
        now: Date = Date()
    ) throws -> ZebraSourceOnboardingState {
        let normalized = ZebraSourceOnboardingCatalog.normalize(rawSourceInput: rawSourceInput)
        var state = sourceOnboardingPreviewState(now: now)
        state.status = normalized.uncatalogedSources.isEmpty ? .running : .attention
        state.progress = ZebraSourceOnboardingState.Progress(
            rawSourceInput: normalized.rawSourceInput,
            normalizedSourceList: normalized.normalizedSourceList,
            uncatalogedSources: normalized.uncatalogedSources,
            sourceConfirmation: ZebraSourceOnboardingState.SourceConfirmation(
                sourceIDs: normalized.normalizedSourceList,
                prompt: normalized.confirmationPrompt,
                status: .pending,
                confirmedAt: nil,
                updatedAt: now
            ),
            sourceRows: normalized.sourceRows,
            pendingQuestion: ZebraSourceOnboardingState.PendingQuestion(
                prompt: normalized.confirmationPrompt,
                status: "pending_source_confirmation",
                askedAt: now
            )
        )
        try writeSourceOnboardingState(state)
        return state
    }

    func confirmSourceOnboardingSources(now: Date = Date()) throws -> ZebraSourceOnboardingState {
        var state = loadSourceOnboardingState() ?? sourceOnboardingPreviewState(now: now)
        let sourceIDs = state.progress.normalizedSourceList
        let prompt = state.progress.sourceConfirmation?.prompt
            ?? ZebraSourceOnboardingCatalog.confirmationPrompt(for: sourceIDs)
        state.status = state.progress.uncatalogedSources.isEmpty ? .ready : .attention
        state.progress.sourceConfirmation = ZebraSourceOnboardingState.SourceConfirmation(
            sourceIDs: sourceIDs,
            prompt: prompt,
            status: .confirmed,
            confirmedAt: now,
            updatedAt: now
        )
        state.progress.pendingQuestion = nil
        for id in sourceIDs {
            guard var row = state.progress.sourceRows[id] else { continue }
            row.selectionState = "confirmed"
            row.updatedAt = now
            state.progress.sourceRows[id] = row
        }
        state.updatedAt = now
        try writeSourceOnboardingState(state)
        return state
    }

    func loadSourceOnboardingState() -> ZebraSourceOnboardingState? {
        guard let data = try? Data(contentsOf: sourceOnboardingStateURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ZebraSourceOnboardingState.self, from: data)
    }

    private func sourceOnboardingCompletionResult() -> StepCompletionResult {
        guard let state = loadSourceOnboardingState() else {
            return StepCompletionResult(isComplete: false, reasons: ["source_onboarding_state_missing"])
        }
        guard state.status == .completed else {
            return StepCompletionResult(isComplete: false, reasons: ["source_onboarding_not_completed"])
        }
        let executionOrder = state.progress.executionOrder ?? state.progress.normalizedSourceList
        guard !executionOrder.isEmpty else {
            return StepCompletionResult(isComplete: false, reasons: ["source_execution_order_missing"])
        }
        for sourceID in executionOrder {
            guard let row = state.progress.sourceRows[sourceID] else {
                return StepCompletionResult(isComplete: false, reasons: ["source_row_missing:\(sourceID)"])
            }
            guard row.status == "checked" || row.status == "skipped" else {
                return StepCompletionResult(isComplete: false, reasons: ["source_row_incomplete:\(sourceID)"])
            }
        }
        if state.progress.sourceRows.values.contains(where: { $0.status == "attention" }) {
            return StepCompletionResult(isComplete: false, reasons: ["source_row_attention"])
        }
        return StepCompletionResult(isComplete: true, reasons: [])
    }

    func sourceOnboardingSubstepsFromCachedState(
        isParentRunning: Bool,
        showsStartForActiveSource: Bool
    ) -> [ZebraOnboardingChecklistSubstepSnapshot] {
        guard let state = loadSourceOnboardingState() else { return [] }
        var substeps: [ZebraOnboardingChecklistSubstepSnapshot] = []

        let orderedSourceIDs = state.progress.normalizedSourceList
            + state.progress.sourceRows.keys
                .filter { !state.progress.normalizedSourceList.contains($0) }
                .sorted()
        let activeSourceID = activeSourceIDForSubsteps(in: state, orderedSourceIDs: orderedSourceIDs)
        for sourceID in orderedSourceIDs {
            guard let row = state.progress.sourceRows[sourceID] else { continue }
            substeps.append(
                sourceRowSubstep(
                    row,
                    isActive: row.id == activeSourceID,
                    isParentRunning: isParentRunning,
                    showsStartForActiveSource: showsStartForActiveSource
                )
            )
        }

        for uncataloged in state.progress.uncatalogedSources {
            substeps.append(uncatalogedSourceSubstep(uncataloged))
        }

        return substeps
    }

    private func sourceRowSubstep(
        _ row: ZebraSourceOnboardingState.SourceRow,
        isActive: Bool,
        isParentRunning: Bool,
        showsStartForActiveSource: Bool
    ) -> ZebraOnboardingChecklistSubstepSnapshot {
        let isCompleted = row.status == "checked"
        let isSkipped = row.status == "skipped"
        let isRunning = isParentRunning && isActive
        let canStart = !isCompleted && !isSkipped && isActive && !isRunning
        let wasStartedBefore = row.playbookStepID != nil
            || row.status == "running"
            || row.status == "attention"
        return ZebraOnboardingChecklistSubstepSnapshot(
            id: "source-row-\(row.id)",
            title: row.displayName ?? row.id,
            detail: nil,
            isCompleted: isCompleted,
            isActive: isActive,
            isWaitingForUser: row.selectionState == "pending_confirmation",
            isRunning: isRunning,
            showsStart: showsStartForActiveSource && canStart,
            wasStartedBefore: wasStartedBefore,
            isAttention: row.status == "attention",
            isSkipped: isSkipped
        )
    }

    private func activeSourceIDForSubsteps(
        in state: ZebraSourceOnboardingState,
        orderedSourceIDs: [String]
    ) -> String? {
        let confirmed = state.progress.sourceConfirmation?.status == .confirmed
        guard confirmed else { return nil }
        if let activeSourceID = state.progress.activeSourceID,
           let activeRow = state.progress.sourceRows[activeSourceID],
           !Self.sourceRowIsTerminal(activeRow) {
            return activeSourceID
        }
        return orderedSourceIDs.first { sourceID in
            guard let row = state.progress.sourceRows[sourceID] else { return false }
            return !Self.sourceRowIsTerminal(row)
        }
    }

    private static func sourceRowIsTerminal(
        _ row: ZebraSourceOnboardingState.SourceRow
    ) -> Bool {
        row.status == "checked" || row.status == "skipped"
    }

    private func uncatalogedSourceSubstep(
        _ uncataloged: ZebraSourceOnboardingState.UncatalogedSource
    ) -> ZebraOnboardingChecklistSubstepSnapshot {
        ZebraOnboardingChecklistSubstepSnapshot(
            id: "uncataloged-source-\(uncataloged.normalizedValue)",
            title: uncataloged.displayName ?? uncataloged.rawValue,
            detail: nil,
            isCompleted: false,
            isActive: false,
            isWaitingForUser: true,
            isRunning: false,
            showsStart: false,
            wasStartedBefore: true,
            isAttention: true
        )
    }

    private func writeSourceOnboardingState(_ state: ZebraSourceOnboardingState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try fileManager.createDirectory(
            at: sourceOnboardingStateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: sourceOnboardingStateURL, options: .atomic)
    }

    func gmailSourceReadiness() -> ZebraSourceOnboardingState.GmailReadiness {
        let envPath = clawvisorEmailEnvURL.path
        if let repair = emailConnectionRepairState {
            return ZebraSourceOnboardingState.GmailReadiness(
                status: .attention,
                connectionPath: "existing_clawvisor_gmail_connection_path",
                envPath: envPath,
                localArtifact: nil,
                repairKind: repair.kind.rawValue,
                reasons: ["connection_repair_active"]
            )
        }
        guard clawvisorEmailEnvHasRequiredKeys else {
            return ZebraSourceOnboardingState.GmailReadiness(
                status: .missingEnv,
                connectionPath: "existing_clawvisor_gmail_connection_path",
                envPath: envPath,
                localArtifact: nil,
                repairKind: nil,
                reasons: ["clawvisor_email_env_missing_or_incomplete"]
            )
        }
        guard emailConnectionVerified else {
            return ZebraSourceOnboardingState.GmailReadiness(
                status: .unverified,
                connectionPath: "existing_clawvisor_gmail_connection_path",
                envPath: envPath,
                localArtifact: nil,
                repairKind: nil,
                reasons: ["email_connection_unverified"]
            )
        }
        return ZebraSourceOnboardingState.GmailReadiness(
            status: .ready,
            connectionPath: "existing_clawvisor_gmail_connection_path",
            envPath: envPath,
            localArtifact: nil,
            repairKind: nil,
            reasons: []
        )
    }

#if os(macOS)
    public func activateCompletionWatching() {
        guard !isCompletionWatching else { return }
        isCompletionWatching = true
        recordWatchedCompletionFileSignatures()
        startCompletionFileWatching()
        refreshDetectedCompletion()
    }

    public func deactivateCompletionWatching() {
        isCompletionWatching = false
        pendingRuntimeInteractiveAuthRequest = nil
        stopCompletionFileWatching()
    }

    private func startCompletionFileWatching() {
        completionWatchSources.forEach { $0.cancel() }
        completionWatchSources = []

        let gbrainDirectoryPath = (homeDirectoryPath as NSString).appendingPathComponent(".gbrain")
        let directoryPaths = Set(watchedCompletionFiles.map { $0.url.deletingLastPathComponent().path })

        for directoryPath in directoryPaths {
            installCompletionDirectoryWatcher(
                directoryPath: directoryPath,
                securePermissions: directoryPath == gbrainDirectoryPath
            )
        }

    }

    private func stopCompletionFileWatching() {
        completionRefreshWorkItem?.cancel()
        completionRefreshWorkItem = nil
        pendingCompletionRefreshStepIDs = []
        completionWatchSources.forEach { $0.cancel() }
        completionWatchSources = []
        watchedCompletionFileSignatures = [:]
    }

    private func installCompletionDirectoryWatcher(
        directoryPath: String,
        securePermissions: Bool
    ) {
        try? fileManager.createDirectory(
            atPath: directoryPath,
            withIntermediateDirectories: true,
            attributes: securePermissions ? [.posixPermissions: 0o700] : nil
        )
        if securePermissions {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryPath)
        }
        let fd = open(directoryPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: completionWatchQueue
        )
        source.setEventHandler { [weak self] in
            let flags = source.data
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isCompletionWatching else { return }
                if securePermissions || flags.contains(.delete) || flags.contains(.rename) {
                    self.startCompletionFileWatching()
                }
                self.scheduleCompletionRefresh(for: self.changedWatchedStepIDs())
            }
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        completionWatchSources.append(source)
    }

    private func scheduleCompletionRefresh(for stepIDs: Set<ZebraOnboardingChecklistStepID>) {
        guard !stepIDs.isEmpty else { return }
        if let runningID = runningStepID, stepIDs.contains(runningID) {
            scheduleStaleTimeout(for: runningID)
        }
        pendingCompletionRefreshStepIDs.formUnion(stepIDs)
        completionRefreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isCompletionWatching else { return }
                let stepIDs = self.pendingCompletionRefreshStepIDs
                self.pendingCompletionRefreshStepIDs = []
                stepIDs.forEach { self.refreshDetectedCompletion(for: $0) }
            }
        }
        completionRefreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: item)
    }

    private var watchedCompletionFiles: [WatchedCompletionFile] {
        [
            WatchedCompletionFile(url: agentOnboardingStateURL, stepID: .agent),
            WatchedCompletionFile(url: agentEventsURL, stepID: .agent),
            WatchedCompletionFile(url: agentPreferenceURL, stepID: .agent),
            WatchedCompletionFile(url: gbrainRuntimeOnboardingStateURL, stepID: .gbrainRuntime),
            WatchedCompletionFile(url: gbrainOnboardingStateURL, stepID: .gbrain),
            WatchedCompletionFile(url: gbrainAdapterOnboardingStateURL, stepID: .adapter),
            WatchedCompletionFile(url: sourceOnboardingStateURL, stepID: .sourceOnboarding),
            WatchedCompletionFile(url: clawvisorEmailEnvURL, stepID: .sourceOnboarding),
        ]
    }

    private func recordWatchedCompletionFileSignatures() {
        watchedCompletionFileSignatures = Dictionary(
            uniqueKeysWithValues: watchedCompletionFiles.map { file in
                (file.url.path, completionFileSignature(for: file.url))
            }
        )
    }

    private func changedWatchedStepIDs() -> Set<ZebraOnboardingChecklistStepID> {
        var changed = Set<ZebraOnboardingChecklistStepID>()
        for file in watchedCompletionFiles {
            let next = completionFileSignature(for: file.url)
            let previous = watchedCompletionFileSignatures[file.url.path]
            if previous != next {
                watchedCompletionFileSignatures[file.url.path] = next
                changed.insert(file.stepID)
            }
        }
        return changed
    }

    private func completionFileSignature(for url: URL) -> CompletionFileSignature {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return CompletionFileSignature(exists: false, modificationTime: nil, size: nil)
        }
        return CompletionFileSignature(
            exists: true,
            modificationTime: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970,
            size: attributes[.size] as? UInt64
        )
    }
#endif

#if DEBUG
    private static func loadDevelopmentIncompleteStepIDs() -> Set<ZebraOnboardingChecklistStepID> {
        loadDevelopmentStepIDs(defaultsKey: developmentIncompleteStepIDsDefaultsKey)
    }

    private static func loadDevelopmentStepIDs(defaultsKey: String) -> Set<ZebraOnboardingChecklistStepID> {
        let rawValues = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        return Set(
            rawValues
                .compactMap(ZebraOnboardingChecklistStepID.init(rawValue:))
        )
    }

    private func applyDevelopmentCompletionOverrides(
        to completed: inout Set<ZebraOnboardingChecklistStepID>
    ) {
        completed.subtract(developmentIncompleteStepIDs)
    }
#endif

    private func isDevelopmentCompleted(_ stepID: ZebraOnboardingChecklistStepID) -> Bool {
        _ = stepID
        return false
    }

    private var clawvisorEmailEnvHasRequiredKeys: Bool {
        guard let raw = try? String(contentsOf: clawvisorEmailEnvURL, encoding: .utf8) else {
            return false
        }
        let requiredKeys = [
            "CLAWVISOR_URL",
            "CLAWVISOR_AGENT_TOKEN",
            "CLAWVISOR_TASK_ID",
        ]
        return requiredKeys.allSatisfy { key in
            raw.split(separator: "\n").contains { line in
                Self.dotEnvKey(in: String(line)) == key
            }
        }
    }

    private static func dotEnvKey(in line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("#") else { return nil }
        if text.hasPrefix("export ") {
            text = String(text.dropFirst("export ".count))
        }
        guard let equals = text.firstIndex(of: "=") else { return nil }
        let key = String(text[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private var clawvisorEmailEnvURL: URL {
        URL(fileURLWithPath: homeDirectoryPath, isDirectory: true)
            .appendingPathComponent(".gbrain", isDirectory: true)
            .appendingPathComponent(".env", isDirectory: false)
    }

    private static func validDirectoryPath(
        _ path: String?,
        fileManager: FileManager
    ) -> String? {
        guard let path else { return nil }
        let standardized = standardizedPath((path as NSString).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return standardized
    }

    private static func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }
}

public enum ZebraOnboardingChecklistCommand {
    public struct LaunchPlan {
        public let startupLine: String
        public let launchesGBrainRuntimeInAgentTerminal: Bool
        public let chainedCommandFilePath: String?
    }

    public static func shellStartupLine(
        for stepID: ZebraOnboardingChecklistStepID,
        selectedVaultPath: String?
    ) -> String? {
        launchPlan(for: stepID, selectedVaultPath: selectedVaultPath)?.startupLine
    }

    public static func launchPlan(
        for stepID: ZebraOnboardingChecklistStepID,
        selectedVaultPath: String?,
        chainGBrainRuntimeAfterAgent: Bool = false,
        useSelectedRuntimeForSourceOnboarding: Bool = true
    ) -> LaunchPlan? {
        let cwd = launchDirectory(selectedVaultPath: selectedVaultPath)
        let language = ZebraOnboardingLanguage.current()
        switch stepID {
        case .agent:
            return agentLaunchPlan(
                cwd: cwd,
                language: language,
                chainGBrainRuntimeAfterAgent: chainGBrainRuntimeAfterAgent
            )
        case .gbrainRuntime:
            guard let launch = ZebraGBrainRuntimeOnboardingStore().prepareLaunch() else {
                return nil
            }
            return standaloneLaunchPlan(gbrainRuntimeStartupLine(launch: launch))
        case .gbrain:
            guard let runtime = ZebraGBrainRuntimeOnboardingStore().selectedRuntimeForGBrainSetup() else {
                return nil
            }
            guard let launch = ZebraGBrainOnboardingStore().prepareLaunch(
                selectedVaultPath: selectedVaultPath
            ) else {
                return nil
            }
            return standaloneLaunchPlan(gbrainSetupRuntimeStartupLine(launch: launch, runtime: runtime))
        case .adapter:
            return ZebraGBrainAdapterOnboardingStore().prepareLaunch(
                selectedVaultPath: selectedVaultPath
            ).flatMap { standaloneLaunchPlan($0.startupLine) }
        case .sourceOnboarding:
            guard let launch = ZebraSourceOnboardingHelper().prepareLaunch(
                selectedVaultPath: selectedVaultPath
            ) else {
                return nil
            }
            let prompt = sourceOnboardingBoundaryPrompt(selectedVaultPath: selectedVaultPath)
            if useSelectedRuntimeForSourceOnboarding,
               let runtime = ZebraGBrainRuntimeOnboardingStore().selectedRuntimeForGBrainSetup() {
                return standaloneLaunchPlan(
                    sourceOnboardingRuntimeStartupLine(
                        launch: launch,
                        runtime: runtime,
                        prompt: prompt
                    )
                )
            }
            return standaloneLaunchPlan(
                agentStartupLine(
                    cwd: launch.launchDirectory,
                    prompt: prompt,
                    shellEnvironmentPrefix: launch.shellEnvironmentPrefix
                )
            )
        case .goals:
            return standaloneLaunchPlan(
                agentStartupLine(
                    cwd: cwd,
                    prompt: """
                    Help me finish Zebra onboarding by creating one useful starter goal and one starter task in this vault using the local brain conventions. Then give a short walkthrough of how to open goals, tasks, email, and documents from the Zebra sidebar.
                    """
                )
            )
        }
    }

    private static func sourceOnboardingBoundaryPrompt(selectedVaultPath: String?) -> String {
        let statePath = ZebraSourceOnboardingState.defaultStateURL().path
        let gbrainWriteTargetContext = selectedVaultPath ?? "not selected"
        let gbrainTargetPath = ZebraGBrainOnboardingStore().resolvedBrainRepoTargetPath()
        let gbrainTargetContext = gbrainTargetPath ?? "missing: gbrain_target_missing"
        return """
        Start Zebra Source Onboarding for the active brain.

        State file path:
        \(statePath)

        Brain write target path (selected brain repo; not an Obsidian source vault):
        \(gbrainWriteTargetContext)

        Brain target context:
        \(gbrainTargetContext)

        Scope for this run:
        - Use the Step 3 GBrain setup receipt as the primary target readiness source.
        - Source Onboarding is Step 5 and runs after Step 4 gbrain-adapter is installed. If `entryContext.adapterReady` is false, stop and tell the user to finish the gbrain-adapter step first.
        - Treat this step as injecting approved user source data into the active brain, not as installing the adapter.
        - You are running inside the selected agent runtime when Zebra has a verified runtime receipt. Treat vault file access results as runtime-specific.
        - If Obsidian listing or file reads fail with permission errors in this runtime, report the runtime access failure instead of saying the vault has 0 Markdown files.
        - Hermes vault access still needs separate verification; if this run is in Hermes, explicitly verify listing and smoke-read before ingest.
        - Treat the brain write target path only as Zebra's selected brain repo write context. Do not use it as an Obsidian source vault path.
        - Ask which sources Zebra should understand for this first source intake.
        - Always run `zebra-source-onboarding status --json` before asking. If its `sourceInputPrompt` is present, use that prompt as the user-facing source question instead of inventing separate copy.
        - If the status payload offers existing agent memory as a source option, fold it into the same source-selection question. Do not ask a separate "found agent memory" question.
        - Normalize source aliases into source candidates when they are in the current source catalog.
        - Keep inputs that are not in the current catalog as uncataloged sources; do not describe them to the user as unavailable or impossible.
        - The source-list confirmation question must include every source the user named, including uncataloged sources.
        - Use the zebra-source-onboarding helper as the Source Onboarding state write path.
        - After source-list confirmation, run zebra-source-onboarding next and follow only the active source returned by the helper.
        - Gmail, Obsidian, iMessage, Notion, and Apple Notes runners are implemented in this helper slice.
        - Do not edit source-onboarding-state.json directly; continue only from helper stdout `nextPrompt` and use `nextPromptPath` only as the file fallback.

        Helper flow:
        1. Run zebra-source-onboarding status --json first to create or inspect the current compact state.
        2. If status shows a pending source confirmation, ask that confirmation question before collecting new source input.
        3. If no source input has been recorded yet, ask the user for free-text source input using the helper-provided `sourceInputPrompt` when available.
        4. Run zebra-source-onboarding intake with the raw answer and your extracted candidates.
           Example:
           zebra-source-onboarding intake --raw "옵시디언, 지메일 사용자소스" --candidate obsidian=옵시디언 --candidate gmail=지메일 --uncataloged custom-source=사용자소스
        5. Ask the source-list confirmation question from the helper output.
        6. Run zebra-source-onboarding confirm --answer yes or zebra-source-onboarding confirm --answer no.
        7. If the confirmation was yes, run zebra-source-onboarding next.
        8. Follow the active source `nextPrompt` exactly. When a source reaches its `complete` step, first run `zebra-source-onboarding report --status completed --source <source-id>` and continue only from that report command's stdout.
        9. Run zebra-source-onboarding status --json and report the saved state path plus compact saved-state summary.

        GBrain live probe policy:
        - Prefer the Step 3 receipt when it is complete and consistent.
        - If the receipt is missing or contradictory and a live read-only probe is necessary, run one command with --timeout=3600s.
        - If that live probe times out, record it as deferred.
        """
    }

    private static func agentLaunchPlan(
        cwd: String,
        language: ZebraOnboardingLanguage,
        chainGBrainRuntimeAfterAgent: Bool
    ) -> LaunchPlan? {
        let commandFilePath: String?
        if chainGBrainRuntimeAfterAgent,
           let launch = ZebraGBrainRuntimeOnboardingStore().prepareLaunch() {
            let commandFileURL = chainedGBrainRuntimeCommandFileURL()
            commandFilePath = writeChainedGBrainRuntimeCommandFile(
                launch: launch,
                commandFileURL: commandFileURL
            ) ? commandFileURL.path : nil
        } else {
            commandFilePath = nil
        }

        guard let startupLine = ZebraAgentOnboardingScriptCommand.shellStartupLine(
                command: .run,
                cwd: cwd,
                languageCode: language.code,
                continueWithCommandFile: commandFilePath
            )
        else { return nil }

        return LaunchPlan(
            startupLine: startupLine,
            launchesGBrainRuntimeInAgentTerminal: commandFilePath != nil,
            chainedCommandFilePath: commandFilePath
        )
    }

    private static func standaloneLaunchPlan(_ startupLine: String?) -> LaunchPlan? {
        guard let startupLine else { return nil }
        return LaunchPlan(
            startupLine: startupLine,
            launchesGBrainRuntimeInAgentTerminal: false,
            chainedCommandFilePath: nil
        )
    }

    private static func chainedGBrainRuntimeCommandFileURL() -> URL {
        ZebraGBrainOnboardingStore.onboardingDirectoryURL()
            .appendingPathComponent(
                "chained-step2-command-\(UUID().uuidString).sh",
                isDirectory: false
            )
    }

    @discardableResult
    static func writeChainedGBrainRuntimeCommandFile(
        launch: ZebraGBrainRuntimeOnboardingStore.LaunchContext,
        commandFileURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        do {
            try fileManager.createDirectory(
                at: commandFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try chainedGBrainRuntimeCommandScript(launch: launch)
                .write(to: commandFileURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: commandFileURL.path)
            return true
        } catch {
            return false
        }
    }

    static func chainedGBrainRuntimeCommandScript(
        launch: ZebraGBrainRuntimeOnboardingStore.LaunchContext
    ) -> String {
        let executableExpression = "\"$ZEBRA_AGENT_EXECUTABLE\""
        let cases = MarkdownPillAgent.allCases.map { agent -> String in
            let command = shellScriptCommand(
                fromTerminalStartupLine: gbrainRuntimeStartupLine(
                    launch: launch,
                    agent: agent,
                    executableShellExpression: executableExpression,
                    shouldPrepareCodexGBrainSetupConfig: false
                )
            )
            return """
              \(agent.rawValue))
                \(command)
                ;;
            """
        }.joined(separator: "\n")

        return """
        #!/usr/bin/env bash
        set -euo pipefail
        : "${ZEBRA_SELECTED_AGENT:?}"
        : "${ZEBRA_AGENT_EXECUTABLE:?}"
        case "${ZEBRA_SELECTED_AGENT}" in
        \(cases)
          *)
            printf 'Unsupported Zebra chained onboarding agent: %s\\n' "${ZEBRA_SELECTED_AGENT}" >&2
            exit 2
            ;;
        esac
        """
    }

    private static func shellScriptCommand(fromTerminalStartupLine line: String) -> String {
        var command = line
        while let last = command.last, last == "\r" || last == "\n" {
            command.removeLast()
        }
        return command
    }

    static func gbrainSetupRuntimeStartupLine(
        launch: ZebraGBrainOnboardingStore.LaunchContext,
        runtime: ZebraGBrainRuntimeOnboardingStore.SelectedRuntime,
        language: ZebraOnboardingLanguage = ZebraOnboardingLanguage.current()
    ) -> String {
        let prepareSourceRepoPrefix = launch.existingInstallVerificationMode
            ? "printf '%s\\n' \(ZebraAgentLaunchCommand.shellQuote(language.gbrainRuntimeLauncherPrepareMessage)) && "
            : [
                "printf '%s\\n' \(ZebraAgentLaunchCommand.shellQuote(language.gbrainSourceRepoPrepareMessage))",
                "zebra-gbrain-onboarding prepare-source-repo",
                "eval \"$(zebra-gbrain-onboarding active-source-env)\"",
                "printf '%s\\n' \(ZebraAgentLaunchCommand.shellQuote(language.gbrainRuntimeLauncherPrepareMessage))",
            ].joined(separator: " && ") + " && "
        let startupLine = gbrainSetupSelectedRuntimeCommand(
            launch: launch,
            runtime: runtime,
            language: language
        )
        return "\(launch.shellEnvironmentPrefix)\(prepareSourceRepoPrefix)\(startupLine)"
    }

    static func gbrainRuntimeStartupLine(
        launch: ZebraGBrainRuntimeOnboardingStore.LaunchContext,
        agent: MarkdownPillAgent = MarkdownPillAgent.defaultAgent(),
        codexConfigURL: URL? = nil,
        executableShellExpression: String? = nil,
        shouldPrepareCodexGBrainSetupConfig: Bool = true
    ) -> String {
        if agent == .codex && shouldPrepareCodexGBrainSetupConfig {
            if let codexConfigURL {
                _ = MarkdownChatPillCommand.prepareCodexGBrainSetupConfig(
                    cwd: launch.launchDirectory,
                    configURL: codexConfigURL
                )
            } else {
                _ = MarkdownChatPillCommand.prepareCodexGBrainSetupConfig(cwd: launch.launchDirectory)
            }
        }
        return agentStartupLine(
            cwd: launch.launchDirectory,
            prompt: launch.startupPrompt,
            agent: agent,
            shellEnvironmentPrefix: launch.shellEnvironmentPrefix,
            useGBrainSetupLaunch: true,
            shouldPrepareCodexGBrainSetupConfig: false,
            executableShellExpression: executableShellExpression
        )
    }

    private static func gbrainSetupSelectedRuntimeCommand(
        launch: ZebraGBrainOnboardingStore.LaunchContext,
        runtime: ZebraGBrainRuntimeOnboardingStore.SelectedRuntime,
        language: ZebraOnboardingLanguage = .en
    ) -> String {
        let executable = ZebraAgentLaunchCommand.shellQuote(runtime.executablePath)
        let runId = ZebraAgentLaunchCommand.shellQuote(launch.runId)
        let runtimeDisplayName = gbrainRuntimeDisplayName(runtime.runtime)
        let startMessage = "printf '%s\\n' \(ZebraAgentLaunchCommand.shellQuote(language.gbrainRuntimeStartMessage(runtimeDisplayName: runtimeDisplayName)))"
        switch runtime.runtime {
        case "openclaw":
            let agentID = openClawAgentID(runId: launch.runId)
            let sessionKey = "agent:\(agentID):\(launch.runId)"
            return "eval \"$(zebra-gbrain-onboarding write-runtime-launcher --runtime 'openclaw' --executable \(executable) --run-id \(runId) --agent-id \(ZebraAgentLaunchCommand.shellQuote(agentID)) --session \(ZebraAgentLaunchCommand.shellQuote(sessionKey)))\" && \(startMessage) && \"$ZEBRA_GBRAIN_RUNTIME_LAUNCHER\"\r"
        case "hermes":
            return "eval \"$(zebra-gbrain-onboarding write-runtime-launcher --runtime 'hermes' --executable \(executable) --run-id \(runId))\" && \(startMessage) && \"$ZEBRA_GBRAIN_RUNTIME_LAUNCHER\"\r"
        default:
            return "echo 'Unsupported OpenClaw/Hermes runtime for GBrain setup: \(runtime.runtime)' >&2 && exit 1\r"
        }
    }

    static func sourceOnboardingRuntimeStartupLine(
        launch: ZebraSourceOnboardingHelper.LaunchContext,
        runtime: ZebraGBrainRuntimeOnboardingStore.SelectedRuntime,
        prompt: String,
        language: ZebraOnboardingLanguage = ZebraOnboardingLanguage.current()
    ) -> String {
        guard let launchPlan = ZebraSourceOnboardingRuntimeLaunchPlan.make(
            launch: launch,
            runtime: runtime,
            prompt: prompt,
            language: language
        ) else {
            return agentStartupLine(
                cwd: launch.launchDirectory,
                prompt: prompt,
                shellEnvironmentPrefix: launch.shellEnvironmentPrefix
            )
        }
        return launchPlan.terminalStartupLine
    }

    private static func gbrainRuntimeDisplayName(_ runtime: String) -> String {
        switch runtime {
        case "openclaw":
            return "OpenClaw"
        case "hermes":
            return "Hermes"
        default:
            return runtime
        }
    }

    private static func openClawAgentID(runId: String) -> String {
        let safeRunId = runId
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "-" {
                    return character
                }
                return "-"
            }
        let suffix = String(String(safeRunId).suffix(12)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "zebra-gbrain-setup-\(suffix.isEmpty ? "run" : suffix)"
    }

    private static func agentStartupLine(
        cwd: String,
        prompt: String,
        agent: MarkdownPillAgent = MarkdownPillAgent.defaultAgent(),
        shellEnvironmentPrefix: String = "",
        useGBrainSetupLaunch: Bool = false,
        shouldPrepareCodexGBrainSetupConfig: Bool = true,
        executableShellExpression: String? = nil
    ) -> String {
        let localizedPrompt = "\(ZebraOnboardingLanguage.current().promptPolicy)\n\n\(prompt)"
        _ = MarkdownChatPillCommand.prepareLaunchEnvironment(
            agent: agent,
            markdownFilePath: nil,
            launchDirectory: cwd
        )
        if useGBrainSetupLaunch, agent == .codex, shouldPrepareCodexGBrainSetupConfig {
            _ = MarkdownChatPillCommand.prepareCodexGBrainSetupConfig(cwd: cwd)
        }
        let startupLine: String
        if useGBrainSetupLaunch {
            startupLine = MarkdownChatPillCommand.shellStartupLineForGBrainSetup(
                agent: agent,
                cwd: cwd,
                userPrompt: localizedPrompt,
                model: gbrainRuntimePrimaryAgentModel(agent),
                allowTrustedAutomation: true,
                allowLaunchDirectoryTrust: true,
                allowApprovalAutomation: true,
                executableShellExpression: executableShellExpression
            )
        } else {
            startupLine = MarkdownChatPillCommand.shellStartupLine(
                agent: agent,
                markdownFilePath: nil,
                surface: .fallback(typeLabel: "onboarding"),
                userPrompt: localizedPrompt,
                launchDirectory: cwd
            )
        }
        if shellEnvironmentPrefix.isEmpty {
            return startupLine
        }
        return "\(shellEnvironmentPrefix)\(startupLine)"
    }

    private static func gbrainRuntimePrimaryAgentModel(_ agent: MarkdownPillAgent) -> String? {
        switch agent {
        case .codex:
            return "gpt-5.5"
        case .claude:
            return "opus"
        case .antigravity:
            return nil
        }
    }

    private static func launchDirectory(selectedVaultPath: String?) -> String {
        if let selectedVaultPath,
           isDirectory(selectedVaultPath) {
            return (selectedVaultPath as NSString).standardizingPath
        }

        let home = NSHomeDirectory()
        return home.isEmpty ? "/" : (home as NSString).standardizingPath
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: (path as NSString).expandingTildeInPath,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}

public struct ZebraOnboardingChecklistCard: View {
    private static let collapsedSubstepDefaultsKey = "ZebraOnboardingChecklistCard.collapsedSubstepStepIDs"

    @ObservedObject private var store: ZebraOnboardingChecklistStore
    private let onStartStep: (ZebraOnboardingChecklistStepID) -> Void
    private let onStopStep: ((ZebraOnboardingChecklistStepID) -> Void)?
    private let onCollapse: (() -> Void)?
    @State private var collapsedSubstepStepIDRawValues: [String]
    @State private var observedCompletedStepIDs: Set<ZebraOnboardingChecklistStepID>?

    public init(
        store: ZebraOnboardingChecklistStore,
        onStartStep: @escaping (ZebraOnboardingChecklistStepID) -> Void,
        onStopStep: ((ZebraOnboardingChecklistStepID) -> Void)? = nil,
        onCollapse: (() -> Void)? = nil
    ) {
        self.store = store
        self.onStartStep = onStartStep
        self.onStopStep = onStopStep
        self.onCollapse = onCollapse
        _collapsedSubstepStepIDRawValues = State(
            initialValue: Self.loadCollapsedSubstepStepIDRawValues()
        )
    }

    public var body: some View {
        Group {
            if store.isVisible {
                VStack(spacing: 0) {
                    header
                    VStack(spacing: 0) {
                        ForEach(store.snapshots) { snapshot in
                            ZebraOnboardingChecklistRow(
                                snapshot: snapshot,
                                title: Self.title(for: snapshot.id),
                                isSubstepListCollapsed: collapsedSubstepStepIDs.contains(snapshot.id),
                                onToggleSubstepList: toggleSubstepListAction(for: snapshot),
                                onStart: { onStartStep(snapshot.id) },
                                onStop: onStopStep.map { callback in { callback(snapshot.id) } },
                                onDevelopmentToggle: developmentToggleAction(for: snapshot.id)
                            )
                        }
                    }
                    .padding(.bottom, 5)
                }
                .background(ZebraOnboardingChecklistPalette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(ZebraOnboardingChecklistPalette.panelBorder, lineWidth: 1)
                )
                .shadow(color: BVColor.shadow, radius: 24, x: 0, y: 10)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ZebraOnboardingChecklistCard")
                .onAppear {
                    store.prefetchGBrainDocsIfNeeded()
                    observedCompletedStepIDs = store.completedStepIDs
                }
                .onChange(of: store.completedStepIDs) { _, completedStepIDs in
                    handleCompletionChange(completedStepIDs)
                }
            }
        }
    }

    private var collapsedSubstepStepIDs: Set<ZebraOnboardingChecklistStepID> {
        get {
            Set(collapsedSubstepStepIDRawValues.compactMap(ZebraOnboardingChecklistStepID.init(rawValue:)))
        }
        nonmutating set {
            let rawValues = newValue.map(\.rawValue).sorted()
            collapsedSubstepStepIDRawValues = rawValues
            UserDefaults.standard.set(rawValues, forKey: Self.collapsedSubstepDefaultsKey)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZebraOnboardingProgressRing(
                completed: store.completedCount,
                total: store.totalCount,
                progress: store.progressFraction
            )
            Text(String(localized: "brain.onboarding.checklist.title", defaultValue: "Get started with Zebra"))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(BVColor.fg)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let onCollapse {
                ZebraOnboardingChecklistCollapseButton(action: onCollapse)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(BVColor.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private static func title(for stepID: ZebraOnboardingChecklistStepID) -> String {
        switch stepID {
        case .agent:
            return String(
                localized: "brain.onboarding.checklist.step.agent",
                defaultValue: "Scan agent CLIs and choose the primary agent"
            )
        case .gbrainRuntime:
            return String(
                localized: "brain.onboarding.checklist.step.gbrainRuntime",
                defaultValue: "Prepare OpenClaw or Hermes"
            )
        case .gbrain:
            return String(
                localized: "brain.onboarding.checklist.step.gbrain",
                defaultValue: "Check GBrain and link the vault/profile"
            )
        case .sourceOnboarding:
            return String(
                localized: "brain.onboarding.checklist.step.sourceOnboarding",
                defaultValue: "Source Onboarding"
            )
        case .adapter:
            return String(
                localized: "brain.onboarding.checklist.step.adapter",
                defaultValue: "Clone and install gbrain-adapter"
            )
        case .goals:
            return String(
                localized: "brain.onboarding.checklist.step.goals",
                defaultValue: "Create a starter task/goal and learn the flow"
            )
        }
    }

    private func developmentToggleAction(
        for stepID: ZebraOnboardingChecklistStepID
    ) -> (() -> Void)? {
        _ = stepID
        return nil
    }

    private func toggleSubstepListAction(
        for snapshot: ZebraOnboardingChecklistStepSnapshot
    ) -> (() -> Void)? {
        guard !snapshot.substeps.isEmpty else { return nil }
        return {
            var collapsed = collapsedSubstepStepIDs
            if collapsed.contains(snapshot.id) {
                collapsed.remove(snapshot.id)
            } else {
                collapsed.insert(snapshot.id)
            }
            collapsedSubstepStepIDs = collapsed
        }
    }

    private func handleCompletionChange(
        _ completedStepIDs: Set<ZebraOnboardingChecklistStepID>
    ) {
        guard let previous = observedCompletedStepIDs else {
            observedCompletedStepIDs = completedStepIDs
            return
        }
        observedCompletedStepIDs = completedStepIDs
        let newlyCompletedStepIDs = completedStepIDs.subtracting(previous)
        let substepStepIDs = store.snapshots
            .filter { newlyCompletedStepIDs.contains($0.id) && !$0.substeps.isEmpty }
            .map(\.id)
        guard !substepStepIDs.isEmpty else { return }
        var collapsed = collapsedSubstepStepIDs
        collapsed.formUnion(substepStepIDs)
        collapsedSubstepStepIDs = collapsed
    }

    private static func loadCollapsedSubstepStepIDRawValues() -> [String] {
        UserDefaults.standard.stringArray(forKey: collapsedSubstepDefaultsKey) ?? []
    }
}

public struct ZebraOnboardingChecklistRailButton: View {
    @ObservedObject private var store: ZebraOnboardingChecklistStore
    private let isCardCollapsed: Bool
    private let action: () -> Void

    public init(
        store: ZebraOnboardingChecklistStore,
        isCardCollapsed: Bool,
        action: @escaping () -> Void
    ) {
        self.store = store
        self.isCardCollapsed = isCardCollapsed
        self.action = action
    }

    public var body: some View {
        Group {
            if store.isVisible {
                Button(action: action) {
                    Image(systemName: "list.number")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(isCardCollapsed ? BVColor.fgMute : BVColor.fg)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isCardCollapsed ? Color.clear : BVColor.bgHover)
                        )
                        .contentShape(Rectangle())
                        .overlay(alignment: .topTrailing) {
                            if isCardCollapsed {
                                progressBadge
                                    .offset(x: 6, y: -3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(helpText)
                .accessibilityLabel(helpText)
                .accessibilityIdentifier("ZebraOnboardingChecklistRailButton")
            }
        }
    }

    private var progressBadge: some View {
        Text("\(store.completedCount)/\(store.totalCount)")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(ZebraOnboardingChecklistPalette.startText)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(ZebraOnboardingChecklistPalette.accent)
            )
            .accessibilityHidden(true)
    }

    private var helpText: String {
        if isCardCollapsed {
            return String(
                localized: "brain.onboarding.checklist.show",
                defaultValue: "Show Start Zebra"
            )
        }
        return String(
            localized: "brain.onboarding.checklist.hide",
            defaultValue: "Hide Start Zebra"
        )
    }
}

private struct ZebraOnboardingChecklistCollapseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(BVColor.fgFaint)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "brain.onboarding.checklist.hide", defaultValue: "Hide Start Zebra"))
        .accessibilityLabel(
            String(localized: "brain.onboarding.checklist.hide", defaultValue: "Hide Start Zebra")
        )
        .accessibilityIdentifier("ZebraOnboardingChecklistCollapseButton")
    }
}

private struct ZebraOnboardingChecklistRow: View {
    private static let rowHeight: CGFloat = 26

    let snapshot: ZebraOnboardingChecklistStepSnapshot
    let title: String
    let isSubstepListCollapsed: Bool
    let onToggleSubstepList: (() -> Void)?
    let onStart: () -> Void
    let onStop: (() -> Void)?
    let onDevelopmentToggle: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if showsExpandedSubsteps {
                substepList
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("ZebraOnboardingChecklistRow.\(snapshot.id.rawValue)")
    }

    private var mainRow: some View {
        HStack(spacing: 9) {
            toggleHitArea
            Spacer(minLength: 0)

            if shouldMoveStartToSubstep {
                substepProgressBadge
                substepListToggleButton
            } else if snapshot.showsStart {
                ZebraOnboardingChecklistStartButton(
                    wasStartedBefore: snapshot.wasStartedBefore,
                    accessibilityIdentifier: "ZebraOnboardingChecklistStartButton.\(snapshot.id.rawValue)",
                    action: onStart
                )
            } else if canToggleSubstepList {
                substepProgressBadge
                substepListToggleButton
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(minHeight: Self.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowBackground)
        .onHover { hovering = $0 }
    }

    private var toggleHitArea: some View {
        HStack(spacing: 9) {
            Text("\(snapshot.number)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(BVColor.fgFaint)
                .frame(width: 15, alignment: .trailing)

            ZebraOnboardingChecklistStatusIndicator(
                isRunning: snapshot.isRunning,
                isCompleted: snapshot.isCompleted,
                isDevelopmentCompleted: snapshot.isDevelopmentCompleted,
                isAttention: false,
                isSkipped: false,
                hovering: hovering,
                onStop: onStop,
                onDevelopmentToggle: nil,
                developmentToggleHelp: developmentToggleHelp,
                accessibilityIdentifier: "ZebraOnboardingChecklistDevelopmentToggleCheckbox.\(snapshot.id.rawValue)"
            )
                .frame(width: 13, height: 13)

            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(snapshot.isCompleted ? BVColor.fgMute : BVColor.fg)
                .strikethrough(snapshot.isCompleted, color: BVColor.fgMute.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .contentShape(Rectangle())
    }

    private var showsSubsteps: Bool {
        !snapshot.substeps.isEmpty
            && (
                snapshot.isActive
                    || snapshot.isRunning
                    || snapshot.wasStartedBefore
                    || snapshot.substeps.contains { $0.isActive || $0.isAttention }
            )
    }

    private var showsExpandedSubsteps: Bool {
        showsSubsteps && !isSubstepListCollapsed
    }

    private var shouldMoveStartToSubstep: Bool {
        showsSubsteps && snapshot.substeps.contains { $0.showsStart || $0.isRunning }
    }

    private var canToggleSubstepList: Bool {
        showsSubsteps && onToggleSubstepList != nil
    }

    private var substepList: some View {
        VStack(spacing: 0) {
            ForEach(snapshot.substeps) { substep in
                ZebraOnboardingChecklistSubstepRow(
                    snapshot: substep,
                    onStart: onStart,
                    onStop: onStop
                )
            }
        }
        .padding(.leading, 44)
        .padding(.trailing, 12)
        .padding(.bottom, 5)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ZebraOnboardingChecklistPalette.substepGuide)
                .frame(width: 1)
                .padding(.leading, 36)
                .padding(.vertical, 4)
        }
    }

    private var substepProgressBadge: some View {
        let completed = snapshot.substeps.filter(\.isCompleted).count
        let total = snapshot.substeps.count
        return Text("\(completed)/\(total)")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(ZebraOnboardingChecklistPalette.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(ZebraOnboardingChecklistPalette.accentSoft)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var substepListToggleButton: some View {
        if let onToggleSubstepList, canToggleSubstepList {
            Button(action: onToggleSubstepList) {
                Image(systemName: isSubstepListCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(BVColor.fgFaint)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(substepListToggleHelp)
            .accessibilityLabel(substepListToggleHelp)
            .accessibilityIdentifier("ZebraOnboardingChecklistSubstepToggle.\(snapshot.id.rawValue)")
        }
    }

    private var substepListToggleHelp: String {
        isSubstepListCollapsed
            ? String(
                localized: "brain.onboarding.checklist.expandSubsteps",
                defaultValue: "Expand substeps"
            )
            : String(
                localized: "brain.onboarding.checklist.collapseSubsteps",
                defaultValue: "Collapse substeps"
            )
    }

    private var developmentToggleHelp: String {
        String(
            localized: "brain.onboarding.checklist.developmentToggle.help",
            defaultValue: "Toggle development completion"
        )
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if snapshot.isActive {
            return ZebraOnboardingChecklistPalette.accentSoft
        }
        if hovering {
            return BVColor.bgHover
        }
        return .clear
    }
}

private struct ZebraOnboardingChecklistSubstepRow: View {
    let snapshot: ZebraOnboardingChecklistSubstepSnapshot
    let onStart: () -> Void
    let onStop: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            ZebraOnboardingChecklistStatusIndicator(
                isRunning: snapshot.isRunning,
                isCompleted: snapshot.isCompleted,
                isDevelopmentCompleted: false,
                isAttention: snapshot.isAttention,
                isSkipped: snapshot.isSkipped,
                hovering: hovering,
                onStop: onStop,
                onDevelopmentToggle: nil,
                developmentToggleHelp: "",
                accessibilityIdentifier: nil
            )
            .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.title)
                    .font(.system(size: 11, weight: snapshot.isActive ? .semibold : .regular))
                    .foregroundColor(snapshot.isCompleted || snapshot.isSkipped ? BVColor.fgMute : BVColor.fg)
                    .strikethrough(snapshot.isCompleted, color: BVColor.fgMute.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail = snapshot.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(BVColor.fgMute)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            if snapshot.showsStart {
                ZebraOnboardingChecklistStartButton(
                    wasStartedBefore: snapshot.wasStartedBefore,
                    accessibilityIdentifier: "ZebraOnboardingChecklistSubstepStartButton.\(snapshot.id)",
                    action: onStart
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minHeight: 28, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowBackground)
        .onHover { hovering = $0 }
        .accessibilityLabel(snapshot.title)
        .accessibilityIdentifier("ZebraOnboardingChecklistSubstepRow.\(snapshot.id)")
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if snapshot.isActive {
            return ZebraOnboardingChecklistPalette.accentSoft
        }
        if hovering {
            return BVColor.bgHover
        }
        return .clear
    }
}

private struct ZebraOnboardingChecklistStatusIndicator: View {
    let isRunning: Bool
    let isCompleted: Bool
    let isDevelopmentCompleted: Bool
    let isAttention: Bool
    let isSkipped: Bool
    let hovering: Bool
    let onStop: (() -> Void)?
    let onDevelopmentToggle: (() -> Void)?
    let developmentToggleHelp: String
    let accessibilityIdentifier: String?

    var body: some View {
        if isRunning {
            if hovering, let onStop {
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(ZebraOnboardingChecklistPalette.accent)
                }
                .buttonStyle(.plain)
                .frame(width: 13, height: 13)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.45)
                    .tint(ZebraOnboardingChecklistPalette.accent)
                    .frame(width: 13, height: 13)
            }
        } else if isCompleted {
            if onDevelopmentToggle != nil {
                developmentToggleButton(label: completedCheckbox)
            } else {
                completedCheckbox
                    .frame(width: 13, height: 13)
            }
        } else if isAttention {
            attentionIndicator
                .frame(width: 13, height: 13)
        } else if isSkipped {
            skippedCheckbox
                .frame(width: 13, height: 13)
        } else if onDevelopmentToggle != nil {
            developmentToggleButton(label: emptyCheckbox)
        } else {
            emptyCheckbox
                .frame(width: 13, height: 13)
        }
    }

    private func developmentToggleButton(label: some View) -> some View {
        Button(action: { onDevelopmentToggle?() }) {
            label
                .frame(width: 13, height: 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(developmentToggleHelp)
        .accessibilityLabel(developmentToggleHelp)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private var completedCheckbox: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(ZebraOnboardingChecklistPalette.accent)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(ZebraOnboardingChecklistPalette.startText)
            )
    }

    private var emptyCheckbox: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(BVColor.fgGhost, lineWidth: 1.3)
    }

    private var skippedCheckbox: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(BVColor.fgGhost.opacity(0.65), lineWidth: 1.2)
    }

    private var attentionIndicator: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(ZebraOnboardingChecklistPalette.accent, lineWidth: 1.3)
            .overlay(
                Text("!")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(ZebraOnboardingChecklistPalette.accent)
            )
    }
}

private struct ZebraOnboardingChecklistStartButton: View {
    let wasStartedBefore: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(wasStartedBefore
                ? String(localized: "brain.onboarding.checklist.restart", defaultValue: "Restart")
                : String(localized: "brain.onboarding.checklist.start", defaultValue: "Start")
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(ZebraOnboardingChecklistPalette.startText)
            .padding(.horizontal, 11)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(ZebraOnboardingChecklistPalette.accent)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct ZebraOnboardingProgressRing: View {
    let completed: Int
    let total: Int
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(ZebraOnboardingChecklistPalette.progressTrack, lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(progress, 1))))
                .stroke(
                    ZebraOnboardingChecklistPalette.accent,
                    style: StrokeStyle(lineWidth: 3, lineCap: .butt)
                )
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(ZebraOnboardingChecklistPalette.panel)
                .frame(width: 20, height: 20)
            Text("\(completed)/\(total)")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(BVColor.fgMute)
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

private enum ZebraOnboardingChecklistPalette {
    static let panel = BVColor.bgElev
    static let panelBorder = BVColor.borderStrong
    static let progressTrack = BVColor.borderStrong
    static let accent = Color(nsColor: NSColor(srgbRed: 0x5a / 255.0, green: 0xa3 / 255.0, blue: 0x7f / 255.0, alpha: 1.0))
    static let accentSoft = accent.opacity(0.16)
    static let substepGuide = accent.opacity(0.42)
    static let startText = BVColor.fgOnAccent
}
