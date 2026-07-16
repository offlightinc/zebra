import Foundation
import Testing
@testable import ZebraVault

@Suite(.serialized)
struct SlackCapturedPollFailureTests {
    @Test func unthreadableSeedDoesNotAbortPollAndDiscoveredPayloadIsCommitted() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try SlackCapturedStore(applicationSupport: directory, workspaceID: "T1")
        let observedAt = Date(timeIntervalSince1970: 300)
        let transport = MixedThreadExpansionTransport()
        let client = SlackWebAPIClient(
            token: "xoxp-test-secret",
            transport: transport,
            baseURL: URL(string: "https://fixture.invalid/api/")!
        )

        try await SlackCapturedPoller(
            workspaceID: "T1",
            authorizedUserID: "U1",
            startDate: Date(timeIntervalSince1970: 100),
            api: client,
            store: store,
            now: { observedAt }
        ).poll()

        let captures = try store.rawCaptures(on: observedAt)
        #expect(Set(captures.compactMap { $0.payload["ts"]?.stringValue }) == ["200.0", "210.0", "211.0"])
        #expect(captures.first { $0.payload["ts"]?.stringValue == "200.0" }?.payload["subtype"]?.stringValue == "channel_join")
        #expect(try store.readCheckpoint()?.committedThrough == "211.0")
        #expect(!String(decoding: try JSONEncoder.slackCaptured.encode(captures), as: UTF8.self).contains("xoxp-test-secret"))
    }
}

private actor MixedThreadExpansionTransport: SlackHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let method = request.url?.lastPathComponent
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value: String
        switch method {
        case "auth.test":
            value = #"{"ok":true,"team_id":"T1","user_id":"U1"}"#
        case "search.messages":
            if query.first(where: { $0.name == "query" })?.value?.hasPrefix("from:") == true {
                value = #"{"ok":true,"messages":{"matches":[{"type":"message","subtype":"channel_join","ts":"200.0","user":"U1","text":"joined","channel":{"id":"CBAD"}},{"type":"message","ts":"210.0","user":"U1","text":"normal","channel":{"id":"CGOOD"}}],"paging":{"pages":1}}}"#
            } else {
                value = #"{"ok":true,"messages":{"matches":[],"paging":{"pages":1}}}"#
            }
        case "reactions.list":
            value = #"{"ok":true,"items":[],"response_metadata":{"next_cursor":""}}"#
        case "users.conversations":
            value = #"{"ok":true,"channels":[],"response_metadata":{"next_cursor":""}}"#
        case "conversations.replies":
            let channel = query.first(where: { $0.name == "channel" })?.value
            if channel == "CBAD" {
                value = #"{"ok":false,"error":"thread_not_found"}"#
            } else {
                value = #"{"ok":true,"messages":[{"type":"message","ts":"210.0","user":"U1","text":"normal"},{"type":"message","ts":"211.0","thread_ts":"210.0","user":"U2","text":"reply"}],"response_metadata":{"next_cursor":""}}"#
            }
        default:
            value = #"{"ok":false,"error":"unexpected_method"}"#
        }
        return (
            Data(value.utf8),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}
