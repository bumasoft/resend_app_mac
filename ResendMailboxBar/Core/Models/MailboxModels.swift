import Foundation
import SwiftUI

enum MailboxFolder: String, CaseIterable, Codable, Hashable, Identifiable {
    case received
    case sent

    var id: Self { self }

    var title: String {
        switch self {
        case .received:
            "Received"
        case .sent:
            "Sent"
        }
    }
}

enum MailboxAccent: String, CaseIterable, Codable, Hashable, Identifiable {
    case blue
    case green
    case orange
    case pink
    case purple
    case slate

    var id: Self { self }

    var color: Color {
        switch self {
        case .blue:
            .blue
        case .green:
            .green
        case .orange:
            .orange
        case .pink:
            .pink
        case .purple:
            .purple
        case .slate:
            .gray
        }
    }
}

struct MailboxProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var symbolName: String
    var accent: MailboxAccent
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = "tray.full",
        accent: MailboxAccent = .blue,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.accent = accent
        self.createdAt = createdAt
    }
}

struct MailboxLocalState: Codable, Hashable {
    var lastRefreshAt: Date?
    var lastSeenReceivedIDs: [String]
    var lastSeenSentIDs: [String]
    var readReceivedIDs: [String]
    var notifiedReceivedIDs: [String]
    var cachedReceivedCount: Int
    var cachedSentCount: Int
    var lastViewedFolder: MailboxFolder

    init(
        lastRefreshAt: Date? = nil,
        lastSeenReceivedIDs: [String] = [],
        lastSeenSentIDs: [String] = [],
        readReceivedIDs: [String] = [],
        notifiedReceivedIDs: [String] = [],
        cachedReceivedCount: Int = 0,
        cachedSentCount: Int = 0,
        lastViewedFolder: MailboxFolder = .received
    ) {
        self.lastRefreshAt = lastRefreshAt
        self.lastSeenReceivedIDs = lastSeenReceivedIDs
        self.lastSeenSentIDs = lastSeenSentIDs
        self.readReceivedIDs = readReceivedIDs
        self.notifiedReceivedIDs = notifiedReceivedIDs
        self.cachedReceivedCount = cachedReceivedCount
        self.cachedSentCount = cachedSentCount
        self.lastViewedFolder = lastViewedFolder
    }

    private enum CodingKeys: String, CodingKey {
        case lastRefreshAt
        case lastSeenReceivedIDs
        case lastSeenSentIDs
        case readReceivedIDs
        case notifiedReceivedIDs
        case cachedReceivedCount
        case cachedSentCount
        case lastViewedFolder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastRefreshAt = try container.decodeIfPresent(Date.self, forKey: .lastRefreshAt)
        lastSeenReceivedIDs = try container.decodeIfPresent([String].self, forKey: .lastSeenReceivedIDs) ?? []
        lastSeenSentIDs = try container.decodeIfPresent([String].self, forKey: .lastSeenSentIDs) ?? []
        readReceivedIDs = try container.decodeIfPresent([String].self, forKey: .readReceivedIDs) ?? []
        notifiedReceivedIDs = try container.decodeIfPresent([String].self, forKey: .notifiedReceivedIDs) ?? []
        cachedReceivedCount = try container.decodeIfPresent(Int.self, forKey: .cachedReceivedCount) ?? 0
        cachedSentCount = try container.decodeIfPresent(Int.self, forKey: .cachedSentCount) ?? 0
        lastViewedFolder = try container.decodeIfPresent(MailboxFolder.self, forKey: .lastViewedFolder) ?? .received
    }
}

struct MailboxSummaryCounts: Hashable {
    var received: Int
    var sent: Int
}

struct ComposeDraft: Equatable {
    var from = ""
    var to = ""
    var cc = ""
    var bcc = ""
    var replyTo = ""
    var subject = ""
    var htmlBody = ""
    var textBody = ""
    var scheduledAtEnabled = false
    var scheduledAt = Date.now.addingTimeInterval(60 * 60)

    static var empty: ComposeDraft { ComposeDraft() }

    mutating func reset() {
        self = .empty
    }

    func makePayload() throws -> SendEmailRequestBody {
        let recipients = Self.tokenize(to)
        guard !from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ComposeDraftError.missingFrom
        }
        guard !recipients.isEmpty else {
            throw ComposeDraftError.missingRecipient
        }
        guard !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ComposeDraftError.missingSubject
        }
        let cleanedHTML = htmlBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedText = textBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedHTML.isEmpty || !cleanedText.isEmpty else {
            throw ComposeDraftError.missingBody
        }

        return SendEmailRequestBody(
            from: from.trimmingCharacters(in: .whitespacesAndNewlines),
            to: recipients,
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            html: cleanedHTML.isEmpty ? nil : cleanedHTML,
            text: cleanedText.isEmpty ? nil : cleanedText,
            cc: Self.tokenize(cc),
            bcc: Self.tokenize(bcc),
            replyTo: Self.tokenize(replyTo),
            scheduledAt: scheduledAtEnabled ? resendScheduleString(from: scheduledAt) : nil
        )
    }

    private static func tokenize(_ text: String) -> [String] {
        text
            .split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum ComposeDraftError: LocalizedError {
    case missingFrom
    case missingRecipient
    case missingSubject
    case missingBody

    var errorDescription: String? {
        switch self {
        case .missingFrom:
            "Add a sender address before sending."
        case .missingRecipient:
            "Add at least one recipient."
        case .missingSubject:
            "Add a subject line."
        case .missingBody:
            "Provide HTML or text content for the message."
        }
    }
}

func resendScheduleString(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
