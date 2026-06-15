import Combine
import Foundation

@MainActor
final class TaskSearchStore: ObservableObject {
    static let resultLimit = 200

    @Published var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch(debounce: true)
        }
    }

    @Published private(set) var results: [TaskItem] = []
    @Published private(set) var isIndexing: Bool = false
    @Published private(set) var lastError: String?

    private let databaseURLForTasksRoot: (String) -> URL
    private let reconcileDebounce: TimeInterval
    private let searchDebounce: TimeInterval
    private var tasksRootPath: String?
    private var index: TaskSearchIndex?
    private var watcher: VaultRecursiveFileWatcher?
    private var openTask: Task<Void, Never>?
    private var reconcileTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var reconcileWorkItem: DispatchWorkItem?
    private var searchWorkItem: DispatchWorkItem?

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        databaseURLForTasksRoot: @escaping (String) -> URL = { TaskSearchIndex.databaseURL(tasksRootPath: $0) },
        reconcileDebounce: TimeInterval = 0.35,
        searchDebounce: TimeInterval = 0.08
    ) {
        self.databaseURLForTasksRoot = databaseURLForTasksRoot
        self.reconcileDebounce = reconcileDebounce
        self.searchDebounce = searchDebounce
    }

    deinit {
        openTask?.cancel()
        reconcileTask?.cancel()
        searchTask?.cancel()
        reconcileWorkItem?.cancel()
        searchWorkItem?.cancel()
        watcher?.stop()
    }

    func bind(tasksRootPath newRootPath: String?) {
        let trimmed = newRootPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (trimmed?.isEmpty == false) ? trimmed : nil
        guard resolved != tasksRootPath else { return }

        tasksRootPath = resolved
        openTask?.cancel()
        reconcileTask?.cancel()
        searchTask?.cancel()
        reconcileWorkItem?.cancel()
        searchWorkItem?.cancel()
        watcher?.stop()
        watcher = nil
        index = nil
        results = []
        isIndexing = false
        lastError = nil

        guard let root = resolved else { return }
        openIndex(tasksRootPath: root)
    }

    func replace(_ updated: TaskItem) {
        guard let idx = results.firstIndex(where: { $0.absolutePath == updated.absolutePath }) else { return }
        objectWillChange.send()
        var next = results
        next[idx] = updated
        results = next
    }

    private func openIndex(tasksRootPath root: String) {
        openTask = Task { [weak self] in
            do {
                guard let self else { return }
                let databaseURL = self.databaseURLForTasksRoot(root)
                let openedIndex = try await Task.detached(priority: .utility) {
                    try TaskSearchIndex(databaseURL: databaseURL)
                }.value
                guard !Task.isCancelled else { return }
                guard self.tasksRootPath == root else { return }
                self.index = openedIndex
                self.startWatcher(root: root)
                self.scheduleReconcile(debounce: false)
                self.scheduleSearch(debounce: false)
            } catch {
                guard !Task.isCancelled else { return }
                self?.lastError = error.localizedDescription
            }
        }
    }

    private func startWatcher(root: String) {
        let nextWatcher = VaultRecursiveFileWatcher(onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleReconcile(debounce: true)
            }
        })
        nextWatcher.watch(path: root)
        watcher = nextWatcher
    }

    private func scheduleReconcile(debounce: Bool) {
        reconcileWorkItem?.cancel()
        guard let root = tasksRootPath, index != nil else { return }

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.startReconcile(root: root)
            }
        }
        reconcileWorkItem = work

        if debounce {
            DispatchQueue.main.asyncAfter(deadline: .now() + reconcileDebounce, execute: work)
        } else {
            work.perform()
        }
    }

    private func startReconcile(root: String) {
        reconcileTask?.cancel()
        guard let index else { return }

        isIndexing = true
        lastError = nil
        reconcileTask = Task { [weak self] in
            let records = await Task.detached(priority: .utility) {
                TaskSearchScanner.scan(root: root)
            }.value

            guard !Task.isCancelled else { return }

            do {
                try await index.replaceAll(records)
                guard !Task.isCancelled else { return }
                guard let self, self.tasksRootPath == root else { return }
                self.isIndexing = false
                self.lastError = nil
                self.scheduleSearch(debounce: false)
            } catch {
                guard !Task.isCancelled else { return }
                guard let self, self.tasksRootPath == root else { return }
                self.isIndexing = false
                self.lastError = error.localizedDescription
            }
        }
    }

    private func scheduleSearch(debounce: Bool) {
        searchWorkItem?.cancel()
        guard hasQuery else {
            searchTask?.cancel()
            results = []
            return
        }
        guard index != nil else { return }

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.startSearch()
            }
        }
        searchWorkItem = work

        if debounce {
            DispatchQueue.main.asyncAfter(deadline: .now() + searchDebounce, execute: work)
        } else {
            work.perform()
        }
    }

    private func startSearch() {
        searchTask?.cancel()
        guard let index else { return }
        let querySnapshot = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !querySnapshot.isEmpty else {
            results = []
            return
        }

        searchTask = Task { [weak self] in
            do {
                let found = try await index.search(querySnapshot, limit: Self.resultLimit)
                guard !Task.isCancelled else { return }
                guard let self,
                      self.query.trimmingCharacters(in: .whitespacesAndNewlines) == querySnapshot else {
                    return
                }
                self.results = found
                self.lastError = nil
            } catch {
                guard !Task.isCancelled else { return }
                guard let self,
                      self.query.trimmingCharacters(in: .whitespacesAndNewlines) == querySnapshot else {
                    return
                }
                self.lastError = error.localizedDescription
            }
        }
    }
}
