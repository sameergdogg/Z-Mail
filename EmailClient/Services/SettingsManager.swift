import Foundation
import SwiftUI

class SettingsManager: ObservableObject {
    @Published var useRichEmailRendering: Bool {
        didSet {
            UserDefaults.standard.set(useRichEmailRendering, forKey: "useRichEmailRendering")
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let richRenderingKey = "useRichEmailRendering"
    
    init() {
        // Default to rich rendering (true)
        self.useRichEmailRendering = userDefaults.object(forKey: richRenderingKey) as? Bool ?? true
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