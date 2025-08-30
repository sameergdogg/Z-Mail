import Foundation
import GoogleSignIn

/// Public API protocol for Gmail service operations
public protocol GmailAPIServiceProtocol {
    /// Fetches email messages for a given user
    /// - Parameters:
    ///   - user: The authenticated Google user
    ///   - maxResults: Maximum number of messages to fetch (default: 50)
    /// - Returns: Array of Gmail messages
    /// - Throws: GmailAPIError on failure
    func fetchMessages(for user: GIDGoogleUser, maxResults: Int) async throws -> [GmailMessage]
    
    /// Converts a Gmail API message to the app's Email model
    /// - Parameters:
    ///   - gmailMessage: The Gmail message from the API
    ///   - accountEmail: The email address of the account
    /// - Returns: Converted Email object
    func convertGmailMessageToEmail(_ gmailMessage: GmailMessage, accountEmail: String) -> Email
    
    /// Marks a message as read
    /// - Parameters:
    ///   - messageId: The ID of the message to mark as read
    ///   - user: The authenticated Google user
    /// - Throws: GmailAPIError on failure
    func markMessageAsRead(messageId: String, user: GIDGoogleUser) async throws
    
    /// Stars or unstars a message
    /// - Parameters:
    ///   - messageId: The ID of the message to star/unstar
    ///   - user: The authenticated Google user
    ///   - isStarred: Whether to star (true) or unstar (false) the message
    /// - Throws: GmailAPIError on failure
    func toggleMessageStar(messageId: String, user: GIDGoogleUser, isStarred: Bool) async throws
    
    /// Fetches attachment data for a message
    /// - Parameters:
    ///   - messageId: The ID of the message containing the attachment
    ///   - attachmentId: The ID of the attachment
    ///   - user: The authenticated Google user
    /// - Returns: Base64-encoded attachment data
    /// - Throws: GmailAPIError on failure
    func fetchAttachment(messageId: String, attachmentId: String, user: GIDGoogleUser) async throws -> String
}

/// Gmail API specific error types
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
        case .noAccessToken:
            return "No access token available"
        case .invalidURL:
            return "Invalid URL for Gmail API request"
        case .networkError:
            return "Network error occurred"
        case .decodingError:
            return "Failed to decode Gmail API response"
        case .authenticationFailed:
            return "Authentication with Gmail API failed"
        case .rateLimitExceeded:
            return "Gmail API rate limit exceeded"
        case .messageNotFound:
            return "Message not found"
        case .attachmentNotFound:
            return "Attachment not found"
        }
    }
}