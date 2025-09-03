// MARK: - Email Classification Service Framework
// This file exports the public API of the Email Classification Service framework

// Public API
@_exported import Foundation
@_exported import SwiftUI
@_exported import SwiftData
@_exported import Combine

// Export Service Protocol and Dependencies  
public typealias EmailClassificationService = EmailClassificationServiceProtocol
public typealias EmailClassificationDependencies = EmailClassificationServiceDependencies
// Note: Factory and Container are internal - use EmailClassificationServiceAPI instead

// Export Configuration and Models
public typealias EmailClassificationConfig = EmailClassificationServiceConfiguration

/// Convenience accessor for the Email Classification Service
public struct EmailClassificationServiceAPI {
    /// Gets the Email Classification Service instance for the given model context
    /// - Parameters:
    ///   - modelContext: SwiftData model context
    ///   - configuration: Optional configuration (uses defaults if nil)
    /// - Returns: The Email Classification Service instance
    @MainActor public static func shared(
        modelContext: ModelContext,
        configuration: EmailClassificationServiceConfiguration = EmailClassificationServiceConfiguration()
    ) -> EmailClassificationServiceProtocol {
        return EmailClassificationServiceContainer.shared.getEmailClassificationService(
            modelContext: modelContext,
            configuration: configuration
        )
    }
    
    /// Creates a new Email Classification Service instance with custom dependencies
    /// - Parameter dependencies: Custom dependencies for the service
    /// - Returns: A new Email Classification Service instance
    @MainActor public static func create(with dependencies: EmailClassificationServiceDependencies) -> EmailClassificationServiceProtocol {
        return EmailClassificationServiceFactory.shared.createEmailClassificationService(dependencies: dependencies)
    }
    
    /// Creates an Email Classification Service instance with default dependencies
    /// - Parameters:
    ///   - modelContext: SwiftData model context
    ///   - configuration: Optional configuration
    /// - Returns: A configured Email Classification Service instance
    @MainActor public static func create(
        modelContext: ModelContext,
        configuration: EmailClassificationServiceConfiguration = EmailClassificationServiceConfiguration()
    ) -> EmailClassificationServiceProtocol {
        return EmailClassificationServiceFactory.shared.createEmailClassificationService(
            modelContext: modelContext,
            configuration: configuration
        )
    }
    
    /// Clears all cached service instances
    public static func clearCache() {
        EmailClassificationServiceContainer.shared.clearCache()
    }
    
    /// Clears the cached service instance for a specific model context
    /// - Parameter modelContext: The model context to clear
    public static func clearCache(for modelContext: ModelContext) {
        EmailClassificationServiceContainer.shared.clearCache(for: modelContext)
    }
    
    /// Creates a test instance with custom dependencies
    /// - Parameters:
    ///   - classificationProvider: Custom classification provider for testing
    ///   - emailRepository: Custom email repository for testing
    ///   - configuration: Custom configuration for testing
    /// - Returns: An Email Classification Service instance configured for testing
    #if DEBUG
    @MainActor public static func createForTesting(
        classificationProvider: EmailClassificationProviderProtocol,
        emailRepository: EmailRepositoryProtocol,
        configuration: EmailClassificationServiceConfiguration = EmailClassificationServiceConfiguration()
    ) -> EmailClassificationServiceProtocol {
        return EmailClassificationServiceFactory.shared.createForTesting(
            classificationProvider: classificationProvider,
            emailRepository: emailRepository,
            configuration: configuration
        )
    }
    #endif
}