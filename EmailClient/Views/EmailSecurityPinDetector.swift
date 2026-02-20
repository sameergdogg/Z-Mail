import Foundation

/// Utility for detecting security PINs (e.g., 6, 8, 10 digit codes) in email content.
public struct EmailSecurityPinDetector {
    /// List of PIN lengths to match (customize as needed)
    public static let pinLengths = [6, 8, 10]
    
    /// Returns the first detected PIN string, or nil if none found
    public static func firstSecurityPin(in text: String) -> String? {
        for length in pinLengths {
            let pattern = "\\b\\d{\(length)}\\b"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if let matchRange = Range(match.range, in: text) {
                        return String(text[matchRange])
                    }
                }
            }
        }
        return nil
    }
    
    /// Returns all detected PIN strings (can be empty)
    public static func allSecurityPins(in text: String) -> [String] {
        var pins: [String] = []
        for length in pinLengths {
            let pattern = "\\b\\d{\(length)}\\b"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: range)
                for match in matches {
                    if let matchRange = Range(match.range, in: text) {
                        pins.append(String(text[matchRange]))
                    }
                }
            }
        }
        return pins
    }
    
    /// Returns true if any valid PIN is detected (for filter/tagging)
    public static func containsSecurityPin(in text: String) -> Bool {
        return firstSecurityPin(in: text) != nil
    }
}
