import Foundation
import SwiftData
import Combine

/// Public API protocol for app data service operations
/// Follows MVVM + Service Layer architecture from CLAUDE.md
public protocol AppDataServiceProtocol: ObservableObject {
    /// Published initialization state
    var isInitialized: Bool { get }
    
    /// Published classification manager
    var classificationManager: ClassificationManagerProtocol? { get }
    
    /// Provides access to the SwiftData model context
    var modelContext: ModelContext? { get }
    
    /// Initializes the SwiftData container and classification manager
    func initialize() async throws
    
    /// Provides access to the model context for dependency injection
    func provideModelContext() -> ModelContext?
    
    /// Saves changes to the SwiftData context
    func save() throws
    
    /// Force re-classification of all emails
    func forceFullClassification() async
    
    /// Gets classification statistics
    func getClassificationStatistics() async -> ClassificationStatistics?
    
    /// Runs background classification
    func runBackgroundClassification() async
    
    /// Resets the database (for testing or data corruption recovery)
    func resetDatabase() async throws
}

/// Protocol for classification manager operations
public protocol ClassificationManagerProtocol: ObservableObject {
    var classificationProgress: Double { get }
    
    func performLaunchClassificationIfNeeded() async
    func forceFullClassification() async
    func getClassificationStatistics() async -> ClassificationStatistics?
    func runBackgroundClassification() async
}


/// Configuration options for app data service behavior
public struct AppDataServiceConfiguration {
    /// Whether to enable automatic classification at launch (default: true)
    public let enableLaunchClassification: Bool
    
    /// CloudKit database configuration (default: .none)
    public let cloudKitDatabase: CloudKitDatabase
    
    /// Whether the data should be stored in memory only (default: false)
    public let isStoredInMemoryOnly: Bool
    
    /// Enable debug logging (default: false)
    public let enableDebugLogging: Bool
    
    /// Maximum retry attempts for database operations (default: 3)
    public let maxRetryAttempts: Int
    
    public init(
        enableLaunchClassification: Bool = true,
        cloudKitDatabase: CloudKitDatabase = .none,
        isStoredInMemoryOnly: Bool = false,
        enableDebugLogging: Bool = false,
        maxRetryAttempts: Int = 3
    ) {
        self.enableLaunchClassification = enableLaunchClassification
        self.cloudKitDatabase = cloudKitDatabase
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        self.enableDebugLogging = enableDebugLogging
        self.maxRetryAttempts = maxRetryAttempts
    }
}

/// CloudKit database configuration options
public enum CloudKitDatabase {
    case none
    case `private`
    case `public`
    case shared
}

/// App data service specific errors
public enum AppDataServiceError: Error, LocalizedError {
    case contextNotInitialized
    case initializationFailed(String)
    case databaseResetFailed(String)
    case schemaVersionMismatch
    case saveFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .contextNotInitialized:
            return "SwiftData context has not been initialized"
        case .initializationFailed(let message):
            return "Failed to initialize app data service: \(message)"
        case .databaseResetFailed(let message):
            return "Failed to reset database: \(message)"
        case .schemaVersionMismatch:
            return "Database schema version mismatch - reset may be required"
        case .saveFailed(let message):
            return "Failed to save data: \(message)"
        }
    }
}

/// Change events for reactive updates
public enum AppDataChangeEvent {
    case initialized(ModelContext)
    case classificationManagerCreated(ClassificationManagerProtocol)
    case databaseReset
    case saveFailed(Error)
}