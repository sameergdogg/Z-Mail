import Foundation

struct Email: Identifiable, Codable {
    let id: String
    let subject: String
    let sender: EmailAddress
    let recipients: [EmailAddress]
    let body: String
    let htmlBody: String?
    let date: Date
    let isRead: Bool
    let isStarred: Bool
    let labels: [String]
    let accountEmail: String
    let threadId: String?
    let attachments: [EmailAttachment]
    let isHTMLContent: Bool
    
    init(id: String, subject: String, sender: EmailAddress, recipients: [EmailAddress], body: String, htmlBody: String? = nil, date: Date, isRead: Bool = false, isStarred: Bool = false, labels: [String] = [], accountEmail: String, threadId: String? = nil, attachments: [EmailAttachment] = [], isHTMLContent: Bool = false) {
        self.id = id
        self.subject = subject
        self.sender = sender
        self.recipients = recipients
        self.body = body
        self.htmlBody = htmlBody
        self.date = date
        self.isRead = isRead
        self.isStarred = isStarred
        self.labels = labels
        self.accountEmail = accountEmail
        self.threadId = threadId
        self.attachments = attachments
        self.isHTMLContent = isHTMLContent
    }
}

struct EmailAddress: Codable {
    let name: String?
    let email: String
    
    var displayName: String {
        return name ?? email
    }
}

struct EmailAttachment: Identifiable, Codable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int64
    let attachmentId: String?
    let downloadURL: URL?
    
    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }
    
    var systemImageName: String {
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
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

struct GmailAccount: Identifiable, Codable {
    let id = UUID()
    let email: String
    let displayName: String?
    var accessToken: String?
    var refreshToken: String?
    let dateAdded: Date
    
    init(email: String, displayName: String? = nil, accessToken: String? = nil, refreshToken: String? = nil) {
        self.email = email
        self.displayName = displayName
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.dateAdded = Date()
    }
}