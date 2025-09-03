import Foundation
import SwiftData
import SwiftUI

/// Service registry dependencies for dependency injection
public struct ServiceRegistryDependencies {
    /// Configuration manager for services
    public let configurationManager: ServiceConfigurationManagerProtocol
    
    /// Lifecycle manager for services
    public let lifecycleManager: ServiceLifecycleManagerProtocol
    
    /// Registry configuration
    public let configuration: ServiceRegistryConfiguration
    
    public init(
        configurationManager: ServiceConfigurationManagerProtocol,
        lifecycleManager: ServiceLifecycleManagerProtocol,
        configuration: ServiceRegistryConfiguration = ServiceRegistryConfiguration()
    ) {
        self.configurationManager = configurationManager
        self.lifecycleManager = lifecycleManager
        self.configuration = configuration
    }
}

/// Service descriptor for metadata about registered services
public struct ServiceDescriptor {
    public let typeName: String
    public let registrationDate: Date
    public let instance: Any
    public let configuration: [String: Any]
    
    internal init(typeName: String, instance: Any, configuration: [String: Any] = [:]) {
        self.typeName = typeName
        self.registrationDate = Date()
        self.instance = instance
        self.configuration = configuration
    }
}

/// Predefined service configurations for common services
public struct ServiceConfigurations {
    
    /// Default configuration for SettingsService
    public static let settingsService: [String: Any] = [
        "autoSave": true,
        "enableDebugLogging": false
    ]
    
    /// Default configuration for AppDataService  
    public static let appDataService: [String: Any] = [
        "enableLaunchClassification": true,
        "cloudKitDatabase": "none",
        "enableDebugLogging": false,
        "maxRetryAttempts": 3
    ]
    
    /// Default configuration for EmailClassificationService
    public static let emailClassificationService: [String: Any] = [
        "batchSize": 3,
        "batchDelay": 1.0,
        "maxConcurrentTasks": 3,
        "enableDebugLogging": false,
        "classificationTimeout": 30.0
    ]
    
    /// Default configuration for EmailImageService
    public static let emailImageService: [String: Any] = [
        "maxCacheItems": 100,
        "maxCacheSize": 52428800, // 50MB
        "requestTimeout": 30.0,
        "enableDebugLogging": false,
        "maxConcurrentDownloads": 3
    ]
    
    /// Gets default configuration for a service type
    /// - Parameter serviceType: The service type name
    /// - Returns: Default configuration dictionary
    public static func defaultConfiguration(for serviceType: String) -> [String: Any] {
        switch serviceType.lowercased() {
        case "settingsservice":
            return settingsService
        case "appdataservice":
            return appDataService
        case "emailclassificationservice":
            return emailClassificationService
        case "emailimageservice":
            return emailImageService
        default:
            return [:]
        }
    }
}

/// Service registry builder for fluent API configuration
public class ServiceRegistryBuilder {
    private var services: [String: Any] = [:]
    private var configurations: [String: [String: Any]] = [:]
    private var registryConfiguration = ServiceRegistryConfiguration()
    
    /// Registers a service instance
    /// - Parameters:
    ///   - service: The service instance
    ///   - type: The service type
    /// - Returns: Self for chaining
    @discardableResult
    public func register<T>(_ service: T, for type: T.Type) -> Self {
        let typeName = String(describing: type)
        services[typeName] = service
        return self
    }
    
    /// Sets configuration for a service type
    /// - Parameters:
    ///   - configuration: Configuration dictionary
    ///   - serviceType: The service type
    /// - Returns: Self for chaining
    @discardableResult
    public func configure(_ configuration: [String: Any], for serviceType: String) -> Self {
        configurations[serviceType] = configuration
        return self
    }
    
    /// Sets the registry configuration
    /// - Parameter configuration: Registry configuration
    /// - Returns: Self for chaining
    @discardableResult
    public func withConfiguration(_ configuration: ServiceRegistryConfiguration) -> Self {
        self.registryConfiguration = configuration
        return self
    }
    
    /// Builds the service registry
    /// - Returns: Configured service registry
    public func build() -> any ServiceRegistryProtocol {
        let configManager = DefaultServiceConfigurationManager(configurations: configurations)
        let lifecycleManager = DefaultServiceLifecycleManager()
        
        let dependencies = ServiceRegistryDependencies(
            configurationManager: configManager,
            lifecycleManager: lifecycleManager,
            configuration: registryConfiguration
        )
        
        let registry = ServiceRegistryFactory.shared.createServiceRegistry(dependencies: dependencies)
        
        // Register all services
        for (typeName, service) in services {
            // This would need to be implemented properly with type erasure
            // For now, this is a conceptual implementation
            print("Registering service: \(typeName)")
        }
        
        return registry
    }
}

/// SwiftUI Environment integration
public struct ServiceRegistryEnvironmentKey: EnvironmentKey {
    public static let defaultValue: ServiceRegistryProtocol? = nil
}

extension EnvironmentValues {
    public var serviceRegistry: ServiceRegistryProtocol? {
        get { self[ServiceRegistryEnvironmentKey.self] }
        set { self[ServiceRegistryEnvironmentKey.self] = newValue }
    }
}

/// Protocol for services that support health checks
public protocol HealthCheckableService {
    /// Performs a health check on the service
    /// - Returns: Service health status
    func performHealthCheck() async -> ServiceHealthStatus
}

/// Protocol for services that support lifecycle management
public protocol LifecycleAwareService {
    /// Initializes the service
    func initialize() async throws
    
    /// Starts the service
    func start() async throws
    
    /// Stops the service
    func stop() async throws
    
    /// Gets the current service state
    var serviceState: ServiceState { get }
}

/// Service state enumeration
public enum ServiceState {
    case uninitialized
    case initialized
    case starting
    case running
    case stopping
    case stopped
    case error(Error)
    
    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}