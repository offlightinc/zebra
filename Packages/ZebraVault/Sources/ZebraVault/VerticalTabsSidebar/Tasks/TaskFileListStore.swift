import Foundation

@MainActor
public final class TaskFileListStore: MarkdownVaultSubdirStore<TaskItem> {
    public init() {
        super.init(
            subdirName: "tasks",
            parse: { TaskFrontmatterParser.parse(filePath: $0) },
            sortKey: { $0.displayName }
        )
    }

    /// Legacy alias preserved for call sites that read `store.tasks`.
    public var tasks: [TaskItem] { entries }

    #if DEBUG
    public static func previewStore(
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
