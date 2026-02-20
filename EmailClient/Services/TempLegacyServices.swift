import Foundation
import SwiftUI
import SwiftData

// TEMPORARY: Minimal stubs for removed services to maintain build compatibility
// These will be removed once all views are migrated to use framework services

class AppDataManager: ObservableObject {
    @Published var emails: [Email] = []
    @Published var isLoading = false

    // Add properties for compatibility with views
    var modelContext: ModelContext? = nil
    var isInitialized: Bool = true

    static let shared = AppDataManager()

    private var realService: (any AppDataServiceProtocol)?

    @MainActor
    func initialize() async {
        print("🔧 AppDataManager.initialize() — creating real AppDataService")
        let service = AppDataServiceAPI.shared(
            configuration: AppDataServiceConfiguration(
                enableLaunchClassification: false,
                enableDebugLogging: true   // verbose so we can trace failures
            )
        )
        self.realService = service
        print("🔧 AppDataManager.initialize() — realService assigned: \(type(of: service))")
        do {
            try await service.initialize()
            print("✅ AppDataManager.initialize() — real service initialized. modelContext nil? \(service.modelContext == nil). classificationManager nil? \(service.classificationManager == nil)")
        } catch {
            print("❌ AppDataManager.initialize() — real service init failed: \(error)")
        }
    }

    func forceFullClassification() async {
        print("🧠 AppDataManager.forceFullClassification() called")
        guard let service = realService else {
            print("❌ AppDataManager.forceFullClassification() — realService is nil, was initialize() called?")
            return
        }
        print("🧠 AppDataManager.forceFullClassification() — classificationManager nil? \(service.classificationManager == nil)")
        print("🧠 AppDataManager.forceFullClassification() — starting classification…")
        await service.forceFullClassification()
        print("🧠 AppDataManager.forceFullClassification() — classification finished, posting notification")
        await MainActor.run {
            NotificationCenter.default.post(name: .classificationCompleted, object: nil)
            print("📣 classificationCompleted notification posted")
        }
    }

    func getClassificationStatistics() async -> ClassificationStatistics? {
        return await realService?.getClassificationStatistics()
    }

    /// Fetches classified emails directly from the classification context.
    /// Use this after classification completes — the EmailService's context is stale
    /// because two separate ModelContainers are used and SwiftData returns cached
    /// in-memory objects rather than re-reading from disk for already-registered objects.
    @MainActor
    func fetchClassifiedEmails() async -> [Email] {
        print("🔍 AppDataManager.fetchClassifiedEmails() called")
        guard let context = realService?.modelContext else {
            print("❌ AppDataManager.fetchClassifiedEmails() — no modelContext (realService nil? \(realService == nil))")
            return []
        }
        do {
            let descriptor = FetchDescriptor<SwiftDataEmail>()
            let all = try context.fetch(descriptor)
            let classified = all.filter { $0.isClassified }
            print("🔍 AppDataManager.fetchClassifiedEmails() — total: \(all.count), classified: \(classified.count)")
            return classified.map { $0.toDomainModel() }
        } catch {
            print("❌ AppDataManager.fetchClassifiedEmails() failed: \(error)")
            return []
        }
    }
}

extension Notification.Name {
    static let classificationCompleted = Notification.Name("com.zmail.classificationCompleted")
}

class SettingsManager: ObservableObject {
    @Published var useRichEmailRendering: Bool = true
    @Published var senderSortOrder: LegacySenderSortOrder = .alphabeticalAscending
}

enum LegacySenderSortOrder: String, CaseIterable {
    case alphabeticalAscending = "alphabeticalAscending"
    case alphabeticalDescending = "alphabeticalDescending"
    case emailCountAscending = "emailCountAscending"
    case emailCountDescending = "emailCountDescending"
    case conversationCountAscending = "conversationCountAscending"
    case conversationCountDescending = "conversationCountDescending"
}

// Environment key for AppDataManager
struct AppDataManagerKey: EnvironmentKey {
    static let defaultValue = AppDataManager.shared
}

extension EnvironmentValues {
    var appDataManager: AppDataManager {
        get { self[AppDataManagerKey.self] }
        set { self[AppDataManagerKey.self] = newValue }
    }
}
