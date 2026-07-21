import Foundation

public enum ZebraAgentPrimaryLaunchResolution: Equatable, Sendable {
    case launch(agent: ZebraAgentKind, executablePath: String, changedPrimary: Bool)
    case manageAgents
}

public struct ZebraAgentLaunchResolver {
    public static let automaticFallbackOrder: [ZebraAgentKind] = [.codex, .claude, .antigravity]

    public init() {}

    public func executablePath(
        for agent: ZebraAgentKind,
        candidates: [ZebraAgentInstallCandidate]
    ) -> String? {
        guard let candidate = candidates.first(where: { $0.id == agent }),
              candidate.installState == .installed,
              candidate.terminalLaunchable,
              let path = validatedAbsolutePath(candidate.executablePath) else {
            return nil
        }
        return path
    }

    public func validatedExecutablePath(
        _ rawPath: String?,
        isExecutableFileAtPath: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> String? {
        guard let path = validatedAbsolutePath(rawPath),
              isExecutableFileAtPath(path) else {
            return nil
        }
        return path
    }

    @discardableResult
    public func refreshSavedPrimaryExecutablePath(
        preferenceStore: ZebraAgentPreferenceStore = ZebraAgentPreferenceStore(),
        candidates: [ZebraAgentInstallCandidate],
        updatedBy: String
    ) throws -> String? {
        let preferences = preferenceStore.load()
        guard let primaryAgent = preferences.primaryAgent,
              let path = executablePath(for: primaryAgent, candidates: candidates) else {
            return nil
        }
        try preferenceStore.setPrimaryAgent(
            primaryAgent,
            executablePath: path,
            updatedBy: updatedBy
        )
        return path
    }

    public func resolvePrimary(
        preferenceStore: ZebraAgentPreferenceStore = ZebraAgentPreferenceStore(),
        candidates: [ZebraAgentInstallCandidate]
    ) throws -> ZebraAgentPrimaryLaunchResolution {
        let preferences = preferenceStore.load()
        if let primary = preferences.primaryAgent,
           let path = executablePath(for: primary, candidates: candidates) {
            return .launch(agent: primary, executablePath: path, changedPrimary: false)
        }

        guard let replacement = Self.automaticFallbackOrder.first(where: {
            executablePath(for: $0, candidates: candidates) != nil
        }), let path = executablePath(for: replacement, candidates: candidates) else {
            return .manageAgents
        }
        try preferenceStore.setPrimaryAgent(
            replacement,
            executablePath: path,
            updatedBy: "resolveAutomaticFallback"
        )
        return .launch(agent: replacement, executablePath: path, changedPrimary: true)
    }

    private func validatedAbsolutePath(_ rawPath: String?) -> String? {
        guard let rawPath, rawPath.hasPrefix("/") else { return nil }
        return (rawPath as NSString).standardizingPath
    }
}
