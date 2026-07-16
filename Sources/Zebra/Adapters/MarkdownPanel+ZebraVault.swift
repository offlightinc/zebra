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

enum ZebraTerminalStartupLineEvent: Equatable {
    case text(String)
    case input(String)
}

enum ZebraTerminalStartupLinePlan {
    static func events(for startupLine: String) -> [ZebraTerminalStartupLineEvent] {
        let lineEnding: String
        let commandText: String
        if startupLine.hasSuffix("\r\n") {
            lineEnding = "\r"
            commandText = String(startupLine.dropLast())
        } else if startupLine.hasSuffix("\r") || startupLine.hasSuffix("\n") {
            lineEnding = "\r"
            commandText = String(startupLine.dropLast())
        } else {
            lineEnding = ""
            commandText = startupLine
        }

        var events: [ZebraTerminalStartupLineEvent] = []
        if !commandText.isEmpty {
            events.append(.text(commandText))
        }
        if !lineEnding.isEmpty {
            events.append(.input(lineEnding))
        }
        return events
    }
}

extension TerminalPanel: ZebraTerminalPanel {
    var isSurfaceReady: Bool {
        surface.surface != nil
    }

    func zebraSendStartupLine(_ startupLine: String) {
        // Long commands overflow the kernel PTY input queue (TTYHOG = 1024 bytes)
        // while the shell is still starting up and not yet draining input, which
        // truncates the command mid-line. Stage long commands into a temp script
        // and inject only a short `source '<path>'` line.
        let injectedLine = ZebraTerminalStartupStaging.stage(startupLine: startupLine)
        let events = ZebraTerminalStartupLinePlan.events(for: injectedLine)
        #if DEBUG
        let eventSummary = events.map { event -> String in
            switch event {
            case .text(let text):
                return "text:\(text.utf8.count)"
            case .input(let input):
                return "input:\(input.utf8.count)"
            }
        }.joined(separator: ",")
        cmuxDebugLog(
            "zebra.startup.send panel=\(id.uuidString.prefix(5)) " +
            "ready=\(isSurfaceReady ? 1 : 0) bytes=\(startupLine.utf8.count) " +
            "staged=\(injectedLine.utf8.count != startupLine.utf8.count ? 1 : 0) " +
            "injectedBytes=\(injectedLine.utf8.count) events=\(eventSummary)"
        )
        #endif
        for event in events {
            switch event {
            case .text(let text):
                sendText(text)
            case .input(let input):
                sendInput(input)
            }
        }
    }

    func zebraSendStartupLineWhenReady(_ startupLine: String) {
        #if DEBUG
        cmuxDebugLog(
            "zebra.startup.wait panel=\(id.uuidString.prefix(5)) " +
            "ready=\(isSurfaceReady ? 1 : 0) bytes=\(startupLine.utf8.count)"
        )
        #endif
        let runSequence = { [weak self] in
            self?.zebraSendStartupLine(startupLine)
        }

        if isSurfaceReady {
            #if DEBUG
            cmuxDebugLog(
                "zebra.startup.wait.immediate panel=\(id.uuidString.prefix(5))"
            )
            #endif
            runSequence()
            return
        }

        var resolved = false
        var observer: NSObjectProtocol?
        let cleanup = {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        observer = NotificationCenter.default.addObserver(
            forName: .terminalSurfaceDidBecomeReady,
            object: surface,
            queue: .main
        ) { [weak self] _ in
            guard let self,
                  !resolved,
                  self.isSurfaceReady else { return }
            resolved = true
            cleanup()
            #if DEBUG
            cmuxDebugLog(
                "zebra.startup.wait.ready panel=\(self.id.uuidString.prefix(5))"
            )
            #endif
            runSequence()
        }

        #if DEBUG
        cmuxDebugLog(
            "zebra.startup.wait.requestStart panel=\(id.uuidString.prefix(5))"
        )
        #endif
        surface.requestBackgroundSurfaceStartIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, !resolved else { return }
            resolved = true
            cleanup()
            #if DEBUG
            cmuxDebugLog(
                "zebra.agentTerminal.startup.timeout panel=\(self.id.uuidString.prefix(5))"
            )
            #endif
        }
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

    func reusableAgentCompanionPane(
        forContentPane paneId: PaneID,
        markedBy registry: ZebraAgentTerminalRegistry
    ) -> PaneID? {
        nearestAgentTerminalPane(
            fromContentPane: paneId,
            placement: ZebraChatPillPanePlacementSettings.resolvedPlacement(),
            markedBy: registry
        )
    }

    func activeAgentTerminalAgent(
        for source: ZebraAgentTerminalSource,
        contentPane paneId: PaneID,
        markedBy registry: ZebraAgentTerminalRegistry
    ) -> MarkdownPillAgent? {
        guard let companionPaneId = reusableAgentCompanionPane(
            forContentPane: paneId,
            markedBy: registry
        ) else { return nil }
        return registry.latestAgent(
            for: source,
            panelIds: panels(inPane: companionPaneId).map(\.id)
        )
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
    func zebraAgentCompanionPaneIds(markedBy registry: ZebraAgentTerminalRegistry) -> Set<PaneID> {
        registry.prune(validPanelIds: Set(panels.keys))
        return Set(
            bonsplitController.allPaneIds.filter { paneId in
                paneHasRegisteredAgentTerminal(paneId, markedBy: registry)
            }
        )
    }

    @discardableResult
    func openZebraAgentTerminal(
        startupLine: String,
        source: ZebraAgentTerminalSource,
        agent: MarkdownPillAgent,
        anchor: ZebraAgentTerminalPlacementAnchor,
        markedBy registry: ZebraAgentTerminalRegistry
    ) -> (any ZebraTerminalPanel)? {
        registry.prune(validPanelIds: Set(panels.keys))
        let panel: TerminalPanel?

        switch anchor {
        case .contentAnchored(let contentPanelId, let contentPaneId):
            let placement = ZebraChatPillPanePlacementSettings.resolvedPlacement()
            if let companionPaneId = nearestAgentTerminalPane(
                fromContentPane: contentPaneId,
                placement: placement,
                markedBy: registry
            ) {
                panel = newTerminalSurface(inPane: companionPaneId, focus: true)
            } else {
                panel = newTerminalSplit(
                    from: contentPanelId,
                    orientation: placement == .below ? .vertical : .horizontal,
                    focus: true
                )
            }

        case .focusAnchored:
            panel = openFocusAnchoredAgentTerminal(markedBy: registry)
        }

        guard let panel else { return nil }
        registry.mark(panelId: panel.id, source: source, agent: agent)
        sendStartupSequence(startupLine, to: panel)
        return panel
    }

    private func openFocusAnchoredAgentTerminal(markedBy registry: ZebraAgentTerminalRegistry) -> TerminalPanel? {
        let agentPaneIds = zebraAgentCompanionPaneIds(markedBy: registry)
        let focusedPaneId = bonsplitController.focusedPaneId

        if let focusedPaneId, agentPaneIds.contains(focusedPaneId) {
            return newTerminalSurface(inPane: focusedPaneId, focus: true)
        }

        if let focusedPaneId,
           let companionPaneId = nearestAgentTerminalPane(
               fromContentPane: focusedPaneId,
               placement: .right,
               markedBy: registry
           ) {
            return newTerminalSurface(inPane: companionPaneId, focus: true)
        }

        if let focusedPaneId,
           paneIsTerminalOnly(focusedPaneId) {
            return newTerminalSurface(inPane: focusedPaneId, focus: true)
        }

        if let focusedPaneId,
           let sourcePanelId = firstPanelId(inPane: focusedPaneId) {
            return newTerminalSplit(
                from: sourcePanelId,
                orientation: .horizontal,
                focus: true
            )
        }

        if let agentPaneId = agentPaneIds.first {
            return newTerminalSurface(inPane: agentPaneId, focus: true)
        }

        if let sourcePanelId = firstPanelIdForContentSplit(
            excludedAgentCompanionPaneIds: []
        ) {
            return newTerminalSplit(
                from: sourcePanelId,
                orientation: .horizontal,
                focus: true
            )
        }
        return nil
    }

    @discardableResult
    func openOrFocusEmailThreadContent(
        thread: EmailThreadItem,
        excludedAgentCompanionPaneIds: Set<PaneID>,
        requestedPaneId: PaneID?
    ) -> ZebraEmailThreadPanel? {
        if let existing = focusExistingEmailThread(
            thread,
            excludedPaneIds: excludedAgentCompanionPaneIds
        ) {
            return existing
        }

        if let paneId = nonAgentPaneForSidebarOpen(
            requestedPaneId: requestedPaneId,
            excludedAgentCompanionPaneIds: excludedAgentCompanionPaneIds
        ) {
            return openOrFocusEmailThreadSurface(
                inPane: paneId,
                thread: thread,
                focus: true,
                excludedPaneIds: excludedAgentCompanionPaneIds
            )
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
        inPane requestedPaneId: PaneID?,
        filePath: String,
        excludedAgentCompanionPaneIds: Set<PaneID>,
        focus: Bool = true
    ) -> MarkdownPanel? {
        let canonical = (filePath as NSString).resolvingSymlinksInPath
        for (existingId, panel) in panels {
            guard let markdown = panel as? MarkdownPanel else { continue }
            if let paneId = paneId(forPanelId: existingId),
               excludedAgentCompanionPaneIds.contains(paneId) {
                continue
            }
            if (markdown.filePath as NSString).resolvingSymlinksInPath == canonical {
                if focus {
                    focusPanel(existingId)
                }
                return markdown
            }
        }

        if let targetPaneId = nonAgentPaneForSidebarOpen(
            requestedPaneId: requestedPaneId,
            excludedAgentCompanionPaneIds: excludedAgentCompanionPaneIds
        ) {
            if let selectedTab = bonsplitController.selectedTab(inPane: targetPaneId),
               let selectedPanelId = panelIdFromSurfaceId(selectedTab.id),
               let markdown = panels[selectedPanelId] as? MarkdownPanel {
                markdown.openFile(filePath)
                panelTitles[selectedPanelId] = markdown.displayTitle
                bonsplitController.updateTab(
                    selectedTab.id,
                    title: panelCustomTitles[selectedPanelId] ?? markdown.displayTitle,
                    hasCustomTitle: panelCustomTitles[selectedPanelId] != nil
                )
                if focus {
                    focusPanel(selectedPanelId)
                } else {
                    objectWillChange.send()
                }
                return markdown
            }
            return newMarkdownSurface(inPane: targetPaneId, filePath: filePath, focus: focus)
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
            focus: focus
        )
    }

    @discardableResult
    func openEmailThreadFromSidebar(
        inPane requestedPaneId: PaneID?,
        thread: EmailThreadItem,
        excludedAgentCompanionPaneIds: Set<PaneID>,
        focus: Bool = true
    ) -> ZebraEmailThreadPanel? {
        if let existing = focusExistingEmailThread(
            thread,
            focus: focus,
            excludedPaneIds: excludedAgentCompanionPaneIds
        ) {
            return existing
        }

        if let targetPaneId = nonAgentPaneForSidebarOpen(
            requestedPaneId: requestedPaneId,
            excludedAgentCompanionPaneIds: excludedAgentCompanionPaneIds
        ) {
            if let reusable = reusableEmailThreadPanel(inPane: targetPaneId) {
                reusable.panel.openThread(thread)
                panelTitles[reusable.panelId] = reusable.panel.displayTitle
                bonsplitController.updateTab(
                    reusable.tabId,
                    title: reusable.panel.displayTitle,
                    icon: .some(reusable.panel.displayIcon)
                )
                if focus {
                    focusPanel(reusable.panelId)
                } else {
                    objectWillChange.send()
                }
                return reusable.panel
            }
            return openOrFocusEmailThreadSurface(
                inPane: targetPaneId,
                thread: thread,
                focus: focus,
                excludedPaneIds: excludedAgentCompanionPaneIds
            )
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
        focus: Bool = true,
        excludedPaneIds: Set<PaneID> = []
    ) -> ZebraEmailThreadPanel? {
        if let existing = focusExistingEmailThread(
            thread,
            focus: focus,
            excludedPaneIds: excludedPaneIds
        ) {
            return existing
        }

        return newEmailThreadSurface(inPane: paneId, thread: thread, focus: focus)
    }

    private func focusExistingEmailThread(
        _ thread: EmailThreadItem,
        focus: Bool = true,
        excludedPaneIds: Set<PaneID> = []
    ) -> ZebraEmailThreadPanel? {
        for (existingId, panel) in panels {
            guard let emailPanel = panel as? ZebraEmailThreadPanel,
                  emailPanel.threadId == thread.id else {
                continue
            }
            if let paneId = paneId(forPanelId: existingId),
               excludedPaneIds.contains(paneId) {
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

    /// Closes every open email tab showing `threadId`. Normally at most one
    /// exists (`openOrFocusEmailThreadSurface` dedups per workspace), but
    /// split flows can leave more. Used after a thread is archived so its
    /// stale tab doesn't linger.
    func closeEmailThreadPanels(threadId: String) {
        let panelIds = panels.compactMap { panelId, panel -> UUID? in
            guard let emailPanel = panel as? ZebraEmailThreadPanel,
                  emailPanel.threadId == threadId else {
                return nil
            }
            return panelId
        }
        for panelId in panelIds {
            closePanel(panelId, force: true)
        }
    }
}

private extension Workspace {
    func nonAgentPaneForSidebarOpen(
        requestedPaneId: PaneID?,
        excludedAgentCompanionPaneIds: Set<PaneID>
    ) -> PaneID? {
        if let requestedPaneId,
           bonsplitController.allPaneIds.contains(requestedPaneId),
           !excludedAgentCompanionPaneIds.contains(requestedPaneId) {
            return requestedPaneId
        }
        return bonsplitController.allPaneIds.first { !excludedAgentCompanionPaneIds.contains($0) }
    }

    func panels(inPane paneId: PaneID) -> [any Panel] {
        bonsplitController.tabs(inPane: paneId).compactMap { tab in
            guard let panelId = panelIdFromSurfaceId(tab.id) else { return nil }
            return panels[panelId]
        }
    }

    func firstPanelId(inPane paneId: PaneID) -> UUID? {
        if let selectedTab = bonsplitController.selectedTab(inPane: paneId),
           let selectedPanelId = panelIdFromSurfaceId(selectedTab.id) {
            return selectedPanelId
        }

        for tab in bonsplitController.tabs(inPane: paneId) {
            if let panelId = panelIdFromSurfaceId(tab.id) {
                return panelId
            }
        }
        return nil
    }

    func paneIsTerminalOnly(_ paneId: PaneID) -> Bool {
        let panePanels = panels(inPane: paneId)
        return !panePanels.isEmpty && panePanels.allSatisfy { $0 is TerminalPanel }
    }

    func reusableEmailThreadPanel(
        inPane paneId: PaneID
    ) -> (panel: ZebraEmailThreadPanel, panelId: UUID, tabId: TabID)? {
        if let selectedTab = bonsplitController.selectedTab(inPane: paneId),
           let selectedPanelId = panelIdFromSurfaceId(selectedTab.id),
           let emailPanel = panels[selectedPanelId] as? ZebraEmailThreadPanel {
            return (emailPanel, selectedPanelId, selectedTab.id)
        }

        for tab in bonsplitController.tabs(inPane: paneId) {
            guard let panelId = panelIdFromSurfaceId(tab.id),
                  let emailPanel = panels[panelId] as? ZebraEmailThreadPanel else {
                continue
            }
            return (emailPanel, panelId, tab.id)
        }
        return nil
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

    func nearestAgentTerminalPane(
        fromContentPane contentPaneId: PaneID,
        placement: ZebraChatPillPanePlacement,
        markedBy registry: ZebraAgentTerminalRegistry
    ) -> PaneID? {
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
        let contentCenterX = contentFrame.map { $0.x + ($0.width * 0.5) } ?? 0
        let contentCenterY = contentFrame.map { $0.y + ($0.height * 0.5) } ?? 0
        let contentTrailingX = contentFrame.map { $0.x + $0.width } ?? 0
        let contentBottomY = contentFrame.map { $0.y + $0.height } ?? 0
        let requiredOrientation = placement == .below ? "vertical" : "horizontal"

        for crumb in path {
            guard crumb.split.orientation == requiredOrientation,
                  crumb.branch == .first else { continue }
            var candidateNodes: [ExternalPaneNode] = []
            zebraCollectPaneNodes(node: crumb.split.second, into: &candidateNodes)
            let sorted = candidateNodes.sorted { lhs, rhs in
                let lhsCrossAxisDistance: Double
                let rhsCrossAxisDistance: Double
                let lhsMainAxisDistance: Double
                let rhsMainAxisDistance: Double
                switch placement {
                case .below:
                    lhsCrossAxisDistance = abs((lhs.frame.x + (lhs.frame.width * 0.5)) - contentCenterX)
                    rhsCrossAxisDistance = abs((rhs.frame.x + (rhs.frame.width * 0.5)) - contentCenterX)
                    lhsMainAxisDistance = abs(lhs.frame.y - contentBottomY)
                    rhsMainAxisDistance = abs(rhs.frame.y - contentBottomY)
                case .right:
                    lhsCrossAxisDistance = abs((lhs.frame.y + (lhs.frame.height * 0.5)) - contentCenterY)
                    rhsCrossAxisDistance = abs((rhs.frame.y + (rhs.frame.height * 0.5)) - contentCenterY)
                    lhsMainAxisDistance = abs(lhs.frame.x - contentTrailingX)
                    rhsMainAxisDistance = abs(rhs.frame.x - contentTrailingX)
                }
                if lhsCrossAxisDistance != rhsCrossAxisDistance {
                    return lhsCrossAxisDistance < rhsCrossAxisDistance
                }
                if lhsMainAxisDistance != rhsMainAxisDistance {
                    return lhsMainAxisDistance < rhsMainAxisDistance
                }

                if lhs.frame.x != rhs.frame.x { return lhs.frame.x < rhs.frame.x }
                if lhs.frame.y != rhs.frame.y { return lhs.frame.y < rhs.frame.y }
                return lhs.id < rhs.id
            }

            for candidate in sorted {
                guard let candidateUUID = UUID(uuidString: candidate.id),
                      candidateUUID != contentPaneId.id,
                      let paneId = bonsplitController.allPaneIds.first(where: { $0.id == candidateUUID }),
                      paneHasRegisteredAgentTerminal(paneId, markedBy: registry) else {
                    continue
                }
                return paneId
            }
        }
        return nil
    }

    func paneHasRegisteredAgentTerminal(
        _ paneId: PaneID,
        markedBy registry: ZebraAgentTerminalRegistry
    ) -> Bool {
        panels(inPane: paneId).contains { panel in
            guard panel is TerminalPanel else { return false }
            return registry.isAgentTerminal(panelId: panel.id)
        }
    }

    func sendStartupSequence(_ startupLine: String, to terminalPanel: TerminalPanel) {
        #if DEBUG
        cmuxDebugLog(
            "zebra.agentTerminal.startup.sequence panel=\(terminalPanel.id.uuidString.prefix(5)) " +
            "bytes=\(startupLine.utf8.count)"
        )
        #endif
        sendStartupSequenceWhenShellIsReady(
            startupLine,
            to: terminalPanel,
            remainingUnknownRetries: 40
        )
    }

    private func sendStartupSequenceWhenShellIsReady(
        _ startupLine: String,
        to terminalPanel: TerminalPanel,
        remainingUnknownRetries: Int
    ) {
        guard panels[terminalPanel.id] === terminalPanel else { return }

        switch panelShellActivityStates[terminalPanel.id] ?? .unknown {
        case .promptIdle:
            terminalPanel.zebraSendStartupLineWhenReady(startupLine)
        case .unknown where remainingUnknownRetries > 0:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak terminalPanel] in
                guard let self, let terminalPanel else { return }
                self.sendStartupSequenceWhenShellIsReady(
                    startupLine,
                    to: terminalPanel,
                    remainingUnknownRetries: remainingUnknownRetries - 1
                )
            }
        case .unknown:
            // Shell integrations are not guaranteed for every user shell. Keep
            // the existing surface-readiness fallback after giving the prompt
            // enough time to become the foreground process group.
            terminalPanel.zebraSendStartupLineWhenReady(startupLine)
        case .commandRunning:
            // A newly-created terminal can briefly report shell startup as a
            // running command. Wait for the first prompt instead of injecting
            // an interactive onboarding command into shell initialization.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak terminalPanel] in
                guard let self, let terminalPanel else { return }
                self.sendStartupSequenceWhenShellIsReady(
                    startupLine,
                    to: terminalPanel,
                    remainingUnknownRetries: remainingUnknownRetries
                )
            }
        }
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
