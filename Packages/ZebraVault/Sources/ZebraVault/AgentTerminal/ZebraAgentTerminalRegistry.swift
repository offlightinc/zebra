import Bonsplit
import Foundation

public enum ZebraAgentTerminalSource: Hashable, Sendable {
    case markdownFile(String)
    case emailThread(String)
    case brainSyncFailure
    case brainSaveFailure
    case onboardingChecklist(ZebraOnboardingChecklistStepID)
}

public struct ZebraAgentTerminalRegistration: Equatable, Sendable {
    public let panelId: UUID
    public let source: ZebraAgentTerminalSource
    public let agent: MarkdownPillAgent?
    public let createdAt: Date

    public init(
        panelId: UUID,
        source: ZebraAgentTerminalSource,
        agent: MarkdownPillAgent?,
        createdAt: Date
    ) {
        self.panelId = panelId
        self.source = source
        self.agent = agent
        self.createdAt = createdAt
    }
}

public enum ZebraAgentTerminalPlacementAnchor: Equatable, Sendable {
    case contentAnchored(contentPanelId: UUID, contentPaneId: PaneID)
    case focusAnchored
}

/// Side-car marker table for terminals launched by Zebra-owned agent actions.
///
/// The registry intentionally marks terminal panel identity instead of pane
/// identity. Tabs can be moved between panes, so placement code should derive
/// the current companion pane from live layout plus this marker table.
@MainActor
public final class ZebraAgentTerminalRegistry {
    private var registrationsByPanelId: [UUID: ZebraAgentTerminalRegistration] = [:]

    public init() {}

    public func mark(
        panelId: UUID,
        source: ZebraAgentTerminalSource,
        agent: MarkdownPillAgent?,
        createdAt: Date = Date()
    ) {
        registrationsByPanelId[panelId] = ZebraAgentTerminalRegistration(
            panelId: panelId,
            source: source,
            agent: agent,
            createdAt: createdAt
        )
    }

    public func unmark(panelId: UUID) {
        registrationsByPanelId.removeValue(forKey: panelId)
    }

    public func registration(panelId: UUID) -> ZebraAgentTerminalRegistration? {
        registrationsByPanelId[panelId]
    }

    public func isAgentTerminal(panelId: UUID) -> Bool {
        registrationsByPanelId[panelId] != nil
    }

    public func latestAgent<S: Sequence>(
        for source: ZebraAgentTerminalSource,
        panelIds: S
    ) -> MarkdownPillAgent? where S.Element == UUID {
        panelIds
            .compactMap { registrationsByPanelId[$0] }
            .filter { $0.source == source }
            .filter { $0.agent != nil }
            .max { lhs, rhs in lhs.createdAt < rhs.createdAt }?
            .agent
    }

    @discardableResult
    public func reassignLatest<S: Sequence>(
        from source: ZebraAgentTerminalSource,
        to newSource: ZebraAgentTerminalSource,
        panelIds: S,
        reassignedAt: Date = Date()
    ) -> ZebraAgentTerminalRegistration? where S.Element == UUID {
        let panelIdSet = Set(panelIds)
        guard let registration = registrationsByPanelId.values
            .filter({ panelIdSet.contains($0.panelId) })
            .filter({ $0.source == source })
            .max(by: { lhs, rhs in lhs.createdAt < rhs.createdAt }) else {
            return nil
        }
        let updated = ZebraAgentTerminalRegistration(
            panelId: registration.panelId,
            source: newSource,
            agent: registration.agent,
            createdAt: reassignedAt
        )
        registrationsByPanelId[registration.panelId] = updated
        return updated
    }

    public func prune(validPanelIds: Set<UUID>) {
        registrationsByPanelId = registrationsByPanelId.filter { validPanelIds.contains($0.key) }
    }
}
