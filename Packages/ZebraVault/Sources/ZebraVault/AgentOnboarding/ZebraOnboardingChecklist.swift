import Foundation
import SwiftUI

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

    @Published public private(set) var completedStepIDs: Set<ZebraOnboardingChecklistStepID> = []
    @Published public private(set) var activeStepID: ZebraOnboardingChecklistStepID?
    @Published public private(set) var runningStepID: ZebraOnboardingChecklistStepID?

    public init(
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory()
    ) {
        self.fileManager = fileManager
        self.homeDirectoryPath = Self.standardizedPath(homeDirectoryPath)
        refreshDetectedCompletion()
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
                isActive: activeStepID == step.id,
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
        guard self.selectedVaultPath != validVaultPath || self.emailConnected != emailConnected else {
            return
        }
        self.selectedVaultPath = validVaultPath
        self.emailConnected = emailConnected
        refreshDetectedCompletion()
    }

    public func beginLaunch(stepID: ZebraOnboardingChecklistStepID) {
        activeStepID = stepID
        runningStepID = stepID
        launchGeneration += 1
        let generation = launchGeneration

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run { [weak self] in
                guard let self,
                      self.launchGeneration == generation,
                      self.runningStepID == stepID else { return }
                self.runningStepID = nil
                self.refreshDetectedCompletion()
            }
        }
    }

    public func refreshDetectedCompletion() {
        var completed = Set<ZebraOnboardingChecklistStepID>()

        if !ZebraAgentOnboardingStartup.shouldRunAutomaticWelcome() {
            completed.insert(.agent)
        }
        if isGbrainSetupReady {
            completed.insert(.gbrain)
        }
        if isAdapterInstalled {
            completed.insert(.adapter)
        }
        if emailConnected || isClawvisorEmailConfigured {
            completed.insert(.email)
        }

        if completedStepIDs != completed {
            completedStepIDs = completed
        }
    }

    private var currentVaultPath: String? {
        selectedVaultPath
            ?? Self.validDirectoryPath(
                (homeDirectoryPath as NSString).appendingPathComponent("brain-offlight"),
                fileManager: fileManager
            )
    }

    private var isGbrainSetupReady: Bool {
        isGbrainVaultReady && (hasGbrainExecutable || hasGbrainProfileWrapper)
    }

    private var isGbrainVaultReady: Bool {
        guard let currentVaultPath else { return false }
        return hasValidGbrainDotfile(".gbrain-mount", in: currentVaultPath)
            || hasValidGbrainDotfile(".gbrain-source", in: currentVaultPath)
    }

    private var isAdapterInstalled: Bool {
        guard let currentVaultPath else { return false }
        let skillPaths = [
            ".gbrain-adapter/skills/router/SKILL.md",
            ".gbrain-adapter/skills/daily-task-manager/SKILL.md",
            ".gbrain-adapter/skills/daily-task-prep/SKILL.md",
        ]
        return directoryExists(".gbrain-adapter", in: currentVaultPath)
            && skillPaths.allSatisfy { fileExists($0, in: currentVaultPath) }
            && hasAdapterBlock("RESOLVER.md", in: currentVaultPath)
            && hasAdapterBlock("schema.md", in: currentVaultPath)
            && hasAdapterBlock("AGENTS.md", in: currentVaultPath)
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

    private var hasGbrainExecutable: Bool {
        let candidates = [
            ".bun/bin/gbrain",
            ".local/bin/gbrain",
            "gbrain/bin/gbrain",
            ".asdf/shims/gbrain",
            ".mise/shims/gbrain",
        ].map { (homeDirectoryPath as NSString).appendingPathComponent($0) } + [
            "/opt/homebrew/bin/gbrain",
            "/usr/local/bin/gbrain",
        ]
        return candidates.contains { fileManager.isExecutableFile(atPath: $0) }
    }

    private var hasGbrainProfileWrapper: Bool {
        let profilesRoot = (homeDirectoryPath as NSString).appendingPathComponent(".gbrain-profiles")
        guard let profileNames = try? fileManager.contentsOfDirectory(atPath: profilesRoot) else {
            return false
        }
        return profileNames.contains { profileName in
            guard !profileName.hasPrefix(".") else { return false }
            let profilePath = (profilesRoot as NSString).appendingPathComponent(profileName)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: profilePath, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  let childNames = try? fileManager.contentsOfDirectory(atPath: profilePath) else {
                return false
            }
            return childNames.contains { childName in
                guard childName.hasPrefix("gbrain-") else { return false }
                let childPath = (profilePath as NSString).appendingPathComponent(childName)
                return fileManager.isExecutableFile(atPath: childPath)
            }
        }
    }

    private func fileExists(_ relativePath: String, in rootPath: String) -> Bool {
        let path = (rootPath as NSString).appendingPathComponent(relativePath)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private func directoryExists(_ relativePath: String, in rootPath: String) -> Bool {
        let path = (rootPath as NSString).appendingPathComponent(relativePath)
        return Self.validDirectoryPath(path, fileManager: fileManager) != nil
    }

    private func hasValidGbrainDotfile(_ relativePath: String, in rootPath: String) -> Bool {
        let path = (rootPath as NSString).appendingPathComponent(relativePath)
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        let value = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return false }
        return value.range(
            of: "^(host|[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?)$",
            options: .regularExpression
        ) != nil
    }

    private func hasAdapterBlock(_ relativePath: String, in rootPath: String) -> Bool {
        let path = (rootPath as NSString).appendingPathComponent(relativePath)
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        return raw.contains("<!-- gbrain-adapter:begin goals-tasks -->")
            && raw.contains("<!-- gbrain-adapter:end goals-tasks -->")
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
        let brainOfflight = (home as NSString).appendingPathComponent("brain-offlight")
        if isDirectory(brainOfflight) {
            return (brainOfflight as NSString).standardizingPath
        }
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
                                onStart: { onStartStep(snapshot.id) }
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
                .shadow(color: Color.black.opacity(0.48), radius: 24, x: 0, y: 10)
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
}

private struct ZebraOnboardingChecklistRow: View {
    let snapshot: ZebraOnboardingChecklistStepSnapshot
    let title: String
    let onStart: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onStart) {
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(rowBackground)
        }
        .buttonStyle(.plain)
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
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ZebraOnboardingChecklistPalette.accent)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                )
        } else {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(BVColor.fgGhost, lineWidth: 1.3)
        }
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
                .stroke(Color.white.opacity(0.10), lineWidth: 3)
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
    static let panel = Color(nsColor: NSColor(srgbRed: 0x27 / 255.0, green: 0x27 / 255.0, blue: 0x28 / 255.0, alpha: 1.0))
    static let panelBorder = Color.white.opacity(0.11)
    static let accent = Color(nsColor: NSColor(srgbRed: 0x5a / 255.0, green: 0xa3 / 255.0, blue: 0x7f / 255.0, alpha: 1.0))
    static let accentSoft = Color(nsColor: NSColor(srgbRed: 0x5a / 255.0, green: 0xa3 / 255.0, blue: 0x7f / 255.0, alpha: 0.16))
    static let startText = Color(nsColor: NSColor(srgbRed: 0x0e / 255.0, green: 0x1f / 255.0, blue: 0x15 / 255.0, alpha: 1.0))
}
