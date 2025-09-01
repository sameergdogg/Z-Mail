import Foundation
import SwiftData
import Combine

/// SwiftData-based implementation of Email Persistence Protocol
internal class SwiftDataEmailPersistenceStoreImpl: EmailPersistenceProtocol {
    
    // MARK: - Properties
    
    private let dependencies: EmailPersistenceDependencies
    private let configuration: PersistenceConfiguration
    private let swiftDataContainer: SwiftDataContainer
    private let modelContext: ModelContext
    
    private let emailChangesSubject = PassthroughSubject<EmailChangeEvent, Never>()
    
    public var emailChanges: AnyPublisher<EmailChangeEvent, Never> {
        emailChangesSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    internal init(dependencies: EmailPersistenceDependencies) throws {
        self.dependencies = dependencies
        self.configuration = dependencies.configuration
        
        print("📦 Initializing SwiftData EmailPersistenceStore...")
        self.swiftDataContainer = try SwiftDataContainer(configuration: configuration)
        self.modelContext = swiftDataContainer.modelContext
        
        setupAutoCleanup()
    }
    
    // MARK: - Public API Implementation
    
    public func fetchEmails(for accountEmail: String, filter: EmailFilter?) async throws -> [Email] {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                print("📦 Fetching emails for \(accountEmail) with filter: \(filter?.description ?? "none")")
                
                let persistedEmails = try fetchEmailsFromSwiftData(
                    for: accountEmail,
                    filter: filter,
                    limit: configuration.maxEmailsPerAccount
                )
                
                let domainEmails = persistedEmails.map { $0.toDomainModel() }
                print("📦 Fetched \(domainEmails.count) emails from SwiftData")
                
                continuation.resume(returning: domainEmails)
            } catch {
                print("❌ Failed to fetch emails: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    public func saveEmails(_ emails: [Email], for accountEmail: String) async throws {
        guard !emails.isEmpty else { return }
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                print("📦 Saving \(emails.count) emails for \(accountEmail)")
                
                // Get or create account
                let account = try getOrCreateAccountInSwiftData(
                    email: accountEmail,
                    displayName: nil
                )
                
                // Get existing email IDs to avoid duplicates
                let existingEmails = try fetchEmailsFromSwiftData(
                    for: accountEmail,
                    filter: nil,
                    limit: Int.max
                )
                let existingIds = Set(existingEmails.map { $0.id })
                
                // Filter out duplicates and create new persisted emails
                var newEmailsCount = 0
                for email in emails {
                    if !existingIds.contains(email.id) {
                        let persistedEmail = email.toSwiftDataModel(account: account)
                        modelContext.insert(persistedEmail)
                        // account.emails.append(persistedEmail) // Relationship commented out
                        newEmailsCount += 1
                    }
                }
                
                // Keep only the most recent emails up to the limit
                // Note: Email limit enforcement disabled due to commented relationship
                // TODO: Implement proper email limit management without relationships
                
                // Update account
                account.emailCount += newEmailsCount // Manual count update
                account.updatedAt = Date()
                
                try saveSwiftDataContext()
                
                print("📦 Successfully saved \(newEmailsCount) new emails (manual count updated)")
                
                // Emit change event for new emails only
                if newEmailsCount > 0 {
                    let newEmails = emails.filter { !existingIds.contains($0.id) }
                    Task { @MainActor in
                        self.emailChangesSubject.send(.emailsAdded(newEmails))
                    }
                }
                
                continuation.resume()
            } catch {
                print("❌ Failed to save emails: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    public func updateEmail(_ email: Email) async throws {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                print("📦 Updating email: \(email.id)")
                
                let predicate = #Predicate<SwiftDataEmail> { persistedEmail in
                    persistedEmail.id == email.id
                }
                let descriptor = FetchDescriptor<SwiftDataEmail>(predicate: predicate)
                
                if let persistedEmail = try modelContext.fetch(descriptor).first {
                    persistedEmail.updateFromDomainModel(email)
                    try saveSwiftDataContext()
                    
                    // Emit change event
                    Task { @MainActor in
                        self.emailChangesSubject.send(.emailUpdated(email))
                    }
                    
                    print("✅ Successfully updated email: \(email.id)")
                } else {
                    print("⚠️ Email not found for update: \(email.id)")
                }
                
                continuation.resume()
            } catch {
                print("❌ Failed to update email: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    public func deleteEmails(for accountEmail: String) async throws {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                print("📦 Deleting all emails for \(accountEmail)")
                
                try deleteEmailsFromSwiftData(for: accountEmail)
                
                // Emit change event
                Task { @MainActor in
                    self.emailChangesSubject.send(.accountDataCleared(accountEmail))
                }
                
                print("✅ Successfully deleted all emails for \(accountEmail)")
                continuation.resume()
            } catch {
                print("❌ Failed to delete emails: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    public func deleteEmail(with emailId: String) async throws {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                print("📦 Deleting email: \(emailId)")
                
                let deleted = try deleteEmailFromSwiftData(with: emailId)
                
                if deleted {
                    // Emit change event
                    Task { @MainActor in
                        self.emailChangesSubject.send(.emailDeleted(emailId))
                    }
                    print("✅ Successfully deleted email: \(emailId)")
                } else {
                    print("⚠️ Email not found for deletion: \(emailId)")
                }
                
                continuation.resume()
            } catch {
                print("❌ Failed to delete email: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    public func hasEmails(for accountEmail: String) async -> Bool {
        do {
            let emails = try fetchEmailsFromSwiftData(for: accountEmail, filter: nil, limit: 1)
            return !emails.isEmpty
        } catch {
            print("❌ Failed to check if account has emails: \(error)")
            return false
        }
    }
    
    public func getLastSyncDate(for accountEmail: String) async -> Date? {
        do {
            let account = try fetchAccountFromSwiftData(email: accountEmail)
            return account?.lastSyncDate
        } catch {
            print("❌ Failed to get last sync date: \(error)")
            return nil
        }
    }
    
    public func updateLastSyncDate(_ date: Date, for accountEmail: String) async throws {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try updateLastSyncDateInSwiftData(date, for: accountEmail)
                continuation.resume()
            } catch {
                print("❌ Failed to update last sync date: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    public func getEmailCount(for accountEmail: String) async -> Int {
        do {
            let account = try fetchAccountFromSwiftData(email: accountEmail)
            return account?.emailCount ?? 0
        } catch {
            print("❌ Failed to get email count: \(error)")
            return 0
        }
    }
    
    public func determineSyncStrategy(for accountEmail: String) async -> SyncStrategy {
        let hasEmails = await self.hasEmails(for: accountEmail)
        let lastSyncDate = await getLastSyncDate(for: accountEmail)
        
        // First time sync or no previous data
        guard hasEmails, let syncDate = lastSyncDate else {
            return .fullSync
        }
        
        // Check if sync is recent enough for cache-only mode
        let timeSinceLastSync = Date().timeIntervalSince(syncDate)
        let cacheThreshold: TimeInterval = 5 * 60 // 5 minutes
        
        if timeSinceLastSync < cacheThreshold {
            return .cacheOnly
        }
        
        // Incremental sync for existing data
        return .incrementalSync(since: syncDate)
    }
    
    public func clearAllData() async throws {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try clearAllDataFromSwiftData()
                print("✅ Successfully cleared all data")
                continuation.resume()
            } catch {
                print("❌ Failed to clear all data: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Private Helper Methods

private extension SwiftDataEmailPersistenceStoreImpl {
    
    func setupAutoCleanup() {
        guard configuration.enableAutoCleanup else { 
            print("📦 Auto cleanup disabled")
            return 
        }
        
        print("📦 Setting up auto cleanup (every 24 hours)")
        // Schedule periodic cleanup
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 24 * 60 * 60 * 1_000_000_000) // 24 hours
                await performCleanup()
            }
        }
    }
    
    func performCleanup() async {
        print("🧹 Starting automatic cleanup...")
        
        do {
            let cutoffDate = Date().addingTimeInterval(-configuration.emailRetentionPeriod)
            let allAccounts = try fetchAllAccountsFromSwiftData()
            
            var totalRemovedCount = 0
            
            for account in allAccounts {
                let oldEmails = try fetchEmailsFromSwiftData(
                    for: account.email,
                    filter: nil,
                    limit: Int.max
                ).filter { $0.date < cutoffDate }
                
                for oldEmail in oldEmails {
                    modelContext.delete(oldEmail)
                    totalRemovedCount += 1
                }
                
                // Update account email count
                account.emailCount -= totalRemovedCount // Manual count update
                account.updatedAt = Date()
            }
            
            if totalRemovedCount > 0 {
                try saveSwiftDataContext()
                print("🧹 Cleaned up \(totalRemovedCount) old emails")
            } else {
                print("🧹 No old emails to clean up")
            }
            
        } catch {
            print("❌ Cleanup failed: \(error)")
        }
    }
    
    // MARK: - Helper Methods for Direct SwiftData Operations
    
    private func fetchEmailsFromSwiftData(for accountEmail: String, filter: EmailFilter?, limit: Int) throws -> [SwiftDataEmail] {
        var predicate = #Predicate<SwiftDataEmail> { email in
            email.accountEmail == accountEmail
        }
        
        // Apply filter if provided
        if let filter = filter {
            switch filter {
            case .all:
                break
            case .unread:
                predicate = #Predicate<SwiftDataEmail> { email in
                    email.accountEmail == accountEmail && !email.isRead
                }
            case .starred:
                predicate = #Predicate<SwiftDataEmail> { email in
                    email.accountEmail == accountEmail && email.isStarred
                }
            case .account(let filterEmail):
                predicate = #Predicate<SwiftDataEmail> { email in
                    email.accountEmail == filterEmail
                }
            case .label(_):
                break // Will filter in memory after fetching
            }
        }
        
        var descriptor = FetchDescriptor<SwiftDataEmail>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        if limit != Int.max {
            descriptor.fetchLimit = limit
        }
        
        var emails = try modelContext.fetch(descriptor)
        
        // Apply label filter in memory if needed
        if case .label(let label) = filter {
            emails = emails.filter { persistedEmail in
                if let labelsData = persistedEmail.labelsData,
                   let labels = try? JSONDecoder().decode([String].self, from: labelsData) {
                    return labels.contains(label)
                }
                return false
            }
        }
        
        return emails
    }
    
    private func fetchAccountFromSwiftData(email: String) throws -> SwiftDataAccount? {
        let predicate = #Predicate<SwiftDataAccount> { account in
            account.email == email
        }
        let descriptor = FetchDescriptor<SwiftDataAccount>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
    
    private func getOrCreateAccountInSwiftData(email: String, displayName: String? = nil) throws -> SwiftDataAccount {
        if let existingAccount = try fetchAccountFromSwiftData(email: email) {
            return existingAccount
        }
        
        let newAccount = SwiftDataAccount(
            email: email,
            displayName: displayName
        )
        modelContext.insert(newAccount)
        try saveSwiftDataContext()
        
        print("📦 Created new account: \(email)")
        return newAccount
    }
    
    private func fetchAllAccountsFromSwiftData() throws -> [SwiftDataAccount] {
        let descriptor = FetchDescriptor<SwiftDataAccount>(
            sortBy: [SortDescriptor(\.email)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    private func saveSwiftDataContext() throws {
        if modelContext.hasChanges {
            try modelContext.save()
            print("✅ SwiftData context saved successfully")
        }
    }
    
    private func deleteEmailsFromSwiftData(for accountEmail: String) throws {
        let emails = try fetchEmailsFromSwiftData(for: accountEmail, filter: nil, limit: Int.max)
        for email in emails {
            modelContext.delete(email)
        }
        
        // Update account email count
        if let account = try fetchAccountFromSwiftData(email: accountEmail) {
            account.emailCount = 0
            account.updatedAt = Date()
        }
        
        try saveSwiftDataContext()
        print("🗑️ Deleted all emails for account: \(accountEmail)")
    }
    
    private func deleteEmailFromSwiftData(with emailId: String) throws -> Bool {
        let predicate = #Predicate<SwiftDataEmail> { email in
            email.id == emailId
        }
        let descriptor = FetchDescriptor<SwiftDataEmail>(predicate: predicate)
        
        if let email = try modelContext.fetch(descriptor).first {
            let accountEmail = email.accountEmail
            modelContext.delete(email)
            
            // Update account email count
            if let account = try fetchAccountFromSwiftData(email: accountEmail) {
                account.emailCount = max(0, account.emailCount - 1)
                account.updatedAt = Date()
            }
            
            try saveSwiftDataContext()
            print("🗑️ Deleted email: \(emailId)")
            return true
        }
        
        return false
    }
    
    private func updateLastSyncDateInSwiftData(_ date: Date, for accountEmail: String) throws {
        if let account = try fetchAccountFromSwiftData(email: accountEmail) {
            account.lastSyncDate = date
            account.updatedAt = Date()
            try saveSwiftDataContext()
            print("📦 Updated last sync date for \(accountEmail): \(date)")
        }
    }
    
    private func clearAllDataFromSwiftData() throws {
        let allEmails = try modelContext.fetch(FetchDescriptor<SwiftDataEmail>())
        let allAccounts = try modelContext.fetch(FetchDescriptor<SwiftDataAccount>())
        
        for email in allEmails {
            modelContext.delete(email)
        }
        
        for account in allAccounts {
            modelContext.delete(account)
        }
        
        try saveSwiftDataContext()
        print("🗑️ Cleared all SwiftData")
    }
}

// MARK: - Extensions for Debugging

extension EmailFilter {
    var description: String {
        switch self {
        case .all: return "all"
        case .unread: return "unread"
        case .starred: return "starred"
        case .account(let email): return "account(\(email))"
        case .label(let label): return "label(\(label))"
        }
    }
}
