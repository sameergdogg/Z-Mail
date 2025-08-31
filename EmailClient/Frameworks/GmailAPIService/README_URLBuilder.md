# Gmail URL Builder

The `GmailURLBuilder` struct provides a clean, type-safe way to build Gmail API URLs with proper query parameter handling and URL encoding.

## Overview

Instead of manually constructing URL strings like:
```swift
let urlString = "\(baseURL)/users/me/messages?maxResults=\(maxResults)"
```

You can now use the URL builder:
```swift
let urlString = urlBuilder.makeMessagesURL(maxResults: maxResults)
```

## Features

- **Type-safe parameters**: All parameters are properly typed and validated
- **Automatic URL encoding**: Query parameters are automatically URL-encoded
- **Comprehensive coverage**: Supports all major Gmail API endpoints
- **Flexible query building**: Advanced search query construction
- **Request body handling**: JSON encoding for POST requests
- **URL validation**: Built-in URL validation with proper error handling

## Basic Usage

### Initialization

```swift
let urlBuilder = GmailURLBuilder(baseURL: "https://www.googleapis.com/gmail/v1")
```

### Fetching Messages

```swift
// Basic message fetching
let messagesURL = urlBuilder.makeMessagesURL(maxResults: 50)

// With search query
let searchURL = urlBuilder.makeMessagesURL(maxResults: 25, query: "important")

// With labels
let labeledURL = urlBuilder.makeMessagesURL(
    maxResults: 100, 
    labelIds: ["INBOX", "UNREAD"]
)

// With pagination
let paginatedURL = urlBuilder.makeMessagesURL(
    maxResults: 20, 
    pageToken: "nextPageToken123"
)
```

### Advanced Search

```swift
// Search with multiple terms and filters
let searchURL = urlBuilder.makeSearchURL(
    searchTerms: ["project", "update"],
    maxResults: 20,
    isUnread: true,
    fromEmail: "manager@company.com",
    hasAttachment: true
)
```

### Message Operations

```swift
// Get message details
let messageURL = urlBuilder.makeMessageDetailURL(messageId: "message123")

// Modify message (labels, etc.)
let modifyURL = urlBuilder.makeMessageModifyURL(messageId: "message123")

// Get attachment
let attachmentURL = urlBuilder.makeAttachmentURL(
    messageId: "message123", 
    attachmentId: "attachment456"
)
```

### Threads and Labels

```swift
// Get threads
let threadsURL = urlBuilder.makeThreadsURL(maxResults: 15, query: "meeting")

// Get thread details
let threadDetailURL = urlBuilder.makeThreadDetailURL(threadId: "thread123")

// Get labels
let labelsURL = urlBuilder.makeLabelsURL()
```

### Custom URLs

```swift
// Custom endpoint with query parameters
let customURL = urlBuilder.makeURL(
    endpoint: "/users/me/messages",
    queryParams: [
        "maxResults": "10",
        "q": "is:important",
        "labelIds": "INBOX,UNREAD"
    ]
)
```

## Request Body Handling

For POST requests that require a request body:

```swift
// Create request body from encodable object
let requestBody = try urlBuilder.makeRequestBody(
    modifyRequest, 
    encoder: jsonEncoder
)
```

## URL Validation

The builder includes built-in URL validation:

```swift
do {
    let urlString = urlBuilder.makeMessagesURL(maxResults: 50)
    let validURL = try urlBuilder.makeValidURL(from: urlString)
    // Use validURL...
} catch {
    // Handle invalid URL error
}
```

## Search Query Building

The builder can construct Gmail search queries with various filters:

```swift
// Basic search
let query = urlBuilder.makeSearchQuery(from: ["invoice", "urgent"])

// With filters
let filteredQuery = urlBuilder.makeSearchQuery(
    from: ["project"],
    isUnread: true,
    isStarred: false,
    fromEmail: "client@company.com",
    hasAttachment: true
)
```

## Gmail Search Operators

The search query builder supports common Gmail search operators:

- `is:unread` / `is:read`
- `is:starred` / `is:unstarred`
- `from:email@domain.com`
- `to:email@domain.com`
- `has:attachment` / `no:attachment`
- `label:INBOX`
- `subject:keyword`
- `after:2024/01/01`
- `before:2024/12/31`

## Error Handling

The URL builder throws `GmailAPIError.invalidURL` when:

- URL construction fails
- Invalid characters in query parameters
- Malformed endpoint paths

## Integration with GmailAPIService

The URL builder is automatically integrated into the `GmailAPIServiceImpl`:

```swift
internal class GmailAPIServiceImpl: GmailAPIServiceProtocol {
    private let dependencies: GmailAPIServiceDependencies
    private lazy var urlBuilder = GmailURLBuilder(baseURL: dependencies.baseURL)
    
    // All URL construction now uses the builder
    let urlString = urlBuilder.makeMessagesURL(maxResults: maxResults)
    let url = try urlBuilder.makeValidURL(from: urlString)
}
```

## Benefits

1. **Maintainability**: Centralized URL construction logic
2. **Type Safety**: Compile-time parameter validation
3. **URL Encoding**: Automatic handling of special characters
4. **Consistency**: Uniform URL structure across all endpoints
5. **Extensibility**: Easy to add new endpoints and parameters
6. **Testing**: Simplified unit testing of URL construction
7. **Documentation**: Self-documenting API with clear method names

## Example Implementation

See `Examples/URLBuilderExample.swift` for comprehensive usage examples.

## Migration from Hardcoded URLs

**Before:**
```swift
let urlString = "\(dependencies.baseURL)/users/me/messages?maxResults=\(maxResults)"
guard let url = URL(string: urlString) else {
    throw GmailAPIError.invalidURL
}
```

**After:**
```swift
let urlString = urlBuilder.makeMessagesURL(maxResults: maxResults)
let url = try urlBuilder.makeValidURL(from: urlString)
```

This approach eliminates string interpolation errors, ensures proper URL encoding, and provides a more maintainable codebase.
