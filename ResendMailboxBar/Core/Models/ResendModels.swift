import Foundation

struct ResendListResponse<Item: Decodable>: Decodable {
    var object: String?
    var hasMore: Bool
    var data: [Item]

    private enum CodingKeys: String, CodingKey {
        case object
        case hasMore = "has_more"
        case data
    }
}

struct ResendEmailSummary: Identifiable, Decodable, Hashable {
    var id: String
    var to: [String]?
    var from: String?
    var createdAt: Date?
    var subject: String?
    var bcc: [String]?
    var cc: [String]?
    var replyTo: [String]?
    var messageId: String?
    var lastEvent: String?
    var scheduledAt: String?
    var attachments: [ResendAttachment]?

    private enum CodingKeys: String, CodingKey {
        case id
        case to
        case from
        case createdAt = "created_at"
        case subject
        case bcc
        case cc
        case replyTo = "reply_to"
        case messageId = "message_id"
        case lastEvent = "last_event"
        case scheduledAt = "scheduled_at"
        case attachments
    }
}

struct ResendEmailDetails: Identifiable, Decodable, Hashable {
    var object: String?
    var id: String
    var to: [String]?
    var from: String?
    var createdAt: Date?
    var subject: String?
    var html: String?
    var text: String?
    var headers: [String: String]?
    var bcc: [String]?
    var cc: [String]?
    var replyTo: [String]?
    var messageId: String?
    var lastEvent: String?
    var scheduledAt: String?
    var raw: ResendRawEmail?
    var attachments: [ResendAttachment]?

    private enum CodingKeys: String, CodingKey {
        case object
        case id
        case to
        case from
        case createdAt = "created_at"
        case subject
        case html
        case text
        case headers
        case bcc
        case cc
        case replyTo = "reply_to"
        case messageId = "message_id"
        case lastEvent = "last_event"
        case scheduledAt = "scheduled_at"
        case raw
        case attachments
    }
}

struct ResendAttachment: Identifiable, Decodable, Hashable {
    var id: String
    var filename: String?
    var size: Int?
    var contentType: String?
    var contentDisposition: String?
    var contentId: String?
    var url: URL?
    var expiresAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case filename
        case size
        case contentType = "content_type"
        case contentDisposition = "content_disposition"
        case contentId = "content_id"
        case url
        case expiresAt = "expires_at"
    }
}

struct ResendRawEmail: Decodable, Hashable {
    var downloadURL: URL?
    var expiresAt: Date?

    private enum CodingKeys: String, CodingKey {
        case downloadURL = "download_url"
        case expiresAt = "expires_at"
    }
}

struct ResendMutationResponse: Decodable, Hashable {
    var id: String
    var object: String?
}

struct SendEmailRequestBody: Encodable {
    var from: String
    var to: [String]
    var subject: String
    var html: String?
    var text: String?
    var cc: [String]?
    var bcc: [String]?
    var replyTo: [String]?
    var scheduledAt: String?
}

struct UpdateEmailRequestBody: Encodable {
    var scheduledAt: String
}

struct ResendErrorResponse: Decodable {
    var name: String?
    var message: String?
    var statusCode: Int?
}

extension ResendEmailSummary {
    var displaySubject: String {
        subject?.nonEmpty ?? "(No subject)"
    }

    var displayParticipants: String {
        switch (from?.nonEmpty, to?.compactMap(\.nonEmpty)) {
        case let (.some(sender), .some(recipients)) where !recipients.isEmpty:
            "\(sender) -> \(recipients.joined(separator: ", "))"
        case let (.some(sender), _):
            sender
        case let (_, .some(recipients)) where !recipients.isEmpty:
            recipients.joined(separator: ", ")
        default:
            "No participants"
        }
    }

    var displayTimestamp: String {
        guard let createdAt else { return "Unknown time" }
        return mailboxTimestampString(from: createdAt)
    }
}

extension ResendEmailDetails {
    var displaySubject: String {
        subject?.nonEmpty ?? "(No subject)"
    }

    var participantSummary: [(String, String)] {
        [
            ("From", from?.nonEmpty ?? "Unknown"),
            ("To", to?.joined(separator: ", ").nonEmpty ?? "Unknown"),
            ("Cc", cc?.joined(separator: ", ").nonEmpty ?? "-"),
            ("Bcc", bcc?.joined(separator: ", ").nonEmpty ?? "-"),
            ("Reply-To", replyTo?.joined(separator: ", ").nonEmpty ?? "-"),
        ]
    }
}

func mailboxTimestampString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
