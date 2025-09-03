import Foundation
import SwiftData
import CloudKit

/// Default implementation of SchemaProviderProtocol using existing SwiftData models
internal class DefaultSchemaProvider: SchemaProviderProtocol {
    
    private let configuration: AppDataServiceConfiguration
    
    internal init(configuration: AppDataServiceConfiguration) {
        self.configuration = configuration
    }
    
    func getSchema() -> Schema {
        return Schema([
            SwiftDataEmail.self,
            SwiftDataAccount.self
        ])
    }
    
    func getModelConfiguration() -> ModelConfiguration {        
        switch configuration.cloudKitDatabase {
        case .none:
            return ModelConfiguration(
                schema: getSchema(),
                isStoredInMemoryOnly: configuration.isStoredInMemoryOnly
            )
        case .private, .public, .shared:
            // For CloudKit integration, use the simpler ModelConfiguration
            // CloudKit configuration would be handled at the container level
            return ModelConfiguration(
                schema: getSchema(),
                isStoredInMemoryOnly: configuration.isStoredInMemoryOnly
            )
        }
    }
}