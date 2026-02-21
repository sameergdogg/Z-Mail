import Foundation
import SwiftData

// MARK: - Email Model (merged @Model class)

/// Single SwiftData model class for email persistence.
/// Replaces the previous dual-model pattern (Email struct + SwiftDataEmail @Model).
@Model
public class Email {
    @Attribute(.unique) public var id: String
    public var subject: String
    public var senderName: String?
    public var senderEmail: String
    public var recipientsData: Data?   // JSON-encoded [EmailAddress]
    public var body: String
    public var htmlBody: String?
    public var date: Date
    public var isRead: Bool
    public var isStarred: Bool
    public var labelsData: Data?       // JSON-encoded [String]
    public var accountEmail: String
    public var threadId: String?
    public var isHTMLContent: Bool
    public var createdAt: Date
    public var updatedAt: Date

    // Classification fields
    public var classificationCategory: String?   // EmailCategory raw value
    public var classificationConfidence: Double?
    public var classificationSummary: String?
    public var classificationDate: Date?
    public var isClassified: Bool

    // MARK: - Computed helpers

    /// Decoded sender as EmailAddress value type
    public var sender: EmailAddress {
        EmailAddress(name: senderName, email: senderEmail)
    }

    /// Decoded recipients from JSON data
    public var recipients: [EmailAddress] {
        guard let data = recipientsData,
              let decoded = try? JSONDecoder().decode([EmailAddress].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Decoded labels from JSON data
    public var labels: [String] {
        guard let data = labelsData,
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    // Attachments are not stored as a relationship to keep the schema simple.
    // They are reconstructed from the Gmail API response on fetch.
    public var attachments: [EmailAttachment] { [] }

    // MARK: - Initializer

    public init(
        id: String,
        subject: String,
        senderName: String?,
        senderEmail: String,
        recipientsData: Data?,
        body: String,
        htmlBody: String? = nil,
        date: Date,
        isRead: Bool = false,
        isStarred: Bool = false,
        labelsData: Data?,
        accountEmail: String,
        threadId: String? = nil,
        isHTMLContent: Bool = false,
        classificationCategory: String? = nil,
        classificationConfidence: Double? = nil,
        classificationSummary: String? = nil,
        classificationDate: Date? = nil,
        isClassified: Bool = false
    ) {
        self.id = id
        self.subject = subject
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.recipientsData = recipientsData
        self.body = body
        self.htmlBody = htmlBody
        self.date = date
        self.isRead = isRead
        self.isStarred = isStarred
        self.labelsData = labelsData
        self.accountEmail = accountEmail
        self.threadId = threadId
        self.isHTMLContent = isHTMLContent
        self.classificationCategory = classificationCategory
        self.classificationConfidence = classificationConfidence
        self.classificationSummary = classificationSummary
        self.classificationDate = classificationDate
        self.isClassified = isClassified
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Convenience factory from EmailAddress values

    /// Convenience initializer using EmailAddress / [EmailAddress] / [String] value types.
    public convenience init(
        id: String,
        subject: String,
        sender: EmailAddress,
        recipients: [EmailAddress] = [],
        body: String,
        htmlBody: String? = nil,
        date: Date,
        isRead: Bool = false,
        isStarred: Bool = false,
        labels: [String] = [],
        accountEmail: String,
        threadId: String? = nil,
        attachments: [EmailAttachment] = [],
        isHTMLContent: Bool = false,
        classificationCategory: String? = nil,
        classificationConfidence: Double? = nil,
        classificationSummary: String? = nil,
        classificationDate: Date? = nil,
        isClassified: Bool = false
    ) {
        let recipientsData = try? JSONEncoder().encode(recipients)
        let labelsData = try? JSONEncoder().encode(labels)
        self.init(
            id: id,
            subject: subject,
            senderName: sender.name,
            senderEmail: sender.email,
            recipientsData: recipientsData,
            body: body,
            htmlBody: htmlBody,
            date: date,
            isRead: isRead,
            isStarred: isStarred,
            labelsData: labelsData,
            accountEmail: accountEmail,
            threadId: threadId,
            isHTMLContent: isHTMLContent,
            classificationCategory: classificationCategory,
            classificationConfidence: classificationConfidence,
            classificationSummary: classificationSummary,
            classificationDate: classificationDate,
            isClassified: isClassified
        )
    }

    // MARK: - Classification helpers

    /// Updates classification fields in-place
    func updateClassification(category: String, confidence: Double, summary: String? = nil) {
        self.classificationCategory = category
        self.classificationConfidence = confidence
        self.classificationSummary = summary
        self.classificationDate = Date()
        self.isClassified = true
        self.updatedAt = Date()
    }

    /// Returns true if this email still needs classification
    func needsClassification(maxAge: TimeInterval = 30 * 24 * 60 * 60) -> Bool {
        guard isClassified else { return true }
        guard let classificationDate = classificationDate else { return true }
        return Date().timeIntervalSince(classificationDate) > maxAge
    }
}

// MARK: - Value-type helpers

/// Lightweight value type representing an email address
public struct EmailAddress: Codable, Equatable {
    public let name: String?
    public let email: String

    public var displayName: String {
        return name ?? email
    }

    public init(name: String? = nil, email: String) {
        self.name = name
        self.email = email
    }
}

/// Lightweight value type representing an email attachment
public struct EmailAttachment: Identifiable, Codable, Equatable {
    public let id: String
    public let filename: String
    public let mimeType: String
    public let size: Int64
    public let attachmentId: String?
    public let downloadURL: URL?

    public var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    public var systemImageName: String {
        switch mimeType {
        case let type where type.hasPrefix("image/"):
            return "photo"
        case let type where type.hasPrefix("video/"):
            return "video"
        case let type where type.hasPrefix("audio/"):
            return "speaker.wave.3"
        case "application/pdf":
            return "doc.text"
        case let type where type.contains("word"):
            return "doc.text"
        case let type where type.contains("excel") || type.contains("spreadsheet"):
            return "tablecells"
        case let type where type.contains("powerpoint") || type.contains("presentation"):
            return "rectangle.3.group"
        case let type where type.contains("zip") || type.contains("archive"):
            return "archivebox"
        default:
            return "doc"
        }
    }

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    public init(
        id: String,
        filename: String,
        mimeType: String,
        size: Int64,
        attachmentId: String? = nil,
        downloadURL: URL? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.attachmentId = attachmentId
        self.downloadURL = downloadURL
    }
}

// MARK: - EmailCategory enum

/// Categories for email classification
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
        case .promotions: return "Promotions"
        case .orderHistory: return "Order History"
        case .finance: return "Finance"
        case .personal: return "Personal"
        case .work: return "Work"
        case .appointments: return "Appointments"
        case .signInAlerts: return "Sign In Alerts"
        case .other: return "Other"
        }
    }

    public var iconName: String {
        switch self {
        case .promotions: return "megaphone"
        case .orderHistory: return "shippingbox"
        case .finance: return "dollarsign.circle"
        case .personal: return "person"
        case .work: return "briefcase"
        case .appointments: return "calendar"
        case .signInAlerts: return "shield.checkered"
        case .other: return "folder"
        }
    }

    public var color: String {
        switch self {
        case .promotions: return "orange"
        case .orderHistory: return "brown"
        case .finance: return "green"
        case .personal: return "blue"
        case .work: return "purple"
        case .appointments: return "red"
        case .signInAlerts: return "yellow"
        case .other: return "gray"
        }
    }
}

// MARK: - Classification models

/// Email data structure used when sending to classification API
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

    /// Convenience initializer from Email model
    public init(from email: Email) {
        let dateFormatter = ISO8601DateFormatter()
        self.init(
            id: email.id,
            from: email.senderEmail,
            subject: email.subject,
            date: dateFormatter.string(from: email.date),
            body: email.body
        )
    }
}

/// Result from the classification model
public struct EmailClassificationResult: Codable, Identifiable {
    public let id: UUID
    public let emailId: String
    public let category: EmailCategory
    public let confidence: Double
    public let rationale: String?
    public let summary: String?
    public let timestamp: Date

    public init(emailId: String, category: EmailCategory, confidence: Double, rationale: String? = nil, summary: String? = nil) {
        self.id = UUID()
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.emailId = try container.decode(String.self, forKey: .emailId)
        self.category = try container.decode(EmailCategory.self, forKey: .category)
        self.confidence = try container.decode(Double.self, forKey: .confidence)
        self.rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    public var isHighConfidence: Bool { confidence >= 0.8 }
    public var needsReview: Bool { confidence < 0.5 }
}

/// Classification statistics summary
public struct ClassificationStatistics {
    public let totalEmails: Int
    public let categoryCounts: [EmailCategory: Int]
    public let averageConfidence: Double
    public let highConfidenceCount: Int
    public let lowConfidenceCount: Int

    public var mostCommonCategory: EmailCategory? {
        categoryCounts.max(by: { $0.value < $1.value })?.key
    }

    public var highConfidencePercentage: Double {
        guard totalEmails > 0 else { return 0 }
        return Double(highConfidenceCount) / Double(totalEmails) * 100
    }

    public var needsReviewPercentage: Double {
        guard totalEmails > 0 else { return 0 }
        return Double(lowConfidenceCount) / Double(totalEmails) * 100
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

/// Email with classification information, used for digest generation
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

// MARK: - Digest Models

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
            let anyArray = array.compactMap { item -> AnyCodable? in
                guard let codable = item as? (any Codable) else { return nil }
                return AnyCodable(codable)
            }
            try container.encode(anyArray)
        case let dict as [String: Any]:
            let anyDict = dict.compactMapValues { item -> AnyCodable? in
                guard let codable = item as? (any Codable) else { return nil }
                return AnyCodable(codable)
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

// MARK: - Digest SwiftData Model

/// SwiftData model for persisting Daily Digest data
@Model
public class SwiftDataDigest {
    @Attribute(.unique) public var id: String
    public var dateKey: String
    public var digestDate: Date
    public var headline: String
    public var pillarsData: Data
    public var highlightsData: Data
    public var actionsData: Data
    public var moneyData: Data
    public var packagesData: Data
    public var calendarData: Data
    public var securityData: Data
    public var statsData: Data
    public var narrativeData: Data
    public var emailCount: Int
    public var accountEmails: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        dateKey: String,
        digestDate: Date,
        headline: String,
        pillarsData: Data,
        highlightsData: Data,
        actionsData: Data,
        moneyData: Data,
        packagesData: Data,
        calendarData: Data,
        securityData: Data,
        statsData: Data,
        narrativeData: Data,
        emailCount: Int,
        accountEmails: [String]
    ) {
        self.id = UUID().uuidString
        self.dateKey = dateKey
        self.digestDate = digestDate
        self.headline = headline
        self.pillarsData = pillarsData
        self.highlightsData = highlightsData
        self.actionsData = actionsData
        self.moneyData = moneyData
        self.packagesData = packagesData
        self.calendarData = calendarData
        self.securityData = securityData
        self.statsData = statsData
        self.narrativeData = narrativeData
        self.emailCount = emailCount
        self.accountEmails = accountEmails
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension SwiftDataDigest {
    func toDomainModel() -> DailyDigest? {
        do {
            let pillars = try JSONDecoder().decode(DigestPillars.self, from: pillarsData)
            let highlights = try JSONDecoder().decode([DigestHighlight].self, from: highlightsData)
            let actions = try JSONDecoder().decode([DigestAction].self, from: actionsData)
            let money = try JSONDecoder().decode(DigestMoney.self, from: moneyData)
            let packages = try JSONDecoder().decode([DigestPackage].self, from: packagesData)
            let calendar = try JSONDecoder().decode([DigestCalendar].self, from: calendarData)
            let security = try JSONDecoder().decode([DigestSecurity].self, from: securityData)
            let stats = try JSONDecoder().decode(DigestStats.self, from: statsData)
            let narrative = try JSONDecoder().decode(DigestNarrative.self, from: narrativeData)
            return DailyDigest(
                headline: headline,
                pillars: pillars,
                highlights: highlights,
                actions: actions,
                money: money,
                packages: packages,
                calendar: calendar,
                security: security,
                stats: stats,
                narrative: narrative
            )
        } catch {
            print("Failed to decode SwiftDataDigest: \(error)")
            return nil
        }
    }

    func updateFromDomainModel(_ digest: DailyDigest, emailCount: Int, accountEmails: [String]) throws {
        self.headline = digest.headline
        self.pillarsData = try JSONEncoder().encode(digest.pillars)
        self.highlightsData = try JSONEncoder().encode(digest.highlights)
        self.actionsData = try JSONEncoder().encode(digest.actions)
        self.moneyData = try JSONEncoder().encode(digest.money)
        self.packagesData = try JSONEncoder().encode(digest.packages)
        self.calendarData = try JSONEncoder().encode(digest.calendar)
        self.securityData = try JSONEncoder().encode(digest.security)
        self.statsData = try JSONEncoder().encode(digest.stats)
        self.narrativeData = try JSONEncoder().encode(digest.narrative)
        self.emailCount = emailCount
        self.accountEmails = accountEmails
        self.updatedAt = Date()
    }

    static func createDateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

extension DailyDigest {
    func toSwiftDataModel(for date: Date, emailCount: Int, accountEmails: [String]) throws -> SwiftDataDigest {
        let dateKey = SwiftDataDigest.createDateKey(for: date)
        return SwiftDataDigest(
            dateKey: dateKey,
            digestDate: date,
            headline: headline,
            pillarsData: try JSONEncoder().encode(pillars),
            highlightsData: try JSONEncoder().encode(highlights),
            actionsData: try JSONEncoder().encode(actions),
            moneyData: try JSONEncoder().encode(money),
            packagesData: try JSONEncoder().encode(packages),
            calendarData: try JSONEncoder().encode(calendar),
            securityData: try JSONEncoder().encode(security),
            statsData: try JSONEncoder().encode(stats),
            narrativeData: try JSONEncoder().encode(narrative),
            emailCount: emailCount,
            accountEmails: accountEmails
        )
    }
}

// MARK: - Classification configuration

public struct ClassificationConfiguration: Hashable {
    public let temperature: Double
    public let maxBodyLength: Int
    public let enableCaching: Bool
    public let cacheExpirationTime: TimeInterval
    public let maxConcurrentRequests: Int
    public let requestTimeout: TimeInterval

    public init(
        temperature: Double = 0.0,
        maxBodyLength: Int = 4000,
        enableCaching: Bool = true,
        cacheExpirationTime: TimeInterval = 24 * 60 * 60,
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

    public static let highAccuracy = ClassificationConfiguration(
        temperature: 0.0, maxBodyLength: 8000, enableCaching: true,
        maxConcurrentRequests: 2, requestTimeout: 45.0
    )
    public static let fastProcessing = ClassificationConfiguration(
        temperature: 0.1, maxBodyLength: 4000, enableCaching: true,
        maxConcurrentRequests: 5, requestTimeout: 20.0
    )
    public static let debug = ClassificationConfiguration(
        temperature: 0.0, maxBodyLength: 6000, enableCaching: false,
        maxConcurrentRequests: 1, requestTimeout: 60.0
    )
}
