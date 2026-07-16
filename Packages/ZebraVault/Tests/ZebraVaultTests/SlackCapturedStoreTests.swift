import Darwin
import Foundation
import Testing
@testable import ZebraVault

@Suite(.serialized)
struct SlackCapturedStoreTests {
    let observed = Date(timeIntervalSince1970: 1_789_494_400)

    @Test func rawAppendDedupesSameVersionAndAppendsChangedPayload() throws {
        let fixture = try Fixture()
        let first = try capture(text: "one", extra: ["files": .array([.object(["id": .string("F1"), "url_private": .string("https://files.slack.com/a")])])])
        #expect(try fixture.store.appendRaw(first))
        #expect(try !fixture.store.appendRaw(first))
        let changed = try capture(text: "edited", extra: ["reactions": .array([.object(["name": .string("eyes"), "count": .number("2"), "users": .array([.string("U1"), .string("U2")])])])])
        #expect(try fixture.store.appendRaw(changed))
        let values = try fixture.store.rawCaptures(on: observed)
        #expect(values.count == 2)
        #expect(values[1].payload["reactions"]?[0]?["count"] == .number("2"))
        #expect(values[0].payload["files"]?[0]?["url_private"]?.stringValue == "https://files.slack.com/a")
    }

    @Test func canonicalIdentityIgnoresObjectKeyOrderButPreservesArrayOrder() throws {
        let a = SlackJSONValue.object(["ts": .string("1789494400.1"), "x": .array([.number("1"), .number("2")]), "text": .string("x")])
        let b = SlackJSONValue.object(["text": .string("x"), "x": .array([.number("1"), .number("2")]), "ts": .string("1789494400.1")])
        let c = SlackJSONValue.object(["ts": .string("1789494400.1"), "x": .array([.number("2"), .number("1")]), "text": .string("x")])
        let one = try SlackRawCapture.make(workspaceID: "T1", authorizedUserID: "U1", conversationID: "C1", observedAt: observed, pollRunID: "p", payload: a)
        let two = try SlackRawCapture.make(workspaceID: "T1", authorizedUserID: "U1", conversationID: "C1", observedAt: observed, pollRunID: "q", payload: b)
        let three = try SlackRawCapture.make(workspaceID: "T1", authorizedUserID: "U1", conversationID: "C1", observedAt: observed, pollRunID: "p", payload: c)
        #expect(one.captureID == two.captureID)
        #expect(one.captureID != three.captureID)
    }

    @Test func rawEnvelopeHasExactlyEightDesignedFields() throws {
        let encoded = try JSONEncoder.slackCaptured.encode(capture(text: "shape"))
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == ["schema_version", "capture_id", "workspace_id", "authorized_user_id",
                                     "conversation_id", "observed_at", "poll_run_id", "payload"])
    }

    @Test func threadReplaySelectsLatestMessageVersion() throws {
        let fixture = try Fixture(); let projector = SlackThreadProjector(store: fixture.store)
        let first = try capture(text: "first"); let changed = try capture(text: "changed")
        _ = try projector.project(first, roles: [.authored], threadRootTS: "1789494400.1")
        _ = try projector.project(changed, roles: [.authored, .reacted], threadRootTS: "1789494400.1")
        let replay = try fixture.store.replayThread(createdOn: observed, threadID: "T1:C1:1789494400.1")
        #expect(replay.count == 1)
        #expect(replay[0].payload["text"]?.stringValue == "changed")
        #expect(replay[0].footprintRoles == [.authored, .reacted])
    }

    @Test func selectionKeepsOldRootAndOnlyRepliesAfterStart() throws {
        let start = Date(timeIntervalSince1970: 200)
        let selection = SlackThreadSelection(startDate: start)
        let result = try selection.select(root: message(ts: "100.0", text: "old root"), replies: [
            message(ts: "150.0", text: "old reply"), message(ts: "201.0", text: "new reply")])
        #expect(result.map { $0.0["text"]?.stringValue } == ["old root", "new reply"])
        #expect(result.allSatisfy { $0.1 == [.threadContext] })
    }

    @Test func seedClassificationCoversAuthoredMentionedReactedAndDM() throws {
        let classifier = SlackSeedClassifier(authorizedUserID: "U1", startDate: Date(timeIntervalSince1970: 100))
        let payload = SlackJSONValue.object(["ts": .string("200.0"), "user": .string("U1"),
            "text": .string("hello <@U1>"), "reactions": .array([.object(["name": .string("eyes"), "users": .array([.string("U1")])])])])
        let roles = try classifier.roles(for: .init(conversationID: "D1", payload: payload, isDirectMessage: true, discoveredByReaction: false))
        #expect(Set(roles) == Set(SlackFootprintRole.allCases.filter { $0 != .threadContext }))
        #expect(try classifier.roles(for: .init(conversationID: "D1", payload: message(ts: "99", text: "old"), isDirectMessage: true, discoveredByReaction: false)).isEmpty)
    }

    @Test func groupsSameThreadOnceAndUnionsRolesPerMessage() throws {
        let fixture = try Fixture()
        let poller = SlackCapturedPoller(workspaceID: "T1", authorizedUserID: "U1",
            startDate: Date(timeIntervalSince1970: 100), api: SlackWebAPIClient(token: "unused"), store: fixture.store)
        let reply = SlackJSONValue.object(["ts": .string("201.0"), "thread_ts": .string("200.0"), "user": .string("U1")])
        let candidate = SlackSeedCandidate(conversationID: "C1", payload: reply, isDirectMessage: false, discoveredByReaction: false)
        let groups = poller.groupSeedsByThread([(candidate, [.authored]), (candidate, [.mentioned, .reacted])])
        #expect(groups.count == 1)
        #expect(groups[0].threadTS == "200.0")
        #expect(groups[0].rolesByMessage["201.0"] == [.authored, .mentioned, .reacted])
    }

    @Test func incrementalDiscoveryStartsAtCheckpoint() throws {
        let fixture = try Fixture(); let initial = Date(timeIntervalSince1970: 100)
        let poller = SlackCapturedPoller(workspaceID: "T1", authorizedUserID: "U1", startDate: initial,
            api: SlackWebAPIClient(token: "unused"), store: fixture.store)
        #expect(poller.discoveryStartDate(checkpoint: nil) == initial)
        #expect(poller.discoveryStartDate(checkpoint: .init(committedThrough: "250.0", lastSuccessfulPollAt: nil)) == Date(timeIntervalSince1970: 250))
        #expect(poller.discoveryStartDate(checkpoint: .init(committedThrough: "50.0", lastSuccessfulPollAt: nil)) == initial)
    }

    @Test func appendUsesInitializationIndexInsteadOfRescanningArchive() throws {
        let fixture = try Fixture(); let first = try capture(text: "first")
        #expect(try fixture.store.appendRaw(first))
        try Data("not-json\n".utf8).write(to: fixture.store.rawDirectory.appending(path: "2000-01-01.jsonl"))
        let changed = try capture(text: "changed")
        #expect(try fixture.store.appendRaw(changed))
        #expect(try !fixture.store.appendRaw(changed))
    }

    @Test func threadAppendUsesInitializationIndexInsteadOfRescanningArchive() throws {
        let fixture = try Fixture(); let projector = SlackThreadProjector(store: fixture.store)
        let first = try capture(text: "first")
        #expect(try projector.project(first, roles: [.authored], threadRootTS: "1789494400.1"))
        let archive = fixture.store.threadDirectory.appending(path: "2026-09-15.jsonl")
        let handle = try FileHandle(forWritingTo: archive)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("not-json\n".utf8)); try handle.close()

        let changed = try capture(text: "changed")
        #expect(try projector.project(changed, roles: [.authored], threadRootTS: "1789494400.1"))
        #expect(try !projector.project(changed, roles: [.authored], threadRootTS: "1789494400.1"))
    }

    @Test func mockHTTPPreservesFullPayloadAndNeverPersistsCredential() async throws {
        let response = #"{"ok":true,"messages":[{"type":"message","ts":"1789494400.1","text":"secretless","blocks":[{"type":"rich_text","elements":[1,2]}],"files":[{"id":"F1","mode":"hosted"}],"reactions":[{"name":"eyes","count":3,"users":["U1"]}]}]}"#
        let transport = MockTransport(body: Data(response.utf8))
        let client = SlackWebAPIClient(token: "xoxp-super-secret", transport: transport, baseURL: URL(string: "https://fixture.invalid/api/")!)
        let envelope = try await client.call("conversations.history")
        let payload = envelope["messages"]!.arrayValue![0]
        #expect(payload["blocks"]?[0]?["elements"]?.arrayValue?.count == 2)
        let fixture = try Fixture()
        let capture = try SlackRawCapture.make(workspaceID: "T1", authorizedUserID: "U1", conversationID: "C1", observedAt: observed, pollRunID: "p", payload: payload)
        _ = try fixture.store.appendRaw(capture)
        let stored = try Data(contentsOf: fixture.store.rawDirectory.appending(path: "2026-09-15.jsonl"))
        #expect(!String(decoding: stored, as: UTF8.self).contains("xoxp-super-secret"))
        #expect(await transport.authorization() == "Bearer xoxp-super-secret")
    }

    @Test func appendBeforeCheckpointCrashReplaysWithoutDuplicate() throws {
        enum Simulated: Error { case crash }
        let fixture = try Fixture(); let committer = SlackCapturedCommitter(store: fixture.store, workspaceID: "T1", authorizedUserID: "U1")
        let batch = [(conversationID: "C1", payload: message(ts: "1789494400.1", text: "one"), roles: [SlackFootprintRole.authored])]
        #expect(throws: Simulated.self) { try committer.commit(messages: batch, pollRunID: "p1", observedAt: observed, committedThrough: "1") { throw Simulated.crash } }
        #expect(try fixture.store.readCheckpoint() == nil)
        try committer.commit(messages: batch, pollRunID: "p2", observedAt: observed, committedThrough: "1")
        #expect(try fixture.store.rawCaptures(on: observed).count == 1)
        #expect(try fixture.store.threadLines(createdOn: observed).count == 1)
        #expect(try fixture.store.readCheckpoint()?.committedThrough == "1")
    }

    @Test func incompleteFinalLineIsRemovedOnOpen() throws {
        let directory = try temporaryDirectory(); var store: SlackCapturedStore? = try SlackCapturedStore(applicationSupport: directory, workspaceID: "T1")
        _ = try store!.appendRaw(capture(text: "valid")); let raw = store!.rawDirectory.appending(path: "2026-09-15.jsonl")
        store = nil
        let handle = try FileHandle(forWritingTo: raw); try handle.seekToEnd(); try handle.write(contentsOf: Data(#"{"partial":"# .utf8)); try handle.close()
        store = try SlackCapturedStore(applicationSupport: directory, workspaceID: "T1")
        #expect(try store!.rawCaptures(on: observed).count == 1)
    }

    @Test func rejectsSecondWriter() throws {
        let directory = try temporaryDirectory(); let first = try SlackCapturedStore(applicationSupport: directory, workspaceID: "T1")
        #expect(throws: SlackCapturedError.writerAlreadyActive) { _ = try SlackCapturedStore(applicationSupport: directory, workspaceID: "T1") }
        withExtendedLifetime(first) {}
    }

    @Test func missingStateDoesNotDeleteAndRecoversWhenSeenAgain() throws {
        let fixture = try Fixture(); let original = try capture(text: "kept"); _ = try fixture.store.appendRaw(original)
        try fixture.store.recordAvailable(sourceID: "C1:1789494400.1", at: observed)
        let later = observed.addingTimeInterval(60)
        try fixture.store.recordMissingOrInaccessible(sourceID: "C1:1789494400.1", at: later, errorCode: "channel_not_found")
        #expect(try fixture.store.readSourceState(sourceID: "C1:1789494400.1")?.availability == .sourceMissingOrInaccessible)
        #expect(try fixture.store.rawCaptures(on: observed).count == 1)
        try fixture.store.recordAvailable(sourceID: "C1:1789494400.1", at: later.addingTimeInterval(60))
        #expect(try fixture.store.readSourceState(sourceID: "C1:1789494400.1")?.availability == .available)
    }

    @Test func storagePermissionsAndSpotlightMarker() throws {
        let fixture = try Fixture(); _ = try fixture.store.appendRaw(capture(text: "permissions"))
        try fixture.store.writeCheckpoint(.init(committedThrough: "1", lastSuccessfulPollAt: observed))
        #expect(mode(fixture.store.root) == 0o700)
        #expect(mode(fixture.store.rawDirectory.appending(path: "2026-09-15.jsonl")) == 0o600)
        #expect(mode(fixture.store.stateDirectory.appending(path: "collector-checkpoint.json")) == 0o600)
        let marker = fixture.store.root.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: ".metadata_never_index")
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    private func capture(text: String, extra: [String: SlackJSONValue] = [:]) throws -> SlackRawCapture {
        var object: [String: SlackJSONValue] = ["type": .string("message"), "ts": .string("1789494400.1"), "user": .string("U1"), "text": .string(text)]
        object.merge(extra) { _, new in new }
        return try SlackRawCapture.make(workspaceID: "T1", authorizedUserID: "U1", conversationID: "C1", observedAt: observed, pollRunID: "poll", payload: .object(object))
    }

    private func message(ts: String, text: String) -> SlackJSONValue { .object(["type": .string("message"), "ts": .string(ts), "text": .string(text)]) }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    private func mode(_ url: URL) -> mode_t { var info = stat(); _ = lstat(url.path, &info); return info.st_mode & 0o777 }

    private struct Fixture {
        let directory: URL; let store: SlackCapturedStore
        init() throws {
            directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            store = try SlackCapturedStore(applicationSupport: directory, workspaceID: "T1")
        }
    }
}

private actor MockTransport: SlackHTTPTransport {
    let body: Data; private var seenAuthorization: String?
    init(body: Data) { self.body = body }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        seenAuthorization = request.value(forHTTPHeaderField: "Authorization")
        return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func authorization() -> String? { seenAuthorization }
}

private extension SlackJSONValue {
    subscript(index: Int) -> SlackJSONValue? { arrayValue.flatMap { $0.indices.contains(index) ? $0[index] : nil } }
}
