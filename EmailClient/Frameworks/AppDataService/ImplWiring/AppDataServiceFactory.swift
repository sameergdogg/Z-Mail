import Foundation
import SwiftData

/// Factory for creating App Data Service instances with dependency injection
/// Follows the three-layer framework pattern from CLAUDE.md
internal class AppDataServiceFactory {
    
    /// Shared factory instance
    internal static let shared = AppDataServiceFactory()
    
    private init() {}
    
    /// Creates an App Data Service instance with the provided dependencies
    /// - Parameter dependencies: The dependencies for the service
    /// - Returns: A configured App Data Service instance
    @MainActor internal func createAppDataService(dependencies: AppDataServiceDependencies) -> AppDataServiceProtocol {
        return AppDataServiceImpl(dependencies: dependencies)
    }
    
    /// Creates an App Data Service instance with default dependencies
    /// - Parameters:
    ///   - configuration: Optional configuration (uses defaults if nil)
    ///   - classificationManagerFactory: Optional classification manager factory
    /// - Returns: A configured App Data Service instance with default dependencies
    @MainActor internal func createAppDataService(
        configuration: AppDataServiceConfiguration = AppDataServiceConfiguration(),
        classificationManagerFactory: ClassificationManagerFactoryProtocol? = nil
    ) -> AppDataServiceProtocol {
        let schemaProvider = DefaultSchemaProvider(configuration: configuration)
        let classificationFactory = classificationManagerFactory ?? DefaultClassificationManagerFactory()
        
        let dependencies = AppDataServiceDependencies(
            schemaProvider: schemaProvider,
            classificationManagerFactory: classificationFactory,
            configuration: configuration
        )
        
        return createAppDataService(dependencies: dependencies)
    }
    
    /// Creates an App Data Service instance for testing with custom dependencies
    /// - Parameters:
    ///   - schemaProvider: Custom schema provider for testing
    ///   - classificationManagerFactory: Custom classification manager factory
    ///   - configuration: Custom configuration for testing
    /// - Returns: An App Data Service instance configured for testing
    #if DEBUG
    @MainActor internal func createForTesting(
        schemaProvider: SchemaProviderProtocol,
        classificationManagerFactory: ClassificationManagerFactoryProtocol,
        configuration: AppDataServiceConfiguration = AppDataServiceConfiguration(isStoredInMemoryOnly: true)
    ) -> AppDataServiceProtocol {
        let dependencies = AppDataServiceDependencies(
            schemaProvider: schemaProvider,
            classificationManagerFactory: classificationManagerFactory,
            configuration: configuration
        )
        return createAppDataService(dependencies: dependencies)
    }
    #endif
}

/// Container for managing App Data Service instances
internal class AppDataServiceContainer {
    
    /// Shared container instance
    internal static let shared = AppDataServiceContainer()
    
    private var cachedService: AppDataServiceProtocol?
    private let lock = NSLock()
    
    private init() {}
    
    /// Gets or creates the shared App Data Service instance
    /// - Parameter configuration: Configuration for the service (only used on first creation)
    /// - Returns: The shared App Data Service instance
    @MainActor internal func getAppDataService(
        configuration: AppDataServiceConfiguration = AppDataServiceConfiguration()
    ) -> AppDataServiceProtocol {
        lock.lock()
        defer { lock.unlock() }
        
        if let existingService = cachedService {
            return existingService
        }
        
        let service = AppDataServiceFactory.shared.createAppDataService(configuration: configuration)
        cachedService = service
        return service
    }
    
    /// Gets or creates the shared App Data Service instance with custom factory
    /// - Parameters:
    ///   - configuration: Configuration for the service
    ///   - classificationManagerFactory: Custom classification manager factory
    /// - Returns: The shared App Data Service instance
    @MainActor internal func getAppDataService(
        configuration: AppDataServiceConfiguration = AppDataServiceConfiguration(),
        classificationManagerFactory: ClassificationManagerFactoryProtocol
    ) -> AppDataServiceProtocol {
        lock.lock()
        defer { lock.unlock() }
        
        if let existingService = cachedService {
            return existingService
        }
        
        let service = AppDataServiceFactory.shared.createAppDataService(
            configuration: configuration,
            classificationManagerFactory: classificationManagerFactory
        )
        cachedService = service
        return service
    }
    
    /// Clears the cached service instance (useful for testing or reset)
    internal func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedService = nil
    }
    
    #if DEBUG
    /// Creates a test container with custom app data service
    /// - Parameter service: The app data service to use
    /// - Returns: A container configured for testing
    internal static func createForTesting(service: AppDataServiceProtocol) -> AppDataServiceContainer {
        let container = AppDataServiceContainer()
        container.cachedService = service
        return container
    }
    #endif
}

/// Default implementation of ClassificationManagerFactoryProtocol
/// This bridges to the existing LaunchClassificationManager until it's migrated to framework structure
internal class DefaultClassificationManagerFactory: ClassificationManagerFactoryProtocol {
    
    @MainActor func createClassificationManager(modelContext: ModelContext) -> ClassificationManagerProtocol {
        // For now, return a bridge to the existing LaunchClassificationManager
        return ClassificationManagerBridge(modelContext: modelContext)
    }
}

/// Bridge to existing LaunchClassificationManager until it's fully migrated
internal class ClassificationManagerBridge: ClassificationManagerProtocol, ObservableObject {
    
    @Published var classificationProgress: Double = 0.0
    
    private let launchManager: LaunchClassificationManager
    
    @MainActor internal init(modelContext: ModelContext) {
        self.launchManager = LaunchClassificationManager(modelContext: modelContext)
        
        // Bind progress updates
        setupProgressBinding()
    }
    
    func performLaunchClassificationIfNeeded() async {
        await launchManager.performLaunchClassificationIfNeeded()
    }
    
    func forceFullClassification() async {
        await launchManager.forceFullClassification()
    }
    
    func getClassificationStatistics() async -> ClassificationStatistics? {
        return await launchManager.getClassificationStatistics()
    }
    
    func runBackgroundClassification() async {
        await launchManager.runBackgroundClassification()
    }
    
    @MainActor private func setupProgressBinding() {
        // Bind the progress from the existing manager
        launchManager.$classificationProgress
            .assign(to: &$classificationProgress)
    }
}