import EventKit
import Foundation

enum ZebraRemindersAuthorizationStatus: String, Codable, Equatable, Sendable {
    case notDetermined
    case requesting
    case authorized
    case denied
    case restricted
    case unavailable
    case failed
}

enum ZebraRemindersOperation: String, Codable, Equatable, Sendable {
    case authorizationStatus = "authorization-status"
    case requestAuthorization = "request-authorization"
    case smokeRead = "smoke-read"
    case scopeRead = "scope-read"
}

enum ZebraRemindersReceiptState: String, Codable, Equatable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case cancelled
}

enum ZebraRemindersExecutionOwner: String, Codable, Equatable, Sendable {
    case zebraApp = "zebra-app"
}

enum ZebraRemindersScopeKind: String, Codable, Equatable, Sendable {
    case allOpen = "all-open"
    case oneList = "one-list"
    case today
    case week
    case custom
    case skip
}

enum ZebraRemindersCompletionFilter: String, Codable, Equatable, Sendable {
    case open
    case completed
    case all
}

enum ZebraRemindersDueWindow: String, Codable, Equatable, Sendable {
    case overdue
    case today
    case week
    case all
}

struct ZebraRemindersScope: Codable, Equatable, Sendable {
    var kind: ZebraRemindersScopeKind
    var listTitles: [String]
    var status: ZebraRemindersCompletionFilter
    var dueWindow: ZebraRemindersDueWindow
    var itemCap: Int?

    static let allOpen = Self(
        kind: .allOpen,
        listTitles: [],
        status: .open,
        dueWindow: .all,
        itemCap: nil
    )
    static let today = Self(
        kind: .today,
        listTitles: [],
        status: .open,
        dueWindow: .today,
        itemCap: nil
    )
    static let week = Self(
        kind: .week,
        listTitles: [],
        status: .open,
        dueWindow: .week,
        itemCap: nil
    )
    static let skip = Self(
        kind: .skip,
        listTitles: [],
        status: .all,
        dueWindow: .all,
        itemCap: nil
    )

    static func oneList(_ title: String) -> Self {
        Self(
            kind: .oneList,
            listTitles: [title],
            status: .open,
            dueWindow: .all,
            itemCap: nil
        )
    }

    static func custom(
        listTitles: [String],
        status: ZebraRemindersCompletionFilter,
        dueWindow: ZebraRemindersDueWindow,
        itemCap: Int?
    ) -> Self {
        Self(
            kind: .custom,
            listTitles: listTitles,
            status: status,
            dueWindow: dueWindow,
            itemCap: itemCap
        )
    }
}

struct ZebraRemindersListSnapshot: Codable, Equatable, Sendable {
    var id: String
    var title: String
}

struct ZebraReminderSnapshot: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var notes: String?
    var listID: String
    var listTitle: String
    var isCompleted: Bool
    var priority: Int
    var dueDate: Date?
}

struct ZebraRemindersStoreSnapshot: Codable, Equatable, Sendable {
    var lists: [ZebraRemindersListSnapshot]
    var reminders: [ZebraReminderSnapshot]
}

struct ZebraRemindersRequest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var requestID: String
    var sourceID: String
    var sourceRunID: String
    var operation: ZebraRemindersOperation
    var scope: ZebraRemindersScope?
    var createdAt: Date

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        requestID: String,
        sourceID: String = "apple-reminders",
        sourceRunID: String,
        operation: ZebraRemindersOperation,
        scope: ZebraRemindersScope? = nil,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.sourceID = sourceID
        self.sourceRunID = sourceRunID
        self.operation = operation
        self.scope = scope
        self.createdAt = createdAt
    }
}

struct ZebraRemindersResult: Codable, Equatable, Sendable {
    var listCount: Int
    var openReminderCount: Int
    var listTitles: [String]
    var supportedFields: [String]
    var reminders: [ZebraReminderSnapshot]?
}

struct ZebraRemindersReceipt: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var requestID: String
    var sourceRunID: String
    var operation: ZebraRemindersOperation
    var state: ZebraRemindersReceiptState
    var executionOwner: ZebraRemindersExecutionOwner
    var authorizationStatus: ZebraRemindersAuthorizationStatus
    var result: ZebraRemindersResult?
    var failureReason: String?
    var retryable: Bool
    var createdAt: Date
    var startedAt: Date
    var completedAt: Date?
}

@MainActor
protocol ZebraRemindersEventStore: AnyObject {
    func authorizationStatus() -> ZebraRemindersAuthorizationStatus
    func requestAuthorization() async throws -> ZebraRemindersAuthorizationStatus
    func fetchSnapshot() async throws -> ZebraRemindersStoreSnapshot
}

@MainActor
final class ZebraRemindersRequestProcessor {
    private let eventStore: any ZebraRemindersEventStore
    private var calendar: Calendar
    private let now: () -> Date

    init(
        eventStore: any ZebraRemindersEventStore,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.eventStore = eventStore
        self.calendar = calendar
        self.now = now
    }

    func process(_ request: ZebraRemindersRequest) async -> ZebraRemindersReceipt {
        let startedAt = now()
        guard request.schemaVersion == ZebraRemindersRequest.currentSchemaVersion,
              request.sourceID == "apple-reminders" else {
            return failureReceipt(
                request,
                status: .failed,
                authorizationStatus: .failed,
                reason: "reminders_request_invalid",
                retryable: false,
                startedAt: startedAt
            )
        }

        switch request.operation {
        case .authorizationStatus:
            return successReceipt(
                request,
                authorizationStatus: eventStore.authorizationStatus(),
                result: nil,
                startedAt: startedAt
            )
        case .requestAuthorization:
            do {
                let current = eventStore.authorizationStatus()
                let resolved = current == .notDetermined
                    ? try await eventStore.requestAuthorization()
                    : current
                if resolved == .authorized {
                    return successReceipt(
                        request,
                        authorizationStatus: resolved,
                        result: nil,
                        startedAt: startedAt
                    )
                }
                return permissionFailureReceipt(request, status: resolved, startedAt: startedAt)
            } catch is CancellationError {
                return failureReceipt(
                    request,
                    status: .cancelled,
                    authorizationStatus: eventStore.authorizationStatus(),
                    reason: "reminders_request_cancelled",
                    retryable: true,
                    startedAt: startedAt
                )
            } catch {
                return failureReceipt(
                    request,
                    status: .failed,
                    authorizationStatus: .failed,
                    reason: "reminders_permission_request_failed",
                    retryable: true,
                    startedAt: startedAt
                )
            }
        case .smokeRead:
            return await readReceipt(request, scope: nil, startedAt: startedAt)
        case .scopeRead:
            guard let scope = request.scope else {
                return failureReceipt(
                    request,
                    status: .failed,
                    authorizationStatus: eventStore.authorizationStatus(),
                    reason: "reminders_scope_invalid",
                    retryable: false,
                    startedAt: startedAt
                )
            }
            if scope.kind == .skip {
                return successReceipt(
                    request,
                    authorizationStatus: eventStore.authorizationStatus(),
                    result: ZebraRemindersResult(
                        listCount: 0,
                        openReminderCount: 0,
                        listTitles: [],
                        supportedFields: supportedFields,
                        reminders: []
                    ),
                    startedAt: startedAt
                )
            }
            return await readReceipt(request, scope: scope, startedAt: startedAt)
        }
    }

    private func readReceipt(
        _ request: ZebraRemindersRequest,
        scope: ZebraRemindersScope?,
        startedAt: Date
    ) async -> ZebraRemindersReceipt {
        let status = eventStore.authorizationStatus()
        guard status == .authorized else {
            return permissionFailureReceipt(request, status: status, startedAt: startedAt)
        }
        do {
            let snapshot = try await eventStore.fetchSnapshot()
            let openCount = snapshot.reminders.filter { !$0.isCompleted }.count
            let reminders = scope.map { filtered(snapshot.reminders, for: $0) }
            return successReceipt(
                request,
                authorizationStatus: .authorized,
                result: ZebraRemindersResult(
                    listCount: snapshot.lists.count,
                    openReminderCount: openCount,
                    listTitles: Array(snapshot.lists.map(\.title).prefix(20)),
                    supportedFields: supportedFields,
                    reminders: reminders
                ),
                startedAt: startedAt
            )
        } catch is CancellationError {
            return failureReceipt(
                request,
                status: .cancelled,
                authorizationStatus: .authorized,
                reason: "reminders_request_cancelled",
                retryable: true,
                startedAt: startedAt
            )
        } catch {
            return failureReceipt(
                request,
                status: .failed,
                authorizationStatus: .authorized,
                reason: "reminders_fetch_failed",
                retryable: true,
                startedAt: startedAt
            )
        }
    }

    private var supportedFields: [String] {
        ["id", "title", "notes", "listID", "listTitle", "isCompleted", "priority", "dueDate"]
    }

    private func filtered(
        _ reminders: [ZebraReminderSnapshot],
        for scope: ZebraRemindersScope
    ) -> [ZebraReminderSnapshot] {
        var result = reminders
        switch scope.kind {
        case .allOpen:
            result = result.filter { !$0.isCompleted }
        case .oneList:
            let names = Set(scope.listTitles)
            result = result.filter { !$0.isCompleted && names.contains($0.listTitle) }
        case .today:
            result = result.filter { reminder in
                !reminder.isCompleted && reminder.dueDate.map { calendar.isDate($0, inSameDayAs: now()) } == true
            }
        case .week:
            let start = calendar.startOfDay(for: now())
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            result = result.filter { reminder in
                guard !reminder.isCompleted, let due = reminder.dueDate else { return false }
                return due >= start && due < end
            }
        case .custom:
            if !scope.listTitles.isEmpty {
                let names = Set(scope.listTitles)
                result = result.filter { names.contains($0.listTitle) }
            }
            switch scope.status {
            case .open: result = result.filter { !$0.isCompleted }
            case .completed: result = result.filter(\.isCompleted)
            case .all: break
            }
            result = result.filter { matchesDueWindow($0.dueDate, scope.dueWindow) }
        case .skip:
            result = []
        }
        if let cap = scope.itemCap, cap >= 0 {
            result = Array(result.prefix(cap))
        }
        return result
    }

    private func matchesDueWindow(_ dueDate: Date?, _ window: ZebraRemindersDueWindow) -> Bool {
        switch window {
        case .all:
            return true
        case .overdue:
            guard let dueDate else { return false }
            return dueDate < calendar.startOfDay(for: now())
        case .today:
            guard let dueDate else { return false }
            return calendar.isDate(dueDate, inSameDayAs: now())
        case .week:
            guard let dueDate else { return false }
            let start = calendar.startOfDay(for: now())
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return dueDate >= start && dueDate < end
        }
    }

    private func permissionFailureReceipt(
        _ request: ZebraRemindersRequest,
        status: ZebraRemindersAuthorizationStatus,
        startedAt: Date
    ) -> ZebraRemindersReceipt {
        let reason: String
        let retryable: Bool
        switch status {
        case .notDetermined, .requesting:
            reason = "reminders_permission_consent_required"
            retryable = true
        case .denied:
            reason = "reminders_permission_denied"
            retryable = true
        case .restricted:
            reason = "reminders_permission_restricted"
            retryable = false
        case .unavailable:
            reason = "reminders_permission_unavailable"
            retryable = false
        case .failed:
            reason = "reminders_permission_request_failed"
            retryable = true
        case .authorized:
            reason = "reminders_permission_unknown"
            retryable = true
        }
        return failureReceipt(
            request,
            status: .failed,
            authorizationStatus: status,
            reason: reason,
            retryable: retryable,
            startedAt: startedAt
        )
    }

    private func successReceipt(
        _ request: ZebraRemindersRequest,
        authorizationStatus: ZebraRemindersAuthorizationStatus,
        result: ZebraRemindersResult?,
        startedAt: Date
    ) -> ZebraRemindersReceipt {
        ZebraRemindersReceipt(
            schemaVersion: ZebraRemindersReceipt.currentSchemaVersion,
            requestID: request.requestID,
            sourceRunID: request.sourceRunID,
            operation: request.operation,
            state: .succeeded,
            executionOwner: .zebraApp,
            authorizationStatus: authorizationStatus,
            result: result,
            failureReason: nil,
            retryable: false,
            createdAt: request.createdAt,
            startedAt: startedAt,
            completedAt: now()
        )
    }

    private func failureReceipt(
        _ request: ZebraRemindersRequest,
        status: ZebraRemindersReceiptState,
        authorizationStatus: ZebraRemindersAuthorizationStatus,
        reason: String,
        retryable: Bool,
        startedAt: Date
    ) -> ZebraRemindersReceipt {
        ZebraRemindersReceipt(
            schemaVersion: ZebraRemindersReceipt.currentSchemaVersion,
            requestID: request.requestID,
            sourceRunID: request.sourceRunID,
            operation: request.operation,
            state: status,
            executionOwner: .zebraApp,
            authorizationStatus: authorizationStatus,
            result: nil,
            failureReason: reason,
            retryable: retryable,
            createdAt: request.createdAt,
            startedAt: startedAt,
            completedAt: now()
        )
    }
}

enum ZebraRemindersRequestStoreError: Error {
    case invalidRequestID
    case invalidSchema
}

final class ZebraRemindersRequestFileStore: @unchecked Sendable {
    static func defaultDirectoryURL(homeDirectoryPath: String = NSHomeDirectory()) -> URL {
        ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: homeDirectoryPath)
            .deletingLastPathComponent()
            .appendingPathComponent("reminders-eventkit", isDirectory: true)
    }

    let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder.dateDecodingStrategy = .iso8601
    }

    var requestsDirectoryURL: URL {
        directoryURL.appendingPathComponent("requests", isDirectory: true)
    }

    var receiptsDirectoryURL: URL {
        directoryURL.appendingPathComponent("receipts", isDirectory: true)
    }

    func prepareDirectories() throws {
        for url in [directoryURL, requestsDirectoryURL, receiptsDirectoryURL] {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }

    func requestURL(requestID: String) -> URL {
        requestsDirectoryURL.appendingPathComponent(requestID + ".json", isDirectory: false)
    }

    func receiptURL(requestID: String) -> URL {
        receiptsDirectoryURL.appendingPathComponent(requestID + ".json", isDirectory: false)
    }

    func writeRequest(_ request: ZebraRemindersRequest) throws {
        try validate(request.requestID)
        try prepareDirectories()
        try writePrivate(encoder.encode(request), to: requestURL(requestID: request.requestID))
    }

    func pendingRequests() throws -> [ZebraRemindersRequest] {
        try prepareDirectories()
        return try fileManager.contentsOfDirectory(
            at: requestsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let request = try? decoder.decode(ZebraRemindersRequest.self, from: data),
                  request.schemaVersion == ZebraRemindersRequest.currentSchemaVersion,
                  (try? validate(request.requestID)) != nil else { return nil }
            return request
        }
    }

    func writeReceipt(_ receipt: ZebraRemindersReceipt) throws {
        try validate(receipt.requestID)
        try prepareDirectories()
        try writePrivate(encoder.encode(receipt), to: receiptURL(requestID: receipt.requestID))
    }

    func readReceipt(requestID: String) -> ZebraRemindersReceipt? {
        guard (try? validate(requestID)) != nil,
              let data = try? Data(contentsOf: receiptURL(requestID: requestID)) else { return nil }
        return try? decoder.decode(ZebraRemindersReceipt.self, from: data)
    }

    private func validate(_ requestID: String) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !requestID.isEmpty,
              requestID.count <= 128,
              requestID.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ZebraRemindersRequestStoreError.invalidRequestID
        }
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

@MainActor
public final class ZebraRemindersRequestBroker {
    private let fileStore: ZebraRemindersRequestFileStore
    private let processor: ZebraRemindersRequestProcessor
    private var timer: Timer?
    private var isProcessing = false

    init(
        fileStore: ZebraRemindersRequestFileStore,
        processor: ZebraRemindersRequestProcessor
    ) {
        self.fileStore = fileStore
        self.processor = processor
    }

    public static func live(
        directoryURL: URL? = nil
    ) -> ZebraRemindersRequestBroker {
        let fileStore = ZebraRemindersRequestFileStore(
            directoryURL: directoryURL ?? ZebraRemindersRequestFileStore.defaultDirectoryURL()
        )
        return ZebraRemindersRequestBroker(
            fileStore: fileStore,
            processor: ZebraRemindersRequestProcessor(eventStore: ZebraSystemRemindersEventStore())
        )
    }

    public func start() {
        guard timer == nil else { return }
        try? fileStore.prepareDirectories()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await self?.processPendingRequestsOnce()
            }
        }
        Task { try? await processPendingRequestsOnce() }
    }

    func processPendingRequestsOnce() async throws {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        for request in try fileStore.pendingRequests() {
            if let receipt = fileStore.readReceipt(requestID: request.requestID),
               [.succeeded, .failed, .cancelled].contains(receipt.state) {
                continue
            }
            let startedAt = Date()
            try fileStore.writeReceipt(ZebraRemindersReceipt(
                schemaVersion: ZebraRemindersReceipt.currentSchemaVersion,
                requestID: request.requestID,
                sourceRunID: request.sourceRunID,
                operation: request.operation,
                state: .running,
                executionOwner: .zebraApp,
                authorizationStatus: .requesting,
                result: nil,
                failureReason: nil,
                retryable: true,
                createdAt: request.createdAt,
                startedAt: startedAt,
                completedAt: nil
            ))
            try fileStore.writeReceipt(await processor.process(request))
        }
    }

    deinit {
        timer?.invalidate()
    }
}

@MainActor
private final class ZebraSystemRemindersEventStore: ZebraRemindersEventStore {
    private let eventStore = EKEventStore()

    func authorizationStatus() -> ZebraRemindersAuthorizationStatus {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .fullAccess, .authorized:
            return .authorized
        case .writeOnly:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func requestAuthorization() async throws -> ZebraRemindersAuthorizationStatus {
        let granted: Bool = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Bool, Error>) in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        return granted ? .authorized : authorizationStatus()
    }

    func fetchSnapshot() async throws -> ZebraRemindersStoreSnapshot {
        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForReminders(in: calendars)
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
        let listByID = Dictionary(uniqueKeysWithValues: calendars.map { ($0.calendarIdentifier, $0.title) })
        return ZebraRemindersStoreSnapshot(
            lists: calendars.map {
                ZebraRemindersListSnapshot(id: $0.calendarIdentifier, title: $0.title)
            },
            reminders: reminders.map { reminder in
                let listID = reminder.calendar.calendarIdentifier
                return ZebraReminderSnapshot(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title ?? "",
                    notes: reminder.notes,
                    listID: listID,
                    listTitle: listByID[listID] ?? reminder.calendar.title,
                    isCompleted: reminder.isCompleted,
                    priority: reminder.priority,
                    dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                )
            }
        )
    }
}
