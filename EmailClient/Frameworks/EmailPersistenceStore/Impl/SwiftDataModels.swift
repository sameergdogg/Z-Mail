import Foundation
import SwiftData

/// SwiftData model for persisting Email data
@Model
public class SwiftDataEmail {
    @Attribute(.unique) public var id: String
    public var subject: String
    public var senderName: String?
    public var senderEmail: String
    public var recipientsData: Data? // JSON-encoded [EmailAddress]
    public var body: String
    public var date: Date
    public var isRead: Bool
    public var isStarred: Bool
    public var labelsData: Data? // JSON-encoded [String]
    public var accountEmail: String
    public var threadId: String?
    public var createdAt: Date
    public var updatedAt: Date
    
    // Relationship to account
    public var account: SwiftDataAccount?
    
    public init(
        id: String,
        subject: String,
        senderName: String?,
        senderEmail: String,
        recipientsData: Data?,
        body: String,
        date: Date,
        isRead: Bool,
        isStarred: Bool,
        labelsData: Data?,
        accountEmail: String,
        threadId: String?,
        account: SwiftDataAccount? = nil
    ) {
        self.id = id
        self.subject = subject
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.recipientsData = recipientsData
        self.body = body
        self.date = date
        self.isRead = isRead
        self.isStarred = isStarred
        self.labelsData = labelsData
        self.accountEmail = accountEmail
        self.threadId = threadId
        self.account = account
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// SwiftData model for persisting Account data
@Model
public class SwiftDataAccount {
    @Attribute(.unique) public var email: String
    public var displayName: String?
    public var isActive: Bool
    public var emailCount: Int
    public var lastSyncDate: Date?
    public var createdAt: Date
    public var updatedAt: Date
    
    // Relationship to emails
    @Relationship(deleteRule: .cascade) public var emails: [SwiftDataEmail]
    
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
        self.emails = []
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
            date: date,
            isRead: isRead,
            isStarred: isStarred,
            labels: labels,
            accountEmail: accountEmail,
            threadId: threadId
        )
    }
    
    /// Update SwiftData model from domain Email model
    func updateFromDomainModel(_ email: Email) {
        self.subject = email.subject
        self.senderName = email.sender.name
        self.senderEmail = email.sender.email
        self.recipientsData = try? JSONEncoder().encode(email.recipients)
        self.body = email.body
        self.date = email.date
        self.isRead = email.isRead
        self.isStarred = email.isStarred
        self.labelsData = try? JSONEncoder().encode(email.labels)
        self.accountEmail = email.accountEmail
        self.threadId = email.threadId
        self.updatedAt = Date()
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
            date: date,
            isRead: isRead,
            isStarred: isStarred,
            labelsData: labelsData,
            accountEmail: accountEmail,
            threadId: threadId,
            account: account
        )
    }
}