import Foundation
import CoreData

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
    public let coreDataStack: CoreDataStack
    
    public init(
        configuration: PersistenceConfiguration = PersistenceConfiguration(),
        coreDataStack: CoreDataStack? = nil
    ) {
        self.configuration = configuration
        self.coreDataStack = coreDataStack ?? CoreDataStack()
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

/// Core Data stack with modern practices
public class CoreDataStack {
    
    // MARK: - Properties
    
    public lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "EmailDataModel")
        
        // Configure for better performance
        let description = container.persistentStoreDescriptions.first
        description?.shouldInferMappingModelAutomatically = true
        description?.shouldMigrateStoreAutomatically = true
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.loadPersistentStores { [weak self] _, error in
            if let error = error as NSError? {
                print("Core Data error: \(error), \(error.userInfo)")
                self?.handleCoreDataError(error)
            }
        }
        
        // Configure view context for better performance
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return container
    }()
    
    public var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    public var backgroundContext: NSManagedObjectContext {
        return persistentContainer.newBackgroundContext()
    }
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Core Data Operations
    
    /// Saves the main context if it has changes
    public func saveContext() throws {
        guard viewContext.hasChanges else { return }
        
        do {
            try viewContext.save()
        } catch {
            print("Failed to save main context: \(error)")
            throw EmailPersistenceError.coreDataError(error)
        }
    }
    
    /// Performs a background task with automatic saving
    public func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            let context = backgroundContext
            context.perform {
                do {
                    let result = try block(context)
                    
                    if context.hasChanges {
                        try context.save()
                    }
                    
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Performs a background task that returns void
    public func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) throws -> Void) async throws {
        let _: Void = try await performBackgroundTask(block)
    }
    
    // MARK: - Error Handling
    
    private func handleCoreDataError(_ error: NSError) {
        // Log the error
        print("Core Data Stack Error: \(error.localizedDescription)")
        
        // Check for common error conditions
        if error.code == NSPersistentStoreIncompatibleVersionHashError {
            // Handle migration errors
            print("Database needs migration or is corrupted")
            // In a real app, you might want to delete and recreate the store
        }
    }
}

// MARK: - Testing Support

#if DEBUG
public extension EmailPersistenceContainer {
    /// Creates an in-memory store for testing
    static func createForTesting() -> EmailPersistenceContainer {
        let container = NSPersistentContainer(name: "EmailDataModel")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to create in-memory store: \(error)")
            }
        }
        
        let coreDataStack = CoreDataStack()
        coreDataStack.persistentContainer = container
        
        let dependencies = EmailPersistenceDependencies(coreDataStack: coreDataStack)
        return EmailPersistenceContainer(dependencies: dependencies)
    }
}

#endif