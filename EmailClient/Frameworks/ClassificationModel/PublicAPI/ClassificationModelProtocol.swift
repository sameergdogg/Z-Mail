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
    
    /// Generates a daily digest from a set of emails
    /// - Parameters:
    ///   - emails: Array of classified emails to include in the digest
    ///   - period: Time period for the digest (e.g., "today", "yesterday")
    ///   - apiKey: OpenAI API key for authentication
    /// - Returns: Daily digest JSON structure
    /// - Throws: ClassificationError on failure
    func generateDailyDigest(_ emails: [ClassifiedEmail], period: String, apiKey: String) async throws -> DailyDigest
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
    public let summary: String?
    public let timestamp: Date
    
    public init(emailId: String, category: EmailCategory, confidence: Double, rationale: String? = nil, summary: String? = nil) {
        self.emailId = emailId
        self.category = category
        self.confidence = confidence
        self.rationale = rationale
        self.summary = summary
        self.timestamp = Date()
    }
    
    private enum CodingKeys: String, CodingKey {
        case emailId, category, confidence, rationale, summary, timestamp
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

/// Email with classification information for digest generation
public struct ClassifiedEmail: Codable {
    public let id: String
    public let sender: String
    public let domain: String
    public let subject: String
    public let date: String
    public let category: String
    public let confidence: Double
    public let summary: String?
    public let bodyExcerpt: String
    public let threadKey: String?
    public let entities: [String: AnyCodable]?
    
    public init(
        id: String,
        sender: String,
        domain: String,
        subject: String,
        date: String,
        category: String,
        confidence: Double,
        summary: String? = nil,
        bodyExcerpt: String,
        threadKey: String? = nil,
        entities: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.sender = sender
        self.domain = domain
        self.subject = subject
        self.date = date
        self.category = category
        self.confidence = confidence
        self.summary = summary
        self.bodyExcerpt = bodyExcerpt
        self.threadKey = threadKey
        self.entities = entities
    }
}

/// Daily digest response structure
public struct DailyDigest: Codable {
    public let headline: String
    public let pillars: DigestPillars
    public let highlights: [DigestHighlight]
    public let actions: [DigestAction]
    public let money: DigestMoney
    public let packages: [DigestPackage]
    public let calendar: [DigestCalendar]
    public let security: [DigestSecurity]
    public let stats: DigestStats
    public let narrative: DigestNarrative
}

public struct DigestPillars: Codable {
    public let power: [String]
    public let pressure: [String]
    public let trouble: [String]
}

public struct DigestHighlight: Codable {
    public let summary: String
    public let category: String
    public let source: String
    public let id: String
}

public struct DigestAction: Codable {
    public let title: String
    public let due: String?
    public let source: String
    public let msgIds: [String]
    public let priority: ActionPriority
    
    private enum CodingKeys: String, CodingKey {
        case title, due, source, priority
        case msgIds = "msg_ids"
    }
}

public enum ActionPriority: String, Codable {
    case low = "low"
    case med = "med"
    case high = "high"
}

public struct DigestMoney: Codable {
    public let charges: [DigestMoneyItem]
    public let payouts: [DigestMoneyItem]
    public let billsDue: [DigestMoneyItem]
    public let balances: [DigestMoneyItem]
    
    private enum CodingKeys: String, CodingKey {
        case charges, payouts, balances
        case billsDue = "bills_due"
    }
}

public struct DigestMoneyItem: Codable {
    public let amount: Double?
    public let currency: String?
    public let description: String?
    public let due: String?
    public let source: String?
}

public struct DigestPackage: Codable {
    public let description: String
    public let status: String?
    public let tracking: String?
    public let source: String
}

public struct DigestCalendar: Codable {
    public let event: String
    public let date: String?
    public let time: String?
    public let source: String
}

public struct DigestSecurity: Codable {
    public let alert: String
    public let severity: String?
    public let source: String
}

public struct DigestStats: Codable {
    public let totals: [String: AnyCodable]
    public let topSenders: [DigestSender]
    public let threads: Int
    
    private enum CodingKeys: String, CodingKey {
        case totals, threads
        case topSenders = "top_senders"
    }
}

public struct DigestSender: Codable {
    public let sender: String
    public let count: Int
}

public struct DigestNarrative: Codable {
    public let long: String
    public let microcopy: DigestMicrocopy
}

public struct DigestMicrocopy: Codable {
    public let power: String
    public let pressure: String
    public let trouble: String
}

/// Type-erased codable value for flexible JSON handling
public struct AnyCodable: Codable {
    public let value: Any
    
    public init<T: Codable>(_ value: T) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Cannot decode value")
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            let anyArray = array.compactMap { item in
                if let codable = item as? (any Codable) {
                    return AnyCodable(codable)
                }
                return nil
            }
            try container.encode(anyArray)
        case let dict as [String: Any]:
            let anyDict = dict.compactMapValues { item in
                if let codable = item as? (any Codable) {
                    return AnyCodable(codable)
                }
                return nil
            }
            try container.encode(anyDict)
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode value")
            )
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
