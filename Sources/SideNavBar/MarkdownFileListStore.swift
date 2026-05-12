import Combine
import Foundation

@MainActor
final class MarkdownFileListStore: ObservableObject {
    @Published private(set) var mdFiles: [MarkdownFileEntry] = []
    @Published private(set) var rootPath: String?
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastError: String?

    private static let excludedDirNames: Set<String> = [
        ".git", ".svn", ".hg",
        "node_modules", ".next", "dist", "build",
        "DerivedData", ".build", "Pods",
        "target", "vendor",
        ".gradle", ".idea", ".vscode",
        // macOS user-level dirs that often trigger TCC or aren't useful for a markdown nav
        "Library", "Movies", "Music", "Pictures", "Public",
    ]
    private static let markdownExtensions: Set<String> = ["md", "markdown"]
    private static let maxScanEntries: Int = 5000
    private static let maxScanDuration: TimeInterval = 5.0

    private struct ScanResult: Sendable {
        let entries: [MarkdownFileEntry]
    }

    private var watcher: FileExplorerDirectoryWatcher?
    private var scanTask: Task<Void, Never>?

    init() {}

    deinit {
        scanTask?.cancel()
        watcher?.stop()
    }

    func bind(rootPath newRoot: String?) {
        let trimmed = newRoot?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (trimmed?.isEmpty == false) ? trimmed : nil
        guard resolved != rootPath else { return }
        rootPath = resolved
        watcher?.stop()
        watcher = nil
        guard let path = resolved else {
            scanTask?.cancel()
            scanTask = nil
            mdFiles = []
            isScanning = false
            lastError = nil
            return
        }
        let nextWatcher = FileExplorerDirectoryWatcher(onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleRescan()
            }
        })
        nextWatcher.watch(path: path)
        watcher = nextWatcher
        scheduleRescan()
    }

    private func scheduleRescan() {
        scanTask?.cancel()
        guard let path = rootPath else { return }
        isScanning = true
        lastError = nil
        let snapshotRoot = path
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.scan(root: snapshotRoot)
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                guard self.rootPath == snapshotRoot else { return }
                switch result {
                case .success(let scanResult):
                    self.mdFiles = scanResult.entries
                    self.lastError = nil
                case .failure(let error):
                    self.mdFiles = []
                    self.lastError = error.localizedDescription
                }
                self.isScanning = false
            }
        }
    }

    nonisolated private static func scan(root: String) -> Result<ScanResult, Error> {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        var entries: [MarkdownFileEntry] = []
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return .success(ScanResult(entries: []))
        }

        let scanStarted = Date()
        while let candidate = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            if entries.count >= maxScanEntries { break }
            if Date().timeIntervalSince(scanStarted) > maxScanDuration { break }
            let name = candidate.lastPathComponent
            if name.hasPrefix(".") {
                let values = try? candidate.resourceValues(forKeys: Set(resourceKeys))
                if values?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            let values = try? candidate.resourceValues(forKeys: Set(resourceKeys))
            if values?.isDirectory == true {
                if excludedDirNames.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let ext = candidate.pathExtension.lowercased()
            guard markdownExtensions.contains(ext) else { continue }
            let abs = candidate.path
            let relativeParent = Self.relativeParent(of: abs, root: root)
            entries.append(MarkdownFileEntry(
                absolutePath: abs,
                displayName: name,
                relativeParentPath: relativeParent
            ))
        }

        entries.sort { lhs, rhs in
            let order = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.relativeParentPath.localizedCaseInsensitiveCompare(rhs.relativeParentPath) == .orderedAscending
        }

        return .success(ScanResult(entries: entries))
    }

    nonisolated private static func relativeParent(of absolutePath: String, root: String) -> String {
        let absNS = absolutePath as NSString
        let parent = absNS.deletingLastPathComponent
        if parent == root { return "" }
        let rootWithSlash = (root.hasSuffix("/") ? root : root + "/")
        if parent.hasPrefix(rootWithSlash) {
            let trimmed = String(parent.dropFirst(rootWithSlash.count))
            return trimmed + "/"
        }
        return parent + "/"
    }
}
