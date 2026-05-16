import Foundation

@MainActor
final class GoalFileListStore: MarkdownVaultSubdirStore<GoalEntry> {
    init() {
        super.init(
            subdirName: "goals",
            parse: { GoalFrontmatterParser.parse(filePath: $0) },
            sortKey: { $0.displayName }
        )
    }

    /// Legacy alias preserved for call sites that read `store.goals`.
    var goals: [GoalEntry] { entries }

    #if DEBUG
    static func previewStore(
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
