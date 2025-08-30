import Foundation
import CoreData

/// Core Data model definitions for email persistence

// MARK: - Managed Object Models

/// Core Data entity for Email
@objc(PersistedEmail)
public class PersistedEmail: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var subject: String
    @NSManaged public var senderName: String?
    @NSManaged public var senderEmail: String
    @NSManaged public var recipientsData: Data?
    @NSManaged public var body: String
    @NSManaged public var htmlBody: String?
    @NSManaged public var date: Date
    @NSManaged public var isRead: Bool
    @NSManaged public var isStarred: Bool
    @NSManaged public var labelsData: Data?
    @NSManaged public var accountEmail: String
    @NSManaged public var threadId: String?
    @NSManaged public var isHTMLContent: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var attachments: Set<PersistedEmailAttachment>
    @NSManaged public var account: PersistedAccount
}

/// Core Data entity for Email Attachment
@objc(PersistedEmailAttachment)
public class PersistedEmailAttachment: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var filename: String
    @NSManaged public var mimeType: String
    @NSManaged public var size: Int64
    @NSManaged public var attachmentId: String?
    @NSManaged public var downloadURL: String?
    @NSManaged public var isDownloaded: Bool
    @NSManaged public var localPath: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var email: PersistedEmail
}

/// Core Data entity for Account metadata
@objc(PersistedAccount)
public class PersistedAccount: NSManagedObject {
    @NSManaged public var email: String
    @NSManaged public var displayName: String?
    @NSManaged public var lastSyncDate: Date?
    @NSManaged public var emailCount: Int32
    @NSManaged public var isActive: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var emails: Set<PersistedEmail>
}

// MARK: - Core Data Extensions

extension PersistedEmail {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PersistedEmail> {
        return NSFetchRequest<PersistedEmail>(entityName: "PersistedEmail")
    }
    
    /// Converts Core Data entity to app Email model
    public func toEmail() -> Email {
        let emailAddress = EmailAddress(name: senderName, email: senderEmail)
        
        let recipients = recipientsData.flatMap { data in
            try? JSONDecoder().decode([EmailAddress].self, from: data)
        } ?? []
        
        let labels = labelsData.flatMap { data in
            try? JSONDecoder().decode([String].self, from: data)
        } ?? []
        
        let emailAttachments = attachments.map { $0.toEmailAttachment() }
        
        return Email(
            id: id,
            subject: subject,
            sender: emailAddress,
            recipients: recipients,
            body: body,
            htmlBody: htmlBody,
            date: date,
            isRead: isRead,
            isStarred: isStarred,
            labels: labels,
            accountEmail: accountEmail,
            threadId: threadId,
            attachments: emailAttachments,
            isHTMLContent: isHTMLContent
        )
    }
    
    /// Updates Core Data entity from app Email model
    public func update(from email: Email) {
        id = email.id
        subject = email.subject
        senderName = email.sender.name
        senderEmail = email.sender.email
        body = email.body
        htmlBody = email.htmlBody
        date = email.date
        isRead = email.isRead
        isStarred = email.isStarred
        accountEmail = email.accountEmail
        threadId = email.threadId
        isHTMLContent = email.isHTMLContent
        updatedAt = Date()
        
        // Encode recipients and labels as JSON
        recipientsData = try? JSONEncoder().encode(email.recipients)
        labelsData = try? JSONEncoder().encode(email.labels)
    }
}

extension PersistedEmailAttachment {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PersistedEmailAttachment> {
        return NSFetchRequest<PersistedEmailAttachment>(entityName: "PersistedEmailAttachment")
    }
    
    /// Converts Core Data entity to app EmailAttachment model
    public func toEmailAttachment() -> EmailAttachment {
        return EmailAttachment(
            id: id,
            filename: filename,
            mimeType: mimeType,
            size: size,
            attachmentId: attachmentId,
            downloadURL: downloadURL.flatMap(URL.init(string:))
        )
    }
    
    /// Updates Core Data entity from app EmailAttachment model
    public func update(from attachment: EmailAttachment) {
        id = attachment.id
        filename = attachment.filename
        mimeType = attachment.mimeType
        size = attachment.size
        attachmentId = attachment.attachmentId
        downloadURL = attachment.downloadURL?.absoluteString
        isDownloaded = false
        localPath = nil
    }
}

extension PersistedAccount {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PersistedAccount> {
        return NSFetchRequest<PersistedAccount>(entityName: "PersistedAccount")
    }
}

// MARK: - Fetch Request Builders

public extension PersistedEmail {
    /// Fetch emails for a specific account
    static func fetchRequest(for accountEmail: String) -> NSFetchRequest<PersistedEmail> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "accountEmail == %@", accountEmail)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PersistedEmail.date, ascending: false)]
        return request
    }
    
    /// Fetch emails with filter
    static func fetchRequest(for accountEmail: String, filter: EmailFilter) -> NSFetchRequest<PersistedEmail> {
        let request = fetchRequest(for: accountEmail)
        
        switch filter {
        case .all:
            break // No additional filtering
        case .unread:
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                request.predicate!,
                NSPredicate(format: "isRead == NO")
            ])
        case .starred:
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                request.predicate!,
                NSPredicate(format: "isStarred == YES")
            ])
        case .account(let email):
            request.predicate = NSPredicate(format: "accountEmail == %@", email)
        case .label(let label):
            // For Core Data, we would need to create a proper relationship or JSON query
            // For now, we'll handle this in the application layer
            break
        }
        
        return request
    }
    
    /// Fetch emails newer than a specific date
    static func fetchRequest(for accountEmail: String, newerThan date: Date) -> NSFetchRequest<PersistedEmail> {
        let request = fetchRequest(for: accountEmail)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            request.predicate!,
            NSPredicate(format: "date > %@", date as NSDate)
        ])
        return request
    }
}