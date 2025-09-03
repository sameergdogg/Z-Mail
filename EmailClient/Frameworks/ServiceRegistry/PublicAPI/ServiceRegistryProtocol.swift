import Foundation
import SwiftData
import SwiftUI
import GoogleSignIn
import Combine

/// Protocol for centralized service registry management
/// Provides dependency injection and service lifecycle management
public protocol ServiceRegistryProtocol: ObservableObject {
    /// Registers a service instance for a specific type
    /// - Parameters:
    ///   - service: The service instance to register
    ///   - type: The service type
    func register<T>(_ service: T, for type: T.Type)
    
    /// Resolves a service instance for a specific type
    /// - Parameter type: The service type to resolve
    /// - Returns: The service instance or nil if not found
    func resolve<T>(_ type: T.Type) -> T?
    
    /// Checks if a service is registered for a specific type
    /// - Parameter type: The service type to check
    /// - Returns: True if registered, false otherwise
    func isRegistered<T>(_ type: T.Type) -> Bool
    
    /// Unregisters a service for a specific type
    /// - Parameter type: The service type to unregister
    func unregister<T>(_ type: T.Type)
    
    /// Clears all registered services
    func clearAll()
    
    /// Gets a list of all registered service types
    /// - Returns: Array of registered service type names
    func getRegisteredServiceTypes() -> [String]
}

/// Protocol for service configuration management
public protocol ServiceConfigurationManagerProtocol {
    /// Gets configuration for a specific service type
    /// - Parameter serviceType: The service type
    /// - Returns: Configuration dictionary
    func getConfiguration(for serviceType: String) -> [String: Any]
    
    /// Sets configuration for a specific service type
    /// - Parameters:
    ///   - configuration: Configuration dictionary
    ///   - serviceType: The service type
    func setConfiguration(_ configuration: [String: Any], for serviceType: String)
    
    /// Resets configuration to defaults for a service type
    /// - Parameter serviceType: The service type
    func resetConfiguration(for serviceType: String)
}

/// Protocol for service lifecycle management
public protocol ServiceLifecycleManagerProtocol {
    /// Initializes all registered services
    func initializeServices() async
    
    /// Starts all services
    func startServices() async
    
    /// Stops all services
    func stopServices() async
    
    /// Restarts a specific service
    /// - Parameter serviceType: The service type to restart
    func restartService(_ serviceType: String) async
    
    /// Gets health status of all services
    /// - Returns: Dictionary of service health statuses
    func getServiceHealthStatus() -> [String: ServiceHealthStatus]
}

/// Service health status enumeration
public enum ServiceHealthStatus {
    case healthy
    case degraded
    case unhealthy
    case unknown
    
    public var displayName: String {
        switch self {
        case .healthy: return "Healthy"
        case .degraded: return "Degraded"
        case .unhealthy: return "Unhealthy"
        case .unknown: return "Unknown"
        }
    }
    
    public var color: Color {
        switch self {
        case .healthy: return .green
        case .degraded: return .orange
        case .unhealthy: return .red
        case .unknown: return .gray
        }
    }
}

/// Service registry configuration
public struct ServiceRegistryConfiguration {
    /// Enable automatic service initialization (default: true)
    public let enableAutoInitialization: Bool
    
    /// Enable service health monitoring (default: true)
    public let enableHealthMonitoring: Bool
    
    /// Health check interval in seconds (default: 60)
    public let healthCheckInterval: TimeInterval
    
    /// Enable debug logging (default: false)
    public let enableDebugLogging: Bool
    
    /// Maximum service initialization timeout in seconds (default: 30)
    public let serviceInitializationTimeout: TimeInterval
    
    public init(
        enableAutoInitialization: Bool = true,
        enableHealthMonitoring: Bool = true,
        healthCheckInterval: TimeInterval = 60.0,
        enableDebugLogging: Bool = false,
        serviceInitializationTimeout: TimeInterval = 30.0
    ) {
        self.enableAutoInitialization = enableAutoInitialization
        self.enableHealthMonitoring = enableHealthMonitoring
        self.healthCheckInterval = healthCheckInterval
        self.enableDebugLogging = enableDebugLogging
        self.serviceInitializationTimeout = serviceInitializationTimeout
    }
}

/// Service registry specific errors
public enum ServiceRegistryError: Error, LocalizedError {
    case serviceNotFound(String)
    case serviceAlreadyRegistered(String)
    case initializationFailed(String)
    case configurationError(String)
    case lifecycleError(String)
    
    public var errorDescription: String? {
        switch self {
        case .serviceNotFound(let type):
            return "Service not found: \(type)"
        case .serviceAlreadyRegistered(let type):
            return "Service already registered: \(type)"
        case .initializationFailed(let message):
            return "Service initialization failed: \(message)"
        case .configurationError(let message):
            return "Service configuration error: \(message)"
        case .lifecycleError(let message):
            return "Service lifecycle error: \(message)"
        }
    }
}

/// Change events for reactive updates
public enum ServiceRegistryChangeEvent {
    case serviceRegistered(String)
    case serviceUnregistered(String)
    case serviceInitialized(String)
    case serviceStarted(String)
    case serviceStopped(String)
    case serviceHealthChanged(String, ServiceHealthStatus)
    case allServicesCleared
}