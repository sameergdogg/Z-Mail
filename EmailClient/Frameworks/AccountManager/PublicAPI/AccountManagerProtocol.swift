import Foundation
import Combine
import GoogleSignIn

/// Public API protocol for account management operations
public protocol AccountManagerProtocol: ObservableObject {
    /// Published array of Gmail accounts
    var accounts: [GmailAccount] { get }
    
    /// Published loading state
    var isLoading: Bool { get }
    
    /// Published array of signed-in Google users
    var signedInUsers: [GIDGoogleUser] { get }
    
    /// Signs in with Google OAuth and Gmail scopes
    /// - Throws: AccountError if sign-in fails
    func signInWithGoogle() async throws
    
    /// Signs out a specific account
    /// - Parameter account: The account to sign out
    func signOut(account: GmailAccount)
    
    /// Signs out all accounts
    func signOutAllAccounts()
    
    /// Removes an account from the manager
    /// - Parameter account: The account to remove
    func removeAccount(_ account: GmailAccount)
    
    /// Gets the Google user for a specific account
    /// - Parameter account: The Gmail account
    /// - Returns: The corresponding Google user or nil if not found
    func getUserForAccount(_ account: GmailAccount) -> GIDGoogleUser?
    
    /// Refreshes the token for a specific user
    /// - Parameter user: The Google user whose token to refresh
    /// - Throws: AccountError if token refresh fails
    func refreshTokenForUser(_ user: GIDGoogleUser) async throws
    
    /// Validates and refreshes token for a user
    /// - Parameter user: The Google user to validate
    /// - Returns: The validated Google user with fresh tokens
    /// - Throws: AccountError if validation/refresh fails
    func validateAndRefreshTokenForUser(_ user: GIDGoogleUser) async throws -> GIDGoogleUser
    
    /// Checks if an account requires re-authentication
    /// - Parameter account: The account to check
    /// - Returns: True if re-authentication is required
    func requiresReauthentication(for account: GmailAccount) -> Bool
    
    /// Re-authenticates a specific account
    /// - Parameter account: The account to re-authenticate
    /// - Throws: AccountError if re-authentication fails
    func reauthenticateAccount(_ account: GmailAccount) async throws
}

/// Account management specific errors
public enum AccountError: Error, LocalizedError {
    case noPresentingViewController
    case signInFailed
    case tokenRefreshFailed
    case reauthenticationRequired
    case networkError
    case invalidCredentials
    case accountNotFound(String)
    case duplicateAccount
    case persistenceError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .noPresentingViewController:
            return "Unable to present sign-in view"
        case .signInFailed:
            return "Sign-in failed"
        case .tokenRefreshFailed:
            return "Failed to refresh authentication token"
        case .reauthenticationRequired:
            return "Please sign in again to continue"
        case .networkError:
            return "Network connection error"
        case .invalidCredentials:
            return "Invalid or expired credentials"
        case .accountNotFound(let email):
            return "Account '\(email)' not found"
        case .duplicateAccount:
            return "Account already exists"
        case .persistenceError(let error):
            return "Account data persistence error: \(error.localizedDescription)"
        }
    }
}

/// Account change events for reactive updates
public enum AccountChangeEvent {
    case accountAdded(GmailAccount)
    case accountUpdated(GmailAccount)
    case accountRemoved(String) // account email
    case userSignedIn(GIDGoogleUser)
    case userSignedOut(String) // user email
    case allAccountsCleared
}

/// Configuration options for account management
public struct AccountManagerConfiguration {
    /// Gmail API scopes to request
    public let gmailScopes: [String]
    
    /// Enable automatic token refresh (default: true)
    public let enableAutoTokenRefresh: Bool
    
    /// Token refresh threshold in seconds before expiry (default: 5 minutes)
    public let tokenRefreshThreshold: TimeInterval
    
    /// Enable account persistence (default: true)
    public let enableAccountPersistence: Bool
    
    /// Maximum number of accounts allowed (default: 10)
    public let maxAccountLimit: Int
    
    /// Enable automatic sign-in restoration on app launch (default: true)
    public let enableAutoSignInRestore: Bool
    
    public init(
        gmailScopes: [String] = ["https://www.googleapis.com/auth/gmail.readonly"],
        enableAutoTokenRefresh: Bool = true,
        tokenRefreshThreshold: TimeInterval = 5 * 60, // 5 minutes
        enableAccountPersistence: Bool = true,
        maxAccountLimit: Int = 10,
        enableAutoSignInRestore: Bool = true
    ) {
        self.gmailScopes = gmailScopes
        self.enableAutoTokenRefresh = enableAutoTokenRefresh
        self.tokenRefreshThreshold = tokenRefreshThreshold
        self.enableAccountPersistence = enableAccountPersistence
        self.maxAccountLimit = maxAccountLimit
        self.enableAutoSignInRestore = enableAutoSignInRestore
    }
}