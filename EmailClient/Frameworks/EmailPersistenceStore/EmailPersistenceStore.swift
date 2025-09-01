// MARK: - Email Persistence Store Framework
// This file exports the public API of the Email Persistence Store framework

// Public API
@_exported import Foundation
@_exported import SwiftData
@_exported import Combine

// Export Factory and Container
public typealias EmailPersistence = EmailPersistenceProtocol
public typealias PersistenceFactory = EmailPersistenceFactory
public typealias PersistenceContainer = EmailPersistenceContainer
public typealias PersistenceDependencies = EmailPersistenceDependencies

// Export Configuration
public typealias PersistenceConfig = PersistenceConfiguration

/// Convenience accessor for the Email Persistence Store
public struct EmailPersistenceAPI {
    /// Gets the shared Email Persistence Store instance
    public static var shared: EmailPersistenceProtocol {
        return EmailPersistenceContainer.shared.getEmailPersistenceStore()
    }
    
    /// Creates a new Email Persistence Store instance with custom dependencies
    /// - Parameter dependencies: Custom dependencies for the store
    /// - Returns: A new Email Persistence Store instance
    public static func create(with dependencies: EmailPersistenceDependencies = EmailPersistenceDependencies()) -> EmailPersistenceProtocol {
        return EmailPersistenceFactory.shared.createEmailPersistenceStore(dependencies: dependencies)
    }
    
    /// Creates a test instance with in-memory storage
    /// - Returns: An Email Persistence Store instance configured for testing
    #if DEBUG
    public static func createForTesting() -> EmailPersistenceProtocol {
        return EmailPersistenceContainer.createForTesting().getEmailPersistenceStore()
    }
    #endif
}