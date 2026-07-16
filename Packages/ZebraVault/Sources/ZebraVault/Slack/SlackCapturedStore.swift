import Darwin
import Foundation

final class SlackCapturedStore: @unchecked Sendable {
    let root: URL
    private let fileManager: FileManager
    private var lockFD: Int32 = -1
    private let mutex = NSLock()
    private var rawCaptureIDs: Set<String> = []
    private var threadCaptureIDs: Set<String> = []

    init(applicationSupport: URL, workspaceID: String, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        root = applicationSupport.appending(path: "outer-brain/slack/\(workspaceID)/captured", directoryHint: .isDirectory)
        try prepareDirectories(applicationSupport: applicationSupport)
        let lockPath = root.appending(path: "writer.lock").path
        lockFD = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFD >= 0 else { throw POSIXError(.EIO) }
        _ = fchmod(lockFD, S_IRUSR | S_IWUSR)
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            close(lockFD); lockFD = -1
            throw SlackCapturedError.writerAlreadyActive
        }
        try recoverAllIncompleteTails()
        rawCaptureIDs = try loadRawCaptureIDs()
        threadCaptureIDs = try loadThreadCaptureIDs()
    }

    deinit {
        if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD) }
    }

    private func prepareDirectories(applicationSupport: URL) throws {
        let outerBrain = applicationSupport.appending(path: "outer-brain", directoryHint: .isDirectory)
        let directories = [outerBrain, root, rawDirectory, threadDirectory, stateDirectory,
                           stateDirectory.appending(path: "poll-runs", directoryHint: .isDirectory)]
        for directory in directories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        let marker = outerBrain.appending(path: ".metadata_never_index")
        if !fileManager.fileExists(atPath: marker.path) { try Data().write(to: marker, options: .atomic) }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
    }

    var rawDirectory: URL { root.appending(path: "raw", directoryHint: .isDirectory) }
    var threadDirectory: URL { root.appending(path: "threads", directoryHint: .isDirectory) }
    var stateDirectory: URL { root.appending(path: "state", directoryHint: .isDirectory) }

    @discardableResult
    func appendRaw(_ capture: SlackRawCapture) throws -> Bool {
        try mutex.withLock {
            let url = rawURL(for: capture.observedAt)
            guard !rawCaptureIDs.contains(capture.captureID) else { return false }
            try appendJSONLine(capture, to: url)
            rawCaptureIDs.insert(capture.captureID)
            return true
        }
    }

    @discardableResult
    func appendThread(_ line: SlackCapturedThreadLine) throws -> Bool {
        try mutex.withLock {
            let url = threadURL(for: line.threadCreatedAt)
            guard !threadCaptureIDs.contains(line.sourceCaptureID) else { return false }
            try appendJSONLine(line, to: url)
            threadCaptureIDs.insert(line.sourceCaptureID)
            return true
        }
    }

    func rawCaptures(on date: Date) throws -> [SlackRawCapture] { try readLines(SlackRawCapture.self, from: rawURL(for: date)) }
    func threadLines(createdOn date: Date) throws -> [SlackCapturedThreadLine] { try readLines(SlackCapturedThreadLine.self, from: threadURL(for: date)) }

    func replayThread(createdOn date: Date, threadID: String) throws -> [SlackCapturedThreadLine] {
        let lines = try threadLines(createdOn: date).filter { $0.threadID == threadID }
        var current: [String: SlackCapturedThreadLine] = [:]
        for line in lines { current[line.messageID] = line }
        return current.values.sorted { ($0.payload["ts"]?.stringValue ?? "") < ($1.payload["ts"]?.stringValue ?? "") }
    }

    func writeCheckpoint(_ checkpoint: SlackCollectorCheckpoint) throws {
        try atomicWrite(checkpoint, to: stateDirectory.appending(path: "collector-checkpoint.json"))
    }

    func readCheckpoint() throws -> SlackCollectorCheckpoint? {
        try readJSON(SlackCollectorCheckpoint.self, from: stateDirectory.appending(path: "collector-checkpoint.json"))
    }

    func writeTrackedThreads(_ threads: [SlackTrackedThread]) throws {
        try atomicWrite(threads, to: stateDirectory.appending(path: "tracked-threads.json"))
    }

    func readTrackedThreads() throws -> [SlackTrackedThread] {
        try readJSON([SlackTrackedThread].self, from: stateDirectory.appending(path: "tracked-threads.json")) ?? []
    }

    func writePollManifest(_ manifest: SlackPollRunManifest) throws {
        try atomicWrite(manifest, to: stateDirectory.appending(path: "poll-runs/\(manifest.pollRunID).json"))
    }

    func writeSourceState(_ state: SlackSourceState, sourceID: String) throws {
        let safeID = sourceID.data(using: .utf8)!.base64EncodedString().replacingOccurrences(of: "/", with: "_")
        try atomicWrite(state, to: stateDirectory.appending(path: "source-\(safeID).json"))
    }

    func readSourceState(sourceID: String) throws -> SlackSourceState? {
        let safeID = sourceID.data(using: .utf8)!.base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return try readJSON(SlackSourceState.self, from: stateDirectory.appending(path: "source-\(safeID).json"))
    }

    func recordAvailable(sourceID: String, at date: Date) throws {
        try writeSourceState(.init(availability: .available, lastSeenAt: date, lastCheckedAt: date,
                                   firstUnavailableAt: nil, errorCode: nil), sourceID: sourceID)
    }

    func recordMissingOrInaccessible(sourceID: String, at date: Date, errorCode: String?) throws {
        let prior = try readSourceState(sourceID: sourceID)
        try writeSourceState(.init(availability: .sourceMissingOrInaccessible, lastSeenAt: prior?.lastSeenAt,
                                   lastCheckedAt: date, firstUnavailableAt: prior?.firstUnavailableAt ?? date,
                                   errorCode: sanitizeSlackError(errorCode)), sourceID: sourceID)
    }

    private func rawURL(for date: Date) -> URL { rawDirectory.appending(path: Self.day(date) + ".jsonl") }
    private func threadURL(for date: Date) -> URL { threadDirectory.appending(path: Self.day(date) + ".jsonl") }

    private func appendJSONLine<T: Encodable>(_ value: T, to url: URL) throws {
        var data = try JSONEncoder.slackCaptured.encode(value); data.append(0x0A)
        let fd = open(url.path, O_CREAT | O_WRONLY | O_APPEND, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        _ = fchmod(fd, S_IRUSR | S_IWUSR)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard written > 0 else { throw POSIXError(.EIO) }
                offset += written
            }
        }
        guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
    }

    private func atomicWrite<T: Encodable>(_ value: T, to url: URL) throws {
        let temporary = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        let data = try JSONEncoder.slackCaptured.encode(value)
        let fd = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        do {
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let written = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    guard written > 0 else { throw POSIXError(.EIO) }
                    offset += written
                }
            }
            guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
            close(fd)
            guard rename(temporary.path, url.path) == 0 else { throw POSIXError(.EIO) }
            let directoryFD = open(url.deletingLastPathComponent().path, O_RDONLY)
            if directoryFD >= 0 { _ = fsync(directoryFD); close(directoryFD) }
        } catch {
            close(fd); unlink(temporary.path); throw error
        }
    }

    private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder.slackCaptured.decode(type, from: Data(contentsOf: url))
    }

    private func readLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try data.split(separator: 0x0A).map { try JSONDecoder.slackCaptured.decode(type, from: Data($0)) }
    }

    private func recoverAllIncompleteTails() throws {
        for directory in [rawDirectory, threadDirectory] {
            for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "jsonl" { try recoverIncompleteTail(at: url) }
        }
    }

    private func loadRawCaptureIDs() throws -> Set<String> {
        var result: Set<String> = []
        for url in try fileManager.contentsOfDirectory(at: rawDirectory, includingPropertiesForKeys: nil)
        where url.pathExtension == "jsonl" {
            result.formUnion(try readLines(SlackRawCapture.self, from: url).map(\.captureID))
        }
        return result
    }

    private func loadThreadCaptureIDs() throws -> Set<String> {
        var result: Set<String> = []
        for url in try fileManager.contentsOfDirectory(at: threadDirectory, includingPropertiesForKeys: nil)
        where url.pathExtension == "jsonl" {
            result.formUnion(try readLines(SlackCapturedThreadLine.self, from: url).map(\.sourceCaptureID))
        }
        return result
    }

    private func recoverIncompleteTail(at url: URL) throws {
        var data = try Data(contentsOf: url)
        guard !data.isEmpty, data.last != 0x0A else { return }
        guard let newline = data.lastIndex(of: 0x0A) else { data.removeAll(); try replaceFile(data, at: url); return }
        data.removeSubrange(data.index(after: newline)..<data.endIndex)
        try replaceFile(data, at: url)
    }

    private func replaceFile(_ data: Data, at url: URL) throws {
        let temporary = url.appendingPathExtension("repair")
        try data.write(to: temporary, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard rename(temporary.path, url.path) == 0 else { throw POSIXError(.EIO) }
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
}

struct SlackPollRunManifest: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case initial, incremental }
    let pollRunID: String
    let kind: Kind
    let startedAt: Date
    let requestedOldest: String
    let completedAt: Date?
    let failureStage: String?
    let failureCode: String?
    let skippedSourceCount: Int?
    let skippedStages: [String]?
    let skippedErrorCodes: [String]?

    init(pollRunID: String, kind: Kind, startedAt: Date, requestedOldest: String,
         completedAt: Date?, failureStage: String? = nil, failureCode: String? = nil,
         skippedSources: [SlackSkippedSource] = []) {
        self.pollRunID = pollRunID
        self.kind = kind
        self.startedAt = startedAt
        self.requestedOldest = requestedOldest
        self.completedAt = completedAt
        self.failureStage = sanitizeSlackError(failureStage)
        self.failureCode = sanitizeSlackError(failureCode)
        self.skippedSourceCount = skippedSources.count
        self.skippedStages = Array(Set(skippedSources.compactMap { sanitizeSlackError($0.stage) })).sorted()
        self.skippedErrorCodes = Array(Set(skippedSources.compactMap { sanitizeSlackError($0.errorCode) })).sorted()
    }

    enum CodingKeys: String, CodingKey {
        case pollRunID = "poll_run_id", kind, startedAt = "started_at"
        case requestedOldest = "requested_oldest", completedAt = "completed_at"
        case failureStage = "failure_stage", failureCode = "failure_code"
        case skippedSourceCount = "skipped_source_count", skippedStages = "skipped_stages"
        case skippedErrorCodes = "skipped_error_codes"
    }
}

private func sanitizeSlackError(_ value: String?) -> String? {
    guard let value else { return nil }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
    return value.unicodeScalars.allSatisfy(allowed.contains) ? String(value.prefix(80)) : "unknown_error"
}
