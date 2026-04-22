import Foundation
import Observation
import UserNotifications

@MainActor
protocol NotificationManaging {
    func requestAuthorization() async
    func notifyNewReceivedEmails(_ emails: [ResendEmailSummary], mailbox: MailboxProfile) async
}

struct NotificationRoutePayload: Equatable {
    static let mailboxIDKey = "mailboxID"
    static let emailIDKey = "emailID"

    let mailboxID: UUID
    let emailID: String

    init(mailboxID: UUID, emailID: String) {
        self.mailboxID = mailboxID
        self.emailID = emailID
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard
            let mailboxIDValue = userInfo[Self.mailboxIDKey] as? String,
            let mailboxID = UUID(uuidString: mailboxIDValue),
            let emailID = userInfo[Self.emailIDKey] as? String,
            !emailID.isEmpty
        else {
            return nil
        }

        self.init(mailboxID: mailboxID, emailID: emailID)
    }

    var userInfo: [AnyHashable: Any] {
        [
            Self.mailboxIDKey: mailboxID.uuidString,
            Self.emailIDKey: emailID,
        ]
    }
}

/// How a refresh should interact with the notification tracking state.
enum RefreshNotificationMode {
    /// Notify for any received email not yet notified (polling / background refresh).
    case notify
    /// Don't notify, but treat current received emails as already-seen so they won't notify later
    /// (e.g. user manually refreshed or opened a mailbox and is looking at the list).
    case markSeen
    /// Don't notify and don't modify seen tracking (side-effect refresh after send/cancel/etc.).
    case ignore
}

@MainActor
@Observable
final class AppState {
    var mailboxes: [MailboxProfile]
    var selectedMailboxID: UUID?
    var selectedFolder: MailboxFolder
    var emailSummaries: [ResendEmailSummary] = []
    var selectedEmailID: String?
    var selectedEmailDetails: ResendEmailDetails?
    var composeDraft: ComposeDraft = .empty
    var isRefreshing = false
    var isLoadingEmailDetails = false
    var isSending = false
    var errorMessage: String?
    var lastRefreshAt: Date?
    private var mailboxStateRevision = 0

    private let mailboxStore: MailboxStore
    private let keychainStore: KeychainStore
    private let notificationManager: any NotificationManaging
    private let apiSession: URLSession
    private let apiBaseURL: URL
    private var snapshots: [UUID: MailboxSnapshot] = [:]
    private var newReceivedIDsByMailbox: [UUID: Set<String>] = [:]
    private var pollingTask: Task<Void, Never>?

    init(
        mailboxStore: MailboxStore = MailboxStore(),
        keychainStore: KeychainStore = KeychainStore(),
        notificationManager: any NotificationManaging = NotificationManager(),
        apiSession: URLSession = .shared,
        apiBaseURL: URL = URL(string: "https://api.resend.com")!,
        startMonitoring: Bool = true
    ) {
        self.mailboxStore = mailboxStore
        self.keychainStore = keychainStore
        self.notificationManager = notificationManager
        self.apiSession = apiSession
        self.apiBaseURL = apiBaseURL
        self.mailboxes = mailboxStore.mailboxes
        let initialMailboxID = mailboxStore.selectedMailboxID ?? mailboxStore.mailboxes.first?.id
        self.selectedMailboxID = initialMailboxID
        self.selectedFolder = mailboxStore.state(for: initialMailboxID ?? UUID()).lastViewedFolder

        syncVisibleState()
        if startMonitoring {
            startPolling()
            Task {
                await notificationManager.requestAuthorization()
                await refreshAllMailboxes(userInitiated: false)
            }
        }
    }

    var selectedMailbox: MailboxProfile? {
        guard let selectedMailboxID else { return nil }
        return mailboxes.first(where: { $0.id == selectedMailboxID })
    }

    var hasMailboxes: Bool {
        !mailboxes.isEmpty
    }

    var currentRecentEmails: [ResendEmailSummary] {
        Array(emailSummaries.prefix(5))
    }

    var menuBarSymbolName: String {
        unreadReceivedCount(for: selectedMailboxID) > 0 ? "tray.and.arrow.down.fill" : "tray.full"
    }

    func summaryCounts(for mailboxID: UUID?) -> MailboxSummaryCounts {
        guard let mailboxID else {
            return MailboxSummaryCounts(received: 0, sent: 0)
        }
        let state = mailboxStore.state(for: mailboxID)
        return MailboxSummaryCounts(received: state.cachedReceivedCount, sent: state.cachedSentCount)
    }

    func newReceivedCount(for mailboxID: UUID?) -> Int {
        guard let mailboxID else { return 0 }
        return newReceivedIDsByMailbox[mailboxID]?.count ?? 0
    }

    func unreadReceivedCount(for mailboxID: UUID?) -> Int {
        guard let mailboxID else { return 0 }
        let _ = mailboxStateRevision
        let state = mailboxStore.state(for: mailboxID)
        let readReceivedIDs = Set(state.readReceivedIDs)

        if let snapshot = snapshots[mailboxID] {
            return snapshot.received.reduce(into: 0) { count, email in
                if !readReceivedIDs.contains(email.id) {
                    count += 1
                }
            }
        }

        return max(state.cachedReceivedCount - readReceivedIDs.count, 0)
    }

    func isRecentlyReceived(_ emailID: String, mailboxID: UUID?) -> Bool {
        guard let mailboxID else { return false }
        return newReceivedIDsByMailbox[mailboxID]?.contains(emailID) == true
    }

    func isRead(_ emailID: String, mailboxID: UUID?) -> Bool {
        guard let mailboxID else { return true }
        let _ = mailboxStateRevision
        return mailboxStore.state(for: mailboxID).readReceivedIDs.contains(emailID)
    }

    func isUnreadReceived(_ emailID: String, mailboxID: UUID?) -> Bool {
        guard mailboxID != nil else { return false }
        return !isRead(emailID, mailboxID: mailboxID)
    }

    func setRead(_ read: Bool, emailID: String, mailboxID: UUID?) {
        guard let mailboxID else { return }

        do {
            try mailboxStore.updateState(for: mailboxID) { state in
                if read {
                    state.readReceivedIDs = Self.mergedIDs(existing: state.readReceivedIDs, appending: [emailID])
                } else {
                    state.readReceivedIDs.removeAll { $0 == emailID }
                }
            }
            if read {
                newReceivedIDsByMailbox[mailboxID]?.remove(emailID)
            }
            touchMailboxState()
        } catch {
            present(error: error.localizedDescription)
        }
    }

    func toggleRead(emailID: String, mailboxID: UUID?) {
        setRead(!isRead(emailID, mailboxID: mailboxID), emailID: emailID, mailboxID: mailboxID)
    }

    func saveMailbox(
        id: UUID?,
        name: String,
        symbolName: String,
        accent: MailboxAccent,
        apiKey: String
    ) throws -> UUID {
        let profile = MailboxProfile(
            id: id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            symbolName: symbolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "tray.full" : symbolName,
            accent: accent,
            createdAt: existingMailbox(id: id)?.createdAt ?? .now
        )

        try mailboxStore.saveMailbox(profile)
        try keychainStore.setAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: profile.id)

        mailboxes = mailboxStore.mailboxes
        if selectedMailboxID == nil {
            selectedMailboxID = profile.id
        }
        mailboxStore.selectedMailboxID = selectedMailboxID
        if selectedMailboxID == profile.id {
            selectedFolder = mailboxStore.state(for: profile.id).lastViewedFolder
        }

        return profile.id
    }

    func deleteMailbox(id: UUID) throws {
        try mailboxStore.removeMailbox(id: id)
        try keychainStore.removeAPIKey(for: id)
        snapshots.removeValue(forKey: id)
        newReceivedIDsByMailbox.removeValue(forKey: id)
        mailboxes = mailboxStore.mailboxes
        selectedMailboxID = mailboxStore.selectedMailboxID
        syncVisibleState()
    }

    func selectMailbox(_ mailboxID: UUID) {
        selectedMailboxID = mailboxID
        mailboxStore.selectedMailboxID = mailboxID
        selectedFolder = mailboxStore.state(for: mailboxID).lastViewedFolder
        syncVisibleState()

        if snapshots[mailboxID] == nil {
            Task { await refreshMailbox(mailboxID: mailboxID, mode: .markSeen) }
        }
    }

    func selectFolder(_ folder: MailboxFolder) {
        selectedFolder = folder
        if let selectedMailboxID {
            try? mailboxStore.updateState(for: selectedMailboxID) { state in
                state.lastViewedFolder = folder
            }
        }
        syncVisibleState()
    }

    func selectEmail(id: String?) async {
        selectedEmailID = id
        await loadSelectedEmailDetails(markReadOnSuccess: true)
    }

    func openReceivedEmail(mailboxID: UUID, emailID: String) async {
        guard mailboxes.contains(where: { $0.id == mailboxID }) else { return }
        selectMailbox(mailboxID)
        selectFolder(.received)
        await selectEmail(id: emailID)
    }

    func refreshAllMailboxes(userInitiated: Bool) async {
        guard !mailboxes.isEmpty else {
            snapshots = [:]
            emailSummaries = []
            selectedEmailID = nil
            selectedEmailDetails = nil
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let mode: RefreshNotificationMode = userInitiated ? .markSeen : .notify
        var firstErrorForSelection: String?
        for mailbox in mailboxes {
            do {
                try await refreshSnapshot(for: mailbox, mode: mode)
            } catch {
                if mailbox.id == selectedMailboxID, firstErrorForSelection == nil {
                    firstErrorForSelection = error.localizedDescription
                }
            }
        }

        syncVisibleState()
        if let firstErrorForSelection {
            present(error: firstErrorForSelection)
        }
    }

    func refreshMailbox(mailboxID: UUID, mode: RefreshNotificationMode) async {
        guard let mailbox = mailboxes.first(where: { $0.id == mailboxID }) else { return }
        do {
            try await refreshSnapshot(for: mailbox, mode: mode)
            syncVisibleState()
        } catch {
            if mailboxID == selectedMailboxID {
                present(error: error.localizedDescription)
            }
        }
    }

    func prepareNewDraft() {
        composeDraft.reset()
    }

    func sendCurrentDraft() async -> Bool {
        guard let mailbox = selectedMailbox else {
            present(error: "Create a mailbox before sending email.")
            return false
        }

        do {
            let payload = try composeDraft.makePayload()
            let client = try client(for: mailbox)
            isSending = true
            defer { isSending = false }

            _ = try await client.sendEmail(payload)
            composeDraft.reset()
            await refreshMailbox(mailboxID: mailbox.id, mode: .ignore)
            return true
        } catch {
            present(error: error.localizedDescription)
            return false
        }
    }

    func loadSelectedEmailDetails(markReadOnSuccess: Bool = false) async {
        guard let mailbox = selectedMailbox, let selectedEmailID else {
            selectedEmailDetails = nil
            return
        }

        isLoadingEmailDetails = true
        defer { isLoadingEmailDetails = false }

        do {
            let client = try client(for: mailbox)
            let details = try await client.getEmail(selectedEmailID, in: selectedFolder)
            selectedEmailDetails = details
            if markReadOnSuccess, selectedFolder == .received {
                setRead(true, emailID: details.id, mailboxID: mailbox.id)
            }
        } catch {
            present(error: error.localizedDescription)
        }
    }

    func updateScheduleForSelectedEmail(to date: Date) async {
        guard let mailbox = selectedMailbox, let selectedEmailID else { return }

        do {
            let client = try client(for: mailbox)
            _ = try await client.updateScheduledEmail(
                id: selectedEmailID,
                scheduledAt: resendScheduleString(from: date)
            )
            await refreshMailbox(mailboxID: mailbox.id, mode: .ignore)
            await loadSelectedEmailDetails()
        } catch {
            present(error: error.localizedDescription)
        }
    }

    func cancelSelectedEmail() async {
        guard let mailbox = selectedMailbox, let selectedEmailID else { return }

        do {
            let client = try client(for: mailbox)
            _ = try await client.cancelScheduledEmail(id: selectedEmailID)
            await refreshMailbox(mailboxID: mailbox.id, mode: .ignore)
            await loadSelectedEmailDetails()
        } catch {
            present(error: error.localizedDescription)
        }
    }

    func resolvedAttachmentURL(for attachment: ResendAttachment) async throws -> URL {
        if let url = attachment.url {
            return url
        }
        guard let mailbox = selectedMailbox, let selectedEmailID else {
            throw ResendAPIError.invalidResponse
        }
        let client = try client(for: mailbox)
        let fetched = try await client.getAttachment(id: attachment.id, emailID: selectedEmailID, in: selectedFolder)
        guard let url = fetched.url else {
            throw ResendAPIError.invalidResponse
        }
        return url
    }

    func testConnection(apiKey: String) async throws {
        let client = ResendAPIClient(apiKey: apiKey, session: apiSession, baseURL: apiBaseURL)
        _ = try await client.listEmails(in: .sent)
    }

    func keychainValue(for mailboxID: UUID) throws -> String? {
        try keychainStore.apiKey(for: mailboxID)
    }

    private func existingMailbox(id: UUID?) -> MailboxProfile? {
        guard let id else { return nil }
        return mailboxes.first(where: { $0.id == id })
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { break }
                await self.refreshAllMailboxes(userInitiated: false)
            }
        }
    }

    private func refreshSnapshot(for mailbox: MailboxProfile, mode: RefreshNotificationMode) async throws {
        let client = try client(for: mailbox)

        async let received = client.listEmails(in: .received)
        async let sent = client.listEmails(in: .sent)

        let snapshot = MailboxSnapshot(
            received: try await received.sorted(by: Self.sortEmailsNewestFirst),
            sent: try await sent.sorted(by: Self.sortEmailsNewestFirst)
        )

        let previousState = mailboxStore.state(for: mailbox.id)
        let previousSeenReceived = Set(previousState.lastSeenReceivedIDs)
        let previouslyNotified = Set(previousState.notifiedReceivedIDs)

        // UI "new" indicator: anything in the current snapshot that wasn't in the previous one.
        let newlyDiscoveredReceived = previousSeenReceived.isEmpty
            ? snapshot.received
            : snapshot.received.filter { !previousSeenReceived.contains($0.id) }

        // Notification eligibility is gated solely by whether we've already notified for this ID.
        // This avoids races where a side-effect refresh (e.g. after sending) quietly populates
        // lastSeenReceivedIDs with a freshly arrived email and suppresses the next poll's notification.
        let notificationCandidates = snapshot.received.filter { !previouslyNotified.contains($0.id) }

        let emailsToNotify: [ResendEmailSummary]
        let idsToMarkNotified: [String]
        switch mode {
        case .notify:
            emailsToNotify = Array(notificationCandidates.prefix(Self.notificationBatchLimit))
            idsToMarkNotified = emailsToNotify.map(\.id)
        case .markSeen:
            emailsToNotify = []
            idsToMarkNotified = snapshot.received.map(\.id)
        case .ignore:
            emailsToNotify = []
            idsToMarkNotified = []
        }

        snapshots[mailbox.id] = snapshot
        newReceivedIDsByMailbox[mailbox.id] = Set(newlyDiscoveredReceived.map(\.id))
        lastRefreshAt = .now

        try mailboxStore.updateState(for: mailbox.id) { state in
            state.lastRefreshAt = .now
            state.lastSeenReceivedIDs = snapshot.received.map(\.id)
            state.lastSeenSentIDs = snapshot.sent.map(\.id)
            state.notifiedReceivedIDs = Self.mergedIDs(
                existing: state.notifiedReceivedIDs,
                appending: idsToMarkNotified
            )
            state.cachedReceivedCount = snapshot.received.count
            state.cachedSentCount = snapshot.sent.count
            if mailbox.id == selectedMailboxID {
                state.lastViewedFolder = selectedFolder
            }
        }

        if !emailsToNotify.isEmpty {
            await notificationManager.notifyNewReceivedEmails(emailsToNotify, mailbox: mailbox)
        }
    }

    private func client(for mailbox: MailboxProfile) throws -> ResendAPIClient {
        guard let apiKey = try keychainStore.apiKey(for: mailbox.id) else {
            throw ResendAPIError.missingAPIKey
        }
        return ResendAPIClient(apiKey: apiKey, session: apiSession, baseURL: apiBaseURL)
    }

    private func syncVisibleState() {
        guard let selectedMailboxID else {
            emailSummaries = []
            selectedEmailID = nil
            selectedEmailDetails = nil
            return
        }

        let snapshot = snapshots[selectedMailboxID]
        switch selectedFolder {
        case .received:
            emailSummaries = snapshot?.received ?? []
        case .sent:
            emailSummaries = snapshot?.sent ?? []
        }

        guard !emailSummaries.isEmpty else {
            selectedEmailID = nil
            selectedEmailDetails = nil
            return
        }

        if let selectedEmailID, emailSummaries.contains(where: { $0.id == selectedEmailID }) {
            return
        }

        selectedEmailID = emailSummaries.first?.id
        Task { await loadSelectedEmailDetails(markReadOnSuccess: false) }
    }

    private func present(error: String) {
        errorMessage = error
    }

    private func touchMailboxState() {
        mailboxStateRevision += 1
    }

    private static func sortEmailsNewestFirst(lhs: ResendEmailSummary, rhs: ResendEmailSummary) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
        case let (.some(left), .some(right)):
            return left > right
        case (.some, nil):
            return true
        default:
            return false
        }
    }

    private static func mergedIDs(existing: [String], appending newIDs: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []

        for id in existing + newIDs where seen.insert(id).inserted {
            merged.append(id)
        }

        return merged
    }

    private static let notificationBatchLimit = 3
}

private struct MailboxSnapshot {
    var received: [ResendEmailSummary]
    var sent: [ResendEmailSummary]
}

@MainActor
struct NotificationManager: NotificationManaging {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.badge, .alert, .sound])
    }

    func notifyNewReceivedEmails(_ emails: [ResendEmailSummary], mailbox: MailboxProfile) async {
        for email in emails {
            let content = UNMutableNotificationContent()
            content.title = email.displaySubject
            content.subtitle = mailbox.name
            content.body = email.displayParticipants
            content.sound = .default
            content.userInfo = NotificationRoutePayload(mailboxID: mailbox.id, emailID: email.id).userInfo

            let request = UNNotificationRequest(
                identifier: "\(mailbox.id.uuidString)-\(email.id)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}
