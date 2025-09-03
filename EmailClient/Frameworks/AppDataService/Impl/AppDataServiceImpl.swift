import Foundation
import SwiftUI
import SwiftData
import Combine

/// Implementation of the App Data Service protocol
/// Follows MVVM + Service Layer architecture from CLAUDE.md
@MainActor
internal class AppDataServiceImpl: AppDataServiceProtocol {
    
    // MARK: - Published Properties
    
    @Published public private(set) var isInitialized = false
    @Published public private(set) var classificationManager: ClassificationManagerProtocol?
    
    // MARK: - Private Properties
    
    private let dependencies: AppDataServiceDependencies
    private var container: ModelContainer?
    private var _modelContext: ModelContext?
    private let changeEventsSubject = PassthroughSubject<AppDataChangeEvent, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    public var modelContext: ModelContext? {
        return _modelContext
    }
    
    public var changeEvents: AnyPublisher<AppDataChangeEvent, Never> {
        changeEventsSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    internal init(dependencies: AppDataServiceDependencies) {
        self.dependencies = dependencies
        
        if dependencies.configuration.enableDebugLogging {
            setupDebugLogging()
        }
    }
    
    // MARK: - Public Methods
    
    public func initialize() async throws {
        guard !isInitialized else {
            if dependencies.configuration.enableDebugLogging {
                print("📦 AppDataService already initialized")
            }
            return
        }
        
        do {
            try await initializeSwiftData()
            await initializeClassificationManager()
            
            isInitialized = true
            
            if dependencies.configuration.enableDebugLogging {
                print("✅ AppDataService initialized successfully")
            }
            
            changeEventsSubject.send(.initialized(_modelContext!))
            
            if dependencies.configuration.enableLaunchClassification {
                await performLaunchClassification()
            }
            
        } catch {
            if dependencies.configuration.enableDebugLogging {
                print("❌ Failed to initialize AppDataService: \(error)")
            }
            throw AppDataServiceError.initializationFailed(error.localizedDescription)
        }
    }
    
    public func provideModelContext() -> ModelContext? {
        return _modelContext
    }
    
    public func save() throws {
        guard let context = _modelContext else {
            throw AppDataServiceError.contextNotInitialized
        }
        
        guard context.hasChanges else {
            return // No changes to save
        }
        
        do {
            try context.save()
            if dependencies.configuration.enableDebugLogging {
                print("💾 AppDataService saved successfully")
            }
        } catch {
            if dependencies.configuration.enableDebugLogging {
                print("❌ AppDataService save failed: \(error)")
            }
            changeEventsSubject.send(.saveFailed(error))
            throw AppDataServiceError.saveFailed(error.localizedDescription)
        }
    }
    
    public func forceFullClassification() async {
        guard let classificationManager = classificationManager else { 
            if dependencies.configuration.enableDebugLogging {
                print("⚠️ Classification manager not available")
            }
            return 
        }
        await classificationManager.forceFullClassification()
    }
    
    public func getClassificationStatistics() async -> ClassificationStatistics? {
        guard let classificationManager = classificationManager else { return nil }
        return await classificationManager.getClassificationStatistics()
    }
    
    public func runBackgroundClassification() async {
        guard let classificationManager = classificationManager else { 
            if dependencies.configuration.enableDebugLogging {
                print("⚠️ Classification manager not available for background classification")
            }
            return 
        }
        await classificationManager.runBackgroundClassification()
    }
    
    public func resetDatabase() async throws {
        if dependencies.configuration.enableDebugLogging {
            print("🗑️ Resetting database...")
        }
        
        do {
            try await performDatabaseReset()
            
            // Reinitialize after reset
            isInitialized = false
            classificationManager = nil
            changeEventsSubject.send(.databaseReset)
            
            // Re-initialize
            try await initializeSwiftData()
            await initializeClassificationManager()
            isInitialized = true
            
            if dependencies.configuration.enableDebugLogging {
                print("✅ Database reset and re-initialized successfully")
            }
            
        } catch {
            if dependencies.configuration.enableDebugLogging {
                print("❌ Database reset failed: \(error)")
            }
            throw AppDataServiceError.databaseResetFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Private Methods
    
    private func initializeSwiftData() async throws {
        let schema = dependencies.schemaProvider.getSchema()
        let modelConfiguration = dependencies.schemaProvider.getModelConfiguration()
        
        // Handle potential schema mismatches with retry logic
        var retryCount = 0
        while retryCount < dependencies.configuration.maxRetryAttempts {
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                _modelContext = ModelContext(container!)
                
                if dependencies.configuration.enableDebugLogging {
                    print("📦 SwiftData initialized with \(schema.entities.count) entities")
                    for entity in schema.entities {
                        print("📦 Entity: \(entity.name)")
                    }
                }
                
                return
                
            } catch let error as SwiftDataError {
                retryCount += 1
                
                if dependencies.configuration.enableDebugLogging {
                    print("⚠️ SwiftData error attempt \(retryCount): \(error)")
                }
                
                if retryCount >= dependencies.configuration.maxRetryAttempts {
                    // Try reset on final attempt
                    try await performDatabaseReset()
                    container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                    _modelContext = ModelContext(container!)
                    return
                }
                
                // Small delay between retries
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
    }
    
    private func initializeClassificationManager() async {
        guard let modelContext = _modelContext else { return }
        
        classificationManager = dependencies.classificationManagerFactory.createClassificationManager(
            modelContext: modelContext
        )
        
        if dependencies.configuration.enableDebugLogging {
            print("📧 Classification manager initialized")
        }
        
        changeEventsSubject.send(.classificationManagerCreated(classificationManager!))
    }
    
    private func performLaunchClassification() async {
        guard let classificationManager = classificationManager else { return }
        
        if dependencies.configuration.enableDebugLogging {
            print("📧 Starting launch-time classification check...")
        }
        
        await classificationManager.performLaunchClassificationIfNeeded()
    }
    
    private func performDatabaseReset() async throws {
        // Clear current references
        _modelContext = nil
        container = nil
        
        // Delete database files
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        
        if let documentsPath = documentsPath {
            let storeURL = documentsPath.appendingPathComponent("default.store")
            
            if fileManager.fileExists(atPath: storeURL.path) {
                try fileManager.removeItem(at: storeURL)
                if dependencies.configuration.enableDebugLogging {
                    print("✅ Database file deleted: \(storeURL.lastPathComponent)")
                }
            }
            
            // Also remove related files
            let storeURLShm = storeURL.appendingPathExtension("shm")
            let storeURLWal = storeURL.appendingPathExtension("wal")
            
            try? fileManager.removeItem(at: storeURLShm)
            try? fileManager.removeItem(at: storeURLWal)
        }
    }
    
    private func setupDebugLogging() {
        changeEvents
            .sink { event in
                switch event {
                case .initialized:
                    print("📦 AppDataService initialized event")
                case .classificationManagerCreated:
                    print("📧 Classification manager created event")
                case .databaseReset:
                    print("🗑️ Database reset event")
                case .saveFailed(let error):
                    print("❌ Save failed event: \(error)")
                }
            }
            .store(in: &cancellables)
    }
}