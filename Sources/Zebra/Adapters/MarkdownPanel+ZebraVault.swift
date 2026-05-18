import Bonsplit
import Combine
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
}

@MainActor
final class ZebraEmailThreadPanel: Panel, ObservableObject {
    let id: UUID
    // First-class panel type. Rendering goes through the generic
    // `customPanelViewFactory` seam in `PanelContentView`, so cmux common
    // code never has to know about `ZebraEmailThreadPanel` directly.
    let panelType: PanelType = .email
    let threadId: String
    var displayIcon: String? { "envelope" }

    @Published private(set) var displayTitle: String
    @Published private(set) var focusFlashToken: Int = 0

    init(threadId: String, subject: String) {
        self.id = UUID()
        self.threadId = threadId
        self.displayTitle = Self.title(from: subject)
    }

    func updateSubject(_ subject: String) {
        let nextTitle = Self.title(from: subject)
        guard displayTitle != nextTitle else { return }
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
    func openOrFocusMarkdownContent(
        filePath: String,
        excludedAgentCompanionPaneIds: Set<PaneID>,
        anchorPanelId: UUID?
    ) -> MarkdownPanel? {
        if let existing = focusExistingMarkdownContent(filePath: filePath) {
            return existing
        }

        if let paneId = resolvePaneForContentOpen(
            kind: .markdown,
            excludedAgentCompanionPaneIds: excludedAgentCompanionPaneIds,
            anchorPanelId: anchorPanelId
        ) {
            return openOrFocusMarkdownSurface(inPane: paneId, filePath: filePath, focus: true)
        }

        guard let sourcePanelId = firstPanelIdForContentSplit(
            excludedAgentCompanionPaneIds: excludedAgentCompanionPaneIds
        ) else {
            return nil
        }
        return newMarkdownSplit(
            from: sourcePanelId,
            orientation: .horizontal,
            insertFirst: true,
            filePath: filePath,
            focus: true
        )
    }

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
    func focusExistingMarkdownContent(filePath: String) -> MarkdownPanel? {
        let canonical = (filePath as NSString).resolvingSymlinksInPath
        for (existingId, panel) in panels {
            guard let markdownPanel = panel as? MarkdownPanel else { continue }
            guard (markdownPanel.filePath as NSString).resolvingSymlinksInPath == canonical else {
                continue
            }
            focusPanel(existingId)
            return markdownPanel
        }
        return nil
    }

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

    func firstPanelIdForContentSplit(
        excludedAgentCompanionPaneIds: Set<PaneID>
    ) -> UUID? {
        let paneIds = bonsplitController.allPaneIds
        let preferredPane = paneIds.first { excludedAgentCompanionPaneIds.contains($0) }
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
}
