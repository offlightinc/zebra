import Combine
import CoreServices
import Foundation

@MainActor
final class VaultIndexStore: ObservableObject {
    @Published private(set) var markdownFiles: [MarkdownFileEntry] = []
    @Published private(set) var goals: [GoalEntry] = []
    @Published private(set) var rootPath: String?
    @Published private(set) var goalsRootPath: String?
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
    private static let maxMarkdownScanEntries: Int = 5000
    private static let maxGoalScanEntries: Int = 1000
    private static let maxScanDuration: TimeInterval = 5.0

    private struct ScanResult: Sendable {
        let markdownFiles: [MarkdownFileEntry]
        let goals: [GoalEntry]
    }

    private var watcher: VaultRecursiveFileWatcher?
    private var scanTask: Task<Void, Never>?
    private var rescanWorkItem: DispatchWorkItem?

    deinit {
        scanTask?.cancel()
        rescanWorkItem?.cancel()
        watcher?.stop()
    }

    func bind(rootPath newRoot: String?) {
        let trimmed = newRoot?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (trimmed?.isEmpty == false) ? trimmed : nil
        guard resolved != rootPath else { return }

        rootPath = resolved
        goalsRootPath = resolved.map { vault in
            vault.hasSuffix("/") ? vault + "goals" : vault + "/goals"
        }
        watcher?.stop()
        watcher = nil

        guard let path = resolved else {
            scanTask?.cancel()
            rescanWorkItem?.cancel()
            scanTask = nil
            rescanWorkItem = nil
            markdownFiles = []
            goals = []
            isScanning = false
            lastError = nil
            return
        }

        let nextWatcher = VaultRecursiveFileWatcher(onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleRescan(debounce: true)
            }
        })
        nextWatcher.watch(path: path)
        watcher = nextWatcher
        scheduleRescan(debounce: false)
    }

    func refresh(reason: String? = nil) {
        _ = reason
        scheduleRescan(debounce: false)
    }

    private func scheduleRescan(debounce: Bool) {
        rescanWorkItem?.cancel()
        guard rootPath != nil else { return }
        if debounce {
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.startScan()
                }
            }
            rescanWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        } else {
            startScan()
        }
    }

    private func startScan() {
        rescanWorkItem?.cancel()
        rescanWorkItem = nil
        scanTask?.cancel()
        guard let path = rootPath else { return }
        isScanning = true
        lastError = nil
        let snapshotRoot = path
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.scan(root: snapshotRoot)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.rootPath == snapshotRoot else { return }
                switch result {
                case .success(let scanResult):
                    self.markdownFiles = scanResult.markdownFiles
                    self.goals = scanResult.goals
                    self.lastError = nil
                case .failure(let error):
                    self.markdownFiles = []
                    self.goals = []
                    self.lastError = error.localizedDescription
                }
                self.isScanning = false
            }
        }
    }

    nonisolated private static func scan(root: String) -> Result<ScanResult, Error> {
        let markdownFiles = scanMarkdown(root: root)
        let goalsRoot = root.hasSuffix("/") ? root + "goals" : root + "/goals"
        let goals = scanGoals(root: goalsRoot)
        return .success(ScanResult(markdownFiles: markdownFiles, goals: goals))
    }

    nonisolated private static func scanMarkdown(root: String) -> [MarkdownFileEntry] {
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
            return []
        }

        let scanStarted = Date()
        while let candidate = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            if entries.count >= maxMarkdownScanEntries { break }
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
            let relativeParent = relativeParent(of: abs, root: root)
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
        return entries
    }

    nonisolated private static func scanGoals(root: String) -> [GoalEntry] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
            return []
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
            return []
        }

        let scanStarted = Date()
        while let candidate = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            if paths.count >= maxGoalScanEntries { break }
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
        return entries
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

final class VaultRecursiveFileWatcher {
    private var stream: FSEventStreamRef?
    private let watchQueue = DispatchQueue(label: "com.cmux.vaultIndexWatcher", qos: .utility)
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func watch(path: String) {
        stop()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, eventCount, _, _, _ in
            guard eventCount > 0, let info else { return }
            let watcher = Unmanaged<VaultRecursiveFileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange()
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer |
                kFSEventStreamCreateFlagWatchRoot
        )
        guard let nextStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(nextStream, watchQueue)
        if FSEventStreamStart(nextStream) {
            stream = nextStream
        } else {
            FSEventStreamInvalidate(nextStream)
            FSEventStreamRelease(nextStream)
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}

@MainActor
final class MarkdownFileListStore: ObservableObject {
    @Published private(set) var mdFiles: [MarkdownFileEntry] = []
    @Published private(set) var rootPath: String?
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastError: String?

    private let indexStore: VaultIndexStore
    private var cancellables: Set<AnyCancellable> = []

    convenience init() {
        self.init(indexStore: VaultIndexStore())
    }

    init(indexStore: VaultIndexStore) {
        self.indexStore = indexStore
        rootPath = indexStore.rootPath
        mdFiles = indexStore.markdownFiles
        isScanning = indexStore.isScanning
        lastError = indexStore.lastError

        indexStore.$rootPath
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.rootPath = $0 }
            .store(in: &cancellables)
        indexStore.$markdownFiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.mdFiles = $0 }
            .store(in: &cancellables)
        indexStore.$isScanning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isScanning = $0 }
            .store(in: &cancellables)
        indexStore.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastError = $0 }
            .store(in: &cancellables)
    }

    func bind(rootPath newRoot: String?) {
        indexStore.bind(rootPath: newRoot)
    }

    func refreshVaultIndex(reason: String? = nil) {
        indexStore.refresh(reason: reason)
    }

    #if DEBUG
    static func previewStore(
        entries: [MarkdownFileEntry],
        rootPath: String? = "/preview/workspace",
        isScanning: Bool = false
    ) -> MarkdownFileListStore {
        let store = MarkdownFileListStore()
        store.rootPath = rootPath
        store.mdFiles = entries
        store.isScanning = isScanning
        return store
    }
    #endif
}
