import Foundation
import Combine

/// Public API protocol for email service operations
/// Follows MVVM + Service Layer architecture from CLAUDE.md
public protocol EmailServiceProtocol: ObservableObject {
    /// Published array of emails
    var emails: [Email] { get }
    
    /// Published array of filtered emails
    var filteredEmails: [Email] { get }
    
    /// Published loading state
    var isLoading: Bool { get }
    
    /// Published current filter
    var currentFilter: EmailFilter { get }
    
    /// Published sort order
    var sortOrder: SortOrder { get }
    
    /// Published error message
    var errorMessage: String? { get }
    
    /// Published authentication errors per account
    var authenticationErrors: [String: EmailServiceError] { get }
    
    /// Published sync progress
    var syncProgress: SyncProgress { get }
    
    /// Load emails on app launch using intelligent sync strategy
    /// This follows the smart persistence pattern from CLAUDE.md
    func loadEmailsOnLaunch() async
    
    /// Refresh emails from server - forces full sync from Gmail API
    /// Used for pull-to-refresh functionality
    func refreshEmails() async
    
    /// Apply filter to emails
    /// - Parameter filter: The filter to apply
    func applyFilter(_ filter: EmailFilter)
    
    /// Apply sort order to emails
    /// - Parameter order: The sort order to apply
    func applySortOrder(_ order: SortOrder)
    
    /// Marks an email as read in both local storage and Gmail API
    /// Follows the service layer pattern with proper error handling
    /// - Parameter email: The email to mark as read
    func markAsRead(_ email: Email) async
    
    /// Marks an email as unread in both local storage and Gmail API
    /// - Parameter email: The email to mark as unread
    func markAsUnread(_ email: Email) async
    
    /// Toggles star status for an email in both local storage and Gmail API
    /// Follows the service layer pattern with proper error handling
    /// - Parameter email: The email to toggle star status
    func toggleStar(_ email: Email) async
    
    /// Updates the account manager and refreshes email data
    /// This follows the service layer pattern for proper dependency management
    /// - Parameter newAccountManager: The new account manager
    func updateAccountManager(_ newAccountManager: AccountManagerProtocol)
    
    /// Gets unique senders from all emails in the persistence store
    /// - Returns: Array of unique email senders sorted by sender name
    func getUniqueSenders() -> [EmailSender]
    
    /// Gets emails from a specific sender
    /// - Parameter sender: The sender to filter by
    /// - Returns: Array of emails from the specified sender
    func getEmailsFromSender(_ sender: EmailSender) -> [Email]
}

/// Email sender model for grouping emails by sender
public struct EmailSender: Identifiable, Hashable {
    public let id = UUID()
    public let email: String
    public let name: String?
    public let emailCount: Int
    
    public var displayName: String {
        return name ?? email
    }
    
    public init(email: String, name: String? = nil, emailCount: Int = 0) {
        self.email = email
        self.name = name
        self.emailCount = emailCount
    }
}

/// Current sync progress state
public enum SyncProgress {
    case idle
    case syncing(accountEmail: String, progress: Double)
    case completed
    case failed(error: String)
}

/// Email service specific errors
public enum EmailServiceError: Error, LocalizedError {
    case noSignedInUser(String)
    case fetchFailed(String)
    case reauthenticationRequired(String)
    case authenticationFailed(String)
    case networkError
    case gmailAPIError(String)
    
    public var errorDescription: String? {
        switch self {
        case .noSignedInUser(let email):
            return "No signed-in user found for \(email). Please sign in again."
        case .fetchFailed(let message):
            return "Failed to fetch emails: \(message)"
        case .reauthenticationRequired(let email):
            return "Authentication expired for \(email). Please sign in again."
        case .authenticationFailed(let email):
            return "Authentication failed for \(email). Please try signing in again."
        case .networkError:
            return "Network connection error. Please check your internet connection and try again."
        case .gmailAPIError(let message):
            return message
        }
    }
    
    public var isAuthenticationError: Bool {
        switch self {
        case .reauthenticationRequired, .authenticationFailed, .noSignedInUser:
            return true
        case .fetchFailed, .networkError, .gmailAPIError:
            return false
        }
    }
}

/// Email filter options
public enum EmailFilter: Equatable {
    case all
    case unread
    case starred
    case account(String)
    case label(String)
    case classification(String)
}

/// Email sort order options
public enum SortOrder {
    case dateAscending
    case dateDescending
    case senderAscending
    case senderDescending
}

/// Configuration options for email service behavior
public struct EmailServiceConfiguration {
    /// Maximum number of emails to fetch per sync (default: 50)
    public let maxEmailsPerSync: Int
    
    /// Enable automatic background sync (default: true)
    public let enableBackgroundSync: Bool
    
    /// Sync interval in seconds (default: 5 minutes)
    public let syncInterval: TimeInterval
    
    /// Enable Gmail API sync for read/star status (default: true)
    public let enableGmailAPISync: Bool
    
    /// Batch size for processing operations (default: 20)
    public let batchSize: Int
    
    public init(
        maxEmailsPerSync: Int = 50,
        enableBackgroundSync: Bool = true,
        syncInterval: TimeInterval = 5 * 60, // 5 minutes
        enableGmailAPISync: Bool = true,
        batchSize: Int = 20
    ) {
        self.maxEmailsPerSync = maxEmailsPerSync
        self.enableBackgroundSync = enableBackgroundSync
        self.syncInterval = syncInterval
        self.enableGmailAPISync = enableGmailAPISync
        self.batchSize = batchSize
    }
}