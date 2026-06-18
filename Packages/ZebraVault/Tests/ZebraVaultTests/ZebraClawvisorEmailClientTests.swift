import XCTest
@testable import ZebraVault

final class ZebraClawvisorEmailClientTests: XCTestCase {
    override func tearDown() {
        ClawvisorMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testStatusCompletesFromCanonicalEnvAndTaskGmailService() async throws {
        let client = makeClient(
            env: [
                "CLAWVISOR_URL": "https://clawvisor.test",
                "CLAWVISOR_AGENT_TOKEN": "cvis_test",
                "CLAWVISOR_TASK_ID": "task_test",
            ]
        ) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cvis_test")
            if request.url?.path == "/api/tasks/task_test" {
                return (
                    200,
                    """
                    {
                      "id": "task_test",
                      "authorized_actions": [
                        {
                          "service": "google.gmail:studyhan92@gmail.com",
                          "action": "list_messages"
                        }
                      ]
                    }
                    """.data(using: .utf8)!
                )
            }
            XCTAssertEqual(request.url?.path, "/api/gateway/request")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try requestBodyData(request)) as? [String: Any])
            XCTAssertEqual(body["task_id"] as? String, "task_test")
            XCTAssertEqual(body["service"] as? String, "google.gmail:studyhan92@gmail.com")
            XCTAssertEqual(body["action"] as? String, "list_messages")
            return (
                200,
                """
                {
                  "status": "executed",
                  "result": {
                    "messages": []
                  }
                }
                """.data(using: .utf8)!
            )
        }

        let status = try await client.status()

        XCTAssertTrue(status.connected)
        XCTAssertEqual(status.email, "studyhan92@gmail.com")
    }

    func testStatusAcceptsBareGoogleGmailService() async throws {
        let client = makeClient(
            env: [
                "CLAWVISOR_URL": "https://clawvisor.test",
                "CLAWVISOR_AGENT_TOKEN": "cvis_test",
                "CLAWVISOR_TASK_ID": "task_test",
            ]
        ) { request in
            if request.url?.path == "/api/tasks/task_test" {
                return (
                    200,
                    """
                    {
                      "id": "task_test",
                      "authorized_actions": [
                        {
                          "service": "google.gmail",
                          "action": "*"
                        }
                      ]
                    }
                    """.data(using: .utf8)!
                )
            }
            XCTAssertEqual(request.url?.path, "/api/gateway/request")
            return (
                200,
                """
                {
                  "status": "executed",
                  "result": {
                    "messages": []
                  }
                }
                """.data(using: .utf8)!
            )
        }

        let status = try await client.status()

        XCTAssertTrue(status.connected)
        XCTAssertNil(status.email)
    }

    func testStatusFailsWhenTaskHasNoGmailService() async throws {
        let client = makeClient(
            env: [
                "CLAWVISOR_URL": "https://clawvisor.test",
                "CLAWVISOR_AGENT_TOKEN": "cvis_test",
                "CLAWVISOR_TASK_ID": "task_test",
            ]
        ) { _ in
            (
                200,
                """
                {
                  "id": "task_test",
                  "authorized_actions": [
                    {
                      "service": "google.calendar:studyhan92@gmail.com",
                      "action": "*"
                    }
                  ]
                }
                """.data(using: .utf8)!
            )
        }

        do {
            _ = try await client.status()
            XCTFail("Expected missing Gmail service to fail")
        } catch let error as ZebraClawvisorEmailClientError {
            XCTAssertEqual(
                error.connectionRepairState?.kind,
                .configurationMissing
            )
            XCTAssertTrue(error.localizedDescription.contains("google.gmail"))
        }
    }

    func testOldGmailTaskEnvDoesNotConfigureClient() async throws {
        let client = makeClient(
            env: [
                "CLAWVISOR_URL": "https://clawvisor.test",
                "CLAWVISOR_AGENT_TOKEN": "cvis_test",
                "CLAWVISOR_GMAIL_TASK_ID": "task_test",
                "ZEBRA_CLAWVISOR_GMAIL_ACCOUNT": "studyhan92@gmail.com",
            ]
        ) { _ in
            XCTFail("Old env keys must not trigger a Clawvisor request")
            return (500, Data("{}".utf8))
        }

        do {
            _ = try await client.status()
            XCTFail("Expected missing canonical task id to fail")
        } catch let error as ZebraClawvisorEmailClientError {
            XCTAssertTrue(error.localizedDescription.contains("CLAWVISOR_TASK_ID"))
        }
    }

    private func makeClient(
        env: [String: String],
        handler: @escaping (URLRequest) throws -> (Int, Data)
    ) -> ZebraClawvisorEmailClient {
        ClawvisorMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClawvisorMockURLProtocol.self]
        return ZebraClawvisorEmailClient(
            session: URLSession(configuration: configuration),
            environmentReader: { env },
            dotEnvReader: { [:] }
        )
    }
}

private func requestBodyData(_ request: URLRequest) throws -> Data {
    if let httpBody = request.httpBody {
        return httpBody
    }
    if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
    throw URLError(.zeroByteResource)
}

private final class ClawvisorMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
