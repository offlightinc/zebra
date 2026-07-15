import Foundation

struct SlackSeedCandidate: Equatable, Sendable {
    let conversationID: String
    let payload: SlackJSONValue
    let isDirectMessage: Bool
    let discoveredByReaction: Bool
}

struct SlackSeedClassifier: Sendable {
    let authorizedUserID: String
    let startDate: Date

    func roles(for candidate: SlackSeedCandidate) throws -> [SlackFootprintRole] {
        guard let timestamp = candidate.payload["ts"]?.stringValue,
              try SlackTimestamp.date(timestamp) >= startDate else { return [] }
        var roles: [SlackFootprintRole] = []
        if candidate.payload["user"]?.stringValue == authorizedUserID { roles.append(.authored) }
        if candidate.payload["text"]?.stringValue?.contains("<@\(authorizedUserID)>") == true { roles.append(.mentioned) }
        if candidate.discoveredByReaction || hasAuthorizedReaction(candidate.payload) { roles.append(.reacted) }
        if candidate.isDirectMessage { roles.append(.directMessage) }
        return roles
    }

    private func hasAuthorizedReaction(_ payload: SlackJSONValue) -> Bool {
        payload["reactions"]?.arrayValue?.contains { reaction in
            reaction["users"]?.arrayValue?.contains { $0.stringValue == authorizedUserID } == true
        } == true
    }
}

struct SlackThreadSelection: Sendable {
    let startDate: Date

    /// Keeps one old root for context and only replies at/after the chosen start date.
    func select(root: SlackJSONValue, replies: [SlackJSONValue]) throws -> [(SlackJSONValue, [SlackFootprintRole])] {
        var selected: [(SlackJSONValue, [SlackFootprintRole])] = [(root, [.threadContext])]
        for reply in replies {
            guard let timestamp = reply["ts"]?.stringValue else { continue }
            if try SlackTimestamp.date(timestamp) >= startDate { selected.append((reply, [.threadContext])) }
        }
        return selected
    }
}

struct SlackThreadProjector: Sendable {
    let store: SlackCapturedStore

    @discardableResult
    func project(_ capture: SlackRawCapture, roles: [SlackFootprintRole], threadRootTS: String) throws -> Bool {
        guard let messageTS = capture.payload["ts"]?.stringValue else { throw SlackCapturedError.invalidMessagePayload }
        let createdAt = try SlackTimestamp.date(threadRootTS)
        let line = SlackCapturedThreadLine(
            schemaVersion: 1, sourceCaptureID: capture.captureID,
            threadID: "\(capture.workspaceID):\(capture.conversationID):\(threadRootTS)",
            threadCreatedAt: createdAt,
            messageID: "\(capture.workspaceID):\(capture.conversationID):\(messageTS)",
            observedAt: capture.observedAt, footprintRoles: Array(Set(roles)).sorted { $0.rawValue < $1.rawValue },
            payload: capture.payload
        )
        return try store.appendThread(line)
    }
}

struct SlackCapturedCommitter: Sendable {
    let store: SlackCapturedStore
    let workspaceID: String
    let authorizedUserID: String

    /// Raw and projection appends are durable before the collector checkpoint advances.
    func commit(messages: [(conversationID: String, payload: SlackJSONValue, roles: [SlackFootprintRole])],
                pollRunID: String, observedAt: Date, committedThrough: String,
                beforeCheckpoint: (() throws -> Void)? = nil) throws {
        let projector = SlackThreadProjector(store: store)
        for message in messages {
            let capture = try SlackRawCapture.make(workspaceID: workspaceID, authorizedUserID: authorizedUserID,
                                                   conversationID: message.conversationID, observedAt: observedAt,
                                                   pollRunID: pollRunID, payload: message.payload)
            if try store.appendRaw(capture) {
                let threadRoot = message.payload["thread_ts"]?.stringValue ?? message.payload["ts"]!.stringValue!
                _ = try projector.project(capture, roles: message.roles, threadRootTS: threadRoot)
            } else {
                // Crash replay may find raw committed but projection/checkpoint absent.
                let threadRoot = message.payload["thread_ts"]?.stringValue ?? message.payload["ts"]!.stringValue!
                _ = try projector.project(capture, roles: message.roles, threadRootTS: threadRoot)
            }
        }
        try beforeCheckpoint?()
        try store.writeCheckpoint(.init(committedThrough: committedThrough, lastSuccessfulPollAt: observedAt))
    }
}

struct SlackTrackedThreadScheduler: Sendable {
    let limit: Int
    func bounded(_ threads: [SlackTrackedThread]) -> [SlackTrackedThread] {
        Array(threads.sorted {
            switch ($0.lastCheckedAt, $1.lastCheckedAt) {
            case (nil, nil): return $0.lastReplyTS > $1.lastReplyTS
            case (nil, _): return true
            case (_, nil): return false
            case (let lhs?, let rhs?): return lhs < rhs
            }
        }.prefix(max(0, limit)))
    }
}

struct SlackCapturedPoller: Sendable {
    let workspaceID: String
    let authorizedUserID: String
    let startDate: Date
    let api: SlackWebAPIClient
    let store: SlackCapturedStore
    let reconcileLimit: Int
    let now: @Sendable () -> Date

    init(workspaceID: String, authorizedUserID: String, startDate: Date, api: SlackWebAPIClient,
         store: SlackCapturedStore, reconcileLimit: Int = 20,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.workspaceID = workspaceID; self.authorizedUserID = authorizedUserID; self.startDate = startDate
        self.api = api; self.store = store; self.reconcileLimit = reconcileLimit; self.now = now
    }

    func poll() async throws {
        try await api.validateIdentity(workspaceID: workspaceID, userID: authorizedUserID)
        let observedAt = now(); let pollRunID = UUID().uuidString
        let checkpoint = try store.readCheckpoint()
        let kind: SlackPollRunManifest.Kind = checkpoint == nil ? .initial : .incremental
        try store.writePollManifest(.init(pollRunID: pollRunID, kind: kind, startedAt: observedAt,
                                          requestedOldest: checkpoint?.committedThrough ?? String(startDate.timeIntervalSince1970), completedAt: nil))

        let discoveryStartDate = discoveryStartDate(checkpoint: checkpoint)
        let classifier = SlackSeedClassifier(authorizedUserID: authorizedUserID, startDate: discoveryStartDate)
        let discovered = try await api.discoverSeeds(authorizedUserID: authorizedUserID, startDate: discoveryStartDate)
        let seeds = try discovered.compactMap { candidate -> (SlackSeedCandidate, [SlackFootprintRole])? in
            let roles = try classifier.roles(for: candidate)
            return roles.isEmpty ? nil : (candidate, roles)
        }
        var trackedByID = Dictionary(uniqueKeysWithValues: try store.readTrackedThreads().map { ("\($0.conversationID):\($0.threadTS)", $0) })
        var collected: [String: (String, SlackJSONValue, [SlackFootprintRole])] = [:]

        for group in groupSeedsByThread(seeds) {
            let messages = try await api.replies(conversationID: group.conversationID, threadTS: group.threadTS)
            guard let root = messages.first(where: { $0["ts"]?.stringValue == group.threadTS })
                    ?? group.seeds.first(where: { $0.0.payload["ts"]?.stringValue == group.threadTS })?.0.payload else { continue }
            let replies = messages.filter { $0["ts"]?.stringValue != group.threadTS }
            let seedRolesByMessage = group.rolesByMessage
            for (payload, contextRoles) in try SlackThreadSelection(startDate: startDate).select(root: root, replies: replies) {
                guard let ts = payload["ts"]?.stringValue else { continue }
                let roles = Set(contextRoles).union(seedRolesByMessage[ts] ?? [])
                mergeCollected(&collected, conversationID: group.conversationID, payload: payload, roles: roles)
            }
            let lastReply = ([group.threadTS] + replies.compactMap { $0["ts"]?.stringValue }).max() ?? group.threadTS
            trackedByID["\(group.conversationID):\(group.threadTS)"] = .init(conversationID: group.conversationID,
                threadTS: group.threadTS, lastReplyTS: lastReply, lastCheckedAt: observedAt)
        }

        let scheduled = SlackTrackedThreadScheduler(limit: reconcileLimit).bounded(Array(trackedByID.values))
        for thread in scheduled {
            let sourceID = "\(thread.conversationID):\(thread.threadTS)"
            do {
                let updates = try await api.replies(conversationID: thread.conversationID, threadTS: thread.threadTS, oldest: thread.lastReplyTS)
                var lastReply = thread.lastReplyTS
                for payload in updates {
                    guard let ts = payload["ts"]?.stringValue, ts != thread.threadTS else { continue }
                    mergeCollected(&collected, conversationID: thread.conversationID, payload: payload, roles: [.threadContext])
                    lastReply = max(lastReply, ts)
                }
                trackedByID[sourceID] = .init(conversationID: thread.conversationID, threadTS: thread.threadTS,
                                              lastReplyTS: lastReply, lastCheckedAt: observedAt)
                try store.recordAvailable(sourceID: sourceID, at: observedAt)
            } catch SlackCapturedError.api(let code) {
                try store.recordMissingOrInaccessible(sourceID: sourceID, at: observedAt, errorCode: code)
            }
        }

        let committedThrough = collected.values.compactMap { $0.1["ts"]?.stringValue }.max()
            ?? checkpoint?.committedThrough ?? String(startDate.timeIntervalSince1970)
        let batch = collected.values.map { (conversationID: $0.0, payload: $0.1, roles: $0.2) }
        try SlackCapturedCommitter(store: store, workspaceID: workspaceID, authorizedUserID: authorizedUserID)
            .commit(messages: batch, pollRunID: pollRunID, observedAt: observedAt, committedThrough: committedThrough) {
                try store.writeTrackedThreads(Array(trackedByID.values))
            }
        try store.writePollManifest(.init(pollRunID: pollRunID, kind: kind, startedAt: observedAt,
                                          requestedOldest: checkpoint?.committedThrough ?? String(startDate.timeIntervalSince1970), completedAt: now()))
    }

    func discoveryStartDate(checkpoint: SlackCollectorCheckpoint?) -> Date {
        guard let timestamp = checkpoint?.committedThrough,
              let checkpointDate = try? SlackTimestamp.date(timestamp) else { return startDate }
        return max(startDate, checkpointDate)
    }

    func groupSeedsByThread(_ seeds: [(SlackSeedCandidate, [SlackFootprintRole])]) -> [SlackThreadSeedGroup] {
        var grouped: [String: SlackThreadSeedGroup] = [:]
        for seed in seeds {
            guard let messageTS = seed.0.payload["ts"]?.stringValue else { continue }
            let threadTS = seed.0.payload["thread_ts"]?.stringValue ?? messageTS
            let key = "\(seed.0.conversationID):\(threadTS)"
            if var group = grouped[key] {
                group.seeds.append(seed); grouped[key] = group
            } else {
                grouped[key] = .init(conversationID: seed.0.conversationID, threadTS: threadTS, seeds: [seed])
            }
        }
        return Array(grouped.values)
    }

    private func mergeCollected(_ collected: inout [String: (String, SlackJSONValue, [SlackFootprintRole])],
                                conversationID: String, payload: SlackJSONValue, roles: Set<SlackFootprintRole>) {
        guard let timestamp = payload["ts"]?.stringValue else { return }
        let key = "\(conversationID):\(timestamp)"
        let mergedRoles = Set(collected[key]?.2 ?? []).union(roles)
        collected[key] = (conversationID, payload, Array(mergedRoles))
    }
}

struct SlackThreadSeedGroup: Sendable {
    let conversationID: String
    let threadTS: String
    var seeds: [(SlackSeedCandidate, [SlackFootprintRole])]

    var rolesByMessage: [String: Set<SlackFootprintRole>] {
        seeds.reduce(into: [:]) { result, seed in
            guard let messageTS = seed.0.payload["ts"]?.stringValue else { return }
            result[messageTS, default: []].formUnion(seed.1)
        }
    }
}
