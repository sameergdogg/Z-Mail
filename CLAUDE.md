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
- `EmailService.swift` - Email data management with filtering/sorting
- `GmailAPIService.swift` - Gmail API communication and message parsing

**Views (`Views/`):**
- `EmailListView.swift` - Main inbox with swipe actions and pull-to-refresh
- `EmailDetailView.swift` - Individual email display
- `FilterView.swift` - Email filtering interface

### Key Architecture Patterns

1. **Service Layer:** Business logic separated from UI components
2. **ObservableObject Managers:** State management with `@Published` properties  
3. **OAuth Integration:** Google Sign-In SDK with automatic token refresh
4. **REST API Communication:** Gmail API integration with proper error handling

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

### Missing Components
- No unit tests or testing infrastructure
- No email sending capabilities  
- No CI/CD configuration
- No push notifications
- No offline storage

### Code Conventions
- SwiftUI for all UI components
- MVVM architecture with clear separation
- `@Published` properties for reactive updates
- Proper error handling with user feedback
- Swift Package Manager for dependencies