import Foundation
import SwiftData

/// SwiftData model for persisting Email data
@Model
public class SwiftDataEmail {
    static let debugMessage = { print("📧 SwiftDataEmail model loaded") }()
    @Attribute(.unique) public var id: String
    public var subject: String
    public var senderName: String?
    public var senderEmail: String
    public var recipientsData: Data? // JSON-encoded [EmailAddress]
    public var body: String
    public var htmlBody: String? // HTML version of the email body
    public var date: Date
    public var isRead: Bool
    public var isStarred: Bool
    public var labelsData: Data? // JSON-encoded [String]
    public var accountEmail: String
    public var threadId: String?
    public var createdAt: Date
    public var updatedAt: Date
    
    // Classification fields
    public var classificationCategory: String? // EmailCategory raw value
    public var classificationConfidence: Double?
    public var classificationDate: Date?
    public var isClassified: Bool
    
    // Relationship to account (removed for now to avoid schema issues)
    // public var account: SwiftDataAccount?
    
    // Relationship to attachments (removed for now to avoid schema issues)
    // @Relationship(deleteRule: .cascade) public var attachments: [SwiftDataEmailAttachment]
    
    public init(
        id: String,
        subject: String,
        senderName: String?,
        senderEmail: String,
        recipientsData: Data?,
        body: String,
        htmlBody: String? = nil,
        date: Date,
        isRead: Bool,
        isStarred: Bool,
        labelsData: Data?,
        accountEmail: String,
        threadId: String?,
        classificationCategory: String? = nil,
        classificationConfidence: Double? = nil,
        classificationDate: Date? = nil,
        isClassified: Bool = false
        // account: SwiftDataAccount? = nil
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
        self.classificationCategory = classificationCategory
        self.classificationConfidence = classificationConfidence
        self.classificationDate = classificationDate
        self.isClassified = isClassified
        // self.account = account
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// SwiftData model for persisting Account data
@Model  
public class SwiftDataAccount {
    static let debugMessage = { print("📧 SwiftDataAccount model loaded") }()
    @Attribute(.unique) public var email: String
    public var displayName: String?
    public var isActive: Bool
    public var emailCount: Int
    public var lastSyncDate: Date?
    public var createdAt: Date
    public var updatedAt: Date
    
    // Relationship to emails (removed for now to avoid schema issues)
    // @Relationship(deleteRule: .cascade) public var emails: [SwiftDataEmail]
    
    public init(
        email: String,
        displayName: String? = nil,
        isActive: Bool = true,
        emailCount: Int = 0,
        lastSyncDate: Date? = nil
    ) {
        self.email = email
        self.displayName = displayName
        self.isActive = isActive
        self.emailCount = emailCount
        self.lastSyncDate = lastSyncDate
        self.createdAt = Date()
        self.updatedAt = Date()
        // self.emails = []
    }
}

/// SwiftData model for persisting EmailAttachment data
@Model
public class SwiftDataEmailAttachment {
    static let debugMessage = { print("📎 SwiftDataEmailAttachment model loaded") }()
    @Attribute(.unique) public var id: String
    public var filename: String
    public var mimeType: String
    public var size: Int64
    public var attachmentId: String?
    public var downloadURL: String? // Store as string, convert to URL when needed
    public var isDownloaded: Bool
    public var localPath: String? // Local file path if downloaded
    public var createdAt: Date
    public var updatedAt: Date
    
    // Relationship to email (optional for now to avoid schema issues)
    // public var email: SwiftDataEmail?
    
    public init(
        id: String,
        filename: String,
        mimeType: String,
        size: Int64,
        attachmentId: String? = nil,
        downloadURL: String? = nil,
        isDownloaded: Bool = false,
        localPath: String? = nil
        // email: SwiftDataEmail? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.attachmentId = attachmentId
        self.downloadURL = downloadURL
        self.isDownloaded = isDownloaded
        self.localPath = localPath
        // self.email = email
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Conversion Extensions

extension SwiftDataEmail {
    /// Convert SwiftData model to domain Email model
    func toDomainModel() -> Email {
        let recipients: [EmailAddress]
        if let recipientsData = recipientsData,
           let decodedRecipients = try? JSONDecoder().decode([EmailAddress].self, from: recipientsData) {
            recipients = decodedRecipients
        } else {
            recipients = []
        }
        
        let labels: [String]
        if let labelsData = labelsData,
           let decodedLabels = try? JSONDecoder().decode([String].self, from: labelsData) {
            labels = decodedLabels
        } else {
            labels = []
        }
        
        return Email(
            id: id,
            subject: subject,
            sender: EmailAddress(name: senderName, email: senderEmail),
            recipients: recipients,
            body: body,
            htmlBody: htmlBody,
            date: date,
            isRead: isRead,
            isStarred: isStarred,
            labels: labels,
            accountEmail: accountEmail,
            threadId: threadId,
            attachments: [], // TODO: Add attachment conversion when relationship is enabled
            isHTMLContent: htmlBody != nil,
            classificationCategory: classificationCategory,
            classificationConfidence: classificationConfidence,
            classificationDate: classificationDate,
            isClassified: isClassified
        )
    }
    
    /// Update SwiftData model from domain Email model
    func updateFromDomainModel(_ email: Email) {
        self.subject = email.subject
        self.senderName = email.sender.name
        self.senderEmail = email.sender.email
        self.recipientsData = try? JSONEncoder().encode(email.recipients)
        self.body = email.body
        self.htmlBody = email.htmlBody
        self.date = email.date
        self.isRead = email.isRead
        self.isStarred = email.isStarred
        self.labelsData = try? JSONEncoder().encode(email.labels)
        self.accountEmail = email.accountEmail
        self.threadId = email.threadId
        self.classificationCategory = email.classificationCategory
        self.classificationConfidence = email.classificationConfidence
        self.classificationDate = email.classificationDate
        self.isClassified = email.isClassified
        self.updatedAt = Date()
    }
    
    /// Update classification information
    func updateClassification(category: String, confidence: Double) {
        self.classificationCategory = category
        self.classificationConfidence = confidence
        self.classificationDate = Date()
        self.isClassified = true
        self.updatedAt = Date()
    }
    
    /// Check if email needs classification (not classified or classification is old)
    func needsClassification(maxAge: TimeInterval = 30 * 24 * 60 * 60) -> Bool { // 30 days default
        guard isClassified else { return true }
        guard let classificationDate = classificationDate else { return true }
        return Date().timeIntervalSince(classificationDate) > maxAge
    }
}

extension Email {
    /// Convert domain Email model to SwiftData model
    func toSwiftDataModel(account: SwiftDataAccount? = nil) -> SwiftDataEmail {
        let recipientsData = try? JSONEncoder().encode(recipients)
        let labelsData = try? JSONEncoder().encode(labels)
        
        return SwiftDataEmail(
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
            classificationCategory: classificationCategory,
            classificationConfidence: classificationConfidence,
            classificationDate: classificationDate,
            isClassified: isClassified
            // account: account
        )
    }
}