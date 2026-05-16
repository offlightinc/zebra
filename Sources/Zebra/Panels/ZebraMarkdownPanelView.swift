import AppKit
import Combine
import SwiftUI
import MarkdownUI
import Bonsplit
import ZebraVault

/// File-scope so it can hold `static let` constants. Lifted out of the
/// generic `ZebraMarkdownPanelView` struct because Swift disallows static
/// stored properties inside a generic context.
fileprivate enum InspectorSplitMetrics {
    static let markdownMinWidth: CGFloat = 360
    static let minInspectorWidth: Double = 280
    static let maxInspectorWidth: Double = 420
    static let dividerWidth: CGFloat = 1
}

/// SwiftUI view that renders a MarkdownPanel's content using MarkdownUI.
///
/// Generic over the model so SwiftUI's `@ObservedObject` sees a concrete
/// `ObservableObject` type at compile time. The cmux side constructs this
/// with `Model = MarkdownPanel`; the protocol seam (`ZebraMarkdownPanelModel`
/// + `ZebraMarkdownWorkspace`) is what lets the view sit inside ZebraVault
/// later without dragging the cmux model with it.
struct ZebraMarkdownPanelView<Model: ZebraMarkdownPanelModel>: View {
    @ObservedObject var panel: Model
    @ObservedObject var controller: MarkdownPanelController
    let workspace: any ZebraMarkdownWorkspace
    let paneId: PaneID
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0
    @AppStorage("cmux.brainViewer.inspectorWidth") private var storedInspectorWidth: Double = 300
    @State private var inspectorWidth: Double?
    @State private var inspectorDragStartWidth: Double?
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var markdownFileListStore: MarkdownFileListStore

    var body: some View {
        Group {
            if panel.isFileUnavailable {
                fileUnavailableView
            } else {
                splitContentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .overlay {
            RoundedRectangle(cornerRadius: FocusFlashPattern.ringCornerRadius)
                .stroke(cmuxAccentColor().opacity(focusFlashOpacity), lineWidth: 3)
                .shadow(color: cmuxAccentColor().opacity(focusFlashOpacity * 0.35), radius: 10)
                .padding(FocusFlashPattern.ringInset)
                .allowsHitTesting(false)
        }
        .overlay {
            if isVisibleInUI {
                // Observe left-clicks without intercepting them so markdown text
                // selection and link activation continue to use the native path.
                MarkdownPointerObserver(onPointerDown: onRequestPanelFocus)
            }
        }
        .onChange(of: panel.focusFlashToken) { _ in
            triggerFocusFlashAnimation()
        }
        .onAppear {
            inspectorWidth = clampedInspectorWidth(storedInspectorWidth, containerWidth: .infinity)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var splitContentView: some View {
        if !isVisibleInUI {
            Color.clear
        } else if controller.showsInspector {
            markdownInspectorSplitView
        } else {
            markdownContentView
        }
    }

    private var markdownInspectorSplitView: some View {
        GeometryReader { proxy in
            let resolvedInspectorWidth = clampedInspectorWidth(
                currentInspectorWidth,
                containerWidth: proxy.size.width
            )

            HStack(spacing: 0) {
                markdownContentView
                    .frame(minWidth: InspectorSplitMetrics.markdownMinWidth)

                MarkdownInspectorResizeHandle(
                    dividerWidth: InspectorSplitMetrics.dividerWidth,
                    onDragStart: {
                        inspectorDragStartWidth = currentInspectorWidth
                    },
                    onDragChanged: { translation in
                        let startWidth = inspectorDragStartWidth ?? currentInspectorWidth
                        let nextWidth = startWidth - Double(translation)
                        withTransaction(Transaction(animation: nil)) {
                            inspectorWidth = clampedInspectorWidth(nextWidth, containerWidth: proxy.size.width)
                        }
                    },
                    onDragEnd: {
                        storedInspectorWidth = clampedInspectorWidth(currentInspectorWidth, containerWidth: proxy.size.width)
                        inspectorDragStartWidth = nil
                    },
                    onCancel: {
                        inspectorDragStartWidth = nil
                    }
                )

                BrainObjectInspectorView(
                    parse: controller.parse,
                    onActivateRelation: activateRelation,
                    onUpdateFrontmatter: { key, value in
                        panel.updateFrontmatter(key: key, value: value)
                        markdownFileListStore.refreshVaultIndex(reason: "markdownPanel.frontmatter")
                    }
                )
                .frame(width: CGFloat(resolvedInspectorWidth))
            }
            .transaction { tx in
                tx.animation = nil
            }
        }
    }

    private var currentInspectorWidth: Double {
        inspectorWidth ?? storedInspectorWidth
    }

    private func clampedInspectorWidth(_ width: Double, containerWidth: CGFloat) -> Double {
        guard containerWidth.isFinite else {
            return min(
                max(width, InspectorSplitMetrics.minInspectorWidth),
                InspectorSplitMetrics.maxInspectorWidth
            )
        }

        let availableWidth = max(
            0,
            Double(containerWidth - InspectorSplitMetrics.markdownMinWidth - InspectorSplitMetrics.dividerWidth)
        )
        let minWidth = min(InspectorSplitMetrics.minInspectorWidth, availableWidth)
        let maxWidth = max(minWidth, min(InspectorSplitMetrics.maxInspectorWidth, availableWidth))
        return min(max(width, minWidth), maxWidth)
    }

    /// Markdown body uses the stripped body when frontmatter parsed
    /// cleanly; falls back to the raw content otherwise so a parse
    /// failure never breaks rendering on the left.
    private var renderedMarkdown: String {
        if let stripped = controller.parse?.strippedBody, !stripped.isEmpty {
            return stripped
        }
        return panel.content
    }

    private var markdownContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // File path breadcrumb + inspector toggle
                filePathHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Divider()
                    .padding(.horizontal, 16)

                // Rendered markdown
                Markdown(renderedMarkdown)
                    .markdownTheme(cmuxMarkdownTheme)
                    .textSelection(.enabled)
                    // Wire link activation through NSWorkspace explicitly.
                    // SwiftUI's default Link path does not fire reliably
                    // for the rendered Markdown in this panel; setting the
                    // env action makes it deterministic. Surface failures
                    // (no registered handler for the scheme, etc.) by
                    // returning .systemAction so the click is not silently
                    // swallowed.
                    .environment(\.openURL, OpenURLAction { url in
                        NSWorkspace.shared.open(url) ? .handled : .systemAction
                    })
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    // Bottom padding leaves room for the floating chat pill
                    // so scrolled-to-end content is not obscured by the pill.
                    .padding(.bottom, 160)
            }
        }
        .overlay(alignment: .bottom) {
            MarkdownChatPill(
                displayTitle: panel.displayTitle,
                activeAgent: liveChatCompanionAgent,
                onSubmit: { text, agent in
                    handlePillSubmit(text: text, agent: agent)
                }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
    }

    private var filePathHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.richtext")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            Text(panel.filePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            inspectorToggle
        }
    }

    private func activateRelation(_ ref: BrainObjectRef) {
        guard let filePath = BrainObjectLinkResolver.resolve(
            ref: ref,
            vaultRoot: markdownFileListStore.rootPath,
            markdownFiles: markdownFileListStore.mdFiles
        ) else {
            return
        }

        _ = workspace.openOrFocusMarkdownSurface(inPane: paneId, filePath: filePath, focus: true)
    }

    /// Chevron that hides/shows the right-pane inspector. The icon
    /// matches the panel-side convention (right-pointing chevron when
    /// closed, left when open).
    private var inspectorToggle: some View {
        Button {
            controller.toggleInspector()
        } label: {
            Image(systemName: controller.showsInspector
                  ? "sidebar.right"
                  : "sidebar.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(controller.showsInspector ? .primary : .secondary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(controller.showsInspector
              ? String(localized: "brain.toggle.hide", defaultValue: "Hide object inspector")
              : String(localized: "brain.toggle.show", defaultValue: "Show object inspector"))
    }

    private var fileUnavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(String(localized: "markdown.fileUnavailable.title", defaultValue: "File unavailable"))
                .font(.headline)
                .foregroundColor(.primary)
            Text(panel.filePath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            Text(String(localized: "markdown.fileUnavailable.message", defaultValue: "The file may have been moved or deleted."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Theme

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.12, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.98, alpha: 1.0))
    }

    private var cmuxMarkdownTheme: Theme {
        let isDark = colorScheme == .dark

        return Theme()
            // Text
            .text {
                ForegroundColor(isDark ? .white.opacity(0.9) : .primary)
                FontSize(14)
            }
            // Headings
            .heading1 { configuration in
                VStack(alignment: .leading, spacing: 8) {
                    configuration.label
                        .markdownTextStyle {
                            FontWeight(.bold)
                            FontSize(28)
                            ForegroundColor(isDark ? .white : .primary)
                        }
                    Divider()
                }
                .markdownMargin(top: 24, bottom: 16)
            }
            .heading2 { configuration in
                VStack(alignment: .leading, spacing: 6) {
                    configuration.label
                        .markdownTextStyle {
                            FontWeight(.bold)
                            FontSize(22)
                            ForegroundColor(isDark ? .white : .primary)
                        }
                    Divider()
                }
                .markdownMargin(top: 20, bottom: 12)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(18)
                        ForegroundColor(isDark ? .white : .primary)
                    }
                    .markdownMargin(top: 16, bottom: 8)
            }
            .heading4 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(16)
                        ForegroundColor(isDark ? .white : .primary)
                    }
                    .markdownMargin(top: 12, bottom: 6)
            }
            .heading5 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.medium)
                        FontSize(14)
                        ForegroundColor(isDark ? .white : .primary)
                    }
                    .markdownMargin(top: 10, bottom: 4)
            }
            .heading6 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.medium)
                        FontSize(13)
                        ForegroundColor(isDark ? .white.opacity(0.7) : .secondary)
                    }
                    .markdownMargin(top: 8, bottom: 4)
            }
            // Code blocks
            .codeBlock { configuration in
                ScrollView(.horizontal, showsIndicators: true) {
                    configuration.label
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(13)
                            ForegroundColor(isDark ? Color(red: 0.9, green: 0.9, blue: 0.9) : Color(red: 0.2, green: 0.2, blue: 0.2))
                        }
                        .padding(12)
                }
                .background(isDark
                    ? Color(nsColor: NSColor(white: 0.08, alpha: 1.0))
                    : Color(nsColor: NSColor(white: 0.93, alpha: 1.0)))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .markdownMargin(top: 8, bottom: 8)
            }
            // Inline code
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(13)
                ForegroundColor(isDark ? Color(red: 0.85, green: 0.6, blue: 0.95) : Color(red: 0.6, green: 0.2, blue: 0.7))
                BackgroundColor(isDark
                    ? Color(nsColor: NSColor(white: 0.18, alpha: 1.0))
                    : Color(nsColor: NSColor(white: 0.92, alpha: 1.0)))
            }
            // Block quotes
            .blockquote { configuration in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isDark ? Color.white.opacity(0.2) : Color.gray.opacity(0.4))
                        .frame(width: 3)
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(isDark ? .white.opacity(0.6) : .secondary)
                            FontSize(14)
                        }
                        .padding(.leading, 12)
                }
                .markdownMargin(top: 8, bottom: 8)
            }
            // Links
            .link {
                ForegroundColor(Color.accentColor)
            }
            // Strong
            .strong {
                FontWeight(.semibold)
            }
            // Tables
            .table { configuration in
                configuration.label
                    .markdownTableBorderStyle(.init(color: isDark ? .white.opacity(0.15) : .gray.opacity(0.3)))
                    .markdownTableBackgroundStyle(
                        .alternatingRows(
                            isDark
                                ? Color(nsColor: NSColor(white: 0.14, alpha: 1.0))
                                : Color(nsColor: NSColor(white: 0.96, alpha: 1.0)),
                            isDark
                                ? Color(nsColor: NSColor(white: 0.10, alpha: 1.0))
                                : Color(nsColor: NSColor(white: 1.0, alpha: 1.0))
                        )
                    )
                    .markdownMargin(top: 8, bottom: 8)
            }
            // Thematic break (horizontal rule)
            .thematicBreak {
                Divider()
                    .markdownMargin(top: 16, bottom: 16)
            }
            // List items
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: 4, bottom: 4)
            }
            // Paragraphs
            .paragraph { configuration in
                configuration.label
                    .markdownMargin(top: 4, bottom: 8)
            }
    }

    // MARK: - Focus Flash

    private func triggerFocusFlashAnimation() {
        focusFlashAnimationGeneration &+= 1
        let generation = focusFlashAnimationGeneration
        focusFlashOpacity = FocusFlashPattern.values.first ?? 0

        for segment in FocusFlashPattern.segments {
            DispatchQueue.main.asyncAfter(deadline: .now() + segment.delay) {
                guard focusFlashAnimationGeneration == generation else { return }
                withAnimation(focusFlashAnimation(for: segment.curve, duration: segment.duration)) {
                    focusFlashOpacity = segment.targetOpacity
                }
            }
        }
    }

    private func focusFlashAnimation(for curve: FocusFlashCurve, duration: TimeInterval) -> Animation {
        switch curve {
        case .easeIn:
            return .easeIn(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        }
    }

    // MARK: - Chat pill — submit routing

    /// Returns nil when the remembered companion pane was closed or merged
    /// away; submit then lazily recreates it next to this markdown panel.
    fileprivate var liveChatCompanionAgent: MarkdownPillAgent? {
        guard let paneId = controller.chatCompanionPaneId,
              workspace.allPaneIds.contains(paneId) else {
            return nil
        }
        return controller.chatCompanionAgent
    }

    fileprivate func handlePillSubmit(text: String, agent: MarkdownPillAgent) {
        guard let newPanel = createAgentTerminalTab() else { return }
        controller.chatCompanionAgent = agent

        let launchEnvironmentReady = MarkdownChatPillCommand.prepareLaunchEnvironment(
            agent: agent,
            markdownFilePath: panel.filePath
        )
        #if DEBUG
        if !launchEnvironmentReady {
            cmuxDebugLog("markdown.chatPill.launchEnvironment.failed agent=\(agent.rawValue)")
        }
        #endif

        let startupLine = MarkdownChatPillCommand.shellStartupLine(
            agent: agent,
            markdownFilePath: panel.filePath,
            userPrompt: text
        )
        sendStartupSequence(
            startup: startupLine,
            to: newPanel
        )
    }

    /// Create a fresh agent terminal for every prompt. The first prompt makes
    /// a companion split; subsequent prompts add tabs to that remembered pane.
    private func createAgentTerminalTab() -> (any ZebraTerminalPanel)? {
        if let paneId = controller.chatCompanionPaneId,
           workspace.allPaneIds.contains(paneId),
           let panel = workspace.newTerminalSurface(
               inPane: paneId,
               focus: true,
               initialCommand: nil
           ) {
            return panel
        }

        controller.chatCompanionPaneId = nil
        guard let newPanel = workspace.newTerminalSplit(
            from: panel.id,
            orientation: .horizontal,
            initialCommand: nil
        ) else { return nil }
        controller.chatCompanionPaneId = workspace.paneId(forPanelId: newPanel.id)
        return newPanel
    }

    /// Drive the new pane like a fast typist: when the Ghostty surface is
    /// alive, push one shell command that launches the CLI with the user's
    /// prompt as its initial argument.
    private func sendStartupSequence(
        startup: String,
        to terminalPanel: any ZebraTerminalPanel
    ) {
        let runSequence = {
            terminalPanel.sendInput(startup)
        }

        if terminalPanel.isSurfaceReady {
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
            object: nil,
            queue: .main
        ) { _ in
            guard !resolved,
                  terminalPanel.isSurfaceReady else { return }
            resolved = true
            cleanup()
            runSequence()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard !resolved else { return }
            resolved = true
            cleanup()
            #if DEBUG
            // 8s without a `terminalSurfaceDidBecomeReady` for this pane
            // means the startup line never reached the CLI — the prompt is
            // silently lost without this trace. Log so we can grep for the
            // pattern in the debug log if a user reports "agent never
            // answered my first prompt".
            cmuxDebugLog(
                "markdown.chatPill.startup.timeout panel=\(terminalPanel.id.uuidString.prefix(5))"
            )
            #endif
        }
    }
}

private struct MarkdownPointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> MarkdownPanelPointerObserverView {
        let view = MarkdownPanelPointerObserverView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: MarkdownPanelPointerObserverView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

private struct MarkdownInspectorResizeHandle: View {
    let dividerWidth: CGFloat
    let onDragStart: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnd: () -> Void
    let onCancel: () -> Void

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var cursorReleaseWorkItem: DispatchWorkItem?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: dividerWidth)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: SidebarResizeInteraction.totalHitWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHovering = hovering
                        if hovering {
                            activateResizeCursor()
                        } else if CGEventSource.buttonState(.combinedSessionState, button: .left) {
                            activateResizeCursor()
                        } else {
                            scheduleCursorRelease(delay: 0.05)
                        }
                    }
                    .onDisappear {
                        cancelDragIfNeeded()
                        scheduleCursorRelease(force: true)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                if !isDragging {
                                    TerminalWindowPortalRegistry.beginInteractiveGeometryResize()
                                    isDragging = true
                                    onDragStart()
                                }
                                activateResizeCursor()
                                onDragChanged(value.translation.width)
                            }
                            .onEnded { _ in
                                if isDragging {
                                    TerminalWindowPortalRegistry.endInteractiveGeometryResize()
                                    isDragging = false
                                    onDragEnd()
                                }
                                activateResizeCursor()
                                scheduleCursorRelease()
                            }
                    )
            }
    }

    private func activateResizeCursor() {
        cursorReleaseWorkItem?.cancel()
        cursorReleaseWorkItem = nil
        NSCursor.resizeLeftRight.set()
    }

    private func scheduleCursorRelease(force: Bool = false, delay: TimeInterval = 0) {
        cursorReleaseWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            cursorReleaseWorkItem = nil
            releaseResizeCursorIfNeeded(force: force)
        }
        cursorReleaseWorkItem = workItem
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            DispatchQueue.main.async(execute: workItem)
        }
    }

    private func releaseResizeCursorIfNeeded(force: Bool = false) {
        let isLeftMouseButtonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        guard force || (!isDragging && !isHovering && !isLeftMouseButtonDown) else { return }
        NSCursor.arrow.set()
    }

    private func cancelDragIfNeeded() {
        if isDragging {
            TerminalWindowPortalRegistry.endInteractiveGeometryResize()
            isDragging = false
        }
        onCancel()
    }
}

final class MarkdownPanelPointerObserverView: NSView {
    var onPointerDown: (() -> Void)?
    private var eventMonitor: Any?
    private weak var forwardedMouseTarget: NSView?

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installEventMonitorIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard PaneFirstClickFocusSettings.isEnabled(),
              window?.isKeyWindow != true,
              bounds.contains(point) else { return nil }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        PaneFirstClickFocusSettings.isEnabled()
    }

    override func mouseDown(with event: NSEvent) {
        onPointerDown?()
        forwardedMouseTarget = forwardedTarget(for: event)
        forwardedMouseTarget?.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        forwardedMouseTarget?.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        forwardedMouseTarget?.mouseUp(with: event)
        forwardedMouseTarget = nil
    }

    func shouldHandle(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown,
              let window,
              event.window === window,
              !isHiddenOrHasHiddenAncestor else { return false }
        if PaneFirstClickFocusSettings.isEnabled(), window.isKeyWindow != true {
            return false
        }
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point)
    }

    func handleEventIfNeeded(_ event: NSEvent) -> NSEvent {
        guard shouldHandle(event) else { return event }
        DispatchQueue.main.async { [weak self] in
            self?.onPointerDown?()
        }
        return event
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleEventIfNeeded(event) ?? event
        }
    }

    private func forwardedTarget(for event: NSEvent) -> NSView? {
        guard let window else {
#if DEBUG
            NSLog("MarkdownPanelPointerObserverView.forwardedTarget skipped, window=0 contentView=0")
#endif
            return nil
        }
        guard let contentView = window.contentView else {
#if DEBUG
            NSLog("MarkdownPanelPointerObserverView.forwardedTarget skipped, window=1 contentView=0")
#endif
            return nil
        }
        isHidden = true
        defer { isHidden = false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        let target = contentView.hitTest(point)
        return target === self ? nil : target
    }
}

private enum BrainObjectLinkResolver {
    static func resolve(
        ref: BrainObjectRef,
        vaultRoot: String?,
        markdownFiles: [MarkdownFileEntry]
    ) -> String? {
        let raw = normalizedRaw(ref.raw)
        guard !raw.isEmpty else { return nil }

        if raw.hasPrefix("/") {
            return existingMarkdownPath(raw)
        }

        if raw.contains("/"), let direct = resolveRelativePath(raw, vaultRoot: vaultRoot) {
            return direct
        }

        return resolveFromScannedFiles(raw, markdownFiles: markdownFiles)
    }

    private static func normalizedRaw(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pipeIndex = value.firstIndex(of: "|") {
            value = String(value[..<pipeIndex])
        }
        if let headingIndex = value.firstIndex(of: "#") {
            value = String(value[..<headingIndex])
        }
        while value.hasPrefix("./") {
            value = String(value.dropFirst(2))
        }
        while value.hasPrefix("../") {
            value = String(value.dropFirst(3))
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveRelativePath(_ raw: String, vaultRoot: String?) -> String? {
        guard let vaultRoot, !vaultRoot.isEmpty else { return nil }
        let base = (vaultRoot as NSString).appendingPathComponent(raw)
        for candidate in markdownCandidates(for: base) {
            if let path = existingMarkdownPath(candidate) {
                return path
            }
        }
        return nil
    }

    private static func resolveFromScannedFiles(_ raw: String, markdownFiles: [MarkdownFileEntry]) -> String? {
        let wanted = stripMarkdownExtension(raw).lowercased()
        let matches = markdownFiles.filter { entry in
            let relative = stripMarkdownExtension(entry.relativeParentPath + entry.displayName).lowercased()
            let filename = stripMarkdownExtension(entry.displayName).lowercased()
            return relative == wanted || filename == wanted
        }
        return matches.count == 1 ? matches[0].absolutePath : nil
    }

    private static func markdownCandidates(for path: String) -> [String] {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            return [path]
        }
        return [path + ".md", path + ".markdown"]
    }

    private static func existingMarkdownPath(_ path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        guard ext == "md" || ext == "markdown" else { return nil }
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private static func stripMarkdownExtension(_ value: String) -> String {
        let ns = value as NSString
        let ext = ns.pathExtension.lowercased()
        guard ext == "md" || ext == "markdown" else { return value }
        return ns.deletingPathExtension
    }
}

// Conformances live in `Sources/Zebra/Adapters/MarkdownPanel+ZebraVault.swift`.
