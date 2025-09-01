import Foundation
import SwiftUI
import GoogleSignIn
import Combine

/// Implementation of the Email Service protocol
/// Follows MVVM + Service Layer architecture from CLAUDE.md
internal class EmailServiceImpl: EmailServiceProtocol {
    
    // MARK: - Published Properties
    
    @Published public var emails: [Email] = []
    @Published public var filteredEmails: [Email] = []
    @Published public var isLoading = false
    @Published public var currentFilter: EmailFilter = .all
    @Published public var sortOrder: SortOrder = .dateDescending
    @Published public var errorMessage: String?
    @Published public var authenticationErrors: [String: EmailServiceError] = [:]
    @Published public var syncProgress: SyncProgress = .idle
    
    // MARK: - Private Properties
    
    private let dependencies: EmailServiceDependencies
    private var accountManager: AccountManagerProtocol
    private let gmailAPIService: GmailAPIServiceProtocol
    private let persistenceStore: EmailPersistenceProtocol
    private let configuration: EmailServiceConfiguration
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(dependencies: EmailServiceDependencies) {
        self.dependencies = dependencies
        self.accountManager = dependencies.accountManager
        self.gmailAPIService = dependencies.gmailAPIService
        self.persistenceStore = dependencies.persistenceStore
        self.configuration = dependencies.configuration
        
        setupPersistenceSubscription()
    }
    
    // MARK: - Public Methods
    
    /// Load emails on app launch using intelligent sync strategy
    /// This follows the smart persistence pattern from CLAUDE.md
    public func loadEmailsOnLaunch() async {
        print("🚀 EmailService.loadEmailsOnLaunch() started - intelligent sync")
        
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
        
        // First load from persistence to show cached data immediately
        await loadEmailsFromPersistence()
        applyCurrentFilter()
        
        // Then perform intelligent sync based on cache state
        await intelligentSync()
        await loadEmailsFromPersistence() // Reload after sync
        applyCurrentFilter()
        
        print("🚀 Final email count: \(emails.count), filtered: \(filteredEmails.count)")
    }
    
    /// Refresh emails from server - forces full sync from Gmail API
    /// Used for pull-to-refresh functionality
    public func refreshEmails() async {
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
    
    public func applyFilter(_ filter: EmailFilter) {
        currentFilter = filter
        applyCurrentFilter()
    }
    
    public func applySortOrder(_ order: SortOrder) {
        sortOrder = order
        DispatchQueue.main.async {
            self.sortEmails()
            self.applyCurrentFilter()
        }
    }
    
    /// Marks an email as read in both local storage and Gmail API
    /// Follows the service layer pattern with proper error handling
    public func markAsRead(_ email: Email) async {
        await updateEmailStatus(email, isRead: true)
    }
    
    /// Marks an email as unread in both local storage and Gmail API
    public func markAsUnread(_ email: Email) async {
        await updateEmailStatus(email, isRead: false)
    }
    
    /// Toggles star status for an email in both local storage and Gmail API
    /// Follows the service layer pattern with proper error handling
    public func toggleStar(_ email: Email) async {
        let newStarredState = !email.isStarred
        
        // Update local state immediately for responsive UI
        await MainActor.run {
            if let index = emails.firstIndex(where: { $0.id == email.id }) {
                let updatedEmail = Email(
                    id: email.id,
                    subject: email.subject,
                    sender: email.sender,
                    recipients: email.recipients,
                    body: email.body,
                    htmlBody: email.htmlBody,
                    date: email.date,
                    isRead: email.isRead,
                    isStarred: newStarredState,
                    labels: email.labels,
                    accountEmail: email.accountEmail,
                    threadId: email.threadId,
                    attachments: email.attachments,
                    isHTMLContent: email.isHTMLContent
                )
                emails[index] = updatedEmail
                applyCurrentFilter()
            }
        }
        
        // Update persistence store
        do {
            let updatedEmail = await MainActor.run {
                emails.first { $0.id == email.id }
            }
            if let updatedEmail = updatedEmail {
                try await persistenceStore.updateEmail(updatedEmail)
            }
        } catch {
            print("Failed to update email in persistence store: \(error)")
        }
        
        // Update Gmail API (if possible)
        if configuration.enableGmailAPISync {
            await syncEmailStarWithGmailAPI(email, isStarred: newStarredState)
        }
    }
    
    /// Updates the account manager and refreshes email data
    /// This follows the service layer pattern for proper dependency management
    public func updateAccountManager(_ newAccountManager: AccountManagerProtocol) {
        self.accountManager = newAccountManager
        
        // Cancel existing subscriptions and setup new ones
        cancellables.removeAll()
        setupPersistenceSubscription()
        
        // Trigger a refresh with the new account manager
        Task {
            await loadEmailsOnLaunch()
        }
    }
    
    /// Gets unique senders from all emails in the persistence store
    /// - Returns: Array of unique email senders sorted by sender name
    public func getUniqueSenders() -> [EmailSender] {
        let senderGroups = Dictionary(grouping: emails) { email in
            email.sender.email
        }
        
        let uniqueSenders = senderGroups.map { (senderEmail, emails) in
            let firstEmail = emails.first!
            return EmailSender(
                email: senderEmail,
                name: firstEmail.sender.name,
                emailCount: emails.count
            )
        }
        
        return uniqueSenders.sorted { sender1, sender2 in
            sender1.displayName.localizedCaseInsensitiveCompare(sender2.displayName) == .orderedAscending
        }
    }
    
    /// Gets emails from a specific sender
    /// - Parameter sender: The sender to filter by
    /// - Returns: Array of emails from the specified sender
    public func getEmailsFromSender(_ sender: EmailSender) -> [Email] {
        return emails.filter { email in
            email.sender.email == sender.email
        }.sorted { email1, email2 in
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
    
    // MARK: - Private Methods
    
    /// Updates email read status with proper service layer handling
    private func updateEmailStatus(_ email: Email, isRead: Bool) async {
        // Update local state immediately for responsive UI
        await MainActor.run {
            if let index = emails.firstIndex(where: { $0.id == email.id }) {
                let updatedEmail = Email(
                    id: email.id,
                    subject: email.subject,
                    sender: email.sender,
                    recipients: email.recipients,
                    body: email.body,
                    htmlBody: email.htmlBody,
                    date: email.date,
                    isRead: isRead,
                    isStarred: email.isStarred,
                    labels: email.labels,
                    accountEmail: email.accountEmail,
                    threadId: email.threadId,
                    attachments: email.attachments,
                    isHTMLContent: email.isHTMLContent
                )
                emails[index] = updatedEmail
                applyCurrentFilter()
            }
        }
        
        // Update persistence store
        do {
            let updatedEmail = await MainActor.run {
                emails.first { $0.id == email.id }
            }
            if let updatedEmail = updatedEmail {
                try await persistenceStore.updateEmail(updatedEmail)
            }
        } catch {
            print("Failed to update email in persistence store: \(error)")
        }
        
        // Update Gmail API (if possible)
        if configuration.enableGmailAPISync {
            await syncEmailStatusWithGmailAPI(email, isRead: isRead)
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
    
    // MARK: - Gmail API Sync Methods
    
    /// Syncs email read status with Gmail API
    /// Follows service layer pattern with graceful error handling
    private func syncEmailStatusWithGmailAPI(_ email: Email, isRead: Bool) async {
        guard let account = accountManager.accounts.first(where: { $0.email == email.accountEmail }),
              let user = accountManager.getUserForAccount(account) else {
            print("❌ No account or user found for syncing email status")
            return
        }
        
        do {
            let validatedUser = try await accountManager.validateAndRefreshTokenForUser(user)
            
            if isRead {
                try await gmailAPIService.markMessageAsRead(messageId: email.id, user: validatedUser)
            }
            // Note: Gmail API doesn't have a "mark as unread" operation
            // This is a limitation of Gmail's API
            
            print("✅ Successfully synced email status with Gmail API")
        } catch {
            print("⚠️ Failed to sync email status with Gmail API: \(error)")
            // Don't show error to user for background sync failures
            // The local state change is still valid
        }
    }
    
    /// Syncs email star status with Gmail API
    /// Follows service layer pattern with graceful error handling
    private func syncEmailStarWithGmailAPI(_ email: Email, isStarred: Bool) async {
        guard let account = accountManager.accounts.first(where: { $0.email == email.accountEmail }),
              let user = accountManager.getUserForAccount(account) else {
            print("❌ No account or user found for syncing email star")
            return
        }
        
        do {
            let validatedUser = try await accountManager.validateAndRefreshTokenForUser(user)
            try await gmailAPIService.toggleMessageStar(messageId: email.id, user: validatedUser, isStarred: isStarred)
            print("✅ Successfully synced email star with Gmail API")
        } catch {
            print("⚠️ Failed to sync email star with Gmail API: \(error)")
            // Don't show error to user for background sync failures
            // The local state change is still valid
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
                    await performFullSync(for: account)
                    
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
        
        // Update sync progress
        await MainActor.run {
            self.syncProgress = .syncing(accountEmail: account.email, progress: 0.0)
        }
        
        do {
            print("🔄 Fetching emails from Gmail API for \(account.email)")
            
            // Update progress
            await MainActor.run {
                self.syncProgress = .syncing(accountEmail: account.email, progress: 0.3)
            }
            
            let accountEmails = try await fetchEmailsForAccount(account)
            print("✅ Fetched \(accountEmails.count) emails from Gmail API")
            
            // Update progress
            await MainActor.run {
                self.syncProgress = .syncing(accountEmail: account.email, progress: 0.7)
            }
            
            print("🔄 Saving \(accountEmails.count) emails to persistence store")
            try await persistenceStore.saveEmails(accountEmails, for: account.email)
            print("✅ Successfully saved emails to persistence store")
            
            // Complete sync
            await MainActor.run {
                self.syncProgress = .completed
            }
            
        } catch {
            print("❌ performFullSync() failed for \(account.email): \(error)")
            
            await MainActor.run {
                self.syncProgress = .failed(error: error.localizedDescription)
                
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
            
            print("📧 Fetching messages from Gmail API (max \(configuration.maxEmailsPerSync))...")
            let gmailMessages = try await gmailAPIService.fetchMessages(for: validatedUser, maxResults: configuration.maxEmailsPerSync)
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
}
