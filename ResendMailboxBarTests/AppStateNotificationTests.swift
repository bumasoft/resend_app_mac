import Foundation
import Testing
@testable import ResendMailboxBar

@MainActor
@Suite(.serialized)
struct AppStateNotificationTests {
    @Test
    func startupBacklogNotificationsPersistNotifiedIDs() async throws {
        let received = try makeListResponse(emails: [
            makeEmailJSON(id: "msg_3", subject: "Third", createdAt: "2026-04-03T22:15:42.674981+00:00"),
            makeEmailJSON(id: "msg_2", subject: "Second", createdAt: "2026-04-03T22:14:42.674981+00:00"),
            makeEmailJSON(id: "msg_1", subject: "First", createdAt: "2026-04-03T22:13:42.674981+00:00"),
        ])
        let sent = try makeListResponse(emails: [])
        let harness = try makeHarness(
            responsesByPath: [
                "/emails/receiving": [received],
                "/emails": [sent],
                "/emails/receiving/msg_3": [try makeDetailResponse(id: "msg_3", subject: "Third")],
            ]
        )

        await harness.appState.refreshAllMailboxes(userInitiated: false)

        #expect(harness.notifications.batches == [["msg_3", "msg_2", "msg_1"]])
        let state = harness.store.state(for: harness.mailbox.id)
        #expect(state.notifiedReceivedIDs == ["msg_3", "msg_2", "msg_1"])
        #expect(state.lastSeenReceivedIDs == ["msg_3", "msg_2", "msg_1"])
    }

    @Test
    func persistedNotifiedIDsPreventBacklogDuplicates() async throws {
        let received = try makeListResponse(emails: [
            makeEmailJSON(id: "msg_2", subject: "Second", createdAt: "2026-04-03T22:14:42.674981+00:00"),
            makeEmailJSON(id: "msg_1", subject: "First", createdAt: "2026-04-03T22:13:42.674981+00:00"),
        ])
        let sent = try makeListResponse(emails: [])
        let harness = try makeHarness(
            responsesByPath: [
                "/emails/receiving": [received],
                "/emails": [sent],
                "/emails/receiving/msg_2": [try makeDetailResponse(id: "msg_2", subject: "Second")],
            ],
            configureStore: { store, mailbox in
                try store.updateState(for: mailbox.id) { state in
                    state.notifiedReceivedIDs = ["msg_1"]
                }
            }
        )

        await harness.appState.refreshAllMailboxes(userInitiated: false)

        #expect(harness.notifications.batches == [["msg_2"]])
        let state = harness.store.state(for: harness.mailbox.id)
        #expect(state.notifiedReceivedIDs == ["msg_1", "msg_2"])
    }

    @Test
    func userInitiatedRefreshSkipsNotificationsButLaterPollNotifiesNewEmail() async throws {
        let baselineReceived = try makeListResponse(emails: [
            makeEmailJSON(id: "msg_1", subject: "First", createdAt: "2026-04-03T22:13:42.674981+00:00"),
        ])
        let incrementalReceived = try makeListResponse(emails: [
            makeEmailJSON(id: "msg_2", subject: "Second", createdAt: "2026-04-03T22:14:42.674981+00:00"),
            makeEmailJSON(id: "msg_1", subject: "First", createdAt: "2026-04-03T22:13:42.674981+00:00"),
        ])
        let sent = try makeListResponse(emails: [])
        let harness = try makeHarness(
            responsesByPath: [
                "/emails/receiving": [baselineReceived, incrementalReceived],
                "/emails": [sent, sent],
                "/emails/receiving/msg_1": [try makeDetailResponse(id: "msg_1", subject: "First")],
            ]
        )

        await harness.appState.refreshAllMailboxes(userInitiated: true)
        #expect(harness.notifications.batches.isEmpty)

        await harness.appState.refreshAllMailboxes(userInitiated: false)
        #expect(harness.notifications.batches == [["msg_2"]])
    }

    @Test
    func selectingReceivedEmailMarksItReadAndAllowsManualUnreadUntilReopened() async throws {
        let received = try makeListResponse(emails: [
            makeEmailJSON(id: "msg_1", subject: "First", createdAt: "2026-04-03T22:13:42.674981+00:00"),
        ])
        let sent = try makeListResponse(emails: [])
        let detail = try makeDetailResponse(id: "msg_1", subject: "First")
        let harness = try makeHarness(
            responsesByPath: [
                "/emails/receiving": [received],
                "/emails": [sent],
                "/emails/receiving/msg_1": [detail, detail, detail],
            ]
        )

        await harness.appState.refreshAllMailboxes(userInitiated: true)
        await Task.yield()

        await harness.appState.selectEmail(id: "msg_1")
        #expect(harness.appState.isRead("msg_1", mailboxID: harness.mailbox.id))

        harness.appState.toggleRead(emailID: "msg_1", mailboxID: harness.mailbox.id)
        #expect(!harness.appState.isRead("msg_1", mailboxID: harness.mailbox.id))

        await harness.appState.selectEmail(id: "msg_1")
        #expect(harness.appState.isRead("msg_1", mailboxID: harness.mailbox.id))
    }
}

@MainActor
private struct AppStateTestHarness {
    let appState: AppState
    let store: MailboxStore
    let mailbox: MailboxProfile
    let notifications: RecordingNotificationManager
}

@MainActor
private func makeHarness(
    responsesByPath: [String: [Data]],
    configureStore: @MainActor (MailboxStore, MailboxProfile) throws -> Void = { _, _ in }
) throws -> AppStateTestHarness {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = MailboxStore(baseDirectoryURL: directory)
    let mailbox = MailboxProfile(name: "Primary")
    try store.saveMailbox(mailbox)
    try configureStore(store, mailbox)

    let backing = InMemorySecretBacking()
    backing.seed("re_test", account: mailbox.id.uuidString)
    let keychainStore = KeychainStore(backing: backing)
    let notifications = RecordingNotificationManager()
    let responseQueue = ResponseQueue(responsesByPath: responsesByPath)
    let session = makeMockSession(queue: responseQueue)

    let appState = AppState(
        mailboxStore: store,
        keychainStore: keychainStore,
        notificationManager: notifications,
        apiSession: session,
        apiBaseURL: URL(string: "https://example.com")!,
        startMonitoring: false
    )

    return AppStateTestHarness(
        appState: appState,
        store: store,
        mailbox: mailbox,
        notifications: notifications
    )
}

@MainActor
private final class RecordingNotificationManager: NotificationManaging {
    var authorizationRequested = false
    var batches: [[String]] = []

    func requestAuthorization() async {
        authorizationRequested = true
    }

    func notifyNewReceivedEmails(_ emails: [ResendEmailSummary], mailbox: MailboxProfile) async {
        batches.append(emails.map(\.id))
    }
}

private final class ResponseQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var responsesByPath: [String: [Data]]

    init(responsesByPath: [String: [Data]]) {
        self.responsesByPath = responsesByPath
    }

    func nextResponse(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        guard let url = request.url else {
            throw ResponseQueueError.missingURL
        }

        lock.lock()
        defer { lock.unlock() }

        guard var queuedResponses = responsesByPath[url.path], !queuedResponses.isEmpty else {
            throw ResponseQueueError.missingResponse(url.path)
        }

        let data = queuedResponses.removeFirst()
        responsesByPath[url.path] = queuedResponses
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        return (response, data)
    }
}

private enum ResponseQueueError: Error {
    case missingURL
    case missingResponse(String)
}

private func makeMockSession(queue: ResponseQueue) -> URLSession {
    AppStateMockURLProtocol.requestHandler = { request in
        try queue.nextResponse(for: request)
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AppStateMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func makeListResponse(emails: [[String: Any]]) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: [
            "object": "list",
            "has_more": false,
            "data": emails,
        ]
    )
}

private func makeDetailResponse(id: String, subject: String) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: [
            "object": "email",
            "id": id,
            "from": "sender@example.com",
            "to": ["team@example.com"],
            "subject": subject,
            "text": "Body",
            "created_at": "2026-04-03T22:13:42.674981+00:00",
        ]
    )
}

private func makeEmailJSON(id: String, subject: String, createdAt: String) -> [String: Any] {
    [
        "id": id,
        "from": "sender@example.com",
        "to": ["team@example.com"],
        "subject": subject,
        "created_at": createdAt,
    ]
}

final class AppStateMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            fatalError("AppStateMockURLProtocol.requestHandler not configured")
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
