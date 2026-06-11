import Foundation
import SwiftUI
#if os(macOS)
import Darwin
#endif

public enum ZebraOnboardingChecklistStepID: String, CaseIterable, Identifiable, Sendable {
    case agent
    case gbrainRuntime
    case gbrain
    case adapter
    case email
    case ingest
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
        StepDefinition(id: .agent, number: 1),
        StepDefinition(id: .gbrainRuntime, number: 2),
        StepDefinition(id: .gbrain, number: 3),
        StepDefinition(id: .adapter, number: 4),
        StepDefinition(id: .email, number: 5),
        StepDefinition(id: .ingest, number: 6),
        StepDefinition(id: .goals, number: 7),
    ]

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
    private var selectedVaultPath: String?
    private var emailConnectionRepairState: ZebraEmailConnectionRepairState?
    private var launchGeneration = 0
    private var gbrainDocsPrefetchTask: Task<Bool, Never>?
    private var gbrainCompletionRefreshTask: Task<Bool, Never>?
    private var completionRefreshGeneration = 0
    private var didStartGBrainDocsPrefetch = false
#if DEBUG
    private static let developmentCompletedStepIDsDefaultsKey = "ZebraOnboardingChecklistStore.developmentCompletedStepIDs"
    private static let developmentManuallyCompletableStepIDs: Set<ZebraOnboardingChecklistStepID> = [
        .gbrainRuntime,
        .gbrain,
        .adapter,
        .ingest,
        .goals,
    ]
    private var developmentCompletedStepIDs: Set<ZebraOnboardingChecklistStepID> = []
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

    public init(
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory(),
        agentOnboardingStateURL: URL = ZebraAgentOnboardingStartup.defaultStateURL(),
        agentPreferenceURL: URL = ZebraAgentPreferenceStore.defaultPreferencesURL(),
        gbrainRuntimeOnboardingStateURL: URL = ZebraGBrainRuntimeOnboardingStore.defaultStateURL(),
        gbrainOnboardingStateURL: URL = ZebraGBrainOnboardingStore.defaultStateURL(),
        gbrainAdapterOnboardingStateURL: URL = ZebraGBrainAdapterOnboardingStore.defaultStateURL()
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
        self.developmentCompletedStepIDs = Self.loadDevelopmentCompletedStepIDs()
#endif
        refreshDetectedCompletion()
        prefetchGBrainDocsIfNeeded()
    }

    deinit {
        gbrainDocsPrefetchTask?.cancel()
        gbrainCompletionRefreshTask?.cancel()
#if os(macOS)
        completionRefreshWorkItem?.cancel()
        completionWatchSources.forEach { $0.cancel() }
#endif
    }

    public var totalCount: Int {
        Self.steps.count
    }

    public var completedCount: Int {
        completedStepIDs.count
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

    public func prefetchGBrainDocsIfNeeded() {
        didStartGBrainDocsPrefetch = true
    }

    public var snapshots: [ZebraOnboardingChecklistStepSnapshot] {
        let firstIncomplete = Self.steps.first { !completedStepIDs.contains($0.id) }?.id
        return Self.steps.map { step in
            ZebraOnboardingChecklistStepSnapshot(
                id: step.id,
                number: step.number,
                isCompleted: completedStepIDs.contains(step.id),
                isDevelopmentCompleted: isDevelopmentCompleted(step.id),
                isActive: firstIncomplete == step.id,
                isRunning: runningStepID == step.id,
                showsStart: firstIncomplete == step.id && runningStepID != step.id
            )
        }
    }

    public func syncExternalState(
        selectedVaultPath: String?,
        emailConnectionRepairState: ZebraEmailConnectionRepairState? = nil
    ) {
        let validVaultPath = Self.validDirectoryPath(
            selectedVaultPath,
            fileManager: fileManager
        )
        if self.selectedVaultPath != validVaultPath || self.emailConnectionRepairState != emailConnectionRepairState {
            self.selectedVaultPath = validVaultPath
            self.emailConnectionRepairState = emailConnectionRepairState
        }
        refreshDetectedCompletion()
        prefetchGBrainDocsIfNeeded()
    }

    public func beginLaunch(stepID: ZebraOnboardingChecklistStepID) {
        activeStepID = stepID
        runningStepID = stepID
        launchGeneration += 1
        let generation = launchGeneration

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            await MainActor.run { [weak self] in
                guard let self,
                      self.launchGeneration == generation,
                      self.runningStepID == stepID else { return }
                self.runningStepID = nil
                self.refreshDetectedCompletion(for: stepID)
            }
        }
    }

#if DEBUG
    /// DEVELOPMENT-ONLY TEMPORARY OVERRIDE.
    /// Steps 2-6 do not have final completion validators yet. Keep this path
    /// DEBUG-only so local development can hide the checklist without teaching
    /// production builds that these steps are actually complete.
    public func developmentToggleStepCompleted(_ stepID: ZebraOnboardingChecklistStepID) {
        guard Self.developmentManuallyCompletableStepIDs.contains(stepID) else { return }
        if developmentCompletedStepIDs.contains(stepID) {
            developmentCompletedStepIDs.remove(stepID)
        } else {
            developmentCompletedStepIDs.insert(stepID)
        }
        saveDevelopmentCompletedStepIDs()
        refreshDetectedCompletion()
    }
#endif

    public func refreshDetectedCompletion() {
        completionRefreshGeneration += 1
        let generation = completionRefreshGeneration
        let runtimeCompletion = runtimeCompletionResult()
        refreshRuntimeInteractiveAuthRequest()
        let cachedGBrainCompletion = gbrainCompletionResultFromCachedReceipt(
            selectedVaultPath: selectedVaultPath
        )
        let adapterCompletion = adapterCompletionResult(
            selectedVaultPath: selectedVaultPath
        )
        applyAllDetectedCompletion(
            agentCompleted: agentCompletionResult().isComplete,
            gbrainRuntimeCompletion: runtimeCompletion,
            gbrainCompleted: cachedGBrainCompletion.isComplete,
            gbrainAdapterCompleted: adapterCompletion.isComplete,
            emailCompleted: emailCompletionResult().isComplete
        )
        guard shouldRefreshGBrainCompletionInBackground(cachedGBrainCompletion) else { return }
        refreshGBrainCompletionInBackground(generation: generation)
    }

    public func refreshDetectedCompletion(for stepID: ZebraOnboardingChecklistStepID) {
        switch stepID {
        case .agent:
            applyDetectedCompletion(for: .agent, result: agentCompletionResult())
        case .gbrainRuntime:
            refreshRuntimeInteractiveAuthRequest()
            applyDetectedCompletion(for: .gbrainRuntime, result: runtimeCompletionResult())
        case .gbrain:
            let cached = gbrainCompletionResultFromCachedReceipt(selectedVaultPath: selectedVaultPath)
            applyDetectedCompletion(
                for: .gbrain,
                result: StepCompletionResult(isComplete: cached.isComplete, reasons: cached.reasons)
            )
            guard shouldRefreshGBrainCompletionInBackground(cached) else { return }
            completionRefreshGeneration += 1
            refreshGBrainCompletionInBackground(generation: completionRefreshGeneration)
        case .adapter:
            applyDetectedCompletion(
                for: .adapter,
                result: adapterCompletionResult(selectedVaultPath: selectedVaultPath)
            )
        case .email:
            applyDetectedCompletion(for: .email, result: emailCompletionResult())
        case .ingest, .goals:
            break
        }
    }

    private func shouldRefreshGBrainCompletionInBackground(
        _ cachedGBrainCompletion: ZebraGBrainOnboardingStore.CompletionResult
    ) -> Bool {
        // The setup helper owns expensive live verification. Once it has written
        // a complete receipt, the checklist should not keep probing PGLite.
        !cachedGBrainCompletion.isComplete
    }

    private func refreshGBrainCompletionInBackground(generation: Int) {
        guard gbrainCompletionRefreshTask == nil else { return }
        let store = gbrainOnboardingStore
        let selectedVaultPath = selectedVaultPath
        let task = Task.detached(priority: .utility) {
            store.isSetupCompleted(selectedVaultPath: selectedVaultPath)
        }
        gbrainCompletionRefreshTask = task
        Task { @MainActor [weak self, task] in
            let completed = await task.value
            guard let self else { return }
            self.gbrainCompletionRefreshTask = nil
            guard self.completionRefreshGeneration == generation,
                  self.selectedVaultPath == selectedVaultPath else {
                self.refreshDetectedCompletion()
                return
            }
            self.applyDetectedCompletion(
                for: .gbrain,
                result: StepCompletionResult(isComplete: completed, reasons: [])
            )
            self.applyDetectedCompletion(
                for: .adapter,
                result: self.adapterCompletionResult(selectedVaultPath: selectedVaultPath)
            )
        }
    }

    private func applyAllDetectedCompletion(
        agentCompleted: Bool,
        gbrainRuntimeCompletion: StepCompletionResult,
        gbrainCompleted: Bool,
        gbrainAdapterCompleted: Bool,
        emailCompleted: Bool
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
        if gbrainAdapterCompleted {
            completed.insert(.adapter)
        }
        if emailCompleted {
            completed.insert(.email)
        }
#if DEBUG
        completed.formUnion(developmentCompletedStepIDs)
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
        if developmentCompletedStepIDs.contains(stepID) {
            completed.insert(stepID)
        }
#endif
        applyCompletedStepIDs(completed)
    }

    private func applyCompletedStepIDs(_ completed: Set<ZebraOnboardingChecklistStepID>) {
        if let runningStepID, completed.contains(runningStepID) {
            self.runningStepID = nil
        }
        if runningStepID == .gbrain,
           gbrainOnboardingStore.hasSourceRepoPrepareAbortMarker() {
            self.runningStepID = nil
        }
        if completedStepIDs != completed {
            completedStepIDs = completed
        }
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

    private func emailCompletionResult() -> StepCompletionResult {
        StepCompletionResult(
            isComplete: emailConnectionRepairState == nil && isClawvisorEmailConfigured,
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
            WatchedCompletionFile(url: clawvisorEmailEnvURL, stepID: .email),
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
    private static func loadDevelopmentCompletedStepIDs() -> Set<ZebraOnboardingChecklistStepID> {
        let rawValues = UserDefaults.standard.stringArray(forKey: developmentCompletedStepIDsDefaultsKey) ?? []
        return Set(
            rawValues
                .compactMap(ZebraOnboardingChecklistStepID.init(rawValue:))
                .filter { developmentManuallyCompletableStepIDs.contains($0) }
        )
    }

    private func saveDevelopmentCompletedStepIDs() {
        let rawValues = developmentCompletedStepIDs.map(\.rawValue).sorted()
        UserDefaults.standard.set(rawValues, forKey: Self.developmentCompletedStepIDsDefaultsKey)
    }
#endif

    private func isDevelopmentCompleted(_ stepID: ZebraOnboardingChecklistStepID) -> Bool {
#if DEBUG
        return developmentCompletedStepIDs.contains(stepID)
#else
        return false
#endif
    }

    private var isClawvisorEmailConfigured: Bool {
        guard let raw = try? String(contentsOf: clawvisorEmailEnvURL, encoding: .utf8) else {
            return false
        }
        let requiredKeys = [
            "CLAWVISOR_URL",
            "CLAWVISOR_AGENT_TOKEN",
            "CLAWVISOR_GMAIL_TASK_ID",
            "ZEBRA_CLAWVISOR_GMAIL_ACCOUNT",
        ]
        return requiredKeys.allSatisfy { key in
            raw.split(separator: "\n").contains { line in
                String(line).trimmingCharacters(in: .whitespaces).hasPrefix("\(key)=")
            }
        }
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
    public static func shellStartupLine(
        for stepID: ZebraOnboardingChecklistStepID,
        selectedVaultPath: String?
    ) -> String? {
        let cwd = launchDirectory(selectedVaultPath: selectedVaultPath)
        let language = ZebraOnboardingLanguage.current()
        switch stepID {
        case .agent:
            return ZebraAgentOnboardingScriptCommand.shellStartupLine(
                command: .run,
                cwd: cwd,
                languageCode: language.code
            )
        case .gbrainRuntime:
            guard let launch = ZebraGBrainRuntimeOnboardingStore().prepareLaunch() else {
                return nil
            }
            return gbrainRuntimeStartupLine(launch: launch)
        case .gbrain:
            guard let runtime = ZebraGBrainRuntimeOnboardingStore().selectedRuntimeForGBrainSetup() else {
                return nil
            }
            guard let launch = ZebraGBrainOnboardingStore().prepareLaunch(
                selectedVaultPath: selectedVaultPath
            ) else {
                return nil
            }
            return gbrainSetupRuntimeStartupLine(launch: launch, runtime: runtime)
        case .adapter:
            return ZebraGBrainAdapterOnboardingStore().prepareLaunch(
                selectedVaultPath: selectedVaultPath
            )?.startupLine
        case .email:
            guard let agent = ZebraClawvisorOnboardingCommand.readyPrimaryAgent() else {
                return nil
            }
            return ZebraClawvisorOnboardingCommand.launchPlan(agent: agent).startupLine
        case .ingest:
            return agentStartupLine(
                cwd: cwd,
                prompt: """
                Help me finish Zebra onboarding for ingest sources in this vault. Check which sources are already present, recommend the smallest useful first source set, connect or document the missing credentials, then run a limited initial ingest if the local tooling is available. Keep all writes within the active brain vault.
                """
            )
        case .goals:
            return agentStartupLine(
                cwd: cwd,
                prompt: """
                Help me finish Zebra onboarding by creating one useful starter goal and one starter task in this vault using the local brain conventions. Then give a short walkthrough of how to open goals, tasks, email, and documents from the Zebra sidebar.
                """
            )
        }
    }

    static func gbrainSetupRuntimeStartupLine(
        launch: ZebraGBrainOnboardingStore.LaunchContext,
        runtime: ZebraGBrainRuntimeOnboardingStore.SelectedRuntime
    ) -> String {
        let prepareSourceRepoPrefix = [
            "zebra-gbrain-onboarding prepare-source-repo",
            "eval \"$(zebra-gbrain-onboarding active-source-env)\"",
            "zebra-gbrain-onboarding write-setup-packet --path \(ZebraAgentLaunchCommand.shellQuote(launch.setupPacketPath))",
        ].joined(separator: " && ") + " && "
        let startupLine = gbrainSetupSelectedRuntimeCommand(
            launch: launch,
            runtime: runtime
        )
        return "\(launch.shellEnvironmentPrefix)\(prepareSourceRepoPrefix)\(startupLine)"
    }

    static func gbrainRuntimeStartupLine(
        launch: ZebraGBrainRuntimeOnboardingStore.LaunchContext,
        agent: MarkdownPillAgent = MarkdownPillAgent.defaultAgent(),
        codexConfigURL: URL? = nil
    ) -> String {
        if agent == .codex {
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
            shouldPrepareCodexGBrainSetupConfig: false
        )
    }

    private static func gbrainSetupSelectedRuntimeCommand(
        launch: ZebraGBrainOnboardingStore.LaunchContext,
        runtime: ZebraGBrainRuntimeOnboardingStore.SelectedRuntime
    ) -> String {
        let executable = ZebraAgentLaunchCommand.shellQuote(runtime.executablePath)
        let setupPacket = ZebraAgentLaunchCommand.shellQuote(launch.setupPacketPath)
        let runId = ZebraAgentLaunchCommand.shellQuote(launch.runId)
        switch runtime.runtime {
        case "openclaw":
            let agentID = openClawAgentID(runId: launch.runId)
            let sessionKey = "agent:\(agentID):\(launch.runId)"
            return "eval \"$(zebra-gbrain-onboarding write-runtime-launcher --runtime 'openclaw' --executable \(executable) --setup-packet \(setupPacket) --run-id \(runId) --agent-id \(ZebraAgentLaunchCommand.shellQuote(agentID)) --session \(ZebraAgentLaunchCommand.shellQuote(sessionKey)))\" && \"$ZEBRA_GBRAIN_RUNTIME_LAUNCHER\"\r"
        case "hermes":
            return "eval \"$(zebra-gbrain-onboarding write-runtime-launcher --runtime 'hermes' --executable \(executable) --setup-packet \(setupPacket) --run-id \(runId))\" && \"$ZEBRA_GBRAIN_RUNTIME_LAUNCHER\"\r"
        default:
            return "echo 'Unsupported OpenClaw/Hermes runtime for GBrain setup: \(runtime.runtime)' >&2 && exit 1\r"
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
        shouldPrepareCodexGBrainSetupConfig: Bool = true
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
                allowTrustedAutomation: true,
                allowLaunchDirectoryTrust: true,
                allowApprovalAutomation: true
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
    @ObservedObject private var store: ZebraOnboardingChecklistStore
    private let onStartStep: (ZebraOnboardingChecklistStepID) -> Void

    public init(
        store: ZebraOnboardingChecklistStore,
        onStartStep: @escaping (ZebraOnboardingChecklistStepID) -> Void
    ) {
        self.store = store
        self.onStartStep = onStartStep
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
                                onStart: { onStartStep(snapshot.id) },
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
                }
            }
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
        }
        .padding(.horizontal, 12)
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
                defaultValue: "Check gbrain and link the vault/profile"
            )
        case .adapter:
            return String(
                localized: "brain.onboarding.checklist.step.adapter",
                defaultValue: "Clone and install gbrain-adapter"
            )
        case .email:
            return String(
                localized: "brain.onboarding.checklist.step.email",
                defaultValue: "Connect email"
            )
        case .ingest:
            return String(
                localized: "brain.onboarding.checklist.step.ingest",
                defaultValue: "Connect ingest sources and run initial ingest"
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
#if DEBUG
        guard stepID != .agent else { return nil }
        return { store.developmentToggleStepCompleted(stepID) }
#else
        return nil
#endif
    }
}

private struct ZebraOnboardingChecklistRow: View {
    private static let actionRowMinimumHeight: CGFloat = 34

    let snapshot: ZebraOnboardingChecklistStepSnapshot
    let title: String
    let onStart: () -> Void
    let onDevelopmentToggle: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Text("\(snapshot.number)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(BVColor.fgFaint)
                .frame(width: 15, alignment: .trailing)

            statusIndicator
                .frame(width: 13, height: 13)

            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(snapshot.isCompleted ? BVColor.fgMute : BVColor.fg)
                .strikethrough(snapshot.isCompleted, color: BVColor.fgMute.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if snapshot.showsStart {
                Button(action: onStart) {
                    Text(String(localized: "brain.onboarding.checklist.start", defaultValue: "Start"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ZebraOnboardingChecklistPalette.startText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(ZebraOnboardingChecklistPalette.accent)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ZebraOnboardingChecklistStartButton.\(snapshot.id.rawValue)")
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: rowMinimumHeight, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowBackground)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityIdentifier("ZebraOnboardingChecklistRow.\(snapshot.id.rawValue)")
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if snapshot.isRunning {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.45)
                .tint(ZebraOnboardingChecklistPalette.accent)
                .frame(width: 13, height: 13)
        } else if snapshot.isCompleted {
            if let onDevelopmentToggle, snapshot.isDevelopmentCompleted {
                Button(action: onDevelopmentToggle) {
                    completedCheckbox
                        .frame(width: 13, height: 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(developmentToggleHelp)
                .accessibilityLabel(developmentToggleHelp)
                .accessibilityIdentifier("ZebraOnboardingChecklistDevelopmentToggleCheckbox.\(snapshot.id.rawValue)")
            } else {
                completedCheckbox
                    .frame(width: 13, height: 13)
            }
        } else if let onDevelopmentToggle {
            Button(action: onDevelopmentToggle) {
                emptyCheckbox
                    .frame(width: 13, height: 13)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(developmentToggleHelp)
            .accessibilityLabel(developmentToggleHelp)
            .accessibilityIdentifier("ZebraOnboardingChecklistDevelopmentToggleCheckbox.\(snapshot.id.rawValue)")
        } else {
            emptyCheckbox
                .frame(width: 13, height: 13)
        }
    }

    private var completedCheckbox: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(ZebraOnboardingChecklistPalette.accent)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
            )
    }

    private var emptyCheckbox: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(BVColor.fgGhost, lineWidth: 1.3)
    }

    private var rowMinimumHeight: CGFloat? {
        snapshot.isActive || snapshot.isRunning ? Self.actionRowMinimumHeight : nil
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
    static let startText = BVColor.fgOnAccent
}
