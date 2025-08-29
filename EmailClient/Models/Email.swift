import Foundation

struct Email: Identifiable, Codable {
    let id: String
    let subject: String
    let sender: EmailAddress
    let recipients: [EmailAddress]
    let body: String
    let date: Date
    let isRead: Bool
    let isStarred: Bool
    let labels: [String]
    let accountEmail: String
    let threadId: String?
    
    init(id: String, subject: String, sender: EmailAddress, recipients: [EmailAddress], body: String, date: Date, isRead: Bool = false, isStarred: Bool = false, labels: [String] = [], accountEmail: String, threadId: String? = nil) {
        self.id = id
        self.subject = subject
        self.sender = sender
        self.recipients = recipients
        self.body = body
        self.date = date
        self.isRead = isRead
        self.isStarred = isStarred
        self.labels = labels
        self.accountEmail = accountEmail
        self.threadId = threadId
    }
}

struct EmailAddress: Codable {
    let name: String?
    let email: String
    
    var displayName: String {
        return name ?? email
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