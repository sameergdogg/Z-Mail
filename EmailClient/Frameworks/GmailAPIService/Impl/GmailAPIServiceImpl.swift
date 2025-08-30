import Foundation
import GoogleSignIn
import SwiftUI

/// Implementation of Gmail API Service Protocol
internal class GmailAPIServiceImpl: GmailAPIServiceProtocol {
    private let dependencies: GmailAPIServiceDependencies
    
    internal init(dependencies: GmailAPIServiceDependencies) {
        self.dependencies = dependencies
    }
    
    // MARK: - Public API Implementation
    
    public func fetchMessages(for user: GIDGoogleUser, maxResults: Int = 50) async throws -> [GmailMessage] {
        print("📧 GmailAPIService.fetchMessages() started for user: \(user.profile?.email ?? "unknown")")
        let accessToken = user.accessToken.tokenString
        print("📧 Access token length: \(accessToken.count)")
        
        let urlString = "\(dependencies.baseURL)/users/me/messages?maxResults=\(maxResults)"
        print("📧 Gmail API URL: \(urlString)")
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL: \(urlString)")
            throw GmailAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await dependencies.urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw GmailAPIError.authenticationFailed
        case 429:
            throw GmailAPIError.rateLimitExceeded
        default:
            throw GmailAPIError.networkError
        }
        
        let messageList = try dependencies.jsonDecoder.decode(GmailMessageList.self, from: data)
        
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
    
    public func convertGmailMessageToEmail(_ gmailMessage: GmailMessage, accountEmail: String) -> Email {
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
        
        let isUnread = gmailMessage.labelIds?.contains(GmailLabels.unread) ?? false
        let isStarred = gmailMessage.labelIds?.contains(GmailLabels.starred) ?? false
        let labels = gmailMessage.labelIds ?? []
        
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
    
    public func markMessageAsRead(messageId: String, user: GIDGoogleUser) async throws {
        let modifyRequest = GmailModifyRequest(
            addLabelIds: nil,
            removeLabelIds: [GmailLabels.unread]
        )
        
        try await modifyMessage(messageId: messageId, user: user, request: modifyRequest)
    }
    
    public func toggleMessageStar(messageId: String, user: GIDGoogleUser, isStarred: Bool) async throws {
        let modifyRequest: GmailModifyRequest
        
        if isStarred {
            modifyRequest = GmailModifyRequest(
                addLabelIds: [GmailLabels.starred],
                removeLabelIds: nil
            )
        } else {
            modifyRequest = GmailModifyRequest(
                addLabelIds: nil,
                removeLabelIds: [GmailLabels.starred]
            )
        }
        
        try await modifyMessage(messageId: messageId, user: user, request: modifyRequest)
    }
    
    public func fetchAttachment(messageId: String, attachmentId: String, user: GIDGoogleUser) async throws -> String {
        let accessToken = user.accessToken.tokenString
        
        guard let url = URL(string: "\(dependencies.baseURL)/users/me/messages/\(messageId)/attachments/\(attachmentId)") else {
            throw GmailAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await dependencies.urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw GmailAPIError.authenticationFailed
        case 404:
            throw GmailAPIError.attachmentNotFound
        case 429:
            throw GmailAPIError.rateLimitExceeded
        default:
            throw GmailAPIError.networkError
        }
        
        let attachment = try dependencies.jsonDecoder.decode(GmailBody.self, from: data)
        return attachment.data ?? ""
    }
}

// MARK: - Private Helper Methods
extension GmailAPIServiceImpl {
    
    private func fetchFullMessage(messageId: String, user: GIDGoogleUser) async throws -> GmailMessage {
        let accessToken = user.accessToken.tokenString
        
        guard let url = URL(string: "\(dependencies.baseURL)/users/me/messages/\(messageId)") else {
            throw GmailAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await dependencies.urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw GmailAPIError.authenticationFailed
        case 404:
            throw GmailAPIError.messageNotFound
        case 429:
            throw GmailAPIError.rateLimitExceeded
        default:
            throw GmailAPIError.networkError
        }
        
        return try dependencies.jsonDecoder.decode(GmailMessage.self, from: data)
    }
    
    private func modifyMessage(messageId: String, user: GIDGoogleUser, request: GmailModifyRequest) async throws {
        let accessToken = user.accessToken.tokenString
        
        guard let url = URL(string: "\(dependencies.baseURL)/users/me/messages/\(messageId)/modify") else {
            throw GmailAPIError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = try dependencies.jsonEncoder.encode(request)
        urlRequest.httpBody = requestBody
        
        let (_, response) = try await dependencies.urlSession.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw GmailAPIError.authenticationFailed
        case 404:
            throw GmailAPIError.messageNotFound
        case 429:
            throw GmailAPIError.rateLimitExceeded
        default:
            throw GmailAPIError.networkError
        }
    }
}