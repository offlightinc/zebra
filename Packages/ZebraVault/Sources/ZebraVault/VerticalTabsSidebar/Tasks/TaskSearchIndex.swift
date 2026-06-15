import Foundation
import SQLite3

struct TaskSearchRecord: Equatable, Sendable {
    let task: TaskItem
    let filename: String
    let basename: String
    let fileModifiedAt: Date
    let fileSize: Int64

    var absolutePath: String { task.absolutePath }

    init(
        task: TaskItem,
        fileModifiedAt: Date,
        fileSize: Int64
    ) {
        self.task = task
        self.filename = (task.absolutePath as NSString).lastPathComponent
        self.basename = ((filename as NSString).deletingPathExtension)
        self.fileModifiedAt = fileModifiedAt
        self.fileSize = fileSize
    }

    static func fromFile(path: String) -> TaskSearchRecord? {
        guard let task = TaskFrontmatterParser.parse(filePath: path) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modifiedAt = attributes?[.modificationDate] as? Date ?? .distantPast
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return TaskSearchRecord(task: task, fileModifiedAt: modifiedAt, fileSize: size)
    }
}

enum TaskSearchScanner {
    private static let markdownExtensions: Set<String> = ["md", "markdown"]

    static func scan(root: String) -> [TaskSearchRecord] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var records: [TaskSearchRecord] = []
        while let candidate = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
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
            guard markdownExtensions.contains(candidate.pathExtension.lowercased()) else { continue }
            if let record = TaskSearchRecord.fromFile(path: candidate.path) {
                records.append(record)
            }
        }

        records.sort { lhs, rhs in
            let titleOrder = lhs.task.title.localizedCaseInsensitiveCompare(rhs.task.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.absolutePath.localizedCaseInsensitiveCompare(rhs.absolutePath) == .orderedAscending
        }
        return records
    }
}

enum TaskSearchIndexError: LocalizedError {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "SQLite open failed: \(message)"
        case .executeFailed(let message):
            return "SQLite execute failed: \(message)"
        case .prepareFailed(let message):
            return "SQLite prepare failed: \(message)"
        case .bindFailed(let message):
            return "SQLite bind failed: \(message)"
        case .stepFailed(let message):
            return "SQLite step failed: \(message)"
        }
    }
}

actor TaskSearchIndex {
    private static let schemaVersion = 1
    private var database: OpaquePointer?

    init(databaseURL: URL) throws {
        try Self.ensureParentDirectoryExists(for: databaseURL)

        var openedDatabase: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &openedDatabase,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let openedDatabase else {
            let message = Self.sqliteMessage(openedDatabase) ?? "unknown SQLite open failure"
            sqlite3_close(openedDatabase)
            throw TaskSearchIndexError.openFailed(message)
        }

        database = openedDatabase
        sqlite3_extended_result_codes(openedDatabase, 1)
        try Self.configureDatabase(openedDatabase)
    }

    deinit {
        sqlite3_close(database)
    }

    static func databaseURL(tasksRootPath: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("zebra", isDirectory: true)
            .appendingPathComponent("task-search", isDirectory: true)
            .appendingPathComponent("\(stableHashHex(tasksRootPath)).sqlite", isDirectory: false)
    }

    func replaceAll(_ records: [TaskSearchRecord]) throws {
        try transaction {
            try execute("DELETE FROM task_search_records")
            for record in records {
                try upsertRecord(record)
            }
        }
    }

    func upsert(_ record: TaskSearchRecord) throws {
        try upsertRecord(record)
    }

    func upsert(_ records: [TaskSearchRecord]) throws {
        try transaction {
            for record in records {
                try upsertRecord(record)
            }
        }
    }

    func delete(path: String) throws {
        try withStatement("DELETE FROM task_search_records WHERE path = ?1") { statement in
            try bind(path, at: 1, in: statement)
            try stepDone(statement)
        }
    }

    func search(_ rawQuery: String, limit: Int = 200) throws -> [TaskItem] {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }
        guard let matchQuery = Self.matchQuery(for: trimmed) else { return [] }

        let sql = """
            SELECT
                r.path,
                r.title,
                r.status_raw,
                r.unrecognized_status_raw,
                r.priority_raw,
                r.owner_slug,
                r.due_ts,
                r.created_ts,
                r.updated_ts,
                r.goal_slug,
                r.related_projects_json,
                r.tags_json
            FROM task_search_fts
            JOIN task_search_records r ON r.rowid = task_search_fts.rowid
            WHERE task_search_fts MATCH ?1
            ORDER BY bm25(task_search_fts, 0.75, 1.0, 1.0) ASC,
                     r.title COLLATE NOCASE ASC,
                     r.path COLLATE NOCASE ASC
            LIMIT ?2
            """

        return try withStatement(sql) { statement in
            try bind(matchQuery, at: 1, in: statement)
            let limitResult = sqlite3_bind_int64(statement, 2, sqlite3_int64(limit))
            guard limitResult == SQLITE_OK else {
                throw TaskSearchIndexError.bindFailed(
                    Self.sqliteMessage(database) ?? "bind failed with code \(limitResult)"
                )
            }

            var tasks: [TaskItem] = []
            while true {
                let stepResult = sqlite3_step(statement)
                switch stepResult {
                case SQLITE_ROW:
                    if let task = Self.task(from: statement) {
                        tasks.append(task)
                    }
                case SQLITE_DONE:
                    return tasks
                default:
                    throw TaskSearchIndexError.stepFailed(
                        Self.sqliteMessage(database) ?? "step failed with code \(stepResult)"
                    )
                }
            }
        }
    }

    #if DEBUG
    func clearForTesting() throws {
        try execute("DELETE FROM task_search_records")
    }
    #endif

    private func upsertRecord(_ record: TaskSearchRecord) throws {
        let sql = """
            INSERT INTO task_search_records (
                path, filename, basename, title,
                status_raw, unrecognized_status_raw, priority_raw, owner_slug,
                due_ts, created_ts, updated_ts, goal_slug,
                related_projects_json, tags_json, file_mtime, file_size
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
            ON CONFLICT(path) DO UPDATE SET
                filename = excluded.filename,
                basename = excluded.basename,
                title = excluded.title,
                status_raw = excluded.status_raw,
                unrecognized_status_raw = excluded.unrecognized_status_raw,
                priority_raw = excluded.priority_raw,
                owner_slug = excluded.owner_slug,
                due_ts = excluded.due_ts,
                created_ts = excluded.created_ts,
                updated_ts = excluded.updated_ts,
                goal_slug = excluded.goal_slug,
                related_projects_json = excluded.related_projects_json,
                tags_json = excluded.tags_json,
                file_mtime = excluded.file_mtime,
                file_size = excluded.file_size
            """

        try withStatement(sql) { statement in
            try bind(record.absolutePath, at: 1, in: statement)
            try bind(record.filename, at: 2, in: statement)
            try bind(record.basename, at: 3, in: statement)
            try bind(record.task.title, at: 4, in: statement)
            try bind(record.task.status?.rawValue, at: 5, in: statement)
            try bind(record.task.unrecognizedStatusRaw, at: 6, in: statement)
            try bind(record.task.priority?.rawValue, at: 7, in: statement)
            try bind(record.task.ownerSlug, at: 8, in: statement)
            try bind(record.task.dueDate, at: 9, in: statement)
            try bind(record.task.createdDate, at: 10, in: statement)
            try bind(record.task.updatedDate, at: 11, in: statement)
            try bind(record.task.goalSlug, at: 12, in: statement)
            try bind(Self.jsonString(record.task.relatedProjects), at: 13, in: statement)
            try bind(Self.jsonString(record.task.tags), at: 14, in: statement)
            try bind(record.fileModifiedAt.timeIntervalSince1970, at: 15, in: statement)
            let sizeResult = sqlite3_bind_int64(statement, 16, sqlite3_int64(record.fileSize))
            guard sizeResult == SQLITE_OK else {
                throw TaskSearchIndexError.bindFailed(
                    Self.sqliteMessage(database) ?? "bind failed with code \(sizeResult)"
                )
            }
            try stepDone(statement)
        }
    }

    private static func configureDatabase(_ database: OpaquePointer) throws {
        let existingSchemaVersion = try userVersion(database)

        try execute("PRAGMA journal_mode = WAL", database: database)
        try execute("PRAGMA synchronous = NORMAL", database: database)
        try execute("""
            CREATE TABLE IF NOT EXISTS task_search_records (
                rowid INTEGER PRIMARY KEY,
                path TEXT NOT NULL UNIQUE,
                filename TEXT NOT NULL,
                basename TEXT NOT NULL,
                title TEXT NOT NULL DEFAULT '',
                status_raw TEXT,
                unrecognized_status_raw TEXT,
                priority_raw TEXT,
                owner_slug TEXT,
                due_ts REAL,
                created_ts REAL,
                updated_ts REAL,
                goal_slug TEXT,
                related_projects_json TEXT NOT NULL DEFAULT '[]',
                tags_json TEXT NOT NULL DEFAULT '[]',
                file_mtime REAL NOT NULL,
                file_size INTEGER NOT NULL
            )
            """, database: database)
        try execute("CREATE INDEX IF NOT EXISTS task_search_records_path_idx ON task_search_records(path)", database: database)
        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS task_search_fts USING fts5(
                title,
                filename,
                basename,
                content = 'task_search_records',
                content_rowid = 'rowid',
                tokenize = 'unicode61 remove_diacritics 2'
            )
            """, database: database)
        try execute("""
            CREATE TRIGGER IF NOT EXISTS task_search_records_ai AFTER INSERT ON task_search_records BEGIN
                INSERT INTO task_search_fts(rowid, title, filename, basename)
                VALUES (new.rowid, new.title, new.filename, new.basename);
            END
            """, database: database)
        try execute("""
            CREATE TRIGGER IF NOT EXISTS task_search_records_ad AFTER DELETE ON task_search_records BEGIN
                INSERT INTO task_search_fts(task_search_fts, rowid, title, filename, basename)
                VALUES('delete', old.rowid, old.title, old.filename, old.basename);
            END
            """, database: database)
        try execute("""
            CREATE TRIGGER IF NOT EXISTS task_search_records_au AFTER UPDATE ON task_search_records BEGIN
                INSERT INTO task_search_fts(task_search_fts, rowid, title, filename, basename)
                VALUES('delete', old.rowid, old.title, old.filename, old.basename);
                INSERT INTO task_search_fts(rowid, title, filename, basename)
                VALUES (new.rowid, new.title, new.filename, new.basename);
            END
            """, database: database)

        if existingSchemaVersion < Self.schemaVersion {
            try execute("INSERT INTO task_search_fts(task_search_fts) VALUES('rebuild')", database: database)
            try execute("PRAGMA user_version = \(Self.schemaVersion)", database: database)
        }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard let database else {
            throw TaskSearchIndexError.executeFailed("database is closed")
        }
        try Self.execute(sql, database: database)
    }

    private static func execute(_ sql: String, database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) }
                ?? Self.sqliteMessage(database)
                ?? "execute failed with code \(result)"
            sqlite3_free(errorMessage)
            throw TaskSearchIndexError.executeFailed(message)
        }
    }

    private static func userVersion(_ database: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw TaskSearchIndexError.prepareFailed(
                sqliteMessage(database) ?? "prepare failed with code \(prepareResult)"
            )
        }
        defer { sqlite3_finalize(statement) }

        let stepResult = sqlite3_step(statement)
        switch stepResult {
        case SQLITE_ROW:
            return Int(sqlite3_column_int(statement, 0))
        case SQLITE_DONE:
            return 0
        default:
            throw TaskSearchIndexError.stepFailed(sqliteMessage(database) ?? "step failed with code \(stepResult)")
        }
    }

    private func withStatement<T>(
        _ sql: String,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        guard let database else {
            throw TaskSearchIndexError.prepareFailed("database is closed")
        }

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw TaskSearchIndexError.prepareFailed(
                Self.sqliteMessage(database) ?? "prepare failed with code \(prepareResult)"
            )
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer) throws {
        let result = sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
        guard result == SQLITE_OK else {
            throw TaskSearchIndexError.bindFailed(Self.sqliteMessage(database) ?? "bind failed with code \(result)")
        }
    }

    private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer) throws {
        guard let value else {
            try bindNull(at: index, in: statement)
            return
        }
        try bind(value, at: index, in: statement)
    }

    private func bind(_ value: Double, at index: Int32, in statement: OpaquePointer) throws {
        let result = sqlite3_bind_double(statement, index, value)
        guard result == SQLITE_OK else {
            throw TaskSearchIndexError.bindFailed(Self.sqliteMessage(database) ?? "bind failed with code \(result)")
        }
    }

    private func bind(_ value: Date?, at index: Int32, in statement: OpaquePointer) throws {
        guard let value else {
            try bindNull(at: index, in: statement)
            return
        }
        try bind(value.timeIntervalSince1970, at: index, in: statement)
    }

    private func bindNull(at index: Int32, in statement: OpaquePointer) throws {
        let result = sqlite3_bind_null(statement, index)
        guard result == SQLITE_OK else {
            throw TaskSearchIndexError.bindFailed(Self.sqliteMessage(database) ?? "bind failed with code \(result)")
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw TaskSearchIndexError.stepFailed(Self.sqliteMessage(database) ?? "step failed with code \(result)")
        }
    }

    private static func task(from statement: OpaquePointer) -> TaskItem? {
        guard let path = sqliteText(statement, 0) else { return nil }
        let title = sqliteText(statement, 1) ?? (path as NSString).lastPathComponent
        let status = sqliteText(statement, 2).flatMap(BrainTaskStatus.init(rawValue:))
        let unrecognizedStatusRaw = sqliteText(statement, 3)
        let priority = sqliteText(statement, 4).flatMap(BrainPriority.init(rawValue:))
        let ownerSlug = sqliteText(statement, 5)
        let dueDate = sqliteDate(statement, 6)
        let createdDate = sqliteDate(statement, 7)
        let updatedDate = sqliteDate(statement, 8)
        let goalSlug = sqliteText(statement, 9)
        let relatedProjects = stringArray(fromJSON: sqliteText(statement, 10))
        let tags = stringArray(fromJSON: sqliteText(statement, 11))

        return TaskItem(
            absolutePath: path,
            displayName: title,
            title: title,
            status: status,
            unrecognizedStatusRaw: unrecognizedStatusRaw,
            priority: priority,
            ownerSlug: ownerSlug,
            dueDate: dueDate,
            createdDate: createdDate,
            updatedDate: updatedDate,
            goalSlug: goalSlug,
            relatedProjects: relatedProjects,
            tags: tags
        )
    }

    static func queryTokens(for rawQuery: String) -> [String] {
        rawQuery
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
    }

    private static func matchQuery(for rawQuery: String) -> String? {
        let tokens = queryTokens(for: rawQuery)
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\($0)*" }.joined(separator: " AND ")
    }

    private static func ensureParentDirectoryExists(for databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private static func jsonString(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    private static func stringArray(fromJSON text: String?) -> [String] {
        guard let text,
              let data = text.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }

    private static func sqliteDate(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private static func sqliteText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private static func sqliteMessage(_ database: OpaquePointer?) -> String? {
        guard let database, let cString = sqlite3_errmsg(database) else { return nil }
        return String(cString: cString)
    }

    private static func stableHashHex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let raw = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - raw.count)) + raw
    }

    private static let sqliteTransient = unsafeBitCast(
        OpaquePointer(bitPattern: -1),
        to: sqlite3_destructor_type.self
    )
}
