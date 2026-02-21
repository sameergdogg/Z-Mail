import Foundation
import SwiftUI
import SwiftData

// MARK: - Notification names

extension Notification.Name {
    static let classificationCompleted = Notification.Name("com.zmail.classificationCompleted")
}

// MARK: - AppDataManager

/// Owns the single ModelContainer for the app and exposes classification operations.
/// Replaces TempLegacyServices.swift + Frameworks/AppDataService/ three-layer pattern.
class AppDataManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isInitialized: Bool = false

    // MARK: - Singleton

    static let shared = AppDataManager()

    // MARK: - Internal Services

    private(set) var modelContext: ModelContext?
    private(set) var classificationService: ClassificationService?

    private var container: ModelContainer?

    // MARK: - Init

    init() {}

    // MARK: - Initialization

    @MainActor
    func initialize() async {
        guard !isInitialized else { return }

        print("AppDataManager.initialize() starting...")

        do {
            let schema = Schema([Email.self, SwiftDataDigest.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            let context = ModelContext(container)

            self.container = container
            self.modelContext = context
            self.classificationService = ClassificationService(modelContext: context)
            self.isInitialized = true

            print("AppDataManager.initialize() complete — context ready")

            // Classify any unclassified emails at launch (if API key is configured)
            await classificationService?.classifyUnclassifiedEmails()

        } catch {
            print("AppDataManager.initialize() failed: \(error)")
        }
    }

    // MARK: - Classification Passthrough

    func forceFullClassification() async {
        guard let service = classificationService else {
            print("AppDataManager.forceFullClassification() — service not ready")
            return
        }

        await service.forceFullClassification()

        await MainActor.run {
            NotificationCenter.default.post(name: .classificationCompleted, object: nil)
            print("classificationCompleted notification posted")
        }
    }

    func getClassificationStatistics() async -> ClassificationStatistics? {
        return await classificationService?.getClassificationStatistics()
    }

    /// Fetches all classified emails from the shared model context.
    @MainActor
    func fetchClassifiedEmails() async -> [Email] {
        guard let context = modelContext else { return [] }

        do {
            let descriptor = FetchDescriptor<Email>()
            let all = try context.fetch(descriptor)
            let classified = all.filter { $0.isClassified }
            print("fetchClassifiedEmails: total=\(all.count) classified=\(classified.count)")
            return classified
        } catch {
            print("fetchClassifiedEmails failed: \(error)")
            return []
        }
    }
}

// MARK: - Environment Key

struct AppDataManagerKey: EnvironmentKey {
    static let defaultValue = AppDataManager.shared
}

extension EnvironmentValues {
    var appDataManager: AppDataManager {
        get { self[AppDataManagerKey.self] }
        set { self[AppDataManagerKey.self] = newValue }
    }
}

// MARK: - SettingsManager (kept for backward compatibility with views)

class SettingsManager: ObservableObject {
    @Published var useRichEmailRendering: Bool = true
    @Published var senderSortOrder: LegacySenderSortOrder = .alphabeticalAscending
}

enum LegacySenderSortOrder: String, CaseIterable {
    case alphabeticalAscending
    case alphabeticalDescending
    case emailCountAscending
    case emailCountDescending
    case conversationCountAscending
    case conversationCountDescending
}
