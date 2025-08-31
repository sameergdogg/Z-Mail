import Foundation
import GoogleSignIn
import SwiftUI

// MARK: - Gmail URL Builder
/// A utility struct for building Gmail API URLs with proper query parameter handling
/// and URL encoding. This struct encapsulates all URL building logic for the Gmail API service.
private struct GmailURLBuilder {
    /// The base URL for Gmail API requests
    private let baseURL: String
    
    init(baseURL: String) {
        self.baseURL = baseURL
    }
    
    /// Builds a URL for fetching messages with optional query parameters
    /// - Parameters:
    ///   - maxResults: Maximum number of messages to return
    ///   - query: Gmail search query string
    ///   - labelIds: Array of label IDs to filter by
    ///   - pageToken: Token for pagination
    /// - Returns: Complete URL string for the messages endpoint
    func makeMessagesURL(maxResults: Int? = nil, query: String? = nil, labelIds: [String]? = nil, pageToken: String? = nil) -> String {
        var urlString = "\(baseURL)/users/me/messages"
        var queryParams: [String] = []
        
        if let maxResults = maxResults {
            queryParams.append("maxResults=\(maxResults)")
        }
        
        if let query = query {
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            queryParams.append("q=\(encodedQuery)")
        }
        
        if let labelIds = labelIds, !labelIds.isEmpty {
            let encodedLabels = labelIds.joined(separator: ",")
            queryParams.append("labelIds=\(encodedLabels)")
        }
        
        if let pageToken = pageToken {
            let encodedToken = pageToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pageToken
            queryParams.append("pageToken=\(encodedToken)")
        }
        
        if !queryParams.isEmpty {
            urlString += "?" + queryParams.joined(separator: "&")
        }
        
        return urlString
    }
    
    func makeSearchQuery(from searchTerms: [String], isUnread: Bool? = nil, isStarred: Bool? = nil, fromEmail: String? = nil, toEmail: String? = nil, hasAttachment: Bool? = nil) -> String {
        var queryParts: [String] = []
        
        // Add search terms
        queryParts.append(contentsOf: searchTerms)
        
        // Add filters
        if let isUnread = isUnread {
            queryParts.append(isUnread ? "is:unread" : "is:read")
        }
        
        if let isStarred = isStarred {
            queryParts.append(isStarred ? "is:starred" : "is:unstarred")
        }
        
        if let fromEmail = fromEmail {
            queryParts.append("from:\(fromEmail)")
        }
        
        if let toEmail = toEmail {
            queryParts.append("to:\(toEmail)")
        }
        
        if let hasAttachment = hasAttachment {
            queryParts.append(hasAttachment ? "has:attachment" : "no:attachment")
        }
        
        return queryParts.joined(separator: " ")
    }
    
    /// Builds a search URL by combining search terms and filters, then creating a messages URL
    /// - Parameters:
    ///   - searchTerms: Array of search terms to look for
    ///   - maxResults: Maximum number of results to return
    ///   - isUnread: Filter for unread messages
    ///   - isStarred: Filter for starred messages
    ///   - fromEmail: Filter for messages from specific email
    ///   - toEmail: Filter for messages to specific email
    ///   - hasAttachment: Filter for messages with/without attachments
    ///   - pageToken: Token for pagination
    /// - Returns: Complete URL string for searching messages
    func makeSearchURL(searchTerms: [String], maxResults: Int? = nil, isUnread: Bool? = nil, isStarred: Bool? = nil, fromEmail: String? = nil, toEmail: String? = nil, hasAttachment: Bool? = nil, pageToken: String? = nil) -> String {
        let query = makeSearchQuery(from: searchTerms, isUnread: isUnread, isStarred: isStarred, fromEmail: fromEmail, toEmail: toEmail, hasAttachment: hasAttachment)
        return makeMessagesURL(maxResults: maxResults, query: query, pageToken: pageToken)
    }
    
    func makeMessageDetailURL(messageId: String) -> String {
        return "\(baseURL)/users/me/messages/\(messageId)"
    }
    
    func makeMessageModifyURL(messageId: String) -> String {
        return "\(baseURL)/users/me/messages/\(messageId)/modify"
    }
    
    func makeAttachmentURL(messageId: String, attachmentId: String) -> String {
        return "\(baseURL)/users/me/messages/\(messageId)/attachments/\(attachmentId)"
    }
    
    func makeLabelsURL() -> String {
        return "\(baseURL)/users/me/labels"
    }
    
    func makeThreadsURL(maxResults: Int? = nil, query: String? = nil, labelIds: [String]? = nil, pageToken: String? = nil) -> String {
        var urlString = "\(baseURL)/users/me/threads"
        var queryParams: [String] = []
        
        if let maxResults = maxResults {
            queryParams.append("maxResults=\(maxResults)")
        }
        
        if let query = query {
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            queryParams.append("q=\(encodedQuery)")
        }
        
        if let labelIds = labelIds, !labelIds.isEmpty {
            let encodedLabels = labelIds.joined(separator: ",")
            queryParams.append("labelIds=\(encodedLabels)")
        }
        
        if let pageToken = pageToken {
            let encodedToken = pageToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pageToken
            queryParams.append("pageToken=\(encodedToken)")
        }
        
        if !queryParams.isEmpty {
            urlString += "?" + queryParams.joined(separator: "&")
        }
        
        return urlString
    }
    
    func makeThreadDetailURL(threadId: String) -> String {
        return "\(baseURL)/users/me/threads/\(threadId)"
    }
    
    func makeCustomURL(path: String, queryParams: [String: String]? = nil) -> String {
        var urlString = "\(baseURL)\(path)"
        
        if let queryParams = queryParams, !queryParams.isEmpty {
            let encodedParams = queryParams.map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }.joined(separator: "&")
            urlString += "?\(encodedParams)"
        }
        
        return urlString
    }
    
    /// Encodes an object to JSON data for use as request body
    /// - Parameters:
    ///   - body: The encodable object to convert to JSON
    ///   - encoder: The JSON encoder to use
    /// - Returns: Encoded JSON data
    /// - Throws: Encoding error if the object cannot be encoded
    func makeRequestBody<T: Encodable>(_ body: T, encoder: JSONEncoder) throws -> Data {
        return try encoder.encode(body)
    }
    
    /// Validates and creates a URL from a URL string
    /// - Parameter urlString: The URL string to validate
    /// - Returns: A valid URL object
    /// - Throws: GmailAPIError.invalidURL if the URL is invalid
    func makeValidURL(from urlString: String) throws -> URL {
        guard let url = URL(string: urlString) else {
            throw GmailAPIError.invalidURL
        }
        return url
    }
    
    /// Builds a URL with custom path and query parameters
    /// - Parameters:
    ///   - endpoint: The Gmail API endpoint (e.g., "/users/me/messages")
    ///   - queryParams: Dictionary of query parameters
    /// - Returns: Complete URL string
    func makeURL(endpoint: String, queryParams: [String: String]? = nil) -> String {
        return makeCustomURL(path: endpoint, queryParams: queryParams)
    }
}

/// Implementation of Gmail API Service Protocol
internal class GmailAPIServiceImpl: GmailAPIServiceProtocol {
    private let dependencies: GmailAPIServiceDependencies
    private lazy var urlBuilder = GmailURLBuilder(baseURL: dependencies.baseURL)
    
    // MARK: - API Response Types
    private enum APIResponseType {
        case messageList
        case message
        case attachment
        case void // For operations that don't return data (like modify)
        
        var expectedStatusCode: Int {
            switch self {
            case .messageList, .message, .attachment:
                return 200
            case .void:
                return 200
            }
        }
    }
    
    internal init(dependencies: GmailAPIServiceDependencies) {
        self.dependencies = dependencies
    }
    
    // MARK: - Generic API Request Method
    private func makeAPIRequest<T: Decodable>(
        for user: GIDGoogleUser,
        urlString: String,
        responseType: APIResponseType,
        httpMethod: String = "GET",
        requestBody: Data? = nil,
        contentType: String? = nil
    ) async throws -> T {
        let accessToken = user.accessToken.tokenString
        let url = try urlBuilder.makeValidURL(from: urlString)
        
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        if let requestBody = requestBody {
            request.httpBody = requestBody
        }
        
        if let contentType = contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        
        let (data, response) = try await dependencies.urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.networkError
        }
        
        // Handle different status codes based on response type
        switch httpResponse.statusCode {
        case responseType.expectedStatusCode:
            break
        case 401:
            throw GmailAPIError.authenticationFailed
        case 404:
            switch responseType {
            case .message:
                throw GmailAPIError.messageNotFound
            case .attachment:
                throw GmailAPIError.attachmentNotFound
            default:
                throw GmailAPIError.networkError
            }
        case 429:
            throw GmailAPIError.rateLimitExceeded
        default:
            throw GmailAPIError.networkError
        }
        
        // For void responses, we don't need to decode
        if responseType == .void {
            // Return a default value or throw an error if T doesn't conform to ExpressibleByNilLiteral
            throw GmailAPIError.networkError // This case shouldn't happen with proper typing
        }
        
        // Decode the response based on type
        return try dependencies.jsonDecoder.decode(T.self, from: data)
    }
    
    // MARK: - Void API Request Method (for operations that don't return data)
    private func makeVoidAPIRequest(
        for user: GIDGoogleUser,
        urlString: String,
        httpMethod: String = "POST",
        requestBody: Data? = nil,
        contentType: String? = nil
    ) async throws {
        let accessToken = user.accessToken.tokenString
        let url = try urlBuilder.makeValidURL(from: urlString)
        
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        if let requestBody = requestBody {
            request.httpBody = requestBody
        }
        
        if let contentType = contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        
        let (_, response) = try await dependencies.urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailAPIError.networkError
        }
        
        // Handle different status codes
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
    
    // MARK: - Public API Implementation
    
    public func fetchMessages(for user: GIDGoogleUser, maxResults: Int = 50) async throws -> [GmailMessage] {
        print("📧 GmailAPIService.fetchMessages() started for user: \(user.profile?.email ?? "unknown")")
        
        let urlString = urlBuilder.makeMessagesURL(maxResults: maxResults)
        print("📧 Gmail API URL: \(urlString)")
        
        let messageList: GmailMessageList = try await makeAPIRequest(
            for: user,
            urlString: urlString,
            responseType: .messageList
        )
        
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
        let urlString = urlBuilder.makeAttachmentURL(messageId: messageId, attachmentId: attachmentId)
        
        let attachment: GmailBody = try await makeAPIRequest(
            for: user,
            urlString: urlString,
            responseType: .attachment
        )
        
        return attachment.data ?? ""
    }
}

// MARK: - Private Helper Methods
extension GmailAPIServiceImpl {
    
    private func fetchFullMessage(messageId: String, user: GIDGoogleUser) async throws -> GmailMessage {
        let urlString = urlBuilder.makeMessageDetailURL(messageId: messageId)
        
        return try await makeAPIRequest(
            for: user,
            urlString: urlString,
            responseType: .message
        )
    }
    
    private func modifyMessage(messageId: String, user: GIDGoogleUser, request: GmailModifyRequest) async throws {
        let urlString = urlBuilder.makeMessageModifyURL(messageId: messageId)
        let requestBody = try urlBuilder.makeRequestBody(request, encoder: dependencies.jsonEncoder)
        
        try await makeVoidAPIRequest(
            for: user,
            urlString: urlString,
            httpMethod: "POST",
            requestBody: requestBody,
            contentType: "application/json"
        )
    }
}