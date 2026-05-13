import Combine
import Foundation

@MainActor
final class GoalFileListStore: ObservableObject {
    @Published private(set) var goals: [GoalEntry] = []
    @Published private(set) var rootPath: String?
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastError: String?

    private static let markdownExtensions: Set<String> = ["md", "markdown"]
    private static let maxScanEntries: Int = 1000
    private static let maxScanDuration: TimeInterval = 5.0

    private struct ScanResult: Sendable {
        let entries: [GoalEntry]
    }

    private var watcher: FileExplorerDirectoryWatcher?
    private var scanTask: Task<Void, Never>?

    init() {}

    deinit {
        scanTask?.cancel()
        watcher?.stop()
    }

    /// Binds to `<vault>/goals/` derived from a vault root path. Pass `nil` to clear.
    func bind(vaultRoot: String?) {
        let trimmed = vaultRoot?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedVault = (trimmed?.isEmpty == false) ? trimmed : nil
        let resolved: String? = {
            guard let vault = resolvedVault else { return nil }
            let suffix = vault.hasSuffix("/") ? "goals" : "/goals"
            return vault + suffix
        }()
        guard resolved != rootPath else { return }
        rootPath = resolved
        watcher?.stop()
        watcher = nil
        guard let path = resolved else {
            scanTask?.cancel()
            scanTask = nil
            goals = []
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
                    self.goals = scanResult.entries
                    self.lastError = nil
                case .failure(let error):
                    self.goals = []
                    self.lastError = error.localizedDescription
                }
                self.isScanning = false
            }
        }
    }

    nonisolated private static func scan(root: String) -> Result<ScanResult, Error> {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
            return .success(ScanResult(entries: []))
        }
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        var paths: [String] = []
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
            if paths.count >= maxScanEntries { break }
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
            if values?.isDirectory == true { continue }
            guard values?.isRegularFile == true else { continue }
            let ext = candidate.pathExtension.lowercased()
            guard markdownExtensions.contains(ext) else { continue }
            paths.append(candidate.path)
        }

        var entries: [GoalEntry] = []
        for p in paths {
            if Task.isCancelled { break }
            guard let entry = GoalFrontmatterParser.parse(filePath: p) else { continue }
            entries.append(entry)
        }

        entries.sort { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return .success(ScanResult(entries: entries))
    }

    #if DEBUG
    static func previewStore(
        entries: [GoalEntry],
        rootPath: String? = "/preview/vault/goals",
        isScanning: Bool = false
    ) -> GoalFileListStore {
        let store = GoalFileListStore()
        store.rootPath = rootPath
        store.goals = entries
        store.isScanning = isScanning
        return store
    }
    #endif
}
