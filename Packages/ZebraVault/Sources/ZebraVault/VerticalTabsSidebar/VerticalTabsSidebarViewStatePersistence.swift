import Foundation

enum VerticalTabsSidebarViewStatePersistence {
    private static let taskStateKeyPrefix = "verticalTabsSidebar.tasks.viewState"
    private static let documentStateKeyPrefix = "verticalTabsSidebar.documents.viewState"

    struct TaskState: Codable, Equatable {
        var groupBy: String
        var filters: [TaskFilterState]
        var collapsedSections: [String]

        static let empty = TaskState(
            groupBy: TaskGroupBy.status.rawValue,
            filters: [],
            collapsedSections: []
        )
    }

    struct TaskFilterState: Codable, Equatable {
        var field: String
        var op: String
        var values: [String]
    }

    struct DocumentState: Codable, Equatable {
        var collapsedFolders: [String]

        static let empty = DocumentState(collapsedFolders: [])
    }

    static func loadTaskState(rootPath: String?, defaults: UserDefaults = .standard) -> TaskState {
        load(TaskState.self, keyPrefix: taskStateKeyPrefix, rootPath: rootPath, defaults: defaults) ?? .empty
    }

    static func saveTaskState(_ state: TaskState, rootPath: String?, defaults: UserDefaults = .standard) {
        save(state, keyPrefix: taskStateKeyPrefix, rootPath: rootPath, defaults: defaults)
    }

    static func loadDocumentState(rootPath: String?, defaults: UserDefaults = .standard) -> DocumentState {
        load(DocumentState.self, keyPrefix: documentStateKeyPrefix, rootPath: rootPath, defaults: defaults) ?? .empty
    }

    static func saveDocumentState(_ state: DocumentState, rootPath: String?, defaults: UserDefaults = .standard) {
        save(state, keyPrefix: documentStateKeyPrefix, rootPath: rootPath, defaults: defaults)
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        keyPrefix: String,
        rootPath: String?,
        defaults: UserDefaults
    ) -> T? {
        guard let key = storageKey(prefix: keyPrefix, rootPath: rootPath),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(
        _ value: T,
        keyPrefix: String,
        rootPath: String?,
        defaults: UserDefaults
    ) {
        guard let key = storageKey(prefix: keyPrefix, rootPath: rootPath),
              let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func storageKey(prefix: String, rootPath: String?) -> String? {
        guard let rootPath else { return nil }
        let trimmed = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let standardized = URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL.path
        let encoded = Data(standardized.utf8).base64EncodedString()
        return "\(prefix).\(encoded)"
    }

}

extension VerticalTabsSidebarViewStatePersistence.TaskState {
    init(
        groupBy: TaskGroupBy,
        filters: [TaskFilter],
        collapsedSections: Set<String>
    ) {
        self.groupBy = groupBy.rawValue
        self.filters = filters.map(VerticalTabsSidebarViewStatePersistence.TaskFilterState.init(filter:))
        self.collapsedSections = collapsedSections.sorted()
    }

    var resolvedGroupBy: TaskGroupBy {
        TaskGroupBy(rawValue: groupBy) ?? .status
    }

    var resolvedFilters: [TaskFilter] {
        filters.compactMap(\.resolvedFilter)
    }
}

extension VerticalTabsSidebarViewStatePersistence.TaskFilterState {
    init(filter: TaskFilter) {
        field = filter.field.rawValue
        op = filter.op.persistenceRawValue
        values = filter.values
    }

    var resolvedFilter: TaskFilter? {
        // Strict parse: unknown field/op → drop the filter rather than silently
        // coerce to a default. Coercing isNot/is would invert filtering results
        // when storage holds a future or corrupted op value.
        guard let field = TaskFilterField(rawValue: field),
              let op = TaskFilterOp(persistenceRawValue: op) else { return nil }
        return TaskFilter(
            field: field,
            op: op,
            values: values
        )
    }
}

extension TaskFilterOp {
    fileprivate var persistenceRawValue: String {
        self == .is ? "is" : "isNot"
    }

    fileprivate init?(persistenceRawValue: String) {
        switch persistenceRawValue {
        case "is":    self = .is
        case "isNot": self = .isNot
        default:      return nil
        }
    }
}
