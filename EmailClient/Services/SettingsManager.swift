import Foundation
import SwiftUI

class SettingsManager: ObservableObject {
    @Published var useRichEmailRendering: Bool {
        didSet {
            UserDefaults.standard.set(useRichEmailRendering, forKey: "useRichEmailRendering")
        }
    }
    
    @Published var senderSortOrder: SenderSortOrder {
        didSet {
            UserDefaults.standard.set(senderSortOrder.rawValue, forKey: "senderSortOrder")
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let richRenderingKey = "useRichEmailRendering"
    private let senderSortOrderKey = "senderSortOrder"
    
    init() {
        // Default to rich rendering (true)
        self.useRichEmailRendering = userDefaults.object(forKey: richRenderingKey) as? Bool ?? true
        
        // Default to alphabetical sorting
        if let savedSortOrder = userDefaults.string(forKey: senderSortOrderKey),
           let sortOrder = SenderSortOrder(rawValue: savedSortOrder) {
            self.senderSortOrder = sortOrder
        } else {
            self.senderSortOrder = .alphabeticalAscending
        }
    }
}

enum EmailRenderingMode {
    case plainText
    case richHTML
    
    var displayName: String {
        switch self {
        case .plainText:
            return "Plain Text"
        case .richHTML:
            return "Rich HTML"
        }
    }
}

enum SenderSortOrder: String, CaseIterable {
    case alphabeticalAscending = "alphabeticalAscending"
    case alphabeticalDescending = "alphabeticalDescending"
    case emailCountAscending = "emailCountAscending"
    case emailCountDescending = "emailCountDescending"
    case conversationCountAscending = "conversationCountAscending"
    case conversationCountDescending = "conversationCountDescending"
    
    var displayName: String {
        switch self {
        case .alphabeticalAscending:
            return "Name (A-Z)"
        case .alphabeticalDescending:
            return "Name (Z-A)"
        case .emailCountAscending:
            return "Message Count (Low to High)"
        case .emailCountDescending:
            return "Message Count (High to Low)"
        case .conversationCountAscending:
            return "Conversation Count (Low to High)"
        case .conversationCountDescending:
            return "Conversation Count (High to Low)"
        }
    }
    
    var iconName: String {
        switch self {
        case .alphabeticalAscending, .alphabeticalDescending:
            return "textformat.abc"
        case .emailCountAscending, .emailCountDescending:
            return "envelope"
        case .conversationCountAscending, .conversationCountDescending:
            return "bubble.left.and.bubble.right"
        }
    }
}