import Foundation
import SwiftData
import Combine

/// Public API protocol for email classification service operations
/// Follows MVVM + Service Layer architecture from CLAUDE.md
public protocol EmailClassificationServiceProtocol: ObservableObject {
    /// Published classification state
    var isClassifying: Bool { get }
    
    /// Published classification progress (0.0 to 1.0)
    var classificationProgress: Double { get }
    
    /// Published classification status message
    var classificationStatus: String { get }
    
    /// Classifies all unclassified emails in the database
    func classifyUnclassifiedEmails() async
    
    /// Classifies a specific email
    /// - Parameter email: The email to classify
    func classifyEmail(_ email: ClassifiableEmail) async throws -> EmailClassificationResult
    
    /// Cancels ongoing classification
    func cancelClassification()
    
    /// Gets classification statistics
    func getClassificationStatistics() async -> EmailClassificationStatistics
    
    /// Retrains the classification model (if supported)
    func retrainModel() async throws
}

/// Protocol for classifiable email data
public protocol ClassifiableEmail {
    var id: String { get }
    var subject: String { get }
    var senderEmail: String { get }
    var body: String { get }
    var date: Date { get }
}

// EmailClassificationResult is imported from ClassificationModel framework - no duplication needed

/// Email classification statistics
public struct EmailClassificationStatistics {
    public let totalEmails: Int
    public let classifiedEmails: Int
    public let unclassifiedEmails: Int
    public let averageConfidence: Double
    public let categoryDistribution: [String: Int]
    public let lastClassificationDate: Date?
    public let totalProcessingTime: TimeInterval
    
    public init(
        totalEmails: Int,
        classifiedEmails: Int,
        unclassifiedEmails: Int,
        averageConfidence: Double,
        categoryDistribution: [String: Int],
        lastClassificationDate: Date?,
        totalProcessingTime: TimeInterval
    ) {
        self.totalEmails = totalEmails
        self.classifiedEmails = classifiedEmails
        self.unclassifiedEmails = unclassifiedEmails
        self.averageConfidence = averageConfidence
        self.categoryDistribution = categoryDistribution
        self.lastClassificationDate = lastClassificationDate
        self.totalProcessingTime = totalProcessingTime
    }
    
    public var classificationPercentage: Double {
        guard totalEmails > 0 else { return 0.0 }
        return Double(classifiedEmails) / Double(totalEmails) * 100.0
    }
}

// REMOVED: EmailCategory is imported from ClassificationModel framework - no duplication needed
/*
/// Email category for classification
public struct EmailCategory: Equatable, Hashable, Codable {
    public let id: String
    public let name: String
    public let displayName: String
    public let description: String
    public let color: String
    public let iconName: String
    
    public init(id: String, name: String, displayName: String, description: String, color: String, iconName: String) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.color = color
        self.iconName = iconName
    }
    
    // Common categories
    public static let work = EmailCategory(
        id: "work",
        name: "work",
        displayName: "Work",
        description: "Professional emails and work-related communications",
        color: "blue",
        iconName: "briefcase"
    )
    
    public static let personal = EmailCategory(
        id: "personal",
        name: "personal", 
        displayName: "Personal",
        description: "Personal communications from friends and family",
        color: "green",
        iconName: "person"
    )
    
    public static let promotions = EmailCategory(
        id: "promotions",
        name: "promotions",
        displayName: "Promotions", 
        description: "Marketing emails and promotional content",
        color: "orange",
        iconName: "tag"
    )
    
    public static let social = EmailCategory(
        id: "social",
        name: "social",
        displayName: "Social",
        description: "Social media notifications and updates",
        color: "purple",
        iconName: "heart"
    )
    
    public static let updates = EmailCategory(
        id: "updates",
        name: "updates",
        displayName: "Updates",
        description: "System updates, newsletters, and notifications",
        color: "gray",
        iconName: "bell"
    )
    
    public static let uncategorized = EmailCategory(
        id: "uncategorized",
        name: "uncategorized",
        displayName: "Uncategorized",
        description: "Emails that don't fit into other categories",
        color: "gray",
        iconName: "questionmark.circle"
    )
    
    public static let allCategories: [EmailCategory] = [
        .work, .personal, .promotions, .social, .updates, .uncategorized
    ]
}
*/

/// Configuration options for email classification service behavior
public struct EmailClassificationServiceConfiguration {
    /// Batch size for processing emails (default: 3)
    public let batchSize: Int
    
    /// Delay between batches in seconds (default: 1.0)
    public let batchDelay: TimeInterval
    
    /// Maximum concurrent classification tasks (default: 3)
    public let maxConcurrentTasks: Int
    
    /// Minimum confidence threshold for classifications (default: 0.5)
    public let minConfidenceThreshold: Double
    
    /// Enable debug logging (default: false)
    public let enableDebugLogging: Bool
    
    /// Maximum retries for failed classifications (default: 2)
    public let maxRetries: Int
    
    /// Timeout for individual classification requests in seconds (default: 30.0)
    public let classificationTimeout: TimeInterval
    
    public init(
        batchSize: Int = 3,
        batchDelay: TimeInterval = 1.0,
        maxConcurrentTasks: Int = 3,
        minConfidenceThreshold: Double = 0.5,
        enableDebugLogging: Bool = false,
        maxRetries: Int = 2,
        classificationTimeout: TimeInterval = 30.0
    ) {
        self.batchSize = batchSize
        self.batchDelay = batchDelay
        self.maxConcurrentTasks = maxConcurrentTasks
        self.minConfidenceThreshold = minConfidenceThreshold
        self.enableDebugLogging = enableDebugLogging
        self.maxRetries = maxRetries
        self.classificationTimeout = classificationTimeout
    }
}

/// Email classification service specific errors
public enum EmailClassificationServiceError: Error, LocalizedError {
    case modelContextNotAvailable
    case classificationProviderNotConfigured
    case classificationFailed(String)
    case batchProcessingFailed(String)
    case configurationInvalid(String)
    case networkError
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .modelContextNotAvailable:
            return "SwiftData model context is not available"
        case .classificationProviderNotConfigured:
            return "Classification provider is not properly configured"
        case .classificationFailed(let message):
            return "Email classification failed: \(message)"
        case .batchProcessingFailed(let message):
            return "Batch classification processing failed: \(message)"
        case .configurationInvalid(let message):
            return "Invalid configuration: \(message)"
        case .networkError:
            return "Network error during classification"
        case .timeout:
            return "Classification request timed out"
        }
    }
}

/// Change events for reactive updates
public enum EmailClassificationChangeEvent {
    case classificationStarted
    case classificationProgressUpdated(Double, String)
    case classificationCompleted(EmailClassificationStatistics)
    case classificationCancelled
    case classificationFailed(Error)
    case emailClassified(String, EmailClassificationResult)
}