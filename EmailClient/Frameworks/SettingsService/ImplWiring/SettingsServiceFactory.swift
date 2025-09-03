import Foundation

/// Factory for creating Settings Service instances with dependency injection
/// Follows the three-layer framework pattern from CLAUDE.md
internal class SettingsServiceFactory {
    
    /// Shared factory instance
    internal static let shared = SettingsServiceFactory()
    
    private init() {}
    
    /// Creates a Settings Service instance with the provided dependencies
    /// - Parameter dependencies: The dependencies for the service
    /// - Returns: A configured Settings Service instance
    internal func createSettingsService(dependencies: SettingsServiceDependencies) -> SettingsServiceProtocol {
        return SettingsServiceImpl(dependencies: dependencies)
    }
    
    /// Creates a Settings Service instance with default UserDefaults persistence
    /// - Parameter configuration: Optional configuration (uses defaults if nil)
    /// - Returns: A configured Settings Service instance with UserDefaults persistence
    internal func createSettingsService(
        configuration: SettingsServiceConfiguration = SettingsServiceConfiguration()
    ) -> SettingsServiceProtocol {
        let persistence = UserDefaultsPersistence(suiteName: configuration.userDefaultsSuite)
        let dependencies = SettingsServiceDependencies(
            persistence: persistence,
            configuration: configuration
        )
        return createSettingsService(dependencies: dependencies)
    }
    
    /// Creates a Settings Service instance for testing with custom persistence
    /// - Parameters:
    ///   - persistence: Custom persistence implementation for testing
    ///   - configuration: Custom configuration for testing
    /// - Returns: A Settings Service instance configured for testing
    #if DEBUG
    internal func createForTesting(
        persistence: SettingsPersistenceProtocol,
        configuration: SettingsServiceConfiguration = SettingsServiceConfiguration()
    ) -> SettingsServiceProtocol {
        let dependencies = SettingsServiceDependencies(
            persistence: persistence,
            configuration: configuration
        )
        return createSettingsService(dependencies: dependencies)
    }
    #endif
}

/// Container for managing Settings Service instances
internal class SettingsServiceContainer {
    
    /// Shared container instance
    internal static let shared = SettingsServiceContainer()
    
    private var cachedService: SettingsServiceProtocol?
    private let lock = NSLock()
    
    private init() {}
    
    /// Gets or creates the shared Settings Service instance
    /// - Parameter configuration: Configuration for the service (only used on first creation)
    /// - Returns: The shared Settings Service instance
    internal func getSettingsService(
        configuration: SettingsServiceConfiguration = SettingsServiceConfiguration()
    ) -> SettingsServiceProtocol {
        lock.lock()
        defer { lock.unlock() }
        
        if let existingService = cachedService {
            return existingService
        }
        
        let service = SettingsServiceFactory.shared.createSettingsService(configuration: configuration)
        cachedService = service
        return service
    }
    
    /// Clears the cached service instance (useful for testing)
    internal func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedService = nil
    }
    
    #if DEBUG
    /// Creates a test container with custom settings service
    /// - Parameter service: The settings service to use
    /// - Returns: A container configured for testing
    internal static func createForTesting(service: SettingsServiceProtocol) -> SettingsServiceContainer {
        let container = SettingsServiceContainer()
        container.cachedService = service
        return container
    }
    #endif
}