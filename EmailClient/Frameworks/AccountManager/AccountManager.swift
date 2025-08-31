// MARK: - Account Manager Framework
// This file exports the public API of the Account Manager framework

// Public API
@_exported import Foundation
@_exported import GoogleSignIn
@_exported import Combine

// Export Factory and Container
public typealias AccountManager = AccountManagerProtocol
public typealias AccountFactory = AccountManagerFactory
public typealias AccountContainer = AccountManagerContainer
public typealias AccountDependencies = AccountManagerDependencies

// Export Configuration and Models
public typealias AccountConfig = AccountManagerConfiguration
public typealias AccountPersistence = AccountPersistenceProtocol

/// Convenience accessor for the Account Manager
public struct AccountManagerAPI {
    /// Gets the shared Account Manager instance
    public static var shared: AccountManagerProtocol {
        return AccountManagerContainer.shared.getAccountManager()
    }
    
    /// Creates a new Account Manager instance with custom dependencies
    /// - Parameter dependencies: Custom dependencies for the manager
    /// - Returns: A new Account Manager instance
    public static func create(with dependencies: AccountManagerDependencies = AccountManagerDependencies()) -> AccountManagerProtocol {
        return AccountManagerFactory.shared.createAccountManager(dependencies: dependencies)
    }
    
    /// Creates a test instance with in-memory storage
    /// - Returns: An Account Manager instance configured for testing
    #if DEBUG
    public static func createForTesting(
        configuration: AccountManagerConfiguration = AccountManagerConfiguration(),
        persistenceStore: AccountPersistenceProtocol? = nil
    ) -> AccountManagerProtocol {
        return AccountManagerContainer.createForTesting(
            configuration: configuration,
            persistenceStore: persistenceStore
        ).getAccountManager()
    }
    #endif
}