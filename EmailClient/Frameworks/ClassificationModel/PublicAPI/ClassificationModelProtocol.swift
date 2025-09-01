import Foundation
import Combine

/// Public API protocol for email classification operations
/// Uses ChatGPT o1-mini to classify emails into predefined categories
public protocol ClassificationModelProtocol {
    /// Classifies a single email into a category
    /// - Parameters:
    ///   - email: The email to classify
    ///   - apiKey: OpenAI API key for authentication
    /// - Returns: Classification result with category, confidence, and rationale
    /// - Throws: ClassificationError on failure
    func classifyEmail(_ email: EmailData, apiKey: String) async throws -> EmailClassificationResult
    
    /// Classifies multiple emails in batch
    /// - Parameters:
    ///   - emails: Array of emails to classify
    ///   - apiKey: OpenAI API key for authentication
    ///   - batchSize: Number of emails to process concurrently (default: 3)
    /// - Returns: Array of classification results
    /// - Throws: ClassificationError on failure
    func classifyEmails(_ emails: [EmailData], apiKey: String, batchSize: Int) async throws -> [EmailClassificationResult]
    
    /// Gets cached classification for an email if available
    /// - Parameter emailId: Unique identifier for the email
    /// - Returns: Cached classification result or nil if not cached
    func getCachedClassification(for emailId: String) -> EmailClassificationResult?
    
    /// Clears all cached classifications
    func clearCache()
    
    /// Publisher for real-time classification updates
    var classificationUpdates: AnyPublisher<EmailClassificationResult, Never> { get }
}

/// Email classification categories
public enum EmailCategory: String, CaseIterable, Codable {
    case promotions = "promotions"
    case orderHistory = "order_history"
    case finance = "finance"
    case personal = "personal"
    case work = "work"
    case appointments = "appointments"
    case signInAlerts = "sign_in_alerts"
    case other = "other"
    
    public var displayName: String {
        switch self {
        case .promotions:
            return "Promotions"
        case .orderHistory:
            return "Order History"
        case .finance:
            return "Finance"
        case .personal:
            return "Personal"
        case .work:
            return "Work"
        case .appointments:
            return "Appointments"
        case .signInAlerts:
            return "Sign In Alerts"
        case .other:
            return "Other"
        }
    }
    
    public var iconName: String {
        switch self {
        case .promotions:
            return "megaphone"
        case .orderHistory:
            return "shippingbox"
        case .finance:
            return "dollarsign.circle"
        case .personal:
            return "person"
        case .work:
            return "briefcase"
        case .appointments:
            return "calendar"
        case .signInAlerts:
            return "shield.checkered"
        case .other:
            return "folder"
        }
    }
    
    public var color: String {
        switch self {
        case .promotions:
            return "orange"
        case .orderHistory:
            return "brown"
        case .finance:
            return "green"
        case .personal:
            return "blue"
        case .work:
            return "purple"
        case .appointments:
            return "red"
        case .signInAlerts:
            return "yellow"
        case .other:
            return "gray"
        }
    }
}

/// Email data structure for classification
public struct EmailData: Codable {
    public let id: String
    public let from: String
    public let subject: String
    public let date: String
    public let body: String
    
    public init(id: String, from: String, subject: String, date: String, body: String) {
        self.id = id
        self.from = from
        self.subject = subject
        self.date = date
        self.body = body
    }
}

/// Classification result from the model
public struct EmailClassificationResult: Codable, Identifiable {
    public let id = UUID()
    public let emailId: String
    public let category: EmailCategory
    public let confidence: Double
    public let rationale: String?
    public let timestamp: Date
    
    public init(emailId: String, category: EmailCategory, confidence: Double, rationale: String? = nil) {
        self.emailId = emailId
        self.category = category
        self.confidence = confidence
        self.rationale = rationale
        self.timestamp = Date()
    }
    
    /// Whether the classification is considered highly confident
    public var isHighConfidence: Bool {
        return confidence >= 0.8
    }
    
    /// Whether the classification is considered low confidence and might need review
    public var needsReview: Bool {
        return confidence < 0.5
    }
}

/// Classification specific errors
public enum ClassificationError: Error, LocalizedError {
    case invalidAPIKey
    case networkError
    case apiRateLimitExceeded
    case invalidResponse
    case emailTooLarge
    case classificationFailed(String)
    case batchProcessingFailed([String])
    
    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid OpenAI API key provided"
        case .networkError:
            return "Network connection error occurred"
        case .apiRateLimitExceeded:
            return "OpenAI API rate limit exceeded. Please try again later"
        case .invalidResponse:
            return "Invalid response from classification service"
        case .emailTooLarge:
            return "Email content is too large for classification"
        case .classificationFailed(let message):
            return "Classification failed: \(message)"
        case .batchProcessingFailed(let emailIds):
            return "Batch processing failed for emails: \(emailIds.joined(separator: ", "))"
        }
    }
}

/// Configuration options for classification behavior
public struct ClassificationConfiguration: Hashable {
    /// Temperature setting for the model (0.0 = deterministic, 1.0 = creative)
    public let temperature: Double
    
    /// Maximum number of characters to include from email body
    public let maxBodyLength: Int
    
    /// Whether to enable result caching
    public let enableCaching: Bool
    
    /// Cache expiration time in seconds (default: 24 hours)
    public let cacheExpirationTime: TimeInterval
    
    /// Maximum number of concurrent API requests
    public let maxConcurrentRequests: Int
    
    /// Request timeout in seconds
    public let requestTimeout: TimeInterval
    
    public init(
        temperature: Double = 0.0,
        maxBodyLength: Int = 4000,
        enableCaching: Bool = true,
        cacheExpirationTime: TimeInterval = 24 * 60 * 60, // 24 hours
        maxConcurrentRequests: Int = 3,
        requestTimeout: TimeInterval = 30.0
    ) {
        self.temperature = temperature
        self.maxBodyLength = maxBodyLength
        self.enableCaching = enableCaching
        self.cacheExpirationTime = cacheExpirationTime
        self.maxConcurrentRequests = maxConcurrentRequests
        self.requestTimeout = requestTimeout
    }
}
