import Foundation
import SwiftUI
#if os(macOS)
import Darwin
#endif

public enum ZebraOnboardingChecklistStepID: String, CaseIterable, Identifiable, Sendable {
    case agent
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
    private struct StepDefinition {
        let id: ZebraOnboardingChecklistStepID
        let number: Int
    }

    private static let steps: [StepDefinition] = [
        StepDefinition(id: .agent, number: 1),
        StepDefinition(id: .gbrain, number: 2),
        StepDefinition(id: .adapter, number: 3),
        StepDefinition(id: .email, number: 4),
        StepDefinition(id: .ingest, number: 5),
        StepDefinition(id: .goals, number: 6),
    ]

    private let fileManager: FileManager
    private let homeDirectoryPath: String
    private var selectedVaultPath: String?
    private var emailConnected = false
    private var launchGeneration = 0
#if DEBUG
    private static let developmentCompletedStepIDsDefaultsKey = "ZebraOnboardingChecklistStore.developmentCompletedStepIDs"
    private static let developmentManuallyCompletableStepIDs: Set<ZebraOnboardingChecklistStepID> = [
        .gbrain,
        .adapter,
        .email,
        .ingest,
        .goals,
    ]
    private var developmentCompletedStepIDs: Set<ZebraOnboardingChecklistStepID> = []
#endif
#if os(macOS)
    private var completionWatchSources: [DispatchSourceFileSystemObject] = []
    private let completionWatchQueue = DispatchQueue(
        label: "com.cmux.zebra.onboarding-checklist-watcher",
        qos: .utility
    )
    private var completionRefreshWorkItem: DispatchWorkItem?
#endif

    @Published public private(set) var completedStepIDs: Set<ZebraOnboardingChecklistStepID> = []
    @Published public private(set) var activeStepID: ZebraOnboardingChecklistStepID?
    @Published public private(set) var runningStepID: ZebraOnboardingChecklistStepID?

    public init(
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory()
    ) {
        self.fileManager = fileManager
        self.homeDirectoryPath = Self.standardizedPath(homeDirectoryPath)
#if DEBUG
        self.developmentCompletedStepIDs = Self.loadDevelopmentCompletedStepIDs()
#endif
#if os(macOS)
        startCompletionFileWatching()
#endif
        refreshDetectedCompletion()
    }

    deinit {
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
        emailConnected: Bool
    ) {
        let validVaultPath = Self.validDirectoryPath(
            selectedVaultPath,
            fileManager: fileManager
        )
        if self.selectedVaultPath != validVaultPath || self.emailConnected != emailConnected {
            self.selectedVaultPath = validVaultPath
            self.emailConnected = emailConnected
        }
        refreshDetectedCompletion()
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
                self.refreshDetectedCompletion()
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
        var completed = Set<ZebraOnboardingChecklistStepID>()

        if !ZebraAgentOnboardingStartup.shouldRunAutomaticWelcome() {
            completed.insert(.agent)
        }
        // TODO(Zebra onboarding): Do not complete steps 2 or 3 by scanning the
        // currently selected vault. The checklist is Zebra onboarding state, so
        // it must stay stable whether the user is looking at ~/,
        // ~/brain-offlight, or any other vault. Final step 2 should write a
        // Zebra-owned GBrain setup receipt that records the verified source /
        // profile target. Final step 3 should read that receipt and verify the
        // adapter on the receipt's target, not on `selectedVaultPath`.
        if emailConnected || isClawvisorEmailConfigured {
            completed.insert(.email)
        }
#if DEBUG
        completed.formUnion(developmentCompletedStepIDs)
#endif

        if let runningStepID, completed.contains(runningStepID) {
            self.runningStepID = nil
        }
        if completedStepIDs != completed {
            completedStepIDs = completed
        }
    }

#if os(macOS)
    private func startCompletionFileWatching() {
        completionWatchSources.forEach { $0.cancel() }
        completionWatchSources = []

        let directoryPaths = Set([
            ZebraAgentOnboardingStartup.defaultStateURL().deletingLastPathComponent().path,
            ZebraAgentPreferenceStore.defaultPreferencesURL().deletingLastPathComponent().path,
        ])

        for directoryPath in directoryPaths {
            installCompletionDirectoryWatcher(directoryPath: directoryPath)
        }
    }

    private func installCompletionDirectoryWatcher(directoryPath: String) {
        try? fileManager.createDirectory(
            atPath: directoryPath,
            withIntermediateDirectories: true,
            attributes: nil
        )
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
                if flags.contains(.delete) || flags.contains(.rename) {
                    self.startCompletionFileWatching()
                }
                self.scheduleCompletionRefresh()
            }
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        completionWatchSources.append(source)
    }

    private func scheduleCompletionRefresh() {
        completionRefreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshDetectedCompletion()
            }
        }
        completionRefreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: item)
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
        let dotEnvPath = (homeDirectoryPath as NSString).appendingPathComponent(".gbrain/.env")
        guard let raw = try? String(contentsOfFile: dotEnvPath, encoding: .utf8) else {
            return false
        }
        let requiredKeys = [
            "CLAWVISOR_URL",
            "CLAWVISOR_AGENT_TOKEN",
            "CLAWVISOR_GMAIL_TASK_ID",
        ]
        return requiredKeys.allSatisfy { key in
            raw.split(separator: "\n").contains { line in
                String(line).trimmingCharacters(in: .whitespaces).hasPrefix("\(key)=")
            }
        }
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
        switch stepID {
        case .agent:
            return ZebraAgentOnboardingScriptCommand.shellStartupLine(
                command: .run,
                cwd: cwd
            )
        case .gbrain:
            return shellScriptStartupLine(cwd: cwd, script: gbrainCheckScript)
        case .adapter:
            return agentStartupLine(
                cwd: cwd,
                prompt: """
                Help me install and verify the gbrain-adapter overlay for this Zebra vault. First inspect the current vault for `.gbrain-adapter/skills`, RESOLVER.md, AGENTS.md, schema.md, and any adapter instructions. If the adapter is missing, identify the correct repository and install command before cloning. After install, verify the adapter fenced blocks and the router, daily-task-manager, and daily-task-prep skills, then summarize the exact result.
                """
            )
        case .email:
            ZebraClawvisorOnboardingCommand.prepareLaunchEnvironment()
            return ZebraClawvisorOnboardingCommand.shellStartupLine(agent: .default)
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

    private static var gbrainCheckScript: String {
        """
        printf 'Zebra gbrain setup check\\n\\n'
        printf 'Vault: %s\\n\\n' "$PWD"
        if command -v gbrain >/dev/null 2>&1; then
          printf 'gbrain CLI:\\n'
          gbrain --version || true
          printf '\\n'
        elif [ -x "$HOME/.bun/bin/gbrain" ]; then
          printf 'gbrain CLI candidate: %s\\n' "$HOME/.bun/bin/gbrain"
          "$HOME/.bun/bin/gbrain" --version || true
          printf '\\n'
        elif [ -x "$HOME/gbrain/bin/gbrain" ]; then
          printf 'gbrain CLI candidate: %s\\n' "$HOME/gbrain/bin/gbrain"
          "$HOME/gbrain/bin/gbrain" --version || true
          printf '\\n'
        else
          printf 'gbrain CLI not found on PATH. Install or expose gbrain before continuing.\\n\\n'
        fi
        printf 'GBrain profile wrappers:\\n'
        found_wrapper=0
        for wrapper in "$HOME"/.gbrain-profiles/*/gbrain-*; do
          [ -x "$wrapper" ] || continue
          found_wrapper=1
          printf '  %s\\n' "$wrapper"
        done
        if [ "$found_wrapper" -eq 0 ]; then
          printf '  none found\\n'
        fi
        printf '\\n'
        if [ -s .gbrain-mount ]; then
          printf '[ok] .gbrain-mount found: '
          head -n 1 .gbrain-mount
        elif [ -s .gbrain-source ]; then
          printf '[ok] .gbrain-source found: '
          head -n 1 .gbrain-source
        else
          printf 'No non-empty .gbrain-mount or .gbrain-source marker found in this vault. Use the vault menu to select your brain repo or initialize one before continuing.\\n'
        fi
        if [ -d tasks ] && [ -d goals ]; then
          printf '[ok] tasks/ and goals/ directories are present.\\n'
        else
          printf 'tasks/ or goals/ directory is missing; the brain schema may not be initialized yet.\\n'
        fi
        """
    }

    private static func agentStartupLine(cwd: String, prompt: String) -> String {
        let agent = MarkdownPillAgent.defaultAgent()
        _ = MarkdownChatPillCommand.prepareLaunchEnvironment(
            agent: agent,
            markdownFilePath: nil,
            launchDirectory: cwd
        )
        return MarkdownChatPillCommand.shellStartupLine(
            agent: agent,
            markdownFilePath: nil,
            surface: .fallback(typeLabel: "onboarding"),
            userPrompt: prompt,
            launchDirectory: cwd
        )
    }

    private static func shellScriptStartupLine(cwd: String, script: String) -> String {
        "cd \(ZebraAgentLaunchCommand.shellQuote(cwd)) && /bin/bash -lc \(ZebraAgentLaunchCommand.shellQuote(script))\r"
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
