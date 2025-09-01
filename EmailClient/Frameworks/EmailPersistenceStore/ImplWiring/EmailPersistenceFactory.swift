import Foundation
import SwiftData

/// Factory for creating Email Persistence Store instances
public class EmailPersistenceFactory {
    
    /// Shared singleton instance of the factory
    public static let shared = EmailPersistenceFactory()
    
    private init() {}
    
    /// Creates and returns an Email Persistence Store instance
    /// - Parameters:
    ///   - dependencies: Dependencies required by the persistence store
    /// - Returns: A configured Email Persistence Store instance
    public func createEmailPersistenceStore(
        dependencies: EmailPersistenceDependencies = EmailPersistenceDependencies()
    ) -> EmailPersistenceProtocol {
        do {
            print("🏭 Creating SwiftData EmailPersistenceStore...")
            return try SwiftDataEmailPersistenceStoreImpl(dependencies: dependencies)
        } catch {
            print("❌ Failed to create SwiftData store: \(error)")
            print("🔄 Falling back to in-memory implementation...")
            // Fallback to in-memory implementation if SwiftData fails
            return EmailPersistenceStoreImpl(dependencies: dependencies)
        }
    }
}

/// Dependencies container for Email Persistence Store
public class EmailPersistenceDependencies {
    public let configuration: PersistenceConfiguration
    
    public init(
        configuration: PersistenceConfiguration = PersistenceConfiguration()
    ) {
        self.configuration = configuration
    }
}

/// Dependency injection container for the Email Persistence Store framework
public class EmailPersistenceContainer {
    public static let shared = EmailPersistenceContainer()
    
    private var storeInstance: EmailPersistenceProtocol?
    private let dependencies: EmailPersistenceDependencies
    
    private init(dependencies: EmailPersistenceDependencies = EmailPersistenceDependencies()) {
        self.dependencies = dependencies
    }
    
    /// Gets or creates the Email Persistence Store instance
    public func getEmailPersistenceStore() -> EmailPersistenceProtocol {
        if let store = storeInstance {
            return store
        }
        
        let store = EmailPersistenceFactory.shared.createEmailPersistenceStore(dependencies: dependencies)
        storeInstance = store
        return store
    }
    
    /// Resets the container (useful for testing)
    public func reset() {
        storeInstance = nil
    }
    
    /// Sets a custom store instance (useful for testing)
    public func setStore(_ store: EmailPersistenceProtocol) {
        storeInstance = store
    }
}

// MARK: - Testing Support

#if DEBUG
public extension EmailPersistenceContainer {
    /// Creates an in-memory store for testing
    static func createForTesting() -> EmailPersistenceContainer {
        let configuration = PersistenceConfiguration(isInMemoryOnly: true)
        let dependencies = EmailPersistenceDependencies(configuration: configuration)
        return EmailPersistenceContainer(dependencies: dependencies)
    }
}
#endif
