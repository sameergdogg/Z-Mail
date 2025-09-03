import Foundation
import SwiftData

/// Protocol for SwiftData schema provider abstraction
public protocol SchemaProviderProtocol {
    /// Provides the SwiftData schema for the app
    func getSchema() -> Schema
    
    /// Gets the model configuration
    func getModelConfiguration() -> ModelConfiguration
}

/// Protocol for classification manager factory
public protocol ClassificationManagerFactoryProtocol {
    /// Creates a classification manager with the provided model context
    func createClassificationManager(modelContext: ModelContext) -> ClassificationManagerProtocol
}

/// App data service dependencies for dependency injection
public struct AppDataServiceDependencies {
    /// Schema provider for SwiftData models
    public let schemaProvider: SchemaProviderProtocol
    
    /// Classification manager factory
    public let classificationManagerFactory: ClassificationManagerFactoryProtocol
    
    /// Configuration options
    public let configuration: AppDataServiceConfiguration
    
    public init(
        schemaProvider: SchemaProviderProtocol,
        classificationManagerFactory: ClassificationManagerFactoryProtocol,
        configuration: AppDataServiceConfiguration = AppDataServiceConfiguration()
    ) {
        self.schemaProvider = schemaProvider
        self.classificationManagerFactory = classificationManagerFactory
        self.configuration = configuration
    }
}

/// SwiftUI Environment integration
public struct AppDataServiceEnvironmentKey: EnvironmentKey {
    public static let defaultValue: AppDataServiceProtocol? = nil
}

extension EnvironmentValues {
    public var appDataService: AppDataServiceProtocol? {
        get { self[AppDataServiceEnvironmentKey.self] }
        set { self[AppDataServiceEnvironmentKey.self] = newValue }
    }
}