// MARK: - Settings Service Framework
// This file exports the public API of the Settings Service framework

// Public API
@_exported import Foundation
@_exported import SwiftUI
@_exported import Combine

// Export Service Protocol and Dependencies
public typealias SettingsService = SettingsServiceProtocol
public typealias SettingsDependencies = SettingsServiceDependencies
// Note: Factory and Container are internal - use SettingsServiceAPI instead

// Export Configuration and Models
public typealias SettingsConfig = SettingsServiceConfiguration

/// Convenience accessor for the Settings Service
public struct SettingsServiceAPI {
    /// Gets the shared Settings Service instance
    /// - Parameter configuration: Optional configuration (uses defaults if nil)
    /// - Returns: The Settings Service instance
    public static func shared(
        configuration: SettingsServiceConfiguration = SettingsServiceConfiguration()
    ) -> SettingsServiceProtocol {
        return SettingsServiceContainer.shared.getSettingsService(configuration: configuration)
    }
    
    /// Gets the current Settings Service instance if it exists
    /// - Returns: The current Settings Service instance or nil
    public static var current: SettingsServiceProtocol? {
        return SettingsServiceContainer.shared.getSettingsService()
    }
    
    /// Creates a new Settings Service instance with custom dependencies
    /// - Parameter dependencies: Custom dependencies for the service
    /// - Returns: A new Settings Service instance
    public static func create(with dependencies: SettingsServiceDependencies) -> SettingsServiceProtocol {
        return SettingsServiceFactory.shared.createSettingsService(dependencies: dependencies)
    }
    
    /// Creates a Settings Service instance with default dependencies
    /// - Parameter configuration: Optional configuration
    /// - Returns: A configured Settings Service instance
    public static func create(
        configuration: SettingsServiceConfiguration = SettingsServiceConfiguration()
    ) -> SettingsServiceProtocol {
        return SettingsServiceFactory.shared.createSettingsService(configuration: configuration)
    }
    
    /// Clears the cached service instance
    public static func clearCache() {
        SettingsServiceContainer.shared.clearCache()
    }
    
    /// Creates a test instance with custom dependencies
    /// - Parameters:
    ///   - persistence: Custom persistence implementation for testing
    ///   - configuration: Custom configuration for testing
    /// - Returns: A Settings Service instance configured for testing
    #if DEBUG
    public static func createForTesting(
        persistence: SettingsPersistenceProtocol,
        configuration: SettingsServiceConfiguration = SettingsServiceConfiguration()
    ) -> SettingsServiceProtocol {
        return SettingsServiceFactory.shared.createForTesting(
            persistence: persistence,
            configuration: configuration
        )
    }
    #endif
}