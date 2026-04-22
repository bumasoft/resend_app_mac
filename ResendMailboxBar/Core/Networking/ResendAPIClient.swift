import Foundation

enum ResendAPIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(status: Int, message: String)
    case emptyResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No Resend API key is configured for this mailbox."
        case .invalidResponse:
            "Resend returned an invalid response."
        case let .requestFailed(status, message):
            "Resend request failed (\(status)): \(message)"
        case .emptyResponse:
            "Resend returned an empty response."
        case let .transport(message):
            message
        }
    }
}

struct ResendAPIClient {
    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        apiKey: String,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.resend.com")!
    ) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .resendFlexible

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func listEmails(in folder: MailboxFolder) async throws -> [ResendEmailSummary] {
        let response: ResendListResponse<ResendEmailSummary> = try await sendRequest(
            path: folder.listPath,
            method: "GET"
        )
        return response.data
    }

    func getEmail(_ id: String, in folder: MailboxFolder) async throws -> ResendEmailDetails {
        try await sendRequest(path: folder.emailPath(for: id), method: "GET")
    }

    func listAttachments(emailID: String, in folder: MailboxFolder) async throws -> [ResendAttachment] {
        let response: ResendListResponse<ResendAttachment> = try await sendRequest(
            path: folder.attachmentsPath(for: emailID),
            method: "GET"
        )
        return response.data
    }

    func getAttachment(id: String, emailID: String, in folder: MailboxFolder) async throws -> ResendAttachment {
        try await sendRequest(path: folder.attachmentPath(emailID: emailID, attachmentID: id), method: "GET")
    }

    func sendEmail(_ payload: SendEmailRequestBody) async throws -> ResendMutationResponse {
        try await sendRequest(path: "/emails", method: "POST", body: payload)
    }

    func updateScheduledEmail(id: String, scheduledAt: String) async throws -> ResendMutationResponse {
        try await sendRequest(
            path: "/emails/\(id)",
            method: "PATCH",
            body: UpdateEmailRequestBody(scheduledAt: scheduledAt)
        )
    }

    func cancelScheduledEmail(id: String) async throws -> ResendMutationResponse {
        try await sendRequest(path: "/emails/\(id)/cancel", method: "POST")
    }

    private func sendRequest<Response: Decodable>(
        path: String,
        method: String
    ) async throws -> Response {
        try await sendRequest(path: path, method: method, body: Optional<String>.none)
    }

    private func sendRequest<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body? = nil
    ) async throws -> Response {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ResendAPIError.missingAPIKey
        }

        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ResendAPIError.invalidResponse
            }

            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                let message = decodeErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                throw ResendAPIError.requestFailed(status: httpResponse.statusCode, message: message)
            }

            guard !data.isEmpty else {
                throw ResendAPIError.emptyResponse
            }

            return try decoder.decode(Response.self, from: data)
        } catch let error as ResendAPIError {
            throw error
        } catch {
            throw ResendAPIError.transport(error.localizedDescription)
        }
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        (try? decoder.decode(ResendErrorResponse.self, from: data).message)?.nonEmpty
            ?? String(data: data, encoding: .utf8)?.nonEmpty
    }
}

private extension MailboxFolder {
    var listPath: String {
        switch self {
        case .received:
            "/emails/receiving"
        case .sent:
            "/emails"
        }
    }

    func emailPath(for emailID: String) -> String {
        switch self {
        case .received:
            "/emails/receiving/\(emailID)"
        case .sent:
            "/emails/\(emailID)"
        }
    }

    func attachmentsPath(for emailID: String) -> String {
        switch self {
        case .received:
            "/emails/receiving/\(emailID)/attachments"
        case .sent:
            "/emails/\(emailID)/attachments"
        }
    }

    func attachmentPath(emailID: String, attachmentID: String) -> String {
        switch self {
        case .received:
            "/emails/receiving/\(emailID)/attachments/\(attachmentID)"
        case .sent:
            "/emails/\(emailID)/attachments/\(attachmentID)"
        }
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static let resendFlexible: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        for formatter in ResendDateParser.allFormatters() {
            if let date = formatter.date(from: value) {
                return date
            }
        }

        if let date = ResendDateParser.iso8601WithFractional().date(from: value)
            ?? ResendDateParser.iso8601().date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported Resend date string: \(value)"
        )
    }
}

enum ResendDateParser {
    static func iso8601WithFractional() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func iso8601() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    static func allFormatters() -> [DateFormatter] {
        [
            makeFormatter("yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX"),
            makeFormatter("yyyy-MM-dd HH:mm:ssXXXXX"),
            makeFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"),
            makeFormatter("yyyy-MM-dd'T'HH:mm:ssXXXXX"),
        ]
    }

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}
