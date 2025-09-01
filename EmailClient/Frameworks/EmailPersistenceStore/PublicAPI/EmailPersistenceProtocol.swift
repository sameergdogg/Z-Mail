import Foundation
import Combine

/// Public API protocol for email persistence operations
public protocol EmailPersistenceProtocol {
    /// Fetches emails for a specific account with optional filtering
    /// - Parameters:
    ///   - accountEmail: The email address of the account
    ///   - filter: Optional filter criteria
    /// - Returns: Array of persisted emails
    func fetchEmails(for accountEmail: String, filter: EmailFilter?) async throws -> [Email]
    
    /// Saves emails to the persistence store
    /// - Parameters:
    ///   - emails: Array of emails to save
    ///   - accountEmail: The email address of the account
    func saveEmails(_ emails: [Email], for accountEmail: String) async throws
    
    /// Updates a specific email in the persistence store
    /// - Parameter email: The email to update
    func updateEmail(_ email: Email) async throws
    
    /// Deletes emails for a specific account
    /// - Parameter accountEmail: The email address of the account
    func deleteEmails(for accountEmail: String) async throws
    
    /// Deletes a specific email
    /// - Parameter emailId: The ID of the email to delete
    func deleteEmail(with emailId: String) async throws
    
    /// Checks if emails exist for an account
    /// - Parameter accountEmail: The email address of the account
    /// - Returns: True if emails exist, false otherwise
    func hasEmails(for accountEmail: String) async -> Bool
    
    /// Gets the last sync date for an account
    /// - Parameter accountEmail: The email address of the account
    /// - Returns: The last sync date or nil if never synced
    func getLastSyncDate(for accountEmail: String) async -> Date?
    
    /// Updates the last sync date for an account
    /// - Parameters:
    ///   - date: The sync date
    ///   - accountEmail: The email address of the account
    func updateLastSyncDate(_ date: Date, for accountEmail: String) async throws
    
    /// Gets the total count of emails for an account
    /// - Parameter accountEmail: The email address of the account
    /// - Returns: Total number of emails
    func getEmailCount(for accountEmail: String) async -> Int
    
    /// Performs intelligent sync determining what needs to be fetched
    /// - Parameter accountEmail: The email address of the account
    /// - Returns: Sync strategy indicating how to proceed
    func determineSyncStrategy(for accountEmail: String) async -> SyncStrategy
    
    /// Clears all data from the persistence store
    func clearAllData() async throws
    
    /// Publisher for real-time email changes
    var emailChanges: AnyPublisher<EmailChangeEvent, Never> { get }
}

/// Sync strategy for intelligent data loading
public enum SyncStrategy {
    case fullSync        // First time or major refresh needed
    case incrementalSync(since: Date)  // Only fetch emails newer than date
    case cacheOnly      // Use only cached data (offline mode)
}

/// Email change events for reactive updates
public enum EmailChangeEvent {
    case emailsAdded([Email])
    case emailUpdated(Email)
    case emailDeleted(String)  // email ID
    case accountDataCleared(String)  // account email
}

/// Email persistence specific errors
public enum EmailPersistenceError: Error, LocalizedError {
    case swiftDataError(Error)
    case emailNotFound(String)
    case accountNotFound(String)
    case saveFailed(String)
    case fetchFailed(String)
    case migrationFailed(Error)
    case diskSpaceFull
    case dataCorrupted
    case initializationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .swiftDataError(let error):
            return "SwiftData error: \(error.localizedDescription)"
        case .emailNotFound(let emailId):
            return "Email with ID '\(emailId)' not found"
        case .accountNotFound(let accountEmail):
            return "Account '\(accountEmail)' not found"
        case .saveFailed(let reason):
            return "Failed to save emails: \(reason)"
        case .fetchFailed(let reason):
            return "Failed to fetch emails: \(reason)"
        case .migrationFailed(let error):
            return "Database migration failed: \(error.localizedDescription)"
        case .diskSpaceFull:
            return "Insufficient disk space for email storage"
        case .dataCorrupted:
            return "Email database is corrupted and needs to be reset"
        case .initializationFailed(let reason):
            return "Failed to initialize persistence store: \(reason)"
        }
    }
}

/// Configuration options for persistence behavior
public struct PersistenceConfiguration {
    /// Maximum number of emails to keep per account (default: 1000)
    public let maxEmailsPerAccount: Int
    
    /// How long to keep emails before auto-deletion (default: 30 days)
    public let emailRetentionPeriod: TimeInterval
    
    /// Enable automatic cleanup of old emails (default: true)
    public let enableAutoCleanup: Bool
    
    /// Batch size for processing operations (default: 50)
    public let batchSize: Int
    
    /// Enable encryption for sensitive data (default: true)
    public let enableEncryption: Bool
    
    /// Use in-memory storage only (for testing, default: false)
    public let isInMemoryOnly: Bool
    
    /// Enable CloudKit sync (default: false)
    public let enableCloudKit: Bool
    
    public init(
        maxEmailsPerAccount: Int = 1000,
        emailRetentionPeriod: TimeInterval = 30 * 24 * 60 * 60, // 30 days
        enableAutoCleanup: Bool = true,
        batchSize: Int = 50,
        enableEncryption: Bool = true,
        isInMemoryOnly: Bool = false,
        enableCloudKit: Bool = false
    ) {
        self.maxEmailsPerAccount = maxEmailsPerAccount
        self.emailRetentionPeriod = emailRetentionPeriod
        self.enableAutoCleanup = enableAutoCleanup
        self.batchSize = batchSize
        self.enableEncryption = enableEncryption
        self.isInMemoryOnly = isInMemoryOnly
        self.enableCloudKit = enableCloudKit
    }
}