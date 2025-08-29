import Foundation
import GoogleSignIn
import SwiftUI

class GmailAPIService: ObservableObject {
    private let baseURL = "https://www.googleapis.com/gmail/v1"
    
    func fetchMessages(for user: GIDGoogleUser, maxResults: Int = 50) async throws -> [GmailMessage] {
        let accessToken = user.accessToken.tokenString
        
        guard let url = URL(string: "\(baseURL)/users/me/messages?maxResults=\(maxResults)") else {
            throw GmailAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GmailAPIError.networkError
        }
        
        let messageList = try JSONDecoder().decode(GmailMessageList.self, from: data)
        
        var messages: [GmailMessage] = []
        
        for messageInfo in messageList.messages ?? [] {
            do {
                let fullMessage = try await fetchFullMessage(messageId: messageInfo.id, user: user)
                messages.append(fullMessage)
            } catch {
                print("Failed to fetch message \(messageInfo.id): \(error)")
            }
        }
        
        return messages
    }
    
    private func fetchFullMessage(messageId: String, user: GIDGoogleUser) async throws -> GmailMessage {
        let accessToken = user.accessToken.tokenString
        
        guard let url = URL(string: "\(baseURL)/users/me/messages/\(messageId)") else {
            throw GmailAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GmailAPIError.networkError
        }
        
        return try JSONDecoder().decode(GmailMessage.self, from: data)
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
        
        let body = extractBody(from: gmailMessage.payload)
        let isUnread = gmailMessage.labelIds?.contains("UNREAD") ?? false
        let isStarred = gmailMessage.labelIds?.contains("STARRED") ?? false
        let labels = gmailMessage.labelIds ?? []
        
        return Email(
            id: gmailMessage.id,
            subject: subject,
            sender: sender,
            recipients: recipients,
            body: body,
            date: date,
            isRead: !isUnread,
            isStarred: isStarred,
            labels: labels,
            accountEmail: accountEmail,
            threadId: gmailMessage.threadId
        )
    }
    
    private func parseEmailAddress(_ emailString: String) -> EmailAddress {
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
    
    private func parseEmailAddresses(_ emailString: String) -> [EmailAddress] {
        let addresses = emailString.components(separatedBy: ",")
        return addresses.map { parseEmailAddress($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    
    private func parseDate(_ dateString: String) -> Date {
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
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        return Date()
    }
    
    private func extractBody(from payload: GmailPayload?) -> String {
        guard let payload = payload else { return "" }
        
        if let body = payload.body?.data {
            return decodeBase64URLSafe(body)
        }
        
        if let parts = payload.parts {
            for part in parts {
                if part.mimeType == "text/plain" || part.mimeType == "text/html" {
                    if let body = part.body?.data {
                        return decodeBase64URLSafe(body)
                    }
                }
            }
            
            for part in parts {
                let bodyText = extractBody(from: GmailPayload(
                    mimeType: part.mimeType,
                    headers: part.headers,
                    body: part.body,
                    parts: part.parts
                ))
                if !bodyText.isEmpty {
                    return bodyText
                }
            }
        }
        
        return ""
    }
    
    private func decodeBase64URLSafe(_ string: String) -> String {
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

struct GmailMessageList: Codable {
    let messages: [GmailMessageInfo]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct GmailMessageInfo: Codable {
    let id: String
    let threadId: String
}

struct GmailMessage: Codable {
    let id: String
    let threadId: String?
    let labelIds: [String]?
    let snippet: String?
    let payload: GmailPayload?
    let sizeEstimate: Int?
    let historyId: String?
    let internalDate: String?
}

struct GmailPayload: Codable {
    let mimeType: String?
    let headers: [GmailHeader]?
    let body: GmailBody?
    let parts: [GmailPart]?
}

struct GmailHeader: Codable {
    let name: String
    let value: String
}

struct GmailBody: Codable {
    let size: Int?
    let data: String?
}

struct GmailPart: Codable {
    let mimeType: String?
    let headers: [GmailHeader]?
    let body: GmailBody?
    let parts: [GmailPart]?
}

enum GmailAPIError: Error {
    case noAccessToken
    case invalidURL
    case networkError
    case decodingError
}