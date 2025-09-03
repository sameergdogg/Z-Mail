import Foundation
import SwiftData

/// Factory for creating Service Registry instances with dependency injection
/// Follows the three-layer framework pattern from CLAUDE.md
internal class ServiceRegistryFactory {
    
    /// Shared factory instance
    internal static let shared = ServiceRegistryFactory()
    
    private init() {}
    
    /// Creates a Service Registry instance with the provided dependencies
    /// - Parameter dependencies: The dependencies for the service registry
    /// - Returns: A configured Service Registry instance
    internal func createServiceRegistry(dependencies: ServiceRegistryDependencies) -> ServiceRegistryProtocol {
        return ServiceRegistryImpl(dependencies: dependencies)
    }
    
    /// Creates a Service Registry instance with default dependencies
    /// - Parameter configuration: Optional configuration (uses defaults if nil)
    /// - Returns: A configured Service Registry instance with default dependencies
    internal func createServiceRegistry(
        configuration: ServiceRegistryConfiguration = ServiceRegistryConfiguration()
    ) -> ServiceRegistryProtocol {
        let configManager = DefaultServiceConfigurationManager()
        let lifecycleManager = DefaultServiceLifecycleManager()
        
        let dependencies = ServiceRegistryDependencies(
            configurationManager: configManager,
            lifecycleManager: lifecycleManager,
            configuration: configuration
        )
        
        return createServiceRegistry(dependencies: dependencies)
    }
    
    /// Creates a Service Registry instance for testing with custom dependencies
    /// - Parameters:
    ///   - configurationManager: Custom configuration manager for testing
    ///   - lifecycleManager: Custom lifecycle manager for testing
    ///   - configuration: Custom configuration for testing
    /// - Returns: A Service Registry instance configured for testing
    #if DEBUG
    internal func createForTesting(
        configurationManager: ServiceConfigurationManagerProtocol,
        lifecycleManager: ServiceLifecycleManagerProtocol,
        configuration: ServiceRegistryConfiguration = ServiceRegistryConfiguration()
    ) -> ServiceRegistryProtocol {
        let dependencies = ServiceRegistryDependencies(
            configurationManager: configurationManager,
            lifecycleManager: lifecycleManager,
            configuration: configuration
        )
        return createServiceRegistry(dependencies: dependencies)
    }
    #endif
}

/// Container for managing Service Registry instances
internal class ServiceRegistryContainer {
    
    /// Shared container instance
    internal static let shared = ServiceRegistryContainer()
    
    private var cachedRegistry: ServiceRegistryProtocol?
    private let lock = NSLock()
    
    private init() {}
    
    /// Gets or creates the shared Service Registry instance
    /// - Parameter configuration: Configuration for the registry (only used on first creation)
    /// - Returns: The shared Service Registry instance
    internal func getServiceRegistry(
        configuration: ServiceRegistryConfiguration = ServiceRegistryConfiguration()
    ) -> ServiceRegistryProtocol {
        lock.lock()
        defer { lock.unlock() }
        
        if let existingRegistry = cachedRegistry {
            return existingRegistry
        }
        
        let registry = ServiceRegistryFactory.shared.createServiceRegistry(configuration: configuration)
        cachedRegistry = registry
        return registry
    }
    
    /// Clears the cached registry instance (useful for testing or reset)
    internal func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedRegistry = nil
    }
    
    #if DEBUG
    /// Creates a test container with custom service registry
    /// - Parameter registry: The service registry to use
    /// - Returns: A container configured for testing
    internal static func createForTesting(registry: ServiceRegistryProtocol) -> ServiceRegistryContainer {
        let container = ServiceRegistryContainer()
        container.cachedRegistry = registry
        return container
    }
    #endif
}

/// Service registry configurator for setting up all framework services
public class ServiceRegistryConfigurator {
    
    private let registry: ServiceRegistryProtocol
    
    internal init(registry: ServiceRegistryProtocol) {
        self.registry = registry
    }
    
    /// Configures all framework services with their default implementations
    /// - Parameter modelContext: SwiftData model context for services that need it
    @MainActor public func configureAllServices(modelContext: ModelContext) {
        // Register SettingsService
        let settingsService = SettingsServiceAPI.shared()
        registry.register(settingsService, for: SettingsServiceProtocol.self)
        
        // Register AppDataService (this needs special handling since it manages the model context)
        let appDataService = AppDataServiceAPI.shared()
        registry.register(appDataService, for: AppDataServiceProtocol.self)
        
        // Register EmailClassificationService
        let classificationService = EmailClassificationServiceAPI.shared(modelContext: modelContext)
        registry.register(classificationService, for: EmailClassificationServiceProtocol.self)
        
        // Register existing framework services
        let accountManager = AccountManagerAPI.shared
        registry.register(accountManager, for: AccountManagerProtocol.self)
        
        let emailService = EmailServiceAPI.shared(with: accountManager)
        registry.register(emailService, for: EmailServiceProtocol.self)
    }
    
    /// Configures services with custom configurations
    /// - Parameters:
    ///   - modelContext: SwiftData model context
    ///   - settingsConfig: Custom settings service configuration
    ///   - appDataConfig: Custom app data service configuration
    ///   - classificationConfig: Custom classification service configuration
    @MainActor public func configureServices(
        modelContext: ModelContext,
        settingsConfig: SettingsServiceConfiguration? = nil,
        appDataConfig: AppDataServiceConfiguration? = nil,
        classificationConfig: EmailClassificationServiceConfiguration? = nil
    ) {
        // Register SettingsService with custom config
        let settingsService = SettingsServiceAPI.create(configuration: settingsConfig ?? SettingsServiceConfiguration())
        registry.register(settingsService, for: SettingsServiceProtocol.self)
        
        // Register AppDataService with custom config
        let appDataService = AppDataServiceAPI.create(configuration: appDataConfig ?? AppDataServiceConfiguration())
        registry.register(appDataService, for: AppDataServiceProtocol.self)
        
        // Register EmailClassificationService with custom config
        let classificationService = EmailClassificationServiceAPI.create(
            modelContext: modelContext,
            configuration: classificationConfig ?? EmailClassificationServiceConfiguration()
        )
        registry.register(classificationService, for: EmailClassificationServiceProtocol.self)
        
        // Register existing framework services
        let accountManager = AccountManagerAPI.shared
        registry.register(accountManager, for: AccountManagerProtocol.self)
        
        let emailService = EmailServiceAPI.shared(with: accountManager)
        registry.register(emailService, for: EmailServiceProtocol.self)
    }
}