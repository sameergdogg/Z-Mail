import Foundation
import GoogleSignIn

// MARK: - Gmail API Data Models

public struct GmailMessageList: Codable {
    public let messages: [GmailMessageInfo]?
    public let nextPageToken: String?
    public let resultSizeEstimate: Int?
}

public struct GmailMessageInfo: Codable {
    public let id: String
    public let threadId: String
}

public struct GmailMessage: Codable {
    public let id: String
    public let threadId: String?
    public let labelIds: [String]?
    public let snippet: String?
    public let payload: GmailPayload?
    public let sizeEstimate: Int?
    public let historyId: String?
    public let internalDate: String?
}

public struct GmailPayload: Codable {
    public let mimeType: String?
    public let headers: [GmailHeader]?
    public let body: GmailBody?
    public let parts: [GmailPart]?

    public init(mimeType: String?, headers: [GmailHeader]?, body: GmailBody?, parts: [GmailPart]?) {
        self.mimeType = mimeType
        self.headers = headers
        self.body = body
        self.parts = parts
    }
}

public struct GmailHeader: Codable {
    public let name: String
    public let value: String
}

public struct GmailBody: Codable {
    public let size: Int?
    public let data: String?
}

public struct GmailPart: Codable {
    public let mimeType: String?
    public let headers: [GmailHeader]?
    public let body: GmailBody?
    public let parts: [GmailPart]?
}

public struct GmailModifyRequest: Codable {
    public let addLabelIds: [String]?
    public let removeLabelIds: [String]?
}

public struct GmailLabels {
    public static let unread = "UNREAD"
    public static let starred = "STARRED"
    public static let inbox = "INBOX"
    public static let sent = "SENT"
    public static let draft = "DRAFT"
    public static let trash = "TRASH"
    public static let spam = "SPAM"
    public static let important = "IMPORTANT"
}

// MARK: - Gmail API Errors

public enum GmailAPIError: Error, LocalizedError {
    case noAccessToken
    case invalidURL
    case networkError
    case decodingError
    case authenticationFailed
    case rateLimitExceeded
    case messageNotFound
    case attachmentNotFound

    public var errorDescription: String? {
        switch self {
        case .noAccessToken: return "No access token available"
        case .invalidURL: return "Invalid URL for Gmail API request"
        case .networkError: return "Network error occurred"
        case .decodingError: return "Failed to decode Gmail API response"
        case .authenticationFailed: return "Authentication with Gmail API failed"
        case .rateLimitExceeded: return "Gmail API rate limit exceeded"
        case .messageNotFound: return "Message not found"
        case .attachmentNotFound: return "Attachment not found"
        }
    }
}

// MARK: - GmailAPIService

/// Communicates with the Gmail REST API.
/// Replaces the Frameworks/GmailAPIService/ three-layer pattern.
class GmailAPIService {

    private let baseURL = "https://gmail.googleapis.com/gmail/v1"
    private let urlSession = URLSession.shared
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    init() {}

    // MARK: - Public Methods

    func fetchMessages(for user: GIDGoogleUser, maxResults: Int = 50) async throws -> [GmailMessage] {
        print("GmailAPIService.fetchMessages() for: \(user.profile?.email ?? "unknown")")

        let urlString = makeMessagesURL(maxResults: maxResults)
        let messageList: GmailMessageList = try await makeAPIRequest(
            for: user, urlString: urlString
        )

        var messages: [GmailMessage] = []
        for info in messageList.messages ?? [] {
            do {
                let full = try await fetchFullMessage(messageId: info.id, user: user)
                messages.append(full)
            } catch {
                print("Failed to fetch message \(info.id): \(error)")
            }
        }
        return messages
    }

    func convertGmailMessageToEmail(_ gmailMessage: GmailMessage, accountEmail: String) -> Email {
        let headers = gmailMessage.payload?.headers ?? []

        let subject = headers.first { $0.name == "Subject" }?.value ?? "No Subject"
        let fromHeader = headers.first { $0.name == "From" }?.value ?? ""
        let toHeader = headers.first { $0.name == "To" }?.value ?? ""
        let dateHeader = headers.first { $0.name == "Date" }?.value ?? ""

        let sender = parseEmailAddress(fromHeader)
        let recipients = parseEmailAddresses(toHeader)
        let date = parseDate(dateHeader)

        let (plainBody, htmlBody, isHTMLContent) = extractBodies(from: gmailMessage.payload)
        let attachments = extractAttachments(from: gmailMessage.payload, messageId: gmailMessage.id)

        var labels = gmailMessage.labelIds ?? []
        if EmailSecurityPinDetector.containsSecurityPin(in: plainBody) && !labels.contains("security_pin") {
            labels.append("security_pin")
        }

        let isUnread = labels.contains(GmailLabels.unread)
        let isStarred = labels.contains(GmailLabels.starred)

        return Email(
            id: gmailMessage.id,
            subject: subject,
            sender: sender,
            recipients: recipients,
            body: plainBody,
            htmlBody: htmlBody,
            date: date,
            isRead: !isUnread,
            isStarred: isStarred,
            labels: labels,
            accountEmail: accountEmail,
            threadId: gmailMessage.threadId,
            attachments: attachments,
            isHTMLContent: isHTMLContent
        )
    }

    func markMessageAsRead(messageId: String, user: GIDGoogleUser) async throws {
        let modifyRequest = GmailModifyRequest(addLabelIds: nil, removeLabelIds: [GmailLabels.unread])
        try await modifyMessage(messageId: messageId, user: user, request: modifyRequest)
    }

    func toggleMessageStar(messageId: String, user: GIDGoogleUser, isStarred: Bool) async throws {
        let modifyRequest: GmailModifyRequest
        if isStarred {
            modifyRequest = GmailModifyRequest(addLabelIds: [GmailLabels.starred], removeLabelIds: nil)
        } else {
            modifyRequest = GmailModifyRequest(addLabelIds: nil, removeLabelIds: [GmailLabels.starred])
        }
        try await modifyMessage(messageId: messageId, user: user, request: modifyRequest)
    }

    func fetchAttachment(messageId: String, attachmentId: String, user: GIDGoogleUser) async throws -> String {
        let urlString = "\(baseURL)/users/me/messages/\(messageId)/attachments/\(attachmentId)"
        let attachment: GmailBody = try await makeAPIRequest(for: user, urlString: urlString)
        return attachment.data ?? ""
    }

    // MARK: - Private: HTTP helpers

    private func fetchFullMessage(messageId: String, user: GIDGoogleUser) async throws -> GmailMessage {
        let urlString = "\(baseURL)/users/me/messages/\(messageId)"
        return try await makeAPIRequest(for: user, urlString: urlString)
    }

    private func modifyMessage(messageId: String, user: GIDGoogleUser, request: GmailModifyRequest) async throws {
        let urlString = "\(baseURL)/users/me/messages/\(messageId)/modify"
        let body = try jsonEncoder.encode(request)
        try await makeVoidAPIRequest(for: user, urlString: urlString, httpMethod: "POST",
                                     requestBody: body, contentType: "application/json")
    }

    private func makeAPIRequest<T: Decodable>(
        for user: GIDGoogleUser,
        urlString: String,
        httpMethod: String = "GET",
        requestBody: Data? = nil,
        contentType: String? = nil
    ) async throws -> T {
        guard let url = URL(string: urlString) else { throw GmailAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("Bearer \(user.accessToken.tokenString)", forHTTPHeaderField: "Authorization")
        if let body = requestBody { request.httpBody = body }
        if let ct = contentType { request.setValue(ct, forHTTPHeaderField: "Content-Type") }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.networkError
        }

        switch httpResponse.statusCode {
        case 200: break
        case 401: throw GmailAPIError.authenticationFailed
        case 404: throw GmailAPIError.messageNotFound
        case 429: throw GmailAPIError.rateLimitExceeded
        default: throw GmailAPIError.networkError
        }

        return try jsonDecoder.decode(T.self, from: data)
    }

    private func makeVoidAPIRequest(
        for user: GIDGoogleUser,
        urlString: String,
        httpMethod: String = "POST",
        requestBody: Data? = nil,
        contentType: String? = nil
    ) async throws {
        guard let url = URL(string: urlString) else { throw GmailAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("Bearer \(user.accessToken.tokenString)", forHTTPHeaderField: "Authorization")
        if let body = requestBody { request.httpBody = body }
        if let ct = contentType { request.setValue(ct, forHTTPHeaderField: "Content-Type") }

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.networkError
        }

        switch httpResponse.statusCode {
        case 200: break
        case 401: throw GmailAPIError.authenticationFailed
        case 404: throw GmailAPIError.messageNotFound
        case 429: throw GmailAPIError.rateLimitExceeded
        default: throw GmailAPIError.networkError
        }
    }

    private func makeMessagesURL(maxResults: Int) -> String {
        return "\(baseURL)/users/me/messages?maxResults=\(maxResults)"
    }

    // MARK: - Email parsing helpers

    func parseEmailAddress(_ emailString: String) -> EmailAddress {
        let pattern = #"^(.*?)\s*<(.+)>$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: emailString, range: NSRange(emailString.startIndex..., in: emailString)) {
            let nameRange = Range(match.range(at: 1), in: emailString)
            let emailRange = Range(match.range(at: 2), in: emailString)

            let name = nameRange.map { String(emailString[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
            let email = emailRange.map { String(emailString[$0]) } ?? emailString

            return EmailAddress(name: name?.isEmpty == false ? name : nil, email: email)
        }
        return EmailAddress(name: nil, email: emailString)
    }

    func parseEmailAddresses(_ emailString: String) -> [EmailAddress] {
        return emailString.components(separatedBy: ",")
            .map { parseEmailAddress($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    func parseDate(_ dateString: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) { return date }
        }
        return Date()
    }

    // MARK: - Body extraction helpers

    func extractBodies(from payload: GmailPayload?) -> (plain: String, html: String?, isHTML: Bool) {
        guard let payload = payload else { return ("", nil, false) }

        var plainText = ""
        var htmlText: String?

        if let body = payload.body?.data, let mimeType = payload.mimeType {
            let decodedBody = decodeBase64URLSafe(body)
            if mimeType == "text/plain" {
                plainText = decodedBody
            } else if mimeType == "text/html" {
                htmlText = decodedBody
                if plainText.isEmpty {
                    plainText = stripHTML(decodedBody)
                }
            }
        }

        if let parts = payload.parts {
            extractFromParts(parts, plainText: &plainText, htmlText: &htmlText)
        }

        if plainText.isEmpty, let html = htmlText {
            plainText = stripHTML(html)
        }

        let isHTMLContent = htmlText != nil && !(htmlText!.isEmpty) && htmlText!.contains("<")
        return (plainText, htmlText, isHTMLContent)
    }

    private func extractFromParts(_ parts: [GmailPart], plainText: inout String, htmlText: inout String?) {
        for part in parts {
            if let mimeType = part.mimeType {
                if mimeType == "text/plain" && plainText.isEmpty {
                    if let body = part.body?.data { plainText = decodeBase64URLSafe(body) }
                } else if mimeType == "text/html" && htmlText == nil {
                    if let body = part.body?.data { htmlText = decodeBase64URLSafe(body) }
                } else if mimeType.hasPrefix("multipart/") {
                    if let subParts = part.parts {
                        extractFromParts(subParts, plainText: &plainText, htmlText: &htmlText)
                    }
                }
            }
            if let subParts = part.parts {
                extractFromParts(subParts, plainText: &plainText, htmlText: &htmlText)
            }
        }
    }

    // MARK: - Attachment helpers

    func extractAttachments(from payload: GmailPayload?, messageId: String) -> [EmailAttachment] {
        guard let payload = payload else { return [] }
        var attachments: [EmailAttachment] = []

        if let parts = payload.parts {
            for part in parts {
                if let filename = part.headers?.first(where: { $0.name.lowercased() == "content-disposition" })?.value,
                   filename.contains("attachment") || filename.contains("filename=") {

                    let attachmentFilename = extractFilename(from: filename) ?? "Unknown File"
                    let mimeType = part.mimeType ?? "application/octet-stream"
                    let size = Int64(part.body?.size ?? 0)
                    let attachmentId = part.body?.data

                    attachments.append(EmailAttachment(
                        id: UUID().uuidString,
                        filename: attachmentFilename,
                        mimeType: mimeType,
                        size: size,
                        attachmentId: attachmentId,
                        downloadURL: nil
                    ))
                }

                if let subParts = part.parts {
                    let subPayload = GmailPayload(
                        mimeType: part.mimeType,
                        headers: part.headers,
                        body: part.body,
                        parts: subParts
                    )
                    attachments.append(contentsOf: extractAttachments(from: subPayload, messageId: messageId))
                }
            }
        }
        return attachments
    }

    private func extractFilename(from contentDisposition: String) -> String? {
        let pattern = #"filename[*]?=(?:"([^"]+)"|([^;\s]+))"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: contentDisposition, range: NSRange(contentDisposition.startIndex..., in: contentDisposition)) {
            if let range = Range(match.range(at: 1), in: contentDisposition) {
                return String(contentDisposition[range])
            } else if let range = Range(match.range(at: 2), in: contentDisposition) {
                return String(contentDisposition[range])
            }
        }
        return nil
    }

    // MARK: - String helpers

    func stripHTML(_ html: String) -> String {
        let htmlRegex = try! NSRegularExpression(pattern: "<[^>]+>", options: [])
        let range = NSRange(location: 0, length: html.count)
        let strippedText = htmlRegex.stringByReplacingMatches(in: html, options: [], range: range, withTemplate: "")

        return strippedText
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func decodeBase64URLSafe(_ string: String) -> String {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = 4 - base64.count % 4
        if padding != 4 {
            base64 += String(repeating: "=", count: padding)
        }

        guard let data = Data(base64Encoded: base64),
              let decoded = String(data: data, encoding: .utf8) else {
            return string
        }
        return decoded
    }
}
