import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol SlackHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct SlackURLSessionTransport: SlackHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SlackCapturedError.invalidResponse }
        return (data, response)
    }
}

struct SlackWebAPIClient: Sendable {
    struct Identity: Equatable, Sendable {
        let workspaceID: String
        let userID: String
    }
    private let token: String
    private let transport: any SlackHTTPTransport
    private let baseURL: URL

    init(token: String, transport: any SlackHTTPTransport = SlackURLSessionTransport(),
         baseURL: URL = URL(string: "https://slack.com/api/")!) {
        self.token = token; self.transport = transport; self.baseURL = baseURL
    }

    func call(_ method: String, query: [URLQueryItem] = []) async throws -> SlackJSONValue {
        var components = URLComponents(url: baseURL.appending(path: method), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 429 {
            throw SlackCapturedError.rateLimited(retryAfter: TimeInterval(response.value(forHTTPHeaderField: "Retry-After") ?? "1") ?? 1)
        }
        guard (200..<300).contains(response.statusCode),
              let envelope = try? JSONDecoder().decode(SlackJSONValue.self, from: data),
              case .bool(true) = envelope["ok"] else {
            if let envelope = try? JSONDecoder().decode(SlackJSONValue.self, from: data),
               let error = envelope["error"]?.stringValue {
                if ["invalid_auth", "token_revoked", "account_inactive", "token_expired"].contains(error) { throw SlackCapturedError.tokenRevoked }
                if error == "missing_scope" { throw SlackCapturedError.partialScope(required: envelope["needed"]?.stringValue ?? "unknown") }
                throw SlackCapturedError.api(error)
            }
            throw SlackCapturedError.invalidResponse
        }
        return envelope
    }

    func validateIdentity(workspaceID: String, userID: String) async throws {
        let identity = try await authenticatedIdentity()
        guard identity.workspaceID == workspaceID, identity.userID == userID else {
            throw SlackCapturedError.workspaceMismatch
        }
    }

    func authenticatedIdentity() async throws -> Identity {
        guard token.hasPrefix("xoxp-") else { throw SlackCapturedError.invalidUserToken }
        let result = try await call("auth.test")
        guard result["bot_id"] == nil,
              let workspaceID = result["team_id"]?.stringValue, !workspaceID.isEmpty,
              let userID = result["user_id"]?.stringValue, !userID.isEmpty else {
            throw SlackCapturedError.invalidUserToken
        }
        return Identity(workspaceID: workspaceID, userID: userID)
    }

    func discoverSeeds(authorizedUserID: String, startDate: Date) async throws -> [SlackSeedCandidate] {
        // Slack's `after:` modifier is exclusive. Search from the previous UTC
        // calendar day, then let SlackSeedClassifier's >= boundary enforce the
        // exact user-selected instant so the selected day itself is included.
        let day = Self.day(startDate.addingTimeInterval(-24 * 60 * 60))
        async let authored = search(query: "from:<@\(authorizedUserID)> after:\(day)", reacted: false)
        async let mentioned = search(query: "<@\(authorizedUserID)> after:\(day)", reacted: false)
        async let reacted = reactionSeeds(userID: authorizedUserID, startDate: startDate)
        async let directMessages = directMessageSeeds(startDate: startDate)
        let combined = try await authored + mentioned + reacted + directMessages
        var unique: [String: SlackSeedCandidate] = [:]
        for candidate in combined {
            guard let ts = candidate.payload["ts"]?.stringValue else { continue }
            let key = "\(candidate.conversationID):\(ts)"
            if let old = unique[key] {
                unique[key] = .init(conversationID: old.conversationID, payload: candidate.payload,
                                    isDirectMessage: old.isDirectMessage || candidate.isDirectMessage,
                                    discoveredByReaction: old.discoveredByReaction || candidate.discoveredByReaction)
            } else { unique[key] = candidate }
        }
        return Array(unique.values)
    }

    func replies(conversationID: String, threadTS: String, oldest: String? = nil) async throws -> [SlackJSONValue] {
        var query = [URLQueryItem(name: "channel", value: conversationID), URLQueryItem(name: "ts", value: threadTS),
                     URLQueryItem(name: "limit", value: "200")]
        if let oldest { query.append(URLQueryItem(name: "oldest", value: oldest)) }
        return try await cursorPages(method: "conversations.replies", query: query, arrayPath: ["messages"])
    }

    private func search(query searchQuery: String, reacted: Bool) async throws -> [SlackSeedCandidate] {
        var page = 1; var result: [SlackSeedCandidate] = []
        while true {
            let envelope = try await call("search.messages", query: [URLQueryItem(name: "query", value: searchQuery),
                URLQueryItem(name: "sort", value: "timestamp"), URLQueryItem(name: "sort_dir", value: "asc"),
                URLQueryItem(name: "highlight", value: "false"), URLQueryItem(name: "count", value: "100"),
                URLQueryItem(name: "page", value: String(page))])
            let matches = envelope["messages"]?["matches"]?.arrayValue ?? []
            result += matches.compactMap { message in
                guard let channel = message["channel"]?["id"]?.stringValue else { return nil }
                return SlackSeedCandidate(conversationID: channel, payload: message, isDirectMessage: false, discoveredByReaction: reacted)
            }
            let pages = envelope["messages"]?["paging"]?["pages"]?.integerValue ?? page
            guard page < pages else { break }; page += 1
        }
        return result
    }

    private func reactionSeeds(userID: String, startDate: Date) async throws -> [SlackSeedCandidate] {
        let items = try await cursorPages(method: "reactions.list", query: [URLQueryItem(name: "user", value: userID),
            URLQueryItem(name: "full", value: "true"), URLQueryItem(name: "limit", value: "200")], arrayPath: ["items"])
        return try items.compactMap { item in
            guard item["type"]?.stringValue == "message", let channel = item["channel"]?.stringValue,
                  let message = item["message"], let ts = message["ts"]?.stringValue,
                  try SlackTimestamp.date(ts) >= startDate else { return nil }
            return .init(conversationID: channel, payload: message, isDirectMessage: channel.hasPrefix("D"), discoveredByReaction: true)
        }
    }

    private func directMessageSeeds(startDate: Date) async throws -> [SlackSeedCandidate] {
        let channels = try await cursorPages(method: "users.conversations", query: [URLQueryItem(name: "types", value: "im"),
            URLQueryItem(name: "limit", value: "200")], arrayPath: ["channels"])
        var result: [SlackSeedCandidate] = []
        for channel in channels {
            guard let id = channel["id"]?.stringValue else { continue }
            let messages = try await cursorPages(method: "conversations.history", query: [URLQueryItem(name: "channel", value: id),
                URLQueryItem(name: "oldest", value: String(startDate.timeIntervalSince1970)), URLQueryItem(name: "limit", value: "200")], arrayPath: ["messages"])
            result += messages.map { .init(conversationID: id, payload: $0, isDirectMessage: true, discoveredByReaction: false) }
        }
        return result
    }

    private func cursorPages(method: String, query base: [URLQueryItem], arrayPath: [String]) async throws -> [SlackJSONValue] {
        var cursor: String?; var result: [SlackJSONValue] = []
        repeat {
            var query = base
            if let cursor, !cursor.isEmpty { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let envelope = try await call(method, query: query)
            var node = envelope
            for key in arrayPath { node = node[key] ?? .array([]) }
            result += node.arrayValue ?? []
            cursor = envelope["response_metadata"]?["next_cursor"]?.stringValue
        } while cursor?.isEmpty == false
        return result
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
}

private extension SlackJSONValue {
    var integerValue: Int? {
        switch self { case .number(let value): return Int(value); default: return nil }
    }
}
