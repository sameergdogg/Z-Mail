# Z-Mail
**A Generation Z Email Client** 📧✨

A modern, native iOS email client built with SwiftUI, designed for Gmail integration with AI-powered email classification and daily digest summaries.

## 📱 Features

- **Multi-Account Gmail Support**: Connect and manage multiple Gmail accounts
- **AI Email Classification**: Automatically categorize emails into smart categories using Claude AI
- **Daily Digest Summaries**: AI-generated daily email summaries for quick overviews
- **Rich Email Rendering**: Toggle between plain text and rich HTML email display
- **Smart Email Management**: Mark emails as read, star/unstar, and organize with labels
- **Sender Filtering**: Filter emails by sender for focused views
- **Auto-Sync on Launch**: Automatically syncs from Gmail when the local database is empty
- **Modern Authentication**: Secure OAuth 2.0 integration with Google Sign-In

## 🏗️ Architecture Overview

Z-Mail uses **MVVM + Service Layer** architecture with flat, co-located service files for simplicity and maintainability.

### High-Level Architecture

```
┌─────────────────────────────────────────────────┐
│                  UI Layer                       │
│  SwiftUI Views (ObservableObject / @Published) │
├─────────────────────────────────────────────────┤
│                Service Layer                    │
│   EmailService, AccountService, AppDataService  │
│   ClassificationService, GmailAPIService        │
│   EmailPersistenceService, SettingsManager      │
├─────────────────────────────────────────────────┤
│                 Data Layer                      │
│     SwiftData Models, Gmail REST API            │
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
│   ├── SettingsView.swift            # App settings and account management
│   ├── ClassificationCategoriesView.swift  # AI category browser
│   ├── CategoryEmailsView.swift      # Emails within a category
│   ├── SummaryView.swift             # Daily digest summaries
│   ├── SenderListView.swift          # Sender-based filtering
│   └── ClassificationSettingsView.swift    # AI classification config
├── 🔧 Services/
│   ├── EmailService.swift            # Email data management and filtering
│   ├── AccountService.swift          # Gmail account authentication
│   ├── AppDataService.swift          # App-wide data manager (SwiftData)
│   ├── ClassificationService.swift   # AI email classification
│   ├── EmailPersistenceService.swift # SwiftData persistence layer
│   ├── GmailAPIService.swift         # Gmail REST API client
│   ├── SecureConfigurationManager.swift  # API key management
│   ├── LaunchClassificationManager.swift # Background classification on launch
│   └── SettingsManager.swift         # User preferences persistence
└── 📊 Models/
    └── Email.swift                   # Data models (Email, EmailAddress, GmailAccount)
```

## 🤖 AI Classification

Z-Mail uses Claude AI to automatically classify incoming emails into smart categories:

- Emails are classified on launch via `LaunchClassificationManager`
- Results are persisted locally via SwiftData
- The classification settings (API key, model, categories) are configurable in Settings
- API keys are stored securely via `SecureConfigurationManager`

## 📅 Daily Digest Summaries

Z-Mail generates AI-powered daily digest summaries:

- Summaries are stored as `SwiftDataDigest` records in the local SwiftData store
- Accessible via the Summary view
- Can be cleared from Settings → AI Features → Clear All Summaries

## 🛠️ Technical Stack

- **UI Framework**: SwiftUI with MVVM pattern
- **Authentication**: Google Sign-In SDK with OAuth 2.0
- **Networking**: URLSession with async/await
- **Data Persistence**: SwiftData for local email and digest storage
- **AI Integration**: Claude API for email classification and summarization
- **Architecture Pattern**: MVVM + flat Service Layer
- **Concurrency**: Swift Concurrency (async/await)
- **Reactive Programming**: Combine framework for real-time UI updates
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

4. **Configure AI Features (Optional)**
   - Open Settings → AI Features → Classification Settings
   - Enter your Anthropic API key to enable email classification and summaries

5. **Build and Run**
   ```bash
   open EmailClient.xcodeproj
   # Build and run in Xcode
   ```

## 🔐 Security Features

- **OAuth 2.0**: Secure authentication without storing passwords
- **Token Management**: Automatic token refresh and secure storage
- **Scoped Permissions**: Minimal required Gmail permissions (read-only)
- **Network Security**: HTTPS-only API communications
- **Secure Key Storage**: API keys stored via Keychain through `SecureConfigurationManager`

## ✨ Current Features & Architecture Highlights

- ✅ **AI Email Classification**: Claude-powered categorization on launch
- ✅ **Daily Digest Summaries**: AI-generated summaries with local persistence
- ✅ **Multi-Account Support**: Seamless management of multiple Gmail accounts
- ✅ **Sender Filtering**: Filter inbox by sender
- ✅ **Auto-Sync**: Automatic Gmail sync when local DB is empty
- ✅ **SwiftData Persistence**: Modern local storage for emails and digests
- ✅ **Real-Time Updates**: Combine publishers for live UI updates
- ✅ **Flat Service Architecture**: Simplified, maintainable service layer

## 🔮 Future Enhancements

- [ ] Email composition and sending
- [ ] Advanced search and filtering
- [ ] Push notifications
- [ ] Attachment preview and download
- [ ] Multiple email provider support (Outlook, Yahoo, etc.)

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
