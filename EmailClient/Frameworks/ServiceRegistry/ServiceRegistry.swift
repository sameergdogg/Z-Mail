// MARK: - Service Registry Framework
// This file exports the public API of the Service Registry framework

// Public API
@_exported import Foundation
@_exported import SwiftUI
@_exported import SwiftData
@_exported import Combine

// Export Service Protocol and Dependencies
public typealias ServiceRegistry = ServiceRegistryProtocol
public typealias ServiceDependencies = ServiceRegistryDependencies
// Note: Factory and Container are internal - use ServiceRegistryAPI instead

// Export Configuration and Models
public typealias ServiceConfig = ServiceRegistryConfiguration

/// Convenience accessor for the Service Registry
public struct ServiceRegistryAPI {
    /// Gets the shared Service Registry instance
    /// - Parameter configuration: Optional configuration (uses defaults if nil)
    /// - Returns: The Service Registry instance
    public static func shared(
        configuration: ServiceRegistryConfiguration = ServiceRegistryConfiguration()
    ) -> ServiceRegistryProtocol {
        return ServiceRegistryContainer.shared.getServiceRegistry(configuration: configuration)
    }
    
    /// Gets the current Service Registry instance if it exists
    /// - Returns: The current Service Registry instance or nil
    public static var current: ServiceRegistryProtocol? {
        return ServiceRegistryContainer.shared.getServiceRegistry()
    }
    
    /// Creates a new Service Registry instance with custom dependencies
    /// - Parameter dependencies: Custom dependencies for the service registry
    /// - Returns: A new Service Registry instance
    public static func create(with dependencies: ServiceRegistryDependencies) -> ServiceRegistryProtocol {
        return ServiceRegistryFactory.shared.createServiceRegistry(dependencies: dependencies)
    }
    
    /// Creates a Service Registry instance with default dependencies
    /// - Parameter configuration: Optional configuration
    /// - Returns: A configured Service Registry instance
    public static func create(
        configuration: ServiceRegistryConfiguration = ServiceRegistryConfiguration()
    ) -> ServiceRegistryProtocol {
        return ServiceRegistryFactory.shared.createServiceRegistry(configuration: configuration)
    }
    
    /// Clears the cached service registry instance
    public static func clearCache() {
        ServiceRegistryContainer.shared.clearCache()
    }
    
    /// Creates a configured service registry with all framework services
    /// - Parameters:
    ///   - modelContext: SwiftData model context for services that need it
    ///   - configuration: Optional registry configuration
    /// - Returns: Fully configured service registry
    @MainActor public static func createConfiguredRegistry(
        modelContext: ModelContext,
        configuration: ServiceRegistryConfiguration = ServiceRegistryConfiguration()
    ) -> ServiceRegistryProtocol {
        let registry = create(configuration: configuration)
        let configurator = ServiceRegistryConfigurator(registry: registry)
        configurator.configureAllServices(modelContext: modelContext)
        return registry
    }
    
    /// Creates a configured service registry with custom service configurations
    /// - Parameters:
    ///   - modelContext: SwiftData model context
    ///   - registryConfig: Registry configuration
    ///   - settingsConfig: Custom settings service configuration
    ///   - appDataConfig: Custom app data service configuration
    ///   - classificationConfig: Custom classification service configuration
    /// - Returns: Fully configured service registry
    @MainActor public static func createConfiguredRegistry(
        modelContext: ModelContext,
        registryConfig: ServiceRegistryConfiguration = ServiceRegistryConfiguration(),
        settingsConfig: SettingsServiceConfiguration? = nil,
        appDataConfig: AppDataServiceConfiguration? = nil,
        classificationConfig: EmailClassificationServiceConfiguration? = nil
    ) -> ServiceRegistryProtocol {
        let registry = create(configuration: registryConfig)
        let configurator = ServiceRegistryConfigurator(registry: registry)
        configurator.configureServices(
            modelContext: modelContext,
            settingsConfig: settingsConfig,
            appDataConfig: appDataConfig,
            classificationConfig: classificationConfig
        )
        return registry
    }
    
    /// Creates a test instance with custom dependencies
    /// - Parameters:
    ///   - configurationManager: Custom configuration manager for testing
    ///   - lifecycleManager: Custom lifecycle manager for testing
    ///   - configuration: Custom configuration for testing
    /// - Returns: A Service Registry instance configured for testing
    #if DEBUG
    public static func createForTesting(
        configurationManager: ServiceConfigurationManagerProtocol,
        lifecycleManager: ServiceLifecycleManagerProtocol,
        configuration: ServiceRegistryConfiguration = ServiceRegistryConfiguration()
    ) -> ServiceRegistryProtocol {
        return ServiceRegistryFactory.shared.createForTesting(
            configurationManager: configurationManager,
            lifecycleManager: lifecycleManager,
            configuration: configuration
        )
    }
    #endif
}

/// Fluent API for building service registries
public func buildServiceRegistry() -> ServiceRegistryBuilder {
    return ServiceRegistryBuilder()
}

/// Protocol extension for easy service resolution
extension ServiceRegistryProtocol {
    /// Resolves a service or throws an error if not found
    /// - Parameter type: The service type to resolve
    /// - Returns: The service instance
    /// - Throws: ServiceRegistryError.serviceNotFound if service is not registered
    public func requireService<T>(_ type: T.Type) throws -> T {
        guard let service = resolve(type) else {
            throw ServiceRegistryError.serviceNotFound(String(describing: type))
        }
        return service
    }
    
    /// Resolves a service with a default fallback
    /// - Parameters:
    ///   - type: The service type to resolve
    ///   - defaultService: Default service to return if not found
    /// - Returns: The resolved service or the default service
    public func resolve<T>(_ type: T.Type, default defaultService: T) -> T {
        return resolve(type) ?? defaultService
    }
}