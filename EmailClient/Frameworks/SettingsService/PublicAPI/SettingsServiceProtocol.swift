import Foundation
import Combine

/// Public API protocol for settings service operations
/// Follows MVVM + Service Layer architecture from CLAUDE.md
public protocol SettingsServiceProtocol: ObservableObject {
    /// Published setting for rich email rendering
    var useRichEmailRendering: Bool { get set }
    
    /// Published setting for sender sort order
    var senderSortOrder: SenderSortOrder { get set }
    
    /// Updates rich email rendering preference
    /// - Parameter enabled: Whether to enable rich rendering
    func setRichEmailRendering(_ enabled: Bool)
    
    /// Updates sender sort order preference
    /// - Parameter order: The new sort order
    func setSenderSortOrder(_ order: SenderSortOrder)
    
    /// Resets all settings to default values
    func resetToDefaults()
}

/// Email rendering mode options
public enum EmailRenderingMode {
    case plainText
    case richHTML
    
    public var displayName: String {
        switch self {
        case .plainText:
            return "Plain Text"
        case .richHTML:
            return "Rich HTML"
        }
    }
}

/// Sender sort order options
public enum SenderSortOrder: String, CaseIterable, Sendable {
    case alphabeticalAscending = "alphabeticalAscending"
    case alphabeticalDescending = "alphabeticalDescending"
    case emailCountAscending = "emailCountAscending"
    case emailCountDescending = "emailCountDescending"
    case conversationCountAscending = "conversationCountAscending"
    case conversationCountDescending = "conversationCountDescending"
    
    public var displayName: String {
        switch self {
        case .alphabeticalAscending:
            return "Name (A-Z)"
        case .alphabeticalDescending:
            return "Name (Z-A)"
        case .emailCountAscending:
            return "Message Count (Low to High)"
        case .emailCountDescending:
            return "Message Count (High to Low)"
        case .conversationCountAscending:
            return "Conversation Count (Low to High)"
        case .conversationCountDescending:
            return "Conversation Count (High to Low)"
        }
    }
    
    public var iconName: String {
        switch self {
        case .alphabeticalAscending, .alphabeticalDescending:
            return "textformat.abc"
        case .emailCountAscending, .emailCountDescending:
            return "envelope"
        case .conversationCountAscending, .conversationCountDescending:
            return "bubble.left.and.bubble.right"
        }
    }
}

/// Configuration options for settings service behavior
public struct SettingsServiceConfiguration {
    /// Whether to persist settings automatically when changed (default: true)
    public let autoSave: Bool
    
    /// Custom UserDefaults suite name (default: nil for standard suite)
    public let userDefaultsSuite: String?
    
    /// Enable debug logging (default: false)
    public let enableDebugLogging: Bool
    
    public init(
        autoSave: Bool = true,
        userDefaultsSuite: String? = nil,
        enableDebugLogging: Bool = false
    ) {
        self.autoSave = autoSave
        self.userDefaultsSuite = userDefaultsSuite
        self.enableDebugLogging = enableDebugLogging
    }
}

/// Settings service specific errors
public enum SettingsServiceError: Error, LocalizedError {
    case persistenceFailed(String)
    case invalidConfiguration
    
    public var errorDescription: String? {
        switch self {
        case .persistenceFailed(let message):
            return "Failed to save settings: \(message)"
        case .invalidConfiguration:
            return "Settings service configuration is invalid"
        }
    }
}