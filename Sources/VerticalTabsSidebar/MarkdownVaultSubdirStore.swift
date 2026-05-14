import Combine
import Foundation

/// Identity contract for entries managed by `MarkdownVaultSubdirStore`.
/// `absolutePath` is the keying field for optimistic `replace(_:)`.
protocol VaultSubdirEntry: Identifiable, Hashable, Sendable {
    var absolutePath: String { get }
}

/// Generic store for a single vault subdirectory of typed markdown entries
/// (e.g. `<vault>/goals/`, `<vault>/tasks/`, `<vault>/people/`).
///
/// Lifecycle: `bind(vaultRoot:)` resolves `<vault>/<subdir>/` and starts a
/// recursive directory watcher; file changes trigger a debounced background
/// rescan that parses every `.md` file head and rebuilds the `entries` array on
/// the main actor.
///
/// Subclasses are expected to be thin wrappers that pin `Entry`, `subdirName`,
/// `parse`, and `sortKey`, and expose a domain-named alias property
/// (`goals`, `tasks`, `people`).
private let markdownExtensions: Set<String> = ["md", "markdown"]
private let maxScanEntries: Int = 1000
private let maxScanDuration: TimeInterval = 5.0

@MainActor
class MarkdownVaultSubdirStore<Entry: VaultSubdirEntry>: ObservableObject {
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var rootPath: String?
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastError: String?

    private let subdirName: String
    private let parse: @Sendable (String) -> Entry?
    private let sortKey: @Sendable (Entry) -> String

    private var watcher: VaultRecursiveFileWatcher?
    private var scanTask: Task<Void, Never>?
    private var rescanWorkItem: DispatchWorkItem?

    init(
        subdirName: String,
        parse: @escaping @Sendable (String) -> Entry?,
        sortKey: @escaping @Sendable (Entry) -> String
    ) {
        self.subdirName = subdirName
        self.parse = parse
        self.sortKey = sortKey
    }

    deinit {
        scanTask?.cancel()
        rescanWorkItem?.cancel()
        watcher?.stop()
    }

    /// Optimistic in-place replacement keyed by `absolutePath`.
    ///
    /// Whole-array reassignment + explicit `objectWillChange` is required:
    /// in-place subscript mutation (`entries[idx] = updated`) on a `@Published`
    /// array does not reliably invalidate `ObservedObject` subscribers when the
    /// body reads through a computed property (see TaskListView).
    func replace(_ updated: Entry) {
        guard let idx = entries.firstIndex(where: { $0.absolutePath == updated.absolutePath }) else { return }
        objectWillChange.send()
        var next = entries
        next[idx] = updated
        entries = next
    }

    /// Binds to `<vault>/<subdirName>/` derived from a vault root path.
    /// Pass `nil` to clear.
    func bind(vaultRoot: String?) {
        let trimmed = vaultRoot?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedVault = (trimmed?.isEmpty == false) ? trimmed : nil
        let resolved: String? = {
            guard let vault = resolvedVault else { return nil }
            let suffix = vault.hasSuffix("/") ? subdirName : "/" + subdirName
            return vault + suffix
        }()
        guard resolved != rootPath else { return }
        rootPath = resolved
        watcher?.stop()
        watcher = nil
        guard let path = resolved else {
            scanTask?.cancel()
            rescanWorkItem?.cancel()
            scanTask = nil
            rescanWorkItem = nil
            entries = []
            isScanning = false
            lastError = nil
            return
        }
        let nextWatcher = VaultRecursiveFileWatcher(onChange: { [weak self] in
            Task { @MainActor in self?.scheduleRescan(debounce: true) }
        })
        nextWatcher.watch(path: path)
        watcher = nextWatcher
        scheduleRescan(debounce: false)
    }

    private func scheduleRescan(debounce: Bool) {
        rescanWorkItem?.cancel()
        scanTask?.cancel()
        guard let path = rootPath else { return }
        if debounce {
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.startScan(root: path)
                }
            }
            rescanWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            return
        }
        startScan(root: path)
    }

    private func startScan(root path: String) {
        rescanWorkItem?.cancel()
        rescanWorkItem = nil
        scanTask?.cancel()
        isScanning = true
        lastError = nil
        let snapshotRoot = path
        let parse = self.parse
        let sortKey = self.sortKey
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.scan(root: snapshotRoot, parse: parse, sortKey: sortKey)
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                guard self.rootPath == snapshotRoot else { return }
                switch result {
                case .success(let scanned):
                    self.entries = scanned
                    self.lastError = nil
                case .failure(let error):
                    self.entries = []
                    self.lastError = error.localizedDescription
                }
                self.isScanning = false
            }
        }
    }

    nonisolated static func scan(
        root: String,
        parse: @Sendable (String) -> Entry?,
        sortKey: @Sendable (Entry) -> String
    ) -> Result<[Entry], Error> {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
            return .success([])
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
            return .success([])
        }

        let scanStarted = Date()
        while let candidate = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            if paths.count >= maxScanEntries { break }
            if Date().timeIntervalSince(scanStarted) > maxScanDuration { break }
            let name = candidate.lastPathComponent
            if name.hasPrefix(".") {
                let values = try? candidate.resourceValues(forKeys: Set(resourceKeys))
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            let values = try? candidate.resourceValues(forKeys: Set(resourceKeys))
            if values?.isDirectory == true { continue }
            guard values?.isRegularFile == true else { continue }
            let ext = candidate.pathExtension.lowercased()
            guard markdownExtensions.contains(ext) else { continue }
            paths.append(candidate.path)
        }

        var collected: [Entry] = []
        for p in paths {
            if Task.isCancelled { break }
            guard let entry = parse(p) else { continue }
            collected.append(entry)
        }

        collected.sort { lhs, rhs in
            sortKey(lhs).localizedCaseInsensitiveCompare(sortKey(rhs)) == .orderedAscending
        }
        return .success(collected)
    }

    #if DEBUG
    /// Subclass-only hook to seed preview state. Public visibility is
    /// limited to file/module — see subclasses' typed `previewStore` factories.
    func _seedForPreview(entries: [Entry], rootPath: String?, isScanning: Bool) {
        self.entries = entries
        self.rootPath = rootPath
        self.isScanning = isScanning
    }
    #endif
}
