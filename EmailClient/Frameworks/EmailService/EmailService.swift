// MARK: - Email Service Framework
// This file exports the public API of the Email Service framework

// Public API
@_exported import Foundation
@_exported import SwiftUI
@_exported import GoogleSignIn
@_exported import Combine

// Export Factory and Container
public typealias EmailService = EmailServiceProtocol
public typealias EmailFactory = EmailServiceFactory
public typealias EmailContainer = EmailServiceContainer
public typealias EmailDependencies = EmailServiceDependencies

// Export Configuration and Models
public typealias EmailConfig = EmailServiceConfiguration

/// Convenience accessor for the Email Service
public struct EmailServiceAPI {
    /// Gets the shared Email Service instance with the provided account manager
    /// - Parameter accountManager: The account manager to use
    /// - Returns: The Email Service instance
    public static func shared(with accountManager: AccountManagerProtocol) -> EmailServiceProtocol {
        return EmailServiceContainer.shared.getEmailService(with: accountManager)
    }
    
    /// Gets the current Email Service instance if it exists
    /// - Returns: The current Email Service instance or nil
    public static var current: EmailServiceProtocol? {
        return EmailServiceContainer.shared.getCurrentEmailService()
    }
    
    /// Creates a new Email Service instance with custom dependencies
    /// - Parameter dependencies: Custom dependencies for the service
    /// - Returns: A new Email Service instance
    public static func create(with dependencies: EmailServiceDependencies) -> EmailServiceProtocol {
        return EmailServiceFactory.shared.createEmailService(dependencies: dependencies)
    }
    
    /// Creates an Email Service instance with default dependencies
    /// - Parameter accountManager: The account manager to use
    /// - Returns: A configured Email Service instance
    public static func create(with accountManager: AccountManagerProtocol) -> EmailServiceProtocol {
        return EmailServiceFactory.shared.createEmailService(with: accountManager)
    }
    
    /// Updates the account manager for the current service
    /// - Parameter newAccountManager: The new account manager
    public static func updateAccountManager(_ newAccountManager: AccountManagerProtocol) {
        EmailServiceContainer.shared.updateAccountManager(newAccountManager)
    }
    
    /// Creates a test instance with custom dependencies
    /// - Parameters:
    ///   - accountManager: The account manager to use
    ///   - configuration: Custom configuration for testing
    ///   - gmailAPIService: Custom Gmail API service for testing
    ///   - persistenceStore: Custom persistence store for testing
    /// - Returns: An Email Service instance configured for testing
    #if DEBUG
    public static func createForTesting(
        accountManager: AccountManagerProtocol,
        configuration: EmailServiceConfiguration = EmailServiceConfiguration(),
        gmailAPIService: GmailAPIServiceProtocol? = nil,
        persistenceStore: EmailPersistenceProtocol? = nil
    ) -> EmailServiceProtocol {
        return EmailServiceContainer.createForTesting(
            accountManager: accountManager,
            configuration: configuration,
            gmailAPIService: gmailAPIService,
            persistenceStore: persistenceStore
        ).getEmailService(with: accountManager)
    }
    #endif
}