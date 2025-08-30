# Z-Mail
**A Generation Z Email Client** 📧✨

A modern, native iOS email client built with SwiftUI, designed with clean architecture principles and focused on Gmail integration.

## 📱 Features

- **Multi-Account Gmail Support**: Connect and manage multiple Gmail accounts
- **Rich Email Rendering**: Toggle between plain text and rich HTML email display
- **Smart Email Management**: Mark emails as read, star/unstar, and organize with labels
- **Responsive Design**: Native iOS interface optimized for all screen sizes
- **Modern Authentication**: Secure OAuth 2.0 integration with Google Sign-In
- **Offline-Ready Architecture**: Robust error handling and authentication management

## 🏗️ Architecture Overview

Z-Mail is built using **Clean Architecture** principles with a modular, framework-based approach that ensures maintainability, testability, and scalability.

### High-Level Architecture

```
┌─────────────────────────────────────────────────┐
│                  UI Layer                       │
│  SwiftUI Views + ViewModels (ObservableObject) │
├─────────────────────────────────────────────────┤
│                Service Layer                    │
│     EmailService, AccountManager, Settings     │
├─────────────────────────────────────────────────┤
│              Framework Layer                    │
│    GmailAPIService & EmailPersistenceStore     │
├─────────────────────────────────────────────────┤
│                 Data Layer                      │
│     Models, APIs, Smart Persistence Layer      │
└─────────────────────────────────────────────────┘
```

## 🗂️ Project Structure

```
EmailClient/
├── 📱 App Entry Point
│   ├── EmailClientApp.swift          # App entry point and configuration
│   └── ContentView.swift             # Root view with navigation logic
├── 🎨 Views/
│   ├── EmailListView.swift           # Main inbox interface
│   ├── EmailDetailView.swift         # Email reading interface
│   ├── FilterView.swift              # Email filtering options
│   └── SettingsView.swift            # App settings and account management
├── 🔧 Services/
│   ├── EmailService.swift            # Email data management and filtering
│   ├── AccountManager.swift          # Gmail account authentication and management
│   └── SettingsManager.swift         # User preferences persistence
├── 📊 Models/
│   └── Email.swift                   # Data models (Email, EmailAddress, GmailAccount)
└── 🏗️ Frameworks/
    ├── GmailAPIService/              # Modular Gmail API framework
    │   ├── GmailAPIService.swift     # Framework entry point and exports
    │   ├── PublicAPI/                # External interface contracts
    │   │   ├── GmailAPIServiceProtocol.swift
    │   │   └── GmailDataModels.swift
    │   ├── ImplWiring/               # Dependency injection and factory
    │   │   └── GmailAPIServiceFactory.swift
    │   └── Impl/                     # Internal implementation
    │       ├── GmailAPIServiceImpl.swift
    │       └── GmailAPIServiceHelpers.swift
    └── EmailPersistenceStore/        # Smart persistence framework
        ├── EmailPersistenceStore.swift  # Framework entry point and exports
        ├── PublicAPI/                # External interface contracts
        │   └── EmailPersistenceProtocol.swift
        ├── ImplWiring/               # Dependency injection and factory
        │   └── EmailPersistenceFactory.swift
        └── Impl/                     # Internal implementation
            ├── EmailPersistenceStoreImpl.swift
            ├── EmailDataModel.xcdatamodeld
            └── CoreDataStack.swift
```

## 🏛️ Framework Architecture

Both major frameworks (GmailAPIService and EmailPersistenceStore) follow a **three-layer framework pattern** for maximum modularity:

### 🏛️ GmailAPIService Framework

The Gmail API Service provides a clean interface for all Gmail operations:

### 📋 PublicAPI Layer
**Purpose**: Defines the contract that external consumers depend on
```swift
// Protocol defining all Gmail operations
public protocol GmailAPIServiceProtocol {
    func fetchMessages(for user: GIDGoogleUser, maxResults: Int) async throws -> [GmailMessage]
    func convertGmailMessageToEmail(_ gmailMessage: GmailMessage, accountEmail: String) -> Email
    func markMessageAsRead(messageId: String, user: GIDGoogleUser) async throws
    func toggleMessageStar(messageId: String, user: GIDGoogleUser, isStarred: Bool) async throws
    func fetchAttachment(messageId: String, attachmentId: String, user: GIDGoogleUser) async throws -> String
}
```

### 🔧 ImplWiring Layer
**Purpose**: Provides dependency injection and factory patterns
```swift
// Factory for creating service instances
public class GmailAPIServiceFactory {
    public static let shared = GmailAPIServiceFactory()
    public func createGmailAPIService(dependencies: GmailAPIServiceDependencies) -> GmailAPIServiceProtocol
}

// Dependency injection container
public class GmailAPIServiceContainer {
    public static let shared = GmailAPIServiceContainer()
    public func getGmailAPIService() -> GmailAPIServiceProtocol
}
```

### ⚙️ Impl Layer
**Purpose**: Contains the actual implementation details
- `GmailAPIServiceImpl.swift`: Core API implementation
- `GmailAPIServiceHelpers.swift`: Email parsing, attachment handling, utility functions

### 🏛️ EmailPersistenceStore Framework

The Email Persistence Store provides intelligent caching and offline capabilities:

### 📋 PublicAPI Layer
**Purpose**: Defines the persistence contract with smart sync strategies
```swift
// Protocol defining all persistence operations
public protocol EmailPersistenceProtocol {
    func fetchEmails(for accountEmail: String, filter: EmailFilter?) async throws -> [Email]
    func saveEmails(_ emails: [Email], for accountEmail: String) async throws
    func determineSyncStrategy(for accountEmail: String) async -> SyncStrategy
    func hasEmails(for accountEmail: String) async -> Bool
    func getLastSyncDate(for accountEmail: String) async -> Date?
    func updateLastSyncDate(_ date: Date, for accountEmail: String) async throws
}

// Smart sync strategies for optimal performance
public enum SyncStrategy {
    case cacheOnly                    // Use cached data (recent sync)
    case fullSync                     // Fetch all emails (first time/old data)
    case incrementalSync(since: Date) // Fetch only new emails since date
}
```

### 🔧 ImplWiring Layer
**Purpose**: Factory and dependency injection for persistence
```swift
// Factory for creating persistence instances
public class EmailPersistenceFactory {
    public static let shared = EmailPersistenceFactory()
    public func createEmailPersistenceStore(dependencies: EmailPersistenceDependencies) -> EmailPersistenceProtocol
}

// Dependency injection container with Core Data stack
public class EmailPersistenceDependencies {
    public let coreDataStack: CoreDataStack
    public let configuration: PersistenceConfiguration
}
```

### ⚙️ Impl Layer
**Purpose**: Thread-safe persistence implementation with intelligent caching
- `EmailPersistenceStoreImpl.swift`: Core persistence logic with concurrent access
- `CoreDataStack.swift`: Modern Core Data stack with async/await support
- `EmailDataModel.xcdatamodeld`: Core Data model for offline storage

### 🎯 Usage Examples
```swift
// Using the shared persistence store
let persistenceStore = EmailPersistenceAPI.shared

// Smart sync strategy determination
let strategy = await persistenceStore.determineSyncStrategy(for: "user@example.com")
switch strategy {
case .cacheOnly:
    // Use cached data, skip API calls
case .fullSync:
    // Fetch all emails from API
case .incrementalSync(let since):
    // Fetch only emails since last sync
}

// Using in EmailService with dependency injection
let emailService = EmailService(
    accountManager: accountManager,
    gmailAPIService: GmailAPI.shared,
    persistenceStore: EmailPersistenceAPI.shared
)

// Real-time updates with Combine
persistenceStore.emailChanges
    .sink { event in
        // Handle email changes (added, updated, deleted)
    }
```

## 🔄 Data Flow with Smart Persistence

The application uses intelligent caching to provide optimal performance:

### 📥 Email Loading Flow
1. **User Opens App** → EmailService.refreshEmails()
2. **Smart Sync Decision** → EmailPersistenceStore.determineSyncStrategy()
   - **Recent data (< 5 min)**: `cacheOnly` - Use cached emails, skip API
   - **First time/no data**: `fullSync` - Fetch all emails from Gmail API
   - **Moderate age**: `incrementalSync` - Fetch only new emails since last sync
3. **Data Loading** → Load from persistence store
4. **API Sync** (if needed) → GmailAPIService.fetchMessages()
5. **Data Persistence** → Save new emails to EmailPersistenceStore
6. **UI Updates** → Real-time updates via Combine publishers

### 🔄 User Action Flow
1. **User Interaction** → SwiftUI Views (mark read, star, etc.)
2. **Local Update** → Immediate UI feedback
3. **Persistence Update** → Save to EmailPersistenceStore
4. **Change Broadcasting** → Combine publisher notifies subscribers
5. **UI Refresh** → Automatic updates across all views

## 🛠️ Technical Stack

- **UI Framework**: SwiftUI with MVVM pattern
- **Authentication**: Google Sign-In SDK with OAuth 2.0
- **Networking**: URLSession with async/await
- **Data Persistence**: Core Data with smart caching strategies
- **Architecture Pattern**: Clean Architecture with Dependency Injection
- **Concurrency**: Swift Concurrency (async/await) with thread-safe concurrent access
- **Reactive Programming**: Combine framework for real-time updates
- **Package Management**: Swift Package Manager

## 📋 Dependencies

```swift
dependencies: [
    .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "9.0.0")
]
```

## 🚀 Getting Started

### Prerequisites
- Xcode 15.0+
- iOS 17.5+
- Apple Developer Account (for device testing)

### Setup Instructions

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd Z-Mail
   ```

2. **Configure Google OAuth**
   - Create a project in [Google Cloud Console](https://console.cloud.google.com/)
   - Enable Gmail API
   - Create OAuth 2.0 client ID for iOS
   - Download `GoogleService-Info.plist` and add to project

3. **Configure URL Scheme**
   - Update `Info.plist` with your OAuth client ID
   - Configure URL scheme in Xcode project settings

4. **Build and Run**
   ```bash
   open EmailClient.xcodeproj
   # Build and run in Xcode
   ```

## 🧪 Testing

The modular architecture enables comprehensive testing:

```swift
// Example: Testing with mock dependencies
let mockDependencies = GmailAPIServiceDependencies(
    urlSession: MockURLSession(),
    jsonDecoder: JSONDecoder()
)
let testService = GmailAPI.create(with: mockDependencies)
```

## 🔐 Security Features

- **OAuth 2.0**: Secure authentication without storing passwords
- **Token Management**: Automatic token refresh and secure storage
- **Scoped Permissions**: Minimal required Gmail permissions (read-only)
- **Network Security**: HTTPS-only API communications

## 🎨 Design Principles

- **Clean Architecture**: Separation of concerns with clear layer boundaries
- **Dependency Injection**: Testable and maintainable code structure
- **Protocol-Oriented Programming**: Interface segregation and abstraction
- **Single Responsibility**: Each class/module has one clear purpose
- **Open/Closed Principle**: Extensible without modifying existing code

## ✨ Current Features & Architecture Highlights

- ✅ **Smart Persistence**: Intelligent caching with automatic sync strategies
- ✅ **Thread-Safe Operations**: Concurrent data access with DispatchQueue
- ✅ **Real-Time Updates**: Combine publishers for live UI updates
- ✅ **Clean Architecture**: Modular framework design with dependency injection
- ✅ **Modern Swift**: Async/await concurrency patterns throughout
- ✅ **Offline Capabilities**: Core Data integration for local storage
- ✅ **Multi-Account Support**: Seamless management of multiple Gmail accounts

## 🔮 Future Enhancements

- [ ] Email composition and sending
- [ ] Advanced search and filtering
- [ ] Push notifications
- [ ] Dark mode theme
- [ ] Attachment preview and download
- [ ] Email templates
- [ ] Multiple email provider support (Outlook, Yahoo, etc.)
- [ ] Enhanced Core Data queries and indexing

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📞 Support

For questions and support, please open an issue in the GitHub repository.

---

Built with ❤️ using SwiftUI and modern iOS development practices