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
    
    func initialize() async {
        // Stub implementation
    }
    
    func forceFullClassification() async {
        // Stub implementation for compatibility with SettingsView
    }
    
    func getClassificationStatistics() async -> ClassificationStatistics? {
        // Stub implementation for compatibility with SettingsView
        return nil
    }
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