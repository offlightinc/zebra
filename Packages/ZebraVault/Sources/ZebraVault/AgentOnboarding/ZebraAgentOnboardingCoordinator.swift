import Foundation

public enum ZebraAgentSelectionMode: String, Equatable, Sendable {
    case savedPrimary
    case autoOneInstalled
    case userSelected
    case installCompleted
}

public enum ZebraAgentOnboardingDecision: Equatable, Sendable {
    case launch(agent: ZebraAgentKind, selectionMode: ZebraAgentSelectionMode, shouldPersistPrimary: Bool)
    case choosePrimary(installed: [ZebraAgentInstallCandidate])
    case chooseInstallTarget(candidates: [ZebraAgentInstallCandidate])
    case primaryMissing(saved: ZebraAgentKind, installed: [ZebraAgentInstallCandidate], candidates: [ZebraAgentInstallCandidate])
    case installFailed(agent: ZebraAgentKind, message: String)
}

public struct ZebraAgentOnboardingCoordinator {
    public init() {}

    public func initialDecision(
        savedPrimary: ZebraAgentKind?,
        candidates: [ZebraAgentInstallCandidate]
    ) -> ZebraAgentOnboardingDecision {
        let installed = installedCandidates(from: candidates)

        if let savedPrimary {
            if installed.contains(where: { $0.id == savedPrimary }) {
                return .launch(agent: savedPrimary, selectionMode: .savedPrimary, shouldPersistPrimary: false)
            }
            return .primaryMissing(saved: savedPrimary, installed: installed, candidates: candidates)
        }

        switch installed.count {
        case 0:
            return .chooseInstallTarget(candidates: candidates)
        case 1:
            return .launch(agent: installed[0].id, selectionMode: .autoOneInstalled, shouldPersistPrimary: true)
        default:
            return .choosePrimary(installed: installed)
        }
    }

    public func decisionAfterUserSelectedInstalledAgent(
        _ agent: ZebraAgentKind,
        candidates: [ZebraAgentInstallCandidate]
    ) -> ZebraAgentOnboardingDecision {
        let installed = installedCandidates(from: candidates)
        guard installed.contains(where: { $0.id == agent }) else {
            return .chooseInstallTarget(candidates: candidates)
        }
        return .launch(agent: agent, selectionMode: .userSelected, shouldPersistPrimary: true)
    }

    public func decisionAfterInstallCompleted(
        selectedAgent: ZebraAgentKind,
        candidates: [ZebraAgentInstallCandidate]
    ) -> ZebraAgentOnboardingDecision {
        let installed = installedCandidates(from: candidates)
        guard installed.contains(where: { $0.id == selectedAgent }) else {
            return .chooseInstallTarget(candidates: candidates)
        }
        return .launch(agent: selectedAgent, selectionMode: .installCompleted, shouldPersistPrimary: true)
    }

    public func decisionAfterInstallFailed(
        selectedAgent: ZebraAgentKind,
        message: String
    ) -> ZebraAgentOnboardingDecision {
        .installFailed(agent: selectedAgent, message: message)
    }

    private func installedCandidates(from candidates: [ZebraAgentInstallCandidate]) -> [ZebraAgentInstallCandidate] {
        candidates.filter { $0.installState == .installed && $0.terminalLaunchable }
    }
}
