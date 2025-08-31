import Foundation

/// Factory for creating Email Service instances
public class EmailServiceFactory {
    
    /// Shared singleton instance of the factory
    public static let shared = EmailServiceFactory()
    
    private init() {}
    
    /// Creates and returns an Email Service instance
    /// - Parameters:
    ///   - dependencies: Dependencies required by the email service
    /// - Returns: A configured Email Service instance
    public func createEmailService(
        dependencies: EmailServiceDependencies
    ) -> EmailServiceProtocol {
        print("🏭 Creating EmailService with configuration...")
        return EmailServiceImpl(dependencies: dependencies)
    }
    
    /// Creates an Email Service instance with default dependencies
    /// - Parameter accountManager: The account manager to use
    /// - Returns: A configured Email Service instance
    public func createEmailService(
        with accountManager: AccountManagerProtocol
    ) -> EmailServiceProtocol {
        let dependencies = EmailServiceDependencies(accountManager: accountManager)
        return createEmailService(dependencies: dependencies)
    }
}

/// Dependencies container for Email Service
public class EmailServiceDependencies {
    public let accountManager: AccountManagerProtocol
    public let configuration: EmailServiceConfiguration
    public let gmailAPIService: GmailAPIServiceProtocol
    public let persistenceStore: EmailPersistenceProtocol
    
    public init(
        accountManager: AccountManagerProtocol,
        configuration: EmailServiceConfiguration = EmailServiceConfiguration(),
        gmailAPIService: GmailAPIServiceProtocol? = nil,
        persistenceStore: EmailPersistenceProtocol? = nil
    ) {
        self.accountManager = accountManager
        self.configuration = configuration
        
        // Use framework containers to get instances
        self.gmailAPIService = gmailAPIService ?? GmailAPIServiceContainer.shared.getGmailAPIService()
        self.persistenceStore = persistenceStore ?? EmailPersistenceContainer.shared.getEmailPersistenceStore()
    }
}

/// Dependency injection container for the Email Service framework
public class EmailServiceContainer {
    public static let shared = EmailServiceContainer()
    
    private var serviceInstance: EmailServiceProtocol?
    private var dependencies: EmailServiceDependencies?
    
    private init() {}
    
    /// Gets or creates the Email Service instance
    /// - Parameter accountManager: The account manager to use
    /// - Returns: The Email Service instance
    public func getEmailService(with accountManager: AccountManagerProtocol) -> EmailServiceProtocol {
        // If we don't have an instance or the account manager changed, create a new one
        if let service = serviceInstance,
           let deps = dependencies,
           deps.accountManager === accountManager {
            return service
        }
        
        let deps = EmailServiceDependencies(accountManager: accountManager)
        let service = EmailServiceFactory.shared.createEmailService(dependencies: deps)
        
        serviceInstance = service
        dependencies = deps
        
        return service
    }
    
    /// Gets the current Email Service instance if it exists
    /// - Returns: The current Email Service instance or nil
    public func getCurrentEmailService() -> EmailServiceProtocol? {
        return serviceInstance
    }
    
    /// Resets the container (useful for testing)
    public func reset() {
        serviceInstance = nil
        dependencies = nil
    }
    
    /// Sets a custom service instance (useful for testing)
    /// - Parameter service: The service instance to set
    public func setService(_ service: EmailServiceProtocol) {
        serviceInstance = service
        dependencies = nil // Clear dependencies since we have a custom instance
    }
    
    /// Updates the account manager for the current service
    /// - Parameter newAccountManager: The new account manager
    public func updateAccountManager(_ newAccountManager: AccountManagerProtocol) {
        if let service = serviceInstance {
            service.updateAccountManager(newAccountManager)
            
            // Update dependencies
            dependencies = EmailServiceDependencies(accountManager: newAccountManager)
        }
    }
}

// MARK: - Testing Support

#if DEBUG
public extension EmailServiceContainer {
    /// Creates an in-memory service for testing
    /// - Parameters:
    ///   - accountManager: The account manager to use
    ///   - configuration: Custom configuration for testing
    ///   - gmailAPIService: Custom Gmail API service for testing
    ///   - persistenceStore: Custom persistence store for testing
    /// - Returns: A test-configured Email Service Container
    static func createForTesting(
        accountManager: AccountManagerProtocol,
        configuration: EmailServiceConfiguration = EmailServiceConfiguration(),
        gmailAPIService: GmailAPIServiceProtocol? = nil,
        persistenceStore: EmailPersistenceProtocol? = nil
    ) -> EmailServiceContainer {
        let container = EmailServiceContainer()
        let dependencies = EmailServiceDependencies(
            accountManager: accountManager,
            configuration: configuration,
            gmailAPIService: gmailAPIService,
            persistenceStore: persistenceStore
        )
        let service = EmailServiceFactory.shared.createEmailService(dependencies: dependencies)
        container.setService(service)
        return container
    }
}
#endif