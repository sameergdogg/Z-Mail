import Foundation

// MARK: - Email Parsing Helpers
extension GmailAPIServiceImpl {
    
    internal func parseEmailAddress(_ emailString: String) -> EmailAddress {
        let pattern = #"^(.*?)\s*<(.+)>$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: emailString, range: NSRange(emailString.startIndex..., in: emailString)) {
            let nameRange = Range(match.range(at: 1), in: emailString)
            let emailRange = Range(match.range(at: 2), in: emailString)
            
            let name = nameRange.map { String(emailString[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
            let email = emailRange.map { String(emailString[$0]) } ?? emailString
            
            return EmailAddress(name: name?.isEmpty == false ? name : nil, email: email)
        }
        
        return EmailAddress(name: nil, email: emailString)
    }
    
    internal func parseEmailAddresses(_ emailString: String) -> [EmailAddress] {
        let addresses = emailString.components(separatedBy: ",")
        return addresses.map { parseEmailAddress($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    
    internal func parseDate(_ dateString: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        return Date()
    }
}

// MARK: - Body Extraction Helpers
extension GmailAPIServiceImpl {
    
    internal func extractBodies(from payload: GmailPayload?) -> (plain: String, html: String?, isHTML: Bool) {
        guard let payload = payload else { return ("", nil, false) }
        
        var plainText = ""
        var htmlText: String?
        
        // First, try to extract from the main payload
        if let body = payload.body?.data, let mimeType = payload.mimeType {
            let decodedBody = decodeBase64URLSafe(body)
            if mimeType == "text/plain" {
                plainText = decodedBody
            } else if mimeType == "text/html" {
                htmlText = decodedBody
                if plainText.isEmpty {
                    plainText = stripHTML(decodedBody)
                }
            }
        }
        
        // Then process parts recursively
        if let parts = payload.parts {
            extractFromParts(parts, plainText: &plainText, htmlText: &htmlText)
        }
        
        // If we still don't have plain text but have HTML, generate it
        if plainText.isEmpty && htmlText != nil {
            plainText = stripHTML(htmlText!)
        }
        
        // Determine if this is HTML content
        let isHTMLContent = htmlText != nil && !htmlText!.isEmpty && htmlText!.contains("<")
        
        return (plainText, htmlText, isHTMLContent)
    }
    
    internal func extractFromParts(_ parts: [GmailPart], plainText: inout String, htmlText: inout String?) {
        for part in parts {
            if let mimeType = part.mimeType {
                if mimeType == "text/plain" && plainText.isEmpty {
                    if let body = part.body?.data {
                        plainText = decodeBase64URLSafe(body)
                    }
                } else if mimeType == "text/html" && htmlText == nil {
                    if let body = part.body?.data {
                        htmlText = decodeBase64URLSafe(body)
                    }
                } else if mimeType.hasPrefix("multipart/") {
                    // Handle nested multipart messages
                    if let subParts = part.parts {
                        extractFromParts(subParts, plainText: &plainText, htmlText: &htmlText)
                    }
                }
            }
            
            // Recursively check nested parts
            if let subParts = part.parts {
                extractFromParts(subParts, plainText: &plainText, htmlText: &htmlText)
            }
        }
    }
}

// MARK: - Attachment Helpers
extension GmailAPIServiceImpl {
    
    internal func extractAttachments(from payload: GmailPayload?, messageId: String) -> [EmailAttachment] {
        guard let payload = payload else { return [] }
        
        var attachments: [EmailAttachment] = []
        
        if let parts = payload.parts {
            for part in parts {
                if let filename = part.headers?.first(where: { $0.name.lowercased() == "content-disposition" })?.value,
                   filename.contains("attachment") || filename.contains("filename=") {
                    
                    let attachmentFilename = extractFilename(from: filename) ?? "Unknown File"
                    let mimeType = part.mimeType ?? "application/octet-stream"
                    let size = Int64(part.body?.size ?? 0)
                    let attachmentId = part.body?.data
                    
                    let attachment = EmailAttachment(
                        id: UUID().uuidString,
                        filename: attachmentFilename,
                        mimeType: mimeType,
                        size: size,
                        attachmentId: attachmentId,
                        downloadURL: nil
                    )
                    
                    attachments.append(attachment)
                }
                
                if let subParts = part.parts {
                    let subPayload = GmailPayload(mimeType: part.mimeType, headers: part.headers, body: part.body, parts: subParts)
                    attachments.append(contentsOf: extractAttachments(from: subPayload, messageId: messageId))
                }
            }
        }
        
        return attachments
    }
    
    internal func extractFilename(from contentDisposition: String) -> String? {
        let pattern = #"filename[*]?=(?:"([^"]+)"|([^;\s]+))"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: contentDisposition, range: NSRange(contentDisposition.startIndex..., in: contentDisposition)) {
            
            if let range = Range(match.range(at: 1), in: contentDisposition) {
                return String(contentDisposition[range])
            } else if let range = Range(match.range(at: 2), in: contentDisposition) {
                return String(contentDisposition[range])
            }
        }
        return nil
    }
}

// MARK: - String Processing Helpers
extension GmailAPIServiceImpl {
    
    internal func stripHTML(_ html: String) -> String {
        let htmlRegex = try! NSRegularExpression(pattern: "<[^>]+>", options: [])
        let range = NSRange(location: 0, length: html.count)
        let strippedText = htmlRegex.stringByReplacingMatches(in: html, options: [], range: range, withTemplate: "")
        
        return strippedText
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    internal func decodeBase64URLSafe(_ string: String) -> String {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let padding = 4 - base64.count % 4
        if padding != 4 {
            base64 += String(repeating: "=", count: padding)
        }
        
        guard let data = Data(base64Encoded: base64),
              let decoded = String(data: data, encoding: .utf8) else {
            return string
        }
        
        return decoded
    }
}