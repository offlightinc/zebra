import Foundation
import Combine
import Bonsplit

/// A panel that renders a markdown file with live file-watching.
/// When the file changes on disk, the content is automatically reloaded.
@MainActor
final class MarkdownPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .markdown

    /// Absolute path to the markdown file being displayed.
    let filePath: String

    /// The workspace this panel belongs to.
    private(set) var workspaceId: UUID

    /// Current markdown content read from the file.
    @Published private(set) var content: String = ""

    /// Latest parsed brain object. `nil` while the first parse is in
    /// flight; the view layer shows the loading skeleton in that window.
    @Published private(set) var parse: BrainObjectParse?

    /// Whether the right-pane inspector is visible. Persisted per main
    /// window via UserDefaults.
    @Published var showsInspector: Bool = MarkdownPanel.loadInspectorVisibility()

    /// Title shown in the tab bar (filename).
    @Published private(set) var displayTitle: String = ""

    /// SF Symbol icon for the tab bar.
    var displayIcon: String? { "doc.richtext" }

    /// Whether the file has been deleted or is unreadable.
    @Published private(set) var isFileUnavailable: Bool = false

    /// Pane where the markdown chat pill accumulates agent terminal tabs.
    /// Stored on the panel model instead of the SwiftUI view so split layout
    /// reparenting does not lose the companion-pane reference.
    @Published var chatCompanionPaneId: PaneID?

    /// Token incremented to trigger focus flash animation.
    @Published private(set) var focusFlashToken: Int = 0

    // MARK: - File watching

    // nonisolated(unsafe) because deinit is not guaranteed to run on the
    // main actor, but DispatchSource.cancel() is thread-safe.
    private nonisolated(unsafe) var fileWatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var isClosed: Bool = false
    private let watchQueue = DispatchQueue(label: "com.cmux.markdown-file-watch", qos: .utility)

    /// Off-main queue for frontmatter parsing. Parses are short — a few
    /// hundred microseconds in practice — but the file-watcher path can
    /// fire on every keystroke when the file is open in another editor,
    /// so we keep them off the main actor.
    private let parseQueue = DispatchQueue(label: "com.cmux.brain-object-parse", qos: .userInitiated)
    /// Bumped per loadFileContent() so stale parses can be ignored.
    private var parseGeneration: Int = 0
    private static let inspectorVisibilityKey = "cmux.brainViewer.showsInspector"

    /// Maximum number of reattach attempts after a file delete/rename event.
    private static let maxReattachAttempts = 6
    /// Delay between reattach attempts (total window: attempts * delay = 3s).
    private static let reattachDelay: TimeInterval = 0.5

    // MARK: - Init

    init(workspaceId: UUID, filePath: String) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.filePath = filePath
        self.displayTitle = (filePath as NSString).lastPathComponent

        loadFileContent()
        startFileWatcher()
        if isFileUnavailable && fileWatchSource == nil {
            // Session restore can create a panel before the file is recreated.
            // Retry briefly so atomic-rename recreations can reconnect.
            scheduleReattach(attempt: 1)
        }
    }

    // MARK: - Panel protocol

    func focus() {
        // Markdown panel is read-only; no first responder to manage.
    }

    func unfocus() {
        // No-op for read-only panel.
    }

    func close() {
        isClosed = true
        stopFileWatcher()
    }

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }

    // MARK: - File I/O

    private func loadFileContent() {
        do {
            let newContent = try String(contentsOfFile: filePath, encoding: .utf8)
            content = newContent
            isFileUnavailable = false
        } catch {
            // Fallback: try ISO Latin-1, which accepts all 256 byte values,
            // covering legacy encodings like Windows-1252.
            if let data = FileManager.default.contents(atPath: filePath),
               let decoded = String(data: data, encoding: .isoLatin1) {
                content = decoded
                isFileUnavailable = false
            } else {
                isFileUnavailable = true
            }
        }
        scheduleParse()
    }

    // MARK: - Object inspector

    /// Toggle inspector visibility and persist.
    func toggleInspector() {
        showsInspector.toggle()
        UserDefaults.standard.set(showsInspector, forKey: MarkdownPanel.inspectorVisibilityKey)
    }

    /// Write a single frontmatter key back to disk. `value == nil` removes
    /// the key. The file watcher will pick up the change and re-parse, but
    /// we also do an optimistic local update so the UI snaps before the
    /// watcher round-trip completes.
    func updateFrontmatter(key: String, value: String?) {
        let snapshot = content
        let newText = BrainFrontmatterWriter.setScalar(key, to: value, in: snapshot)
        guard newText != snapshot else { return }
        do {
            try newText.write(toFile: filePath, atomically: true, encoding: .utf8)
            content = newText
            scheduleParse()
        } catch {
            NSLog("MarkdownPanel.updateFrontmatter failed for key=\(key): \(error)")
        }
    }

    private static func loadInspectorVisibility() -> Bool {
        if UserDefaults.standard.object(forKey: inspectorVisibilityKey) == nil {
            // Inspector ships visible by default — that's the whole point
            // of the brain-viewer feature.
            return true
        }
        return UserDefaults.standard.bool(forKey: inspectorVisibilityKey)
    }

    /// Parse the current content off-main, then publish on the main actor.
    private func scheduleParse() {
        parseGeneration &+= 1
        let gen = parseGeneration
        let snapshot = content
        let path = filePath
        parseQueue.async { [weak self] in
            let result = BrainObjectParser.parse(snapshot, filename: path)
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.parseGeneration == gen else { return }
                self.parse = result
            }
        }
    }

    // MARK: - File watcher via DispatchSource

    private func startFileWatcher() {
        let fd = open(filePath, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: watchQueue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // File was deleted or renamed. The old file descriptor points to
                // a stale inode, so we must always stop and reattach the watcher
                // even if the new file is already readable (atomic save case).
                DispatchQueue.main.async {
                    self.stopFileWatcher()
                    self.loadFileContent()
                    if self.isFileUnavailable {
                        // File not yet replaced — retry until it reappears.
                        self.scheduleReattach(attempt: 1)
                    } else {
                        // File already replaced — reattach to the new inode immediately.
                        self.startFileWatcher()
                    }
                }
            } else {
                // Content changed — reload.
                DispatchQueue.main.async {
                    self.loadFileContent()
                }
            }
        }

        source.setCancelHandler {
            Darwin.close(fd)
        }

        source.resume()
        fileWatchSource = source
    }

    /// Retry reattaching the file watcher up to `maxReattachAttempts` times.
    /// Each attempt checks if the file has reappeared. Bails out early if
    /// the panel has been closed.
    private func scheduleReattach(attempt: Int) {
        guard attempt <= Self.maxReattachAttempts else { return }
        watchQueue.asyncAfter(deadline: .now() + Self.reattachDelay) { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                guard !self.isClosed else { return }
                if FileManager.default.fileExists(atPath: self.filePath) {
                    self.isFileUnavailable = false
                    self.loadFileContent()
                    self.startFileWatcher()
                } else {
                    self.scheduleReattach(attempt: attempt + 1)
                }
            }
        }
    }

    private func stopFileWatcher() {
        if let source = fileWatchSource {
            source.cancel()
            fileWatchSource = nil
        }
        // File descriptor is closed by the cancel handler.
        fileDescriptor = -1
    }

    deinit {
        // DispatchSource cancel is safe from any thread.
        fileWatchSource?.cancel()
    }
}
