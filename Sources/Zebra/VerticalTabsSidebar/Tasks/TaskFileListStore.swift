import Foundation

@MainActor
final class TaskFileListStore: MarkdownVaultSubdirStore<TaskItem> {
    init() {
        super.init(
            subdirName: "tasks",
            parse: { TaskFrontmatterParser.parse(filePath: $0) },
            sortKey: { $0.displayName }
        )
    }

    /// Legacy alias preserved for call sites that read `store.tasks`.
    var tasks: [TaskItem] { entries }

    #if DEBUG
    static func previewStore(
        entries: [TaskItem],
        rootPath: String? = "/preview/vault/tasks",
        isScanning: Bool = false
    ) -> TaskFileListStore {
        let store = TaskFileListStore()
        store._seedForPreview(entries: entries, rootPath: rootPath, isScanning: isScanning)
        return store
    }
    #endif
}
