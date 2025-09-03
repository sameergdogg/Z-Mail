import Foundation
import SwiftData

/// Factory for creating Email Classification Service instances with dependency injection
/// Follows the three-layer framework pattern from CLAUDE.md
internal class EmailClassificationServiceFactory {
    
    /// Shared factory instance
    internal static let shared = EmailClassificationServiceFactory()
    
    private init() {}
    
    /// Creates an Email Classification Service instance with the provided dependencies
    /// - Parameter dependencies: The dependencies for the service
    /// - Returns: A configured Email Classification Service instance
    @MainActor internal func createEmailClassificationService(dependencies: EmailClassificationServiceDependencies) -> EmailClassificationServiceProtocol {
        return EmailClassificationServiceImpl(dependencies: dependencies)
    }
    
    /// Creates an Email Classification Service instance with SwiftData repository and secure config provider
    /// - Parameters:
    ///   - modelContext: SwiftData model context
    ///   - configuration: Optional configuration (uses defaults if nil)
    /// - Returns: A configured Email Classification Service instance with default dependencies
    @MainActor internal func createEmailClassificationService(
        modelContext: ModelContext,
        configuration: EmailClassificationServiceConfiguration = EmailClassificationServiceConfiguration()
    ) -> EmailClassificationServiceProtocol {
        let repository = SwiftDataEmailRepository(
            modelContext: modelContext,
            enableDebugLogging: configuration.enableDebugLogging
        )
        let provider = SecureConfigClassificationProvider()
        
        let dependencies = EmailClassificationServiceDependencies(
            classificationProvider: provider,
            emailRepository: repository,
            configuration: configuration
        )
        
        return createEmailClassificationService(dependencies: dependencies)
    }
    
    /// Creates an Email Classification Service instance for testing with custom dependencies
    /// - Parameters:
    ///   - classificationProvider: Custom classification provider for testing
    ///   - emailRepository: Custom email repository for testing
    ///   - configuration: Custom configuration for testing
    /// - Returns: An Email Classification Service instance configured for testing
    #if DEBUG
    @MainActor internal func createForTesting(
        classificationProvider: EmailClassificationProviderProtocol,
        emailRepository: EmailRepositoryProtocol,
        configuration: EmailClassificationServiceConfiguration = EmailClassificationServiceConfiguration()
    ) -> EmailClassificationServiceProtocol {
        let dependencies = EmailClassificationServiceDependencies(
            classificationProvider: classificationProvider,
            emailRepository: emailRepository,
            configuration: configuration
        )
        return createEmailClassificationService(dependencies: dependencies)
    }
    #endif
}

/// Container for managing Email Classification Service instances
internal class EmailClassificationServiceContainer {
    
    /// Shared container instance
    internal static let shared = EmailClassificationServiceContainer()
    
    private var cachedServices: [String: EmailClassificationServiceProtocol] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    /// Gets or creates an Email Classification Service instance for the given model context
    /// - Parameters:
    ///   - modelContext: SwiftData model context
    ///   - configuration: Configuration for the service (only used on first creation)
    /// - Returns: The Email Classification Service instance
    @MainActor internal func getEmailClassificationService(
        modelContext: ModelContext,
        configuration: EmailClassificationServiceConfiguration = EmailClassificationServiceConfiguration()
    ) -> EmailClassificationServiceProtocol {
        let contextKey = String(describing: modelContext)
        
        lock.lock()
        defer { lock.unlock() }
        
        if let existingService = cachedServices[contextKey] {
            return existingService
        }
        
        let service = EmailClassificationServiceFactory.shared.createEmailClassificationService(
            modelContext: modelContext,
            configuration: configuration
        )
        cachedServices[contextKey] = service
        return service
    }
    
    /// Clears all cached service instances (useful for testing or memory management)
    internal func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedServices.removeAll()
    }
    
    /// Clears the cached service instance for a specific model context
    /// - Parameter modelContext: The model context to clear
    internal func clearCache(for modelContext: ModelContext) {
        let contextKey = String(describing: modelContext)
        
        lock.lock()
        defer { lock.unlock() }
        cachedServices.removeValue(forKey: contextKey)
    }
    
    #if DEBUG
    /// Creates a test container with custom email classification service
    /// - Parameter service: The email classification service to use
    /// - Returns: A container configured for testing
    internal static func createForTesting(service: any EmailClassificationServiceProtocol) -> EmailClassificationServiceContainer {
        let container = EmailClassificationServiceContainer()
        container.cachedServices["test"] = service
        return container
    }
    #endif
}

/// Bridge to existing SecureConfigurationManager for classification provider
internal class SecureConfigClassificationProvider: EmailClassificationProviderProtocol {
    
    private let secureConfigManager = SecureConfigurationManager.shared
    
    func classifyEmail(_ emailData: EmailData) async throws -> EmailClassificationResult {
        // This bridges to the existing SecureConfigurationManager's classifyEmail method
        let result = try await secureConfigManager.classifyEmail(emailData)
        
        // Convert the result to our framework's structure
        return EmailClassificationResult(
            emailId: emailData.id,
            category: EmailCategory.allCases.first { $0.rawValue == result.category.rawValue } ?? .other,
            confidence: result.confidence,
            rationale: result.rationale,
            summary: result.summary
        )
    }
    
    func isConfigured() -> Bool {
        return secureConfigManager.hasOpenAIAPIKey()
    }
    
    func getConfigurationError() -> String? {
        if !secureConfigManager.hasOpenAIAPIKey() {
            return "OpenAI API key not configured"
        }
        return nil
    }
}