import Foundation

@MainActor
public final class GoalFileListStore: MarkdownVaultSubdirStore<GoalEntry> {
    public init() {
        super.init(
            subdirName: "goals",
            parse: { GoalFrontmatterParser.parse(filePath: $0) },
            sortKey: { $0.displayName }
        )
    }

    /// Legacy alias preserved for call sites that read `store.goals`.
    public var goals: [GoalEntry] { entries }

    #if DEBUG
    public static func previewStore(
        entries: [GoalEntry],
        rootPath: String? = "/preview/vault/goals",
        isScanning: Bool = false
    ) -> GoalFileListStore {
        let store = GoalFileListStore()
        store._seedForPreview(entries: entries, rootPath: rootPath, isScanning: isScanning)
        return store
    }
    #endif
}
