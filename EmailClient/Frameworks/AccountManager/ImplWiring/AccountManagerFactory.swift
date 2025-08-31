import Foundation
import GoogleSignIn

/// Factory for creating Account Manager instances
public class AccountManagerFactory {
    
    /// Shared singleton instance of the factory
    public static let shared = AccountManagerFactory()
    
    private init() {}
    
    /// Creates and returns an Account Manager instance
    /// - Parameters:
    ///   - dependencies: Dependencies required by the account manager
    /// - Returns: A configured Account Manager instance
    public func createAccountManager(
        dependencies: AccountManagerDependencies = AccountManagerDependencies()
    ) -> AccountManagerProtocol {
        print("🏭 Creating AccountManager with configuration...")
        return AccountManagerImpl(dependencies: dependencies)
    }
}

/// Dependencies container for Account Manager
public class AccountManagerDependencies {
    public let configuration: AccountManagerConfiguration
    public let persistenceStore: AccountPersistenceProtocol
    public let googleSignInConfig: GIDConfiguration?
    
    public init(
        configuration: AccountManagerConfiguration = AccountManagerConfiguration(),
        persistenceStore: AccountPersistenceProtocol? = nil,
        googleSignInConfig: GIDConfiguration? = nil
    ) {
        self.configuration = configuration
        self.persistenceStore = persistenceStore ?? UserDefaultsAccountPersistence()
        self.googleSignInConfig = googleSignInConfig
    }
}

/// Dependency injection container for the Account Manager framework
public class AccountManagerContainer {
    public static let shared = AccountManagerContainer()
    
    private var managerInstance: AccountManagerProtocol?
    private let dependencies: AccountManagerDependencies
    
    private init(dependencies: AccountManagerDependencies = AccountManagerDependencies()) {
        self.dependencies = dependencies
    }
    
    /// Gets or creates the Account Manager instance
    public func getAccountManager() -> AccountManagerProtocol {
        if let manager = managerInstance {
            return manager
        }
        
        let manager = AccountManagerFactory.shared.createAccountManager(dependencies: dependencies)
        managerInstance = manager
        return manager
    }
    
    /// Resets the container (useful for testing)
    public func reset() {
        managerInstance = nil
    }
    
    /// Sets a custom manager instance (useful for testing)
    public func setManager(_ manager: AccountManagerProtocol) {
        managerInstance = manager
    }
}

// MARK: - Account Persistence Protocol

/// Protocol for persisting account data
public protocol AccountPersistenceProtocol {
    /// Saves accounts to persistent storage
    /// - Parameter accounts: Array of accounts to save
    func saveAccounts(_ accounts: [GmailAccount]) throws
    
    /// Loads accounts from persistent storage
    /// - Returns: Array of saved accounts
    func loadAccounts() throws -> [GmailAccount]
    
    /// Clears all saved account data
    func clearAllAccounts() throws
    
    /// Saves a single account
    /// - Parameter account: The account to save
    func saveAccount(_ account: GmailAccount) throws
    
    /// Removes a specific account
    /// - Parameter accountId: ID of the account to remove
    func removeAccount(with accountId: String) throws
}

// MARK: - UserDefaults Implementation

/// UserDefaults-based implementation of account persistence
internal class UserDefaultsAccountPersistence: AccountPersistenceProtocol {
    private let userDefaults = UserDefaults.standard
    private let accountsKey = "gmail_accounts"
    
    func saveAccounts(_ accounts: [GmailAccount]) throws {
        do {
            let data = try JSONEncoder().encode(accounts)
            userDefaults.set(data, forKey: accountsKey)
            print("💾 Saved \(accounts.count) accounts to UserDefaults")
        } catch {
            throw AccountError.persistenceError(error)
        }
    }
    
    func loadAccounts() throws -> [GmailAccount] {
        guard let data = userDefaults.data(forKey: accountsKey) else {
            print("💾 No account data found in UserDefaults")
            return []
        }
        
        do {
            let accounts = try JSONDecoder().decode([GmailAccount].self, from: data)
            print("💾 Loaded \(accounts.count) accounts from UserDefaults")
            return accounts
        } catch {
            print("❌ Failed to decode account data: \(error)")
            throw AccountError.persistenceError(error)
        }
    }
    
    func clearAllAccounts() throws {
        userDefaults.removeObject(forKey: accountsKey)
        print("💾 Cleared all account data from UserDefaults")
    }
    
    func saveAccount(_ account: GmailAccount) throws {
        var accounts = try loadAccounts()
        
        // Remove existing account with same ID if it exists
        accounts.removeAll { $0.id == account.id }
        
        // Add the new/updated account
        accounts.append(account)
        
        try saveAccounts(accounts)
    }
    
    func removeAccount(with accountId: String) throws {
        var accounts = try loadAccounts()
        accounts.removeAll { $0.id == accountId }
        try saveAccounts(accounts)
    }
}

// MARK: - Testing Support

#if DEBUG
public extension AccountManagerContainer {
    /// Creates an in-memory manager for testing
    static func createForTesting(
        configuration: AccountManagerConfiguration = AccountManagerConfiguration(),
        persistenceStore: AccountPersistenceProtocol? = nil
    ) -> AccountManagerContainer {
        let testPersistence = persistenceStore ?? InMemoryAccountPersistence()
        let dependencies = AccountManagerDependencies(
            configuration: configuration,
            persistenceStore: testPersistence
        )
        return AccountManagerContainer(dependencies: dependencies)
    }
}

/// In-memory persistence implementation for testing
internal class InMemoryAccountPersistence: AccountPersistenceProtocol {
    private var accounts: [GmailAccount] = []
    
    func saveAccounts(_ accounts: [GmailAccount]) throws {
        self.accounts = accounts
        print("🧪 Saved \(accounts.count) accounts to in-memory storage")
    }
    
    func loadAccounts() throws -> [GmailAccount] {
        print("🧪 Loaded \(accounts.count) accounts from in-memory storage")
        return accounts
    }
    
    func clearAllAccounts() throws {
        accounts.removeAll()
        print("🧪 Cleared all accounts from in-memory storage")
    }
    
    func saveAccount(_ account: GmailAccount) throws {
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        print("🧪 Saved account \(account.email) to in-memory storage")
    }
    
    func removeAccount(with accountId: String) throws {
        accounts.removeAll { $0.id == accountId }
        print("🧪 Removed account \(accountId) from in-memory storage")
    }
}
#endif