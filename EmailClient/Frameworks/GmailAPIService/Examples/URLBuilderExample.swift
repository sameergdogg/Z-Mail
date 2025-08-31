import Foundation

/// Example usage of the GmailURLBuilder struct
/// This file demonstrates how to use the URL builder for various Gmail API operations
class URLBuilderExample {
    
    // Example: Basic message fetching
    func exampleBasicMessageFetching() {
        let urlBuilder = GmailURLBuilder(baseURL: "https://www.googleapis.com/gmail/v1")
        
        // Fetch messages with max results
        let messagesURL = urlBuilder.makeMessagesURL(maxResults: 100)
        print("Messages URL: \(messagesURL)")
        
        // Fetch messages with search query
        let searchURL = urlBuilder.makeMessagesURL(maxResults: 50, query: "important")
        print("Search URL: \(searchURL)")
        
        // Fetch messages with labels
        let labeledURL = urlBuilder.makeMessagesURL(maxResults: 25, labelIds: ["INBOX", "UNREAD"])
        print("Labeled URL: \(labeledURL)")
    }
    
    // Example: Advanced search queries
    func exampleAdvancedSearch() {
        let urlBuilder = GmailURLBuilder(baseURL: "https://www.googleapis.com/gmail/v1")
        
        // Search for unread messages from specific sender
        let searchURL = urlBuilder.makeSearchURL(
            searchTerms: ["project", "update"],
            maxResults: 20,
            isUnread: true,
            fromEmail: "manager@company.com"
        )
        print("Advanced Search URL: \(searchURL)")
        
        // Search for starred messages with attachments
        let starredURL = urlBuilder.makeSearchURL(
            searchTerms: ["invoice"],
            isStarred: true,
            hasAttachment: true
        )
        print("Starred with Attachments URL: \(starredURL)")
    }
    
    // Example: Custom URL building
    func exampleCustomURLs() {
        let urlBuilder = GmailURLBuilder(baseURL: "https://www.googleapis.com/gmail/v1")
        
        // Custom endpoint with query parameters
        let customURL = urlBuilder.makeURL(
            endpoint: "/users/me/messages",
            queryParams: [
                "maxResults": "10",
                "q": "is:important",
                "labelIds": "INBOX,UNREAD"
            ]
        )
        print("Custom URL: \(customURL)")
        
        // Thread-related URLs
        let threadsURL = urlBuilder.makeThreadsURL(maxResults: 15, query: "meeting")
        print("Threads URL: \(threadsURL)")
        
        let threadDetailURL = urlBuilder.makeThreadDetailURL(threadId: "thread123")
        print("Thread Detail URL: \(threadDetailURL)")
    }
    
    // Example: URL validation
    func exampleURLValidation() {
        let urlBuilder = GmailURLBuilder(baseURL: "https://www.googleapis.com/gmail/v1")
        
        do {
            let urlString = urlBuilder.makeMessagesURL(maxResults: 50)
            let validURL = try urlBuilder.makeValidURL(from: urlString)
            print("Valid URL: \(validURL)")
        } catch {
            print("URL validation failed: \(error)")
        }
    }
    
    // Example: Request body creation
    func exampleRequestBodyCreation() {
        let urlBuilder = GmailURLBuilder(baseURL: "https://www.googleapis.com/gmail/v1")
        let encoder = JSONEncoder()
        
        // Example modify request
        struct ModifyRequest: Codable {
            let addLabelIds: [String]?
            let removeLabelIds: [String]?
        }
        
        let modifyRequest = ModifyRequest(
            addLabelIds: ["IMPORTANT"],
            removeLabelIds: ["UNREAD"]
        )
        
        do {
            let requestBody = try urlBuilder.makeRequestBody(modifyRequest, encoder: encoder)
            print("Request body size: \(requestBody.count) bytes")
        } catch {
            print("Failed to create request body: \(error)")
        }
    }
}

// MARK: - Usage Examples
extension URLBuilderExample {
    
    /// Demonstrates all examples
    static func runAllExamples() {
        let example = URLBuilderExample()
        
        print("=== Gmail URL Builder Examples ===\n")
        
        print("1. Basic Message Fetching:")
        example.exampleBasicMessageFetching()
        print()
        
        print("2. Advanced Search:")
        example.exampleAdvancedSearch()
        print()
        
        print("3. Custom URL Building:")
        example.exampleCustomURLs()
        print()
        
        print("4. URL Validation:")
        example.exampleURLValidation()
        print()
        
        print("5. Request Body Creation:")
        example.exampleRequestBodyCreation()
        print()
    }
}
