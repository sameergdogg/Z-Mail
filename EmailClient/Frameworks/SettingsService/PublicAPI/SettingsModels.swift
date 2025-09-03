import Foundation

/// Settings data models and default values
public struct SettingsDefaults {
    /// Default value for rich email rendering (true)
    public static let useRichEmailRendering = true
    
    /// Default sender sort order (alphabetical ascending) - internal to avoid conflict
    internal static let senderSortOrder = SenderSortOrder.alphabeticalAscending
    
    /// UserDefaults keys for settings persistence
    public struct Keys {
        public static let useRichEmailRendering = "useRichEmailRendering"
        public static let senderSortOrder = "senderSortOrder"
    }
}

/// Settings change event for reactive updates
public enum SettingsChangeEvent {
    case richRenderingChanged(Bool)
    case senderSortOrderChanged(SenderSortOrder)
    case settingsReset
}

/// Protocol for settings persistence abstraction
public protocol SettingsPersistenceProtocol {
    /// Stores a value for the given key
    func setValue<T>(_ value: T, forKey key: String)
    
    /// Retrieves a value for the given key
    func value<T>(forKey key: String, defaultValue: T) -> T
    
    /// Removes a value for the given key
    func removeValue(forKey key: String)
    
    /// Synchronizes data to disk
    func synchronize()
}

/// Settings service dependencies for dependency injection
public struct SettingsServiceDependencies {
    /// Persistence layer for settings storage
    public let persistence: SettingsPersistenceProtocol
    
    /// Configuration options
    public let configuration: SettingsServiceConfiguration
    
    public init(
        persistence: SettingsPersistenceProtocol,
        configuration: SettingsServiceConfiguration = SettingsServiceConfiguration()
    ) {
        self.persistence = persistence
        self.configuration = configuration
    }
}