import Foundation

// MARK: - Gmail API Response Models
public struct GmailMessageList: Codable {
    public let messages: [GmailMessageInfo]?
    public let nextPageToken: String?
    public let resultSizeEstimate: Int?
    
    public init(messages: [GmailMessageInfo]?, nextPageToken: String?, resultSizeEstimate: Int?) {
        self.messages = messages
        self.nextPageToken = nextPageToken
        self.resultSizeEstimate = resultSizeEstimate
    }
}

public struct GmailMessageInfo: Codable {
    public let id: String
    public let threadId: String
    
    public init(id: String, threadId: String) {
        self.id = id
        self.threadId = threadId
    }
}

public struct GmailMessage: Codable {
    public let id: String
    public let threadId: String?
    public let labelIds: [String]?
    public let snippet: String?
    public let payload: GmailPayload?
    public let sizeEstimate: Int?
    public let historyId: String?
    public let internalDate: String?
    
    public init(id: String, threadId: String?, labelIds: [String]?, snippet: String?, payload: GmailPayload?, sizeEstimate: Int?, historyId: String?, internalDate: String?) {
        self.id = id
        self.threadId = threadId
        self.labelIds = labelIds
        self.snippet = snippet
        self.payload = payload
        self.sizeEstimate = sizeEstimate
        self.historyId = historyId
        self.internalDate = internalDate
    }
}

public struct GmailPayload: Codable {
    public let mimeType: String?
    public let headers: [GmailHeader]?
    public let body: GmailBody?
    public let parts: [GmailPart]?
    
    public init(mimeType: String?, headers: [GmailHeader]?, body: GmailBody?, parts: [GmailPart]?) {
        self.mimeType = mimeType
        self.headers = headers
        self.body = body
        self.parts = parts
    }
}

public struct GmailHeader: Codable {
    public let name: String
    public let value: String
    
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct GmailBody: Codable {
    public let size: Int?
    public let data: String?
    
    public init(size: Int?, data: String?) {
        self.size = size
        self.data = data
    }
}

public struct GmailPart: Codable {
    public let mimeType: String?
    public let headers: [GmailHeader]?
    public let body: GmailBody?
    public let parts: [GmailPart]?
    
    public init(mimeType: String?, headers: [GmailHeader]?, body: GmailBody?, parts: [GmailPart]?) {
        self.mimeType = mimeType
        self.headers = headers
        self.body = body
        self.parts = parts
    }
}

// MARK: - Gmail API Request Models
public struct GmailModifyRequest: Codable {
    public let addLabelIds: [String]?
    public let removeLabelIds: [String]?
    
    public init(addLabelIds: [String]?, removeLabelIds: [String]?) {
        self.addLabelIds = addLabelIds
        self.removeLabelIds = removeLabelIds
    }
}

// MARK: - Gmail Labels
public struct GmailLabels {
    public static let unread = "UNREAD"
    public static let starred = "STARRED"
    public static let inbox = "INBOX"
    public static let sent = "SENT"
    public static let draft = "DRAFT"
    public static let trash = "TRASH"
    public static let spam = "SPAM"
    public static let important = "IMPORTANT"
}