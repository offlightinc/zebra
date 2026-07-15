import CryptoKit
import Foundation

enum SlackCapturedError: Error, Equatable {
    case invalidMessagePayload
    case invalidTimestamp(String)
    case writerAlreadyActive
    case invalidJSONL
    case missingCredential
    case invalidResponse
    case api(String)
    case rateLimited(retryAfter: TimeInterval)
    case tokenRevoked
    case partialScope(required: String)
    case workspaceMismatch
    case invalidUserToken
}

/// A lossless JSON value. Objects preserve every Slack field; canonical encoding
/// sorts object keys while retaining array order.
enum SlackJSONValue: Codable, Equatable, Sendable {
    case object([String: SlackJSONValue])
    case array([SlackJSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: SlackJSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([SlackJSONValue].self) { self = .array(value) }
        else if let value = try? container.decode(Decimal.self) { self = .number(NSDecimalNumber(decimal: value).stringValue) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value):
            guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
                throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Invalid JSON number"))
            }
            try container.encode(decimal)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    subscript(key: String) -> SlackJSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var arrayValue: [SlackJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    func canonicalData() throws -> Data {
        var output = Data()
        try appendCanonical(to: &output)
        return output
    }

    private func appendCanonical(to output: inout Data) throws {
        switch self {
        case .null: output.append(contentsOf: "null".utf8)
        case .bool(let value): output.append(contentsOf: (value ? "true" : "false").utf8)
        case .number(let value): output.append(contentsOf: value.utf8)
        case .string(let value):
            let encoded = try JSONEncoder().encode(value)
            output.append(encoded)
        case .array(let values):
            output.append(UInt8(ascii: "["))
            for (index, value) in values.enumerated() {
                if index > 0 { output.append(UInt8(ascii: ",")) }
                try value.appendCanonical(to: &output)
            }
            output.append(UInt8(ascii: "]"))
        case .object(let object):
            output.append(UInt8(ascii: "{"))
            for (index, key) in object.keys.sorted().enumerated() {
                if index > 0 { output.append(UInt8(ascii: ",")) }
                output.append(try JSONEncoder().encode(key))
                output.append(UInt8(ascii: ":"))
                try object[key]!.appendCanonical(to: &output)
            }
            output.append(UInt8(ascii: "}"))
        }
    }
}

enum SlackFootprintRole: String, Codable, CaseIterable, Sendable {
    case authored
    case mentioned
    case reacted
    case directMessage = "direct_message"
    case threadContext = "thread_context"
}

struct SlackRawCapture: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let captureID: String
    let workspaceID: String
    let authorizedUserID: String
    let conversationID: String
    let observedAt: Date
    let pollRunID: String
    let payload: SlackJSONValue

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case captureID = "capture_id"
        case workspaceID = "workspace_id"
        case authorizedUserID = "authorized_user_id"
        case conversationID = "conversation_id"
        case observedAt = "observed_at"
        case pollRunID = "poll_run_id"
        case payload
    }

    static func make(workspaceID: String, authorizedUserID: String, conversationID: String,
                     observedAt: Date, pollRunID: String, payload: SlackJSONValue) throws -> Self {
        guard let messageTS = payload["ts"]?.stringValue else { throw SlackCapturedError.invalidMessagePayload }
        let messageVersion = sha256(try payload.canonicalData())
        let identity = SlackJSONValue.object([
            "conversation_id": .string(conversationID), "message_ts": .string(messageTS),
            "message_version": .string(messageVersion), "workspace_id": .string(workspaceID),
        ])
        return Self(schemaVersion: 1, captureID: sha256(try identity.canonicalData()), workspaceID: workspaceID,
                    authorizedUserID: authorizedUserID, conversationID: conversationID, observedAt: observedAt,
                    pollRunID: pollRunID, payload: payload)
    }
}

struct SlackCapturedThreadLine: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sourceCaptureID: String
    let threadID: String
    let threadCreatedAt: Date
    let messageID: String
    let observedAt: Date
    let footprintRoles: [SlackFootprintRole]
    let payload: SlackJSONValue

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sourceCaptureID = "source_capture_id"
        case threadID = "thread_id"
        case threadCreatedAt = "thread_created_at"
        case messageID = "message_id"
        case observedAt = "observed_at"
        case footprintRoles = "footprint_roles"
        case payload
    }
}

enum SlackSourceAvailability: String, Codable, Sendable { case available, sourceMissingOrInaccessible = "source_missing_or_inaccessible" }

struct SlackSourceState: Codable, Equatable, Sendable {
    var availability: SlackSourceAvailability
    var lastSeenAt: Date?
    var lastCheckedAt: Date
    var firstUnavailableAt: Date?
    var errorCode: String?
}

struct SlackCollectorCheckpoint: Codable, Equatable, Sendable {
    var committedThrough: String?
    var lastSuccessfulPollAt: Date?
}

struct SlackTrackedThread: Codable, Equatable, Sendable {
    let conversationID: String
    let threadTS: String
    var lastReplyTS: String
    var lastCheckedAt: Date?
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

enum SlackTimestamp {
    static func date(_ timestamp: String) throws -> Date {
        guard let seconds = TimeInterval(timestamp) else { throw SlackCapturedError.invalidTimestamp(timestamp) }
        return Date(timeIntervalSince1970: seconds)
    }
}

extension JSONEncoder {
    static var slackCaptured: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var slackCaptured: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
