import SwiftUI
import SwiftData

/// Manages app-level data operations and provides SwiftData context access
@MainActor
class AppDataManager: ObservableObject {
    
    // MARK: - Shared Instance
    
    static let shared = AppDataManager()
    
    // MARK: - Published Properties
    
    @Published var isInitialized = false
    @Published var classificationManager: LaunchClassificationManager?
    
    // MARK: - Private Properties
    
    private var container: ModelContainer?
    private var _modelContext: ModelContext?
    
    // MARK: - Public Properties
    
    var modelContext: ModelContext? {
        return _modelContext
    }
    
    // MARK: - Private Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Initializes the SwiftData container and classification manager
    func initialize() async {
        guard !isInitialized else { return }
        
        do {
            // Set up SwiftData container
            print("📦 Creating SwiftData schema...")
            let schema = Schema([
                SwiftDataEmail.self,
                SwiftDataAccount.self
            ])
            
            // Try to create container, and if it fails due to schema mismatch, reset the database
            do {
                try await createModelContainer(with: schema)
            } catch let error as SwiftDataError {
                print("⚠️ SwiftData error detected: \(error)")
                // For now, just reset the database on any SwiftData error
                // TODO: Implement proper error handling based on SwiftData error types
                print("⚠️ Resetting database due to SwiftData error...")
                try await resetDatabase()
                try await createModelContainer(with: schema)
            }
            
            print("📦 Schema created with \(schema.entities.count) entities:")
            for entity in schema.entities {
                print("📦 Entity: \(entity.name)")
                for property in entity.properties {
                    print("📦   Property: \(property.name)")
                }
            }
            print("📦 Initializing classification manager...")
            
            // Initialize classification manager
            classificationManager = LaunchClassificationManager(modelContext: _modelContext!)
            
            isInitialized = true
            print("✅ AppDataManager initialized successfully")
            
            // Perform launch-time classification
            await performLaunchClassification()
            
        } catch {
            print("❌ Failed to initialize AppDataManager: \(error)")
            if let swiftDataError = error as? SwiftDataError {
                print("❌ SwiftData specific error: \(swiftDataError)")
                print("❌ SwiftData error description: \(swiftDataError.localizedDescription)")
            }
            print("❌ Full error details: \(String(describing: error))")
        }
    }
    
    /// Performs launch-time email classification
    private func performLaunchClassification() async {
        guard let classificationManager = classificationManager else { return }
        
        print("📧 Starting launch-time classification check...")
        await classificationManager.performLaunchClassificationIfNeeded()
    }
    
    /// Force re-classification of all emails
    func forceFullClassification() async {
        guard let classificationManager = classificationManager else { return }
        await classificationManager.forceFullClassification()
    }
    
    /// Get classification statistics
    func getClassificationStatistics() async -> ClassificationStatistics? {
        guard let classificationManager = classificationManager else { return nil }
        return await classificationManager.getClassificationStatistics()
    }
    
    /// Run background classification
    func runBackgroundClassification() async {
        guard let classificationManager = classificationManager else { return }
        await classificationManager.runBackgroundClassification()
    }
    
    // MARK: - SwiftData Context Access
    
    /// Provides access to the model context for dependency injection
    func provideModelContext() -> ModelContext? {
        return _modelContext
    }
    
    /// Save changes to the SwiftData context
    func save() throws {
        guard let context = _modelContext else {
            throw AppDataError.contextNotInitialized
        }
        
        if context.hasChanges {
            try context.save()
        }
    }
    
    // MARK: - Helper Methods
    
    /// Creates the ModelContainer with the given schema
    private func createModelContainer(with schema: Schema) async throws {
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        
        container = try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
        print("✅ ModelContainer created successfully")
        
        _modelContext = ModelContext(container!)
        print("✅ ModelContext created successfully")
    }
    
    /// Resets the database by deleting the store file
    private func resetDatabase() async throws {
        print("🗑️ Resetting database...")
        
        // Get the store URL from the container
        if let container = container {
            let storeURL = container.configurations.first?.url
            if let url = storeURL {
                try FileManager.default.removeItem(at: url)
                print("✅ Database file deleted: \(url.lastPathComponent)")
            }
        }
        
        // Also try to delete the default store location
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let documentsPath = documentsPath {
            let defaultStoreURL = documentsPath.appendingPathComponent("default.store")
            if FileManager.default.fileExists(atPath: defaultStoreURL.path) {
                try FileManager.default.removeItem(at: defaultStoreURL)
                print("✅ Default store file deleted")
            }
        }
        
        // Reset container and context
        container = nil
        _modelContext = nil
        print("✅ Database reset completed")
    }
}

// MARK: - Error Types

enum AppDataError: LocalizedError {
    case contextNotInitialized
    
    var errorDescription: String? {
        switch self {
        case .contextNotInitialized:
            return "SwiftData context has not been initialized"
        }
    }
}

// MARK: - SwiftUI Environment Integration

struct AppDataManagerKey: EnvironmentKey {
    static let defaultValue: AppDataManager = {
        return AppDataManager.shared
    }()
}

extension EnvironmentValues {
    var appDataManager: AppDataManager {
        get { self[AppDataManagerKey.self] }
        set { self[AppDataManagerKey.self] = newValue }
    }
}
