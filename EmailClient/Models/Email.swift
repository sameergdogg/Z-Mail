import Foundation

public struct Email: Identifiable, Codable, Equatable {
    public let id: String
    public let subject: String
    public let sender: EmailAddress
    public let recipients: [EmailAddress]
    public let body: String
    public let htmlBody: String?
    public let date: Date
    public let isRead: Bool
    public let isStarred: Bool
    public let labels: [String]
    public let accountEmail: String
    public let threadId: String?
    public let attachments: [EmailAttachment]
    public let isHTMLContent: Bool
    
    public init(id: String, subject: String, sender: EmailAddress, recipients: [EmailAddress], body: String, htmlBody: String? = nil, date: Date, isRead: Bool = false, isStarred: Bool = false, labels: [String] = [], accountEmail: String, threadId: String? = nil, attachments: [EmailAttachment] = [], isHTMLContent: Bool = false) {
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

public struct EmailAddress: Codable, Equatable {
    public let name: String?
    public let email: String
    
    public var displayName: String {
        return name ?? email
    }
}

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
}

