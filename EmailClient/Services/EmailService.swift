import Foundation
import SwiftUI
import GoogleSignIn
import Combine

class EmailService: ObservableObject {
    @Published var emails: [Email] = []
    @Published var filteredEmails: [Email] = []
    @Published var isLoading = false
    @Published var currentFilter: EmailFilter = .all
    @Published var sortOrder: SortOrder = .dateDescending
    @Published var errorMessage: String?
    
    private var accountManager: AccountManagerProtocol
    private let gmailAPIService: GmailAPIServiceProtocol
    private let persistenceStore: EmailPersistenceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(
        accountManager: AccountManagerProtocol,
        gmailAPIService: GmailAPIServiceProtocol = GmailAPI.shared,
        persistenceStore: EmailPersistenceProtocol = EmailPersistenceAPI.shared
    ) {
        self.accountManager = accountManager
        self.gmailAPIService = gmailAPIService
        self.persistenceStore = persistenceStore
        
        setupPersistenceSubscription()
    }
    
    func updateAccountManager(_ newAccountManager: AccountManagerProtocol) {
        self.accountManager = newAccountManager
    }
    
    /// Load emails on app launch - only reads from persistence store, no server calls
    func loadEmailsOnLaunch() async {
        print("🚀 EmailService.loadEmailsOnLaunch() started - persistence only")
        
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                self.isLoading = false
                print("🚀 EmailService.loadEmailsOnLaunch() completed")
            }
        }
        
        print("🚀 Accounts count: \(accountManager.accounts.count)")
        for account in accountManager.accounts {
            print("🚀 Account: \(account.email)")
        }
        
        await loadEmailsFromPersistence()
        applyCurrentFilter()
        
        print("🚀 Final email count: \(emails.count), filtered: \(filteredEmails.count)")
    }
    
    /// Refresh emails from server - used for pull-to-refresh
    func refreshEmails() async {
        print("🔄 EmailService.refreshEmails() started - server sync")
        
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        defer {
            Task { @MainActor in
                self.isLoading = false
                print("🔄 EmailService.refreshEmails() completed")
            }
        }
        
        print("🔄 Accounts count: \(accountManager.accounts.count)")
        for account in accountManager.accounts {
            print("🔄 Account: \(account.email)")
        }
        
        await forceSyncFromServer()
        await loadEmailsFromPersistence()
        applyCurrentFilter()
        
        print("🔄 Final email count: \(emails.count), filtered: \(filteredEmails.count)")
    }
    
    @Published var authenticationErrors: [String: EmailServiceError] = [:]
    
    private func fetchEmailsFromAllAccounts() async {
        var allEmails: [Email] = []
        var hasAuthErrors = false
        
        await MainActor.run {
            self.errorMessage = nil
            self.authenticationErrors.removeAll()
        }
        
        for account in accountManager.accounts {
            do {
                let accountEmails = try await fetchEmailsForAccount(account)
                allEmails.append(contentsOf: accountEmails)
            } catch let error as EmailServiceError {
                await MainActor.run {
                    if error.isAuthenticationError {
                        self.authenticationErrors[account.email] = error
                        hasAuthErrors = true
                    } else {
                        self.errorMessage = error.errorDescription
                    }
                }
                print("Error fetching emails for \(account.email): \(error)")
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to fetch emails for \(account.email): \(error.localizedDescription)"
                }
                print("Error fetching emails for \(account.email): \(error)")
            }
        }
        
        await MainActor.run {
            self.emails = allEmails.sorted { email1, email2 in
                switch self.sortOrder {
                case .dateAscending:
                    return email1.date < email2.date
                case .dateDescending:
                    return email1.date > email2.date
                case .senderAscending:
                    return email1.sender.displayName < email2.sender.displayName
                case .senderDescending:
                    return email1.sender.displayName > email2.sender.displayName
                }
            }
            
            // If we have authentication errors and no other emails, show auth error message
            if allEmails.isEmpty && hasAuthErrors {
                let authErrorAccounts = Array(self.authenticationErrors.keys)
                if authErrorAccounts.count == 1 {
                    self.errorMessage = self.authenticationErrors[authErrorAccounts.first!]?.errorDescription
                } else {
                    self.errorMessage = "Authentication expired for multiple accounts. Please sign in again."
                }
            }
        }
    }
    
    private func fetchEmailsForAccount(_ account: GmailAccount) async throws -> [Email] {
        print("📧 fetchEmailsForAccount() started for \(account.email)")
        
        // Check if account requires re-authentication
        print("📧 Checking if account requires re-authentication...")
        if accountManager.requiresReauthentication(for: account) {
            print("❌ Account \(account.email) requires re-authentication")
            throw EmailServiceError.reauthenticationRequired(account.email)
        }
        print("✅ Account authentication check passed")
        
        print("📧 Getting user for account...")
        guard let user = accountManager.getUserForAccount(account) else {
            print("❌ No signed-in user found for account \(account.email)")
            throw EmailServiceError.noSignedInUser(account.email)
        }
        print("✅ Found signed-in user for \(account.email)")
        
        do {
            print("📧 Validating and refreshing token for user...")
            // Use the new validation method that handles re-authentication gracefully
            let validatedUser = try await accountManager.validateAndRefreshTokenForUser(user)
            print("✅ Token validation completed")
            
            print("📧 Fetching messages from Gmail API (max 50)...")
            let gmailMessages = try await gmailAPIService.fetchMessages(for: validatedUser, maxResults: 50)
            print("✅ Fetched \(gmailMessages.count) messages from Gmail API")
            
            print("📧 Converting Gmail messages to Email objects...")
            let emails = gmailMessages.map { gmailMessage in
                gmailAPIService.convertGmailMessageToEmail(gmailMessage, accountEmail: account.email)
            }
            print("✅ Converted \(emails.count) messages to Email objects")
            
            return emails
            
        } catch AccountError.reauthenticationRequired {
            throw EmailServiceError.reauthenticationRequired(account.email)
        } catch AccountError.tokenRefreshFailed {
            throw EmailServiceError.authenticationFailed(account.email)
        } catch AccountError.networkError {
            throw EmailServiceError.networkError
        } catch {
            // Handle Gmail API specific errors
            if let errorMessage = parseGmailAPIError(error) {
                throw EmailServiceError.gmailAPIError(errorMessage)
            } else {
                throw EmailServiceError.fetchFailed(error.localizedDescription)
            }
        }
    }
    
    private func parseGmailAPIError(_ error: Error) -> String? {
        let errorDescription = error.localizedDescription.lowercased()
        
        if errorDescription.contains("401") || errorDescription.contains("unauthorized") {
            return "Authentication expired. Please sign in again."
        } else if errorDescription.contains("403") || errorDescription.contains("forbidden") {
            return "Access denied. Please check your account permissions."
        } else if errorDescription.contains("404") || errorDescription.contains("not found") {
            return "Gmail service temporarily unavailable."
        } else if errorDescription.contains("429") || errorDescription.contains("quota") {
            return "Gmail API quota exceeded. Please try again later."
        } else if errorDescription.contains("network") || errorDescription.contains("connection") {
            return "Network connection error. Please check your internet connection."
        }
        
        return nil
    }
    
    func applyFilter(_ filter: EmailFilter) {
        currentFilter = filter
        applyCurrentFilter()
    }
    
    func applySortOrder(_ order: SortOrder) {
        sortOrder = order
        DispatchQueue.main.async {
            self.emails = self.emails.sorted { email1, email2 in
                switch order {
                case .dateAscending:
                    return email1.date < email2.date
                case .dateDescending:
                    return email1.date > email2.date
                case .senderAscending:
                    return email1.sender.displayName < email2.sender.displayName
                case .senderDescending:
                    return email1.sender.displayName > email2.sender.displayName
                }
            }
            self.applyCurrentFilter()
        }
    }
    
    private func applyCurrentFilter() {
        DispatchQueue.main.async {
            switch self.currentFilter {
            case .all:
                self.filteredEmails = self.emails
            case .unread:
                self.filteredEmails = self.emails.filter { !$0.isRead }
            case .starred:
                self.filteredEmails = self.emails.filter { $0.isStarred }
            case .account(let email):
                self.filteredEmails = self.emails.filter { $0.accountEmail == email }
            case .label(let label):
                self.filteredEmails = self.emails.filter { $0.labels.contains(label) }
            }
        }
    }
    
    func markAsRead(_ email: Email) {
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            let updatedEmail = Email(
                id: email.id,
                subject: email.subject,
                sender: email.sender,
                recipients: email.recipients,
                body: email.body,
                date: email.date,
                isRead: true,
                isStarred: email.isStarred,
                labels: email.labels,
                accountEmail: email.accountEmail,
                threadId: email.threadId
            )
            emails[index] = updatedEmail
            
            // Update persistence store
            Task {
                try? await persistenceStore.updateEmail(updatedEmail)
            }
            
            applyCurrentFilter()
        }
    }
    
    func toggleStar(_ email: Email) {
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            let updatedEmail = Email(
                id: email.id,
                subject: email.subject,
                sender: email.sender,
                recipients: email.recipients,
                body: email.body,
                date: email.date,
                isRead: email.isRead,
                isStarred: !email.isStarred,
                labels: email.labels,
                accountEmail: email.accountEmail,
                threadId: email.threadId
            )
            emails[index] = updatedEmail
            
            // Update persistence store
            Task {
                try? await persistenceStore.updateEmail(updatedEmail)
            }
            
            applyCurrentFilter()
        }
    }
    
    // MARK: - Persistence Integration
    
    private func setupPersistenceSubscription() {
        persistenceStore.emailChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handlePersistenceEvent(event)
            }
            .store(in: &cancellables)
    }
    
    private func handlePersistenceEvent(_ event: EmailChangeEvent) {
        switch event {
        case .emailsAdded(let newEmails):
            // Merge new emails with existing ones, avoiding duplicates
            let existingIds = Set(emails.map { $0.id })
            let uniqueNewEmails = newEmails.filter { !existingIds.contains($0.id) }
            emails.append(contentsOf: uniqueNewEmails)
            sortEmails()
            applyCurrentFilter()
            
        case .emailUpdated(let updatedEmail):
            if let index = emails.firstIndex(where: { $0.id == updatedEmail.id }) {
                emails[index] = updatedEmail
                applyCurrentFilter()
            }
            
        case .emailDeleted(let emailId):
            emails.removeAll { $0.id == emailId }
            applyCurrentFilter()
            
        case .accountDataCleared(let accountEmail):
            emails.removeAll { $0.accountEmail == accountEmail }
            applyCurrentFilter()
        }
    }
    
    /// Force sync from server - always fetches from Gmail API regardless of cache state
    private func forceSyncFromServer() async {
        print("🌐 forceSyncFromServer() started - bypassing cache")
        
        if accountManager.accounts.isEmpty {
            print("❌ No accounts available for sync")
            await MainActor.run {
                self.errorMessage = "No Gmail accounts connected. Please add an account to continue."
            }
            return
        }
        
        for account in accountManager.accounts {
            print("🌐 Force syncing from server for account: \(account.email)")
            do {
                // Always perform full sync from server
                await performFullSync(for: account)
                
                // Update last sync date
                try await persistenceStore.updateLastSyncDate(Date(), for: account.email)
                
            } catch {
                await MainActor.run {
                    self.errorMessage = "Force sync failed for \(account.email): \(error.localizedDescription)"
                }
                print("Force sync failed for \(account.email): \(error)")
            }
        }
    }
    
    private func intelligentSync() async {
        print("🔄 intelligentSync() started with \(accountManager.accounts.count) accounts")
        
        if accountManager.accounts.isEmpty {
            print("❌ No accounts available for sync")
            await MainActor.run {
                self.errorMessage = "No Gmail accounts connected. Please add an account to continue."
            }
            return
        }
        
        for account in accountManager.accounts {
            print("🔄 Processing account: \(account.email)")
            do {
                let strategy = await persistenceStore.determineSyncStrategy(for: account.email)
                print("📊 Sync strategy for \(account.email): \(strategy)")
                
                switch strategy {
                case .cacheOnly:
                    print("💾 Using cache-only for \(account.email)")
                    continue // Skip API calls, use cached data
                    
                case .fullSync:
                    print("🔄 Performing full sync for \(account.email)")
                    print("🔄 About to call performFullSync...")
                    await performFullSync(for: account)
                    print("🔄 performFullSync returned")
                    
                case .incrementalSync(let since):
                    print("📈 Performing incremental sync for \(account.email) since \(since)")
                    await performIncrementalSync(for: account, since: since)
                }
                
                // Update last sync date
                try await persistenceStore.updateLastSyncDate(Date(), for: account.email)
                
            } catch {
                await MainActor.run {
                    self.errorMessage = "Sync failed for \(account.email): \(error.localizedDescription)"
                }
                print("Sync failed for \(account.email): \(error)")
            }
        }
    }
    
    private func performFullSync(for account: GmailAccount) async {
        print("🔄 performFullSync() started for \(account.email)")
        
        do {
            print("🔄 Fetching emails from Gmail API for \(account.email)")
            let accountEmails = try await fetchEmailsForAccount(account)
            print("✅ Fetched \(accountEmails.count) emails from Gmail API")
            
            print("🔄 Saving \(accountEmails.count) emails to persistence store")
            try await persistenceStore.saveEmails(accountEmails, for: account.email)
            print("✅ Successfully saved emails to persistence store")
            
        } catch {
            print("❌ performFullSync() failed for \(account.email): \(error)")
            
            await MainActor.run {
                if let error = error as? EmailServiceError {
                    if error.isAuthenticationError {
                        print("❌ Authentication error for \(account.email)")
                        self.authenticationErrors[account.email] = error
                    } else {
                        print("❌ API error for \(account.email): \(error.errorDescription ?? "unknown")")
                        self.errorMessage = error.errorDescription
                    }
                } else {
                    print("❌ Generic error for \(account.email): \(error.localizedDescription)")
                    self.errorMessage = "Failed to sync \(account.email): \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func performIncrementalSync(for account: GmailAccount, since date: Date) async {
        // For now, perform a full sync. In a production app, you would implement
        // incremental fetching based on the date
        await performFullSync(for: account)
    }
    
    private func loadEmailsFromPersistence() async {
        print("💾 loadEmailsFromPersistence() started")
        var allEmails: [Email] = []
        
        for account in accountManager.accounts {
            do {
                print("💾 Loading emails for \(account.email) from persistence")
                let accountEmails = try await persistenceStore.fetchEmails(for: account.email, filter: nil)
                print("💾 Loaded \(accountEmails.count) emails for \(account.email)")
                allEmails.append(contentsOf: accountEmails)
            } catch {
                print("❌ Failed to load emails for \(account.email) from persistence: \(error)")
            }
        }
        
        print("💾 Total emails loaded from persistence: \(allEmails.count)")
        
        await MainActor.run {
            self.emails = allEmails
            self.sortEmails()
        }
    }
    
    private func sortEmails() {
        emails.sort { email1, email2 in
            switch sortOrder {
            case .dateAscending:
                return email1.date < email2.date
            case .dateDescending:
                return email1.date > email2.date
            case .senderAscending:
                return email1.sender.displayName < email2.sender.displayName
            case .senderDescending:
                return email1.sender.displayName > email2.sender.displayName
            }
        }
    }
    
    // MARK: - Test Data (Temporary for debugging)
    
    private func createTestEmails(for accountEmail: String) -> [Email] {
        return [
            Email(
                id: "test-1",
                subject: "🧪 Test Email 1 - Welcome to Z-Mail!",
                sender: EmailAddress(name: "Demo Sender", email: "demo@example.com"),
                recipients: [EmailAddress(name: "You", email: accountEmail)],
                body: "This is a test email to verify the persistence store is working correctly.",
                date: Date().addingTimeInterval(-3600), // 1 hour ago
                isRead: false,
                isStarred: false,
                labels: ["INBOX", "IMPORTANT"],
                accountEmail: accountEmail,
                threadId: "thread-1"
            ),
            Email(
                id: "test-2",
                subject: "📧 Test Email 2 - Persistence Store Works!",
                sender: EmailAddress(name: "Test User", email: "test@example.com"),
                recipients: [EmailAddress(name: "You", email: accountEmail)],
                body: "Congratulations! The smart persistence store is successfully saving and loading emails.",
                date: Date().addingTimeInterval(-7200), // 2 hours ago
                isRead: true,
                isStarred: true,
                labels: ["INBOX"],
                accountEmail: accountEmail,
                threadId: "thread-2"
            ),
            Email(
                id: "test-3",
                subject: "🚀 Test Email 3 - Smart Sync Strategy Active",
                sender: EmailAddress(name: "Z-Mail System", email: "system@zmail.com"),
                recipients: [EmailAddress(name: "You", email: accountEmail)],
                body: "Your intelligent sync system is working! This email was created as a fallback while debugging Gmail API connectivity.",
                date: Date().addingTimeInterval(-10800), // 3 hours ago
                isRead: false,
                isStarred: false,
                labels: ["INBOX", "SYSTEM"],
                accountEmail: accountEmail,
                threadId: "thread-3"
            )
        ]
    }
    
}

enum EmailServiceError: Error, LocalizedError {
    case noSignedInUser(String)
    case fetchFailed(String)
    case reauthenticationRequired(String)
    case authenticationFailed(String)
    case networkError
    case gmailAPIError(String)
    
    var errorDescription: String? {
        switch self {
        case .noSignedInUser(let email):
            return "No signed-in user found for \(email). Please sign in again."
        case .fetchFailed(let message):
            return "Failed to fetch emails: \(message)"
        case .reauthenticationRequired(let email):
            return "Authentication expired for \(email). Please sign in again."
        case .authenticationFailed(let email):
            return "Authentication failed for \(email). Please try signing in again."
        case .networkError:
            return "Network connection error. Please check your internet connection and try again."
        case .gmailAPIError(let message):
            return message
        }
    }
    
    var isAuthenticationError: Bool {
        switch self {
        case .reauthenticationRequired, .authenticationFailed, .noSignedInUser:
            return true
        case .fetchFailed, .networkError, .gmailAPIError:
            return false
        }
    }
}

public enum EmailFilter {
    case all
    case unread
    case starred
    case account(String)
    case label(String)
}

enum SortOrder {
    case dateAscending
    case dateDescending
    case senderAscending
    case senderDescending
}