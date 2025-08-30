# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Z-Mail is an iOS email client built with SwiftUI that integrates with Gmail via Google OAuth and Gmail API. The app targets Generation Z users and supports multiple Gmail accounts with a modern interface.

## Development Commands

### Building and Running
```bash
# Open project in Xcode
open EmailClient.xcodeproj

# Run build verification script
./build.sh
```

### Project Configuration
- **Target:** EmailClient
- **Bundle ID:** com.emailclient.EmailClient  
- **Minimum iOS:** 17.5
- **Swift Version:** 5.9
- **Dependencies:** GoogleSignIn-iOS (v7.0.0+), google-api-swift-client (v2.0.0+)

## Architecture

The codebase follows **MVVM + Service Layer** architecture:

### Core Components

**App Entry Point:**
- `EmailClientApp.swift` - Main app with Google Sign-In configuration
- `ContentView.swift` - Root view handling navigation

**Models (`Models/`):**
- `Email.swift` - Email data structures and GmailAccount model
- Uses `@Published` properties for reactive UI updates

**Services (`Services/`):**
- `AccountManager.swift` - OAuth authentication and multi-account management
- `EmailService.swift` - Email data management with filtering/sorting and persistence integration
- `SettingsManager.swift` - User preferences and app settings

**Views (`Views/`):**
- `EmailListView.swift` - Main inbox with swipe actions and pull-to-refresh
- `EmailDetailView.swift` - Individual email display
- `FilterView.swift` - Email filtering interface
- `SettingsView.swift` - App settings and account management

**Frameworks (`Frameworks/`):**
- `GmailAPIService/` - Gmail API integration framework (PublicAPI/ImplWiring/Impl)
- `EmailPersistenceStore/` - Smart persistence framework (PublicAPI/ImplWiring/Impl)

### Key Architecture Patterns

1. **Three-Layer Framework Pattern:** PublicAPI/ImplWiring/Impl for modular design
2. **Smart Persistence:** Intelligent sync strategies (cacheOnly/fullSync/incrementalSync)
3. **Service Layer:** Business logic separated from UI components
4. **ObservableObject Managers:** State management with `@Published` properties  
5. **OAuth Integration:** Google Sign-In SDK with automatic token refresh
6. **REST API Communication:** Gmail API integration with proper error handling
7. **Reactive Programming:** Combine publishers for real-time data updates
8. **Thread-Safe Concurrency:** Modern async/await with concurrent DispatchQueue

## Google OAuth Setup

**Configuration Files:**
- `GoogleService-Info.plist` - OAuth client configuration
- `Info.plist` - URL schemes for OAuth redirect

**OAuth Details:**
- **Scope:** `https://www.googleapis.com/auth/gmail.readonly` (read-only access)
- **Multiple Accounts:** Supported via AccountManager
- **Token Management:** Automatic refresh with persistent storage

## Development Notes

### Current Features
- Multi-account Gmail integration (read-only)
- Email list with filtering and sorting
- Swipe actions (mark read/unread, star/unstar)
- Pull-to-refresh functionality
- Modern SwiftUI interface
- **Smart Persistence Store:** Intelligent caching with automatic sync strategies
- **Real-Time Updates:** Live UI updates via Combine publishers
- **Offline Capabilities:** Core Data integration for local email storage
- **Thread-Safe Operations:** Concurrent data access patterns

### Missing Components
- No unit tests or testing infrastructure
- No email sending capabilities  
- No CI/CD configuration
- No push notifications

### Code Conventions
- SwiftUI for all UI components
- MVVM architecture with clear separation
- `@Published` properties for reactive updates
- Proper error handling with user feedback
- Swift Package Manager for dependencies

## Documentation Practices

### README Maintenance
**IMPORTANT:** Always update the README.md file when implementing new features or making architectural changes:

1. **After Feature Implementation:** Update the Features section with new capabilities
2. **After Architecture Changes:** Update the Architecture Overview and Project Structure diagrams
3. **After New Dependencies:** Update the Technical Stack and Dependencies sections
4. **After Adding New Frameworks:** Document the new framework structure and usage examples
5. **After Major Refactoring:** Update code examples and usage patterns

### Documentation Checklist
When completing any significant development work:
- [ ] Update README.md with new features/changes
- [ ] Update architecture diagrams if structure changed
- [ ] Add or update code examples for new APIs
- [ ] Update setup instructions if new dependencies were added
- [ ] Update Future Enhancements list (remove completed items, add new planned features)

This ensures the documentation stays current and helpful for future developers working on the project.