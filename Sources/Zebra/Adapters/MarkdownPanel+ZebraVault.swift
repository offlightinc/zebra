import Bonsplit
import Combine
import CoreGraphics
import Foundation
import ZebraVault

// MARK: - cmux model conformances to ZebraVault protocols
//
// `MarkdownPanel`, `TerminalPanel`, and `Workspace` are internal to the
// cmux app target. The protocols (`ZebraMarkdownPanelModel`,
// `ZebraTerminalPanel`, `ZebraMarkdownWorkspace`) live in the ZebraVault
// SPM package. Conformances stay on the cmux side because that is where
// the conformed types live; Zebra views consume them only through the
// protocol-typed surface.

extension MarkdownPanel: ZebraMarkdownPanelModel {}

extension TerminalPanel: ZebraTerminalPanel {
    var isSurfaceReady: Bool {
        surface.surface != nil
    }
}

extension Workspace: ZebraMarkdownWorkspace {
    var allPaneIds: [PaneID] {
        bonsplitController.allPaneIds
    }

    func paneWidth(forPane paneId: PaneID) -> Double? {
        bonsplitController.layoutSnapshot().panes
            .first(where: { $0.paneId == paneId.id.uuidString })?
            .frame
            .width
    }

    @discardableResult
    func ensurePaneWidth(_ minimumWidth: Double, forPane paneId: PaneID) -> Bool {
        guard minimumWidth.isFinite, minimumWidth > 0 else { return false }

        let tolerance = 0.5
        if let currentWidth = paneWidth(forPane: paneId),
           currentWidth + tolerance >= minimumWidth {
            return true
        }

        let targetPaneId = paneId.id.uuidString
        var candidates: [ZebraPaneWidthResizeCandidate] = []
        let trace = zebraCollectPaneWidthResizeCandidates(
            node: bonsplitController.treeSnapshot(),
            targetPaneId: targetPaneId,
            candidates: &candidates
        )
        guard trace.containsTarget else { return false }

        var didSetDivider = false
        for candidate in candidates where candidate.orientation == "horizontal" {
            guard candidate.targetPaneWidth > 1,
                  candidate.targetBranchWidth > 1 else {
                continue
            }
            let branchScale = CGFloat(minimumWidth) / candidate.targetPaneWidth
            let requiredBranchWidth = candidate.targetBranchWidth * branchScale
            let targetFraction = requiredBranchWidth / candidate.axisPixels
            let requested = candidate.paneInFirstChild ? targetFraction : (1 - targetFraction)
            let clamped = min(max(requested, 0.1), 0.9)
            guard bonsplitController.setDividerPosition(
                clamped,
                forSplit: candidate.splitId,
                fromExternal: true
            ) else {
                continue
            }
            didSetDivider = true
            notifyZebraPaneWidthChange()

            if let updatedWidth = paneWidth(forPane: paneId),
               updatedWidth + tolerance >= minimumWidth {
                return true
            }
        }

        if didSetDivider {
            scheduleZebraPaneWidthFollowUp()
        }
        return (paneWidth(forPane: paneId) ?? 0) + tolerance >= minimumWidth
    }

    func openOrFocusMarkdownSurface(
        inPane paneId: PaneID,
        filePath: String,
        focus: Bool
    ) -> (any ZebraMarkdownPanelModel)? {
        let concrete: MarkdownPanel? = openOrFocusMarkdownSurface(
            inPane: paneId,
            filePath: filePath,
            focus: focus
        )
        return concrete
    }

    func newTerminalSurface(
        inPane paneId: PaneID,
        focus: Bool?,
        initialCommand: String?
    ) -> (any ZebraTerminalPanel)? {
        let concrete: TerminalPanel? = newTerminalSurface(
            inPane: paneId,
            focus: focus,
            initialCommand: initialCommand
        )
        return concrete
    }

    func newTerminalSplit(
        from panelId: UUID,
        orientation: SplitOrientation,
        initialCommand: String?
    ) -> (any ZebraTerminalPanel)? {
        let concrete: TerminalPanel? = newTerminalSplit(
            from: panelId,
            orientation: orientation,
            initialCommand: initialCommand
        )
        return concrete
    }

    func reusableAgentCompanionPane(forContentPane paneId: PaneID) -> PaneID? {
        nearestRightTerminalPane(fromContentPane: paneId)
    }

    func paneHasTerminalSurface(_ paneId: PaneID) -> Bool {
        panels(inPane: paneId).contains { $0 is TerminalPanel }
    }
}

private extension Workspace {
    func notifyZebraPaneWidthChange() {
        didProgrammaticallyChangeSplitGeometry()
    }

    func scheduleZebraPaneWidthFollowUp() {
        DispatchQueue.main.async { [weak self] in
            self?.didProgrammaticallyChangeSplitGeometry()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.didProgrammaticallyChangeSplitGeometry()
        }
    }
}

private struct ZebraPaneWidthResizeCandidate {
    let splitId: UUID
    let orientation: String
    let paneInFirstChild: Bool
    let axisPixels: CGFloat
    let targetPaneWidth: CGFloat
    let targetBranchWidth: CGFloat
}

private struct ZebraPaneWidthResizeTrace {
    let containsTarget: Bool
    let bounds: CGRect
    let targetBounds: CGRect?
}

private func zebraCollectPaneWidthResizeCandidates(
    node: ExternalTreeNode,
    targetPaneId: String,
    candidates: inout [ZebraPaneWidthResizeCandidate]
) -> ZebraPaneWidthResizeTrace {
    switch node {
    case .pane(let pane):
        let bounds = CGRect(
            x: pane.frame.x,
            y: pane.frame.y,
            width: pane.frame.width,
            height: pane.frame.height
        )
        return ZebraPaneWidthResizeTrace(
            containsTarget: pane.id == targetPaneId,
            bounds: bounds,
            targetBounds: pane.id == targetPaneId ? bounds : nil
        )

    case .split(let split):
        let first = zebraCollectPaneWidthResizeCandidates(
            node: split.first,
            targetPaneId: targetPaneId,
            candidates: &candidates
        )
        let second = zebraCollectPaneWidthResizeCandidates(
            node: split.second,
            targetPaneId: targetPaneId,
            candidates: &candidates
        )

        let combinedBounds = first.bounds.union(second.bounds)
        let containsTarget = first.containsTarget || second.containsTarget
        let targetBounds = first.targetBounds ?? second.targetBounds

        if containsTarget,
           let splitUUID = UUID(uuidString: split.id),
           let targetBounds {
            let orientation = split.orientation.lowercased()
            let axisPixels: CGFloat = orientation == "horizontal"
                ? combinedBounds.width
                : combinedBounds.height
            let targetBranchBounds = first.containsTarget ? first.bounds : second.bounds
            candidates.append(ZebraPaneWidthResizeCandidate(
                splitId: splitUUID,
                orientation: orientation,
                paneInFirstChild: first.containsTarget,
                axisPixels: max(axisPixels, 1),
                targetPaneWidth: max(targetBounds.width, 1),
                targetBranchWidth: max(targetBranchBounds.width, 1)
            ))
        }

        return ZebraPaneWidthResizeTrace(
            containsTarget: containsTarget,
            bounds: combinedBounds,
            targetBounds: targetBounds
        )
    }
}

@MainActor
final class ZebraEmailThreadPanel: Panel, ObservableObject {
    let id: UUID
    // First-class panel type. Rendering goes through the generic
    // `customPanelViewFactory` seam in `PanelContentView`, so cmux common
    // code never has to know about `ZebraEmailThreadPanel` directly.
    let panelType: PanelType = .email
    @Published private(set) var threadId: String
    /// Owning workspace id. Needed by the panel host to look the workspace
    /// up from `TabManager` for chat-pill split/tab creation — same pattern
    /// `MarkdownPanel.workspaceId` follows on the markdown side.
    let workspaceId: UUID
    var displayIcon: String? { "envelope" }

    @Published private(set) var displayTitle: String
    @Published private(set) var focusFlashToken: Int = 0

    init(workspaceId: UUID, threadId: String, subject: String) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.threadId = threadId
        self.displayTitle = Self.title(from: subject)
    }

    func updateSubject(_ subject: String) {
        let nextTitle = Self.title(from: subject)
        guard displayTitle != nextTitle else { return }
        displayTitle = nextTitle
    }

    func openThread(_ thread: EmailThreadItem) {
        let nextTitle = Self.title(from: thread.subject)
        guard threadId != thread.id || displayTitle != nextTitle else { return }
        threadId = thread.id
        displayTitle = nextTitle
    }

    func focus() {}

    func unfocus() {}

    func close() {}

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }

    private static func title(from subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? String(localized: "email.detail.noSubject", defaultValue: "(no subject)")
            : trimmed
    }
}

extension Workspace {
    @discardableResult
    func openOrFocusEmailThreadContent(
        thread: EmailThreadItem,
        excludedAgentCompanionPaneIds: Set<PaneID>,
        anchorPanelId: UUID?
    ) -> ZebraEmailThreadPanel? {
        if let existing = focusExistingEmailThread(thread) {
            return existing
        }

        if let paneId = resolvePaneForContentOpen(
            kind: .email,
            excludedAgentCompanionPaneIds: excludedAgentCompanionPaneIds,
            anchorPanelId: anchorPanelId
        ) {
            return openOrFocusEmailThreadSurface(inPane: paneId, thread: thread, focus: true)
        }

        guard let sourcePanelId = firstPanelIdForContentSplit(
            excludedAgentCompanionPaneIds: excludedAgentCompanionPaneIds
        ) else {
            return nil
        }
        return newEmailThreadSplit(
            from: sourcePanelId,
            orientation: .horizontal,
            insertFirst: true,
            thread: thread,
            focus: true
        )
    }

    @discardableResult
    func openMarkdownFromZebraSidebar(
        filePath: String,
        excludedAgentCompanionPaneIds: Set<PaneID>,
        anchorPanelId: UUID?,
        focus: Bool = true
    ) -> MarkdownPanel? {
        let targetPaneId = resolvePaneForContentOpen(
            kind: .markdown,
            excludedAgentCompanionPaneIds: excludedAgentCompanionPaneIds,
            anchorPanelId: anchorPanelId
        ) ?? bonsplitController.allPaneIds.first { !excludedAgentCompanionPaneIds.contains($0) }
            ?? bonsplitController.allPaneIds.first

        guard let targetPaneId else { return nil }
        return openMarkdownFromSidebar(inPane: targetPaneId, filePath: filePath, focus: focus)
    }

    @discardableResult
    func openEmailThreadFromSidebar(
        inPane requestedPaneId: PaneID?,
        thread: EmailThreadItem,
        excludedAgentCompanionPaneIds: Set<PaneID>,
        anchorPanelId: UUID?,
        focus: Bool = true
    ) -> ZebraEmailThreadPanel? {
        if let existing = focusExistingEmailThread(thread, focus: focus) {
            return existing
        }

        let targetPaneId: PaneID? = {
            if let requestedPaneId,
               !excludedAgentCompanionPaneIds.contains(requestedPaneId),
               selectedEmailThreadPanel(inPane: requestedPaneId) != nil {
                return requestedPaneId
            }
            return resolvePaneForContentOpen(
                kind: .email,
                excludedAgentCompanionPaneIds: excludedAgentCompanionPaneIds,
                anchorPanelId: anchorPanelId
            )
        }()

        if let targetPaneId,
           let selected = selectedEmailThreadPanel(inPane: targetPaneId) {
            selected.panel.openThread(thread)
            panelTitles[selected.panelId] = selected.panel.displayTitle
            bonsplitController.updateTab(
                selected.tabId,
                title: selected.panel.displayTitle,
                icon: .some(selected.panel.displayIcon)
            )
            if focus {
                focusPanel(selected.panelId)
            } else {
                objectWillChange.send()
            }
            return selected.panel
        }

        if let targetPaneId {
            return openOrFocusEmailThreadSurface(inPane: targetPaneId, thread: thread, focus: focus)
        }

        guard let sourcePanelId = firstPanelIdForContentSplit(
            excludedAgentCompanionPaneIds: excludedAgentCompanionPaneIds
        ) else {
            return nil
        }
        return newEmailThreadSplit(
            from: sourcePanelId,
            orientation: .horizontal,
            insertFirst: true,
            thread: thread,
            focus: focus
        )
    }

    @discardableResult
    func openOrFocusEmailThreadSurface(
        inPane paneId: PaneID,
        thread: EmailThreadItem,
        focus: Bool = true
    ) -> ZebraEmailThreadPanel? {
        if let existing = focusExistingEmailThread(thread, focus: focus) {
            return existing
        }

        return newEmailThreadSurface(inPane: paneId, thread: thread, focus: focus)
    }

    private func focusExistingEmailThread(
        _ thread: EmailThreadItem,
        focus: Bool = true
    ) -> ZebraEmailThreadPanel? {
        for (existingId, panel) in panels {
            guard let emailPanel = panel as? ZebraEmailThreadPanel,
                  emailPanel.threadId == thread.id else {
                continue
            }
            emailPanel.updateSubject(thread.subject)
            panelTitles[existingId] = emailPanel.displayTitle
            if let tabId = surfaceIdFromPanelId(existingId) {
                bonsplitController.updateTab(
                    tabId,
                    title: emailPanel.displayTitle,
                    icon: .some(emailPanel.displayIcon)
                )
            }
            if focus {
                focusPanel(existingId)
            }
            return emailPanel
        }
        return nil
    }

    @discardableResult
    private func newEmailThreadSplit(
        from panelId: UUID,
        orientation: SplitOrientation,
        insertFirst: Bool,
        thread: EmailThreadItem,
        focus: Bool
    ) -> ZebraEmailThreadPanel? {
        guard let sourceTabId = surfaceIdFromPanelId(panelId) else { return nil }
        var sourcePaneId: PaneID?
        for paneId in bonsplitController.allPaneIds {
            let tabs = bonsplitController.tabs(inPane: paneId)
            if tabs.contains(where: { $0.id == sourceTabId }) {
                sourcePaneId = paneId
                break
            }
        }
        guard let paneId = sourcePaneId else { return nil }

        let emailPanel = ZebraEmailThreadPanel(
            workspaceId: id,
            threadId: thread.id,
            subject: thread.subject
        )
        panels[emailPanel.id] = emailPanel
        panelTitles[emailPanel.id] = emailPanel.displayTitle

        let newTab = Bonsplit.Tab(
            title: emailPanel.displayTitle,
            icon: emailPanel.displayIcon,
            kind: Workspace.SurfaceKind.email,
            isDirty: false,
            isLoading: false,
            isPinned: false
        )
        surfaceIdToPanelId[newTab.id] = emailPanel.id

        guard let newPaneId = bonsplitController.splitPane(
            paneId,
            orientation: orientation,
            withTab: newTab,
            insertFirst: insertFirst
        ) else {
            surfaceIdToPanelId.removeValue(forKey: newTab.id)
            panels.removeValue(forKey: emailPanel.id)
            panelTitles.removeValue(forKey: emailPanel.id)
            return nil
        }
        publishCmuxSplitCreated(
            newPaneId,
            sourcePaneId: paneId,
            orientation: orientation,
            surfaceId: emailPanel.id,
            kind: "email",
            origin: "email_split",
            focused: focus
        )

        if focus {
            focusPanel(emailPanel.id)
        }
        return emailPanel
    }

    @discardableResult
    private func newEmailThreadSurface(
        inPane paneId: PaneID,
        thread: EmailThreadItem,
        focus: Bool
    ) -> ZebraEmailThreadPanel? {
        let emailPanel = ZebraEmailThreadPanel(
            workspaceId: id,
            threadId: thread.id,
            subject: thread.subject
        )
        panels[emailPanel.id] = emailPanel
        panelTitles[emailPanel.id] = emailPanel.displayTitle

        guard let newTabId = bonsplitController.createTab(
            title: emailPanel.displayTitle,
            icon: emailPanel.displayIcon,
            kind: Workspace.SurfaceKind.email,
            isDirty: false,
            isLoading: false,
            isPinned: false,
            inPane: paneId
        ) else {
            panels.removeValue(forKey: emailPanel.id)
            panelTitles.removeValue(forKey: emailPanel.id)
            return nil
        }

        surfaceIdToPanelId[newTabId] = emailPanel.id
        publishCmuxSurfaceCreated(
            emailPanel.id,
            paneId: paneId,
            kind: "email",
            origin: "email_tab",
            focused: focus
        )
        if focus {
            focusPanel(emailPanel.id)
        }
        return emailPanel
    }
}

private enum ZebraContentPlacementKind {
    case markdown
    case email
}

private extension Workspace {
    func resolvePaneForContentOpen(
        kind: ZebraContentPlacementKind,
        excludedAgentCompanionPaneIds: Set<PaneID>,
        anchorPanelId: UUID?
    ) -> PaneID? {
        let anchorPaneId = anchorPanelId.flatMap { paneId(forPanelId: $0) }
        var best: (paneId: PaneID, score: Int)?

        for paneId in bonsplitController.allPaneIds {
            let panePanels = panels(inPane: paneId)
            if excludedAgentCompanionPaneIds.contains(paneId),
               panePanels.contains(where: { $0 is TerminalPanel }) {
                continue
            }

            var score = scorePaneForContentOpen(kind: kind, panels: panePanels)
            if anchorPaneId == paneId {
                score += 10
            }

            if let current = best {
                if score > current.score {
                    best = (paneId, score)
                }
            } else {
                best = (paneId, score)
            }
        }

        return best?.paneId
    }

    func scorePaneForContentOpen(
        kind: ZebraContentPlacementKind,
        panels panePanels: [any Panel]
    ) -> Int {
        let hasMarkdown = panePanels.contains { $0 is MarkdownPanel }
        let hasEmail = panePanels.contains { $0 is ZebraEmailThreadPanel }
        let hasFilePreview = panePanels.contains { $0 is FilePreviewPanel }
        let hasAnyContent = hasMarkdown || hasEmail || hasFilePreview

        switch kind {
        case .markdown:
            if hasMarkdown { return 100 }
        case .email:
            if hasEmail { return 100 }
        }

        if hasAnyContent { return 70 }
        if panePanels.isEmpty { return 20 }
        return 30
    }

    func panels(inPane paneId: PaneID) -> [any Panel] {
        bonsplitController.tabs(inPane: paneId).compactMap { tab in
            guard let panelId = panelIdFromSurfaceId(tab.id) else { return nil }
            return panels[panelId]
        }
    }

    func selectedEmailThreadPanel(
        inPane paneId: PaneID
    ) -> (panel: ZebraEmailThreadPanel, panelId: UUID, tabId: TabID)? {
        guard let selectedTab = bonsplitController.selectedTab(inPane: paneId),
              let selectedPanelId = panelIdFromSurfaceId(selectedTab.id),
              let emailPanel = panels[selectedPanelId] as? ZebraEmailThreadPanel else {
            return nil
        }
        return (emailPanel, selectedPanelId, selectedTab.id)
    }

    func firstPanelIdForContentSplit(
        excludedAgentCompanionPaneIds: Set<PaneID>
    ) -> UUID? {
        let paneIds = bonsplitController.allPaneIds
        let preferredPane = paneIds.first { !excludedAgentCompanionPaneIds.contains($0) }
            ?? paneIds.first
        guard let preferredPane else { return nil }

        for tab in bonsplitController.tabs(inPane: preferredPane) {
            if let panelId = panelIdFromSurfaceId(tab.id) {
                return panelId
            }
        }

        for paneId in paneIds where paneId != preferredPane {
            for tab in bonsplitController.tabs(inPane: paneId) {
                if let panelId = panelIdFromSurfaceId(tab.id) {
                    return panelId
                }
            }
        }
        return nil
    }

    func nearestRightTerminalPane(fromContentPane contentPaneId: PaneID) -> PaneID? {
        let targetPaneId = contentPaneId.id.uuidString
        guard let path = zebraPathToPane(
            targetPaneId: targetPaneId,
            node: bonsplitController.treeSnapshot()
        ) else {
            return nil
        }

        let contentFrame = bonsplitController.layoutSnapshot().panes
            .first(where: { $0.paneId == targetPaneId })?
            .frame
        let contentCenterY = contentFrame.map { $0.y + ($0.height * 0.5) } ?? 0
        let contentRightX = contentFrame.map { $0.x + $0.width } ?? 0

        for crumb in path {
            guard crumb.split.orientation == "horizontal", crumb.branch == .first else { continue }
            var candidateNodes: [ExternalPaneNode] = []
            zebraCollectPaneNodes(node: crumb.split.second, into: &candidateNodes)
            let sorted = candidateNodes.sorted { lhs, rhs in
                let lhsDy = abs((lhs.frame.y + (lhs.frame.height * 0.5)) - contentCenterY)
                let rhsDy = abs((rhs.frame.y + (rhs.frame.height * 0.5)) - contentCenterY)
                if lhsDy != rhsDy { return lhsDy < rhsDy }

                let lhsDx = abs(lhs.frame.x - contentRightX)
                let rhsDx = abs(rhs.frame.x - contentRightX)
                if lhsDx != rhsDx { return lhsDx < rhsDx }

                if lhs.frame.x != rhs.frame.x { return lhs.frame.x < rhs.frame.x }
                return lhs.id < rhs.id
            }

            for candidate in sorted {
                guard let candidateUUID = UUID(uuidString: candidate.id),
                      candidateUUID != contentPaneId.id,
                      let paneId = bonsplitController.allPaneIds.first(where: { $0.id == candidateUUID }),
                      paneHasTerminalSurface(paneId) else {
                    continue
                }
                return paneId
            }
        }
        return nil
    }
}

private enum ZebraPaneBranch {
    case first
    case second
}

private struct ZebraPaneBreadcrumb {
    let split: ExternalSplitNode
    let branch: ZebraPaneBranch
}

private func zebraPathToPane(targetPaneId: String, node: ExternalTreeNode) -> [ZebraPaneBreadcrumb]? {
    switch node {
    case .pane(let paneNode):
        return paneNode.id == targetPaneId ? [] : nil
    case .split(let splitNode):
        if var path = zebraPathToPane(targetPaneId: targetPaneId, node: splitNode.first) {
            path.append(ZebraPaneBreadcrumb(split: splitNode, branch: .first))
            return path
        }
        if var path = zebraPathToPane(targetPaneId: targetPaneId, node: splitNode.second) {
            path.append(ZebraPaneBreadcrumb(split: splitNode, branch: .second))
            return path
        }
        return nil
    }
}

private func zebraCollectPaneNodes(node: ExternalTreeNode, into output: inout [ExternalPaneNode]) {
    switch node {
    case .pane(let paneNode):
        output.append(paneNode)
    case .split(let splitNode):
        zebraCollectPaneNodes(node: splitNode.first, into: &output)
        zebraCollectPaneNodes(node: splitNode.second, into: &output)
    }
}
