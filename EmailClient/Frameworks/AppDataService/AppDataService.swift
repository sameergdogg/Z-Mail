// MARK: - App Data Service Framework
// This file exports the public API of the App Data Service framework

// Public API
@_exported import Foundation
@_exported import SwiftUI
@_exported import SwiftData
@_exported import Combine

// Export Factory and Container
public typealias AppDataService = AppDataServiceProtocol
internal typealias AppDataFactory = AppDataServiceFactory
internal typealias AppDataContainer = AppDataServiceContainer
public typealias AppDataDependencies = AppDataServiceDependencies

// Export Configuration and Models
public typealias AppDataConfig = AppDataServiceConfiguration

/// Convenience accessor for the App Data Service
public struct AppDataServiceAPI {
    /// Gets the shared App Data Service instance
    /// - Parameter configuration: Optional configuration (uses defaults if nil)
    /// - Returns: The App Data Service instance
    @MainActor public static func shared(
        configuration: AppDataServiceConfiguration = AppDataServiceConfiguration()
    ) -> AppDataServiceProtocol {
        return AppDataServiceContainer.shared.getAppDataService(configuration: configuration)
    }
    
    /// Gets the shared App Data Service instance with custom classification manager factory
    /// - Parameters:
    ///   - configuration: Configuration for the service
    ///   - classificationManagerFactory: Custom classification manager factory
    /// - Returns: The App Data Service instance
    @MainActor public static func shared(
        configuration: AppDataServiceConfiguration = AppDataServiceConfiguration(),
        classificationManagerFactory: ClassificationManagerFactoryProtocol
    ) -> AppDataServiceProtocol {
        return AppDataServiceContainer.shared.getAppDataService(
            configuration: configuration,
            classificationManagerFactory: classificationManagerFactory
        )
    }
    
    /// Gets the current App Data Service instance if it exists
    /// - Returns: The current App Data Service instance or nil
    public static var current: AppDataServiceProtocol? {
        // Note: This requires MainActor context, return nil if not available
        return nil
    }
    
    /// Creates a new App Data Service instance with custom dependencies
    /// - Parameter dependencies: Custom dependencies for the service
    /// - Returns: A new App Data Service instance
    @MainActor public static func create(with dependencies: AppDataServiceDependencies) -> AppDataServiceProtocol {
        return AppDataServiceFactory.shared.createAppDataService(dependencies: dependencies)
    }
    
    /// Creates an App Data Service instance with default dependencies
    /// - Parameters:
    ///   - configuration: Optional configuration
    ///   - classificationManagerFactory: Optional custom classification manager factory
    /// - Returns: A configured App Data Service instance
    @MainActor public static func create(
        configuration: AppDataServiceConfiguration = AppDataServiceConfiguration(),
        classificationManagerFactory: ClassificationManagerFactoryProtocol? = nil
    ) -> AppDataServiceProtocol {
        return AppDataServiceFactory.shared.createAppDataService(
            configuration: configuration,
            classificationManagerFactory: classificationManagerFactory
        )
    }
    
    /// Clears the cached service instance
    public static func clearCache() {
        AppDataServiceContainer.shared.clearCache()
    }
    
    /// Creates a test instance with custom dependencies
    /// - Parameters:
    ///   - schemaProvider: Custom schema provider for testing
    ///   - classificationManagerFactory: Custom classification manager factory
    ///   - configuration: Custom configuration for testing
    /// - Returns: An App Data Service instance configured for testing
    #if DEBUG
    @MainActor public static func createForTesting(
        schemaProvider: SchemaProviderProtocol,
        classificationManagerFactory: ClassificationManagerFactoryProtocol,
        configuration: AppDataServiceConfiguration = AppDataServiceConfiguration(isStoredInMemoryOnly: true)
    ) -> AppDataServiceProtocol {
        return AppDataServiceFactory.shared.createForTesting(
            schemaProvider: schemaProvider,
            classificationManagerFactory: classificationManagerFactory,
            configuration: configuration
        )
    }
    #endif
}