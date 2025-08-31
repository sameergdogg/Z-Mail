import Foundation
import GoogleSignIn

/// Gmail account data model for persistence and management
public struct GmailAccount: Codable, Identifiable, Hashable {
    public let id: String
    public let email: String
    public let displayName: String?
    public var accessToken: String
    public var refreshToken: String
    public let createdAt: Date
    public var lastUsed: Date
    public var isActive: Bool
    
    public init(
        email: String,
        displayName: String?,
        accessToken: String,
        refreshToken: String
    ) {
        self.id = UUID().uuidString
        self.email = email
        self.displayName = displayName
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.createdAt = Date()
        self.lastUsed = Date()
        self.isActive = true
    }
    
    /// Internal initializer with all properties for persistence
    internal init(
        id: String,
        email: String,
        displayName: String?,
        accessToken: String,
        refreshToken: String,
        createdAt: Date,
        lastUsed: Date,
        isActive: Bool
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.createdAt = createdAt
        self.lastUsed = lastUsed
        self.isActive = isActive
    }
    
    /// Updates the account with new token information
    /// - Parameters:
    ///   - accessToken: New access token
    ///   - refreshToken: New refresh token
    /// - Returns: Updated account instance
    public func updatingTokens(accessToken: String, refreshToken: String) -> GmailAccount {
        return GmailAccount(
            id: self.id,
            email: self.email,
            displayName: self.displayName,
            accessToken: accessToken,
            refreshToken: refreshToken,
            createdAt: self.createdAt,
            lastUsed: Date(),
            isActive: self.isActive
        )
    }
    
    /// Updates the last used timestamp
    /// - Returns: Updated account instance
    public func markAsUsed() -> GmailAccount {
        return GmailAccount(
            id: self.id,
            email: self.email,
            displayName: self.displayName,
            accessToken: self.accessToken,
            refreshToken: self.refreshToken,
            createdAt: self.createdAt,
            lastUsed: Date(),
            isActive: self.isActive
        )
    }
    
    /// Activates or deactivates the account
    /// - Parameter active: Whether the account should be active
    /// - Returns: Updated account instance
    public func settingActive(_ active: Bool) -> GmailAccount {
        return GmailAccount(
            id: self.id,
            email: self.email,
            displayName: self.displayName,
            accessToken: self.accessToken,
            refreshToken: self.refreshToken,
            createdAt: self.createdAt,
            lastUsed: self.lastUsed,
            isActive: active
        )
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(email)
    }
    
    // MARK: - Equatable
    
    public static func == (lhs: GmailAccount, rhs: GmailAccount) -> Bool {
        return lhs.id == rhs.id && lhs.email == rhs.email
    }
}

/// Account authentication state
public enum AccountAuthState {
    case authenticated
    case tokenExpired
    case authenticationRequired
    case networkError
    case unknown
}

/// Account validation result
public struct AccountValidationResult {
    public let account: GmailAccount
    public let authState: AccountAuthState
    public let user: GIDGoogleUser?
    public let error: AccountError?
    
    public init(
        account: GmailAccount,
        authState: AccountAuthState,
        user: GIDGoogleUser? = nil,
        error: AccountError? = nil
    ) {
        self.account = account
        self.authState = authState
        self.user = user
        self.error = error
    }
}

/// Bulk account operation result
public struct BulkAccountResult {
    public let successful: [GmailAccount]
    public let failed: [(GmailAccount, AccountError)]
    
    public init(successful: [GmailAccount] = [], failed: [(GmailAccount, AccountError)] = []) {
        self.successful = successful
        self.failed = failed
    }
    
    /// Whether all operations succeeded
    public var allSucceeded: Bool {
        return failed.isEmpty
    }
    
    /// Whether any operations succeeded
    public var anySucceeded: Bool {
        return !successful.isEmpty
    }
}

/// Account statistics and information
public struct AccountStatistics {
    public let totalAccounts: Int
    public let activeAccounts: Int
    public let authenticatedAccounts: Int
    public let oldestAccount: GmailAccount?
    public let newestAccount: GmailAccount?
    public let mostRecentlyUsed: GmailAccount?
    
    public init(
        totalAccounts: Int,
        activeAccounts: Int,
        authenticatedAccounts: Int,
        oldestAccount: GmailAccount? = nil,
        newestAccount: GmailAccount? = nil,
        mostRecentlyUsed: GmailAccount? = nil
    ) {
        self.totalAccounts = totalAccounts
        self.activeAccounts = activeAccounts
        self.authenticatedAccounts = authenticatedAccounts
        self.oldestAccount = oldestAccount
        self.newestAccount = newestAccount
        self.mostRecentlyUsed = mostRecentlyUsed
    }
}