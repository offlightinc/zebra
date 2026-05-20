import Foundation

@MainActor
public final class PersonFileListStore: MarkdownVaultSubdirStore<PersonEntry> {
    public init() {
        super.init(
            subdirName: "people",
            parse: { PersonFrontmatterParser.parse(filePath: $0) },
            sortKey: { $0.slug }
        )
    }

    /// Legacy alias preserved for call sites that read `store.people`.
    public var people: [PersonEntry] { entries }

    #if DEBUG
    public static func previewStore(
        entries: [PersonEntry],
        rootPath: String? = "/preview/vault/people",
        isScanning: Bool = false
    ) -> PersonFileListStore {
        let store = PersonFileListStore()
        store._seedForPreview(entries: entries, rootPath: rootPath, isScanning: isScanning)
        return store
    }
    #endif
}
