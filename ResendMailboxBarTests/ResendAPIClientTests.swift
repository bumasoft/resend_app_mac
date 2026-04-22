import Foundation
import Testing
@testable import ResendMailboxBar

@Suite(.serialized)
struct ResendAPIClientTests {
    @Test
    func listsReceivedEmailsAgainstExpectedEndpoint() async throws {
        let session = try #require(makeMockSession())
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.absoluteString == "https://example.com/emails/receiving")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer re_test")

            let body = """
            {
              "object": "list",
              "has_more": false,
              "data": [
                {
                  "id": "email_123",
                  "from": "sender@example.com",
                  "to": ["team@example.com"],
                  "subject": "Hello",
                  "created_at": "2026-04-03T22:13:42.674981+00:00"
                }
              ]
            }
            """
            return try response(body: body)
        }

        let client = ResendAPIClient(
            apiKey: "re_test",
            session: session,
            baseURL: URL(string: "https://example.com")!
        )

        let emails = try await client.listEmails(in: .received)

        #expect(emails.count == 1)
        #expect(emails.first?.id == "email_123")
        #expect(emails.first?.displaySubject == "Hello")
    }

    @Test
    func updatesScheduledEmailWithPatchAndSnakeCaseBody() async throws {
        let session = try #require(makeMockSession())
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.absoluteString == "https://example.com/emails/msg_123")
            let body = try #require(readRequestBody(from: request))
            let bodyString = try #require(String(data: body, encoding: .utf8))
            #expect(bodyString.contains("\"scheduled_at\""))

            return try response(body: """
            { "id": "msg_123", "object": "email" }
            """)
        }

        let client = ResendAPIClient(
            apiKey: "re_test",
            session: session,
            baseURL: URL(string: "https://example.com")!
        )

        let result = try await client.updateScheduledEmail(id: "msg_123", scheduledAt: "2026-08-05T11:52:01.858Z")
        #expect(result.id == "msg_123")
    }

    @Test
    func surfacesAPIErrors() async throws {
        let session = try #require(makeMockSession())
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com/emails")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = Data(#"{"message":"Invalid API key"}"#.utf8)
            return (response, data)
        }

        let client = ResendAPIClient(
            apiKey: "re_test",
            session: session,
            baseURL: URL(string: "https://example.com")!
        )

        await #expect(throws: ResendAPIError.self) {
            _ = try await client.listEmails(in: .sent)
        }
    }
}

private func readRequestBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
        let readCount = stream.read(buffer, maxLength: bufferSize)
        if readCount <= 0 {
            break
        }
        data.append(buffer, count: readCount)
    }
    return data.isEmpty ? nil : data
}

private func makeMockSession() -> URLSession? {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func response(body: String, statusCode: Int = 200) throws -> (HTTPURLResponse, Data) {
    let url = try #require(URL(string: "https://example.com/test"))
    let response = try #require(
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )
    )
    return (response, Data(body.utf8))
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            fatalError("MockURLProtocol.requestHandler not configured")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
