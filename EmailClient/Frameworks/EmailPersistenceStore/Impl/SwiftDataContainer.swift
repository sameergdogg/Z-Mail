import Foundation
import SwiftData

/// SwiftData container manager for email persistence
public class SwiftDataContainer {
    public let modelContainer: ModelContainer
    public let modelContext: ModelContext
    
    public init(configuration: PersistenceConfiguration) throws {
        let schema = Schema([
            SwiftDataEmail.self,
            SwiftDataAccount.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: configuration.isInMemoryOnly,
            cloudKitDatabase: configuration.enableCloudKit ? .automatic : .none
        )
        
        print("📦 Initializing SwiftData container...")
        print("📦 In-memory only: \(configuration.isInMemoryOnly)")
        print("📦 CloudKit enabled: \(configuration.enableCloudKit)")
        
        do {
            self.modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            self.modelContext = ModelContext(modelContainer)
            print("✅ SwiftData container initialized successfully")
        } catch {
            print("❌ Failed to initialize SwiftData container: \(error)")
            throw error
        }
    }
}

// MARK: - SwiftData Operations Helper

extension SwiftDataContainer {
    
    /// Fetch all accounts
    public func fetchAccounts() throws -> [SwiftDataAccount] {
        let descriptor = FetchDescriptor<SwiftDataAccount>(
            sortBy: [SortDescriptor(\.email)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetch account by email
    public func fetchAccount(email: String) throws -> SwiftDataAccount? {
        let predicate = #Predicate<SwiftDataAccount> { account in
            account.email == email
        }
        let descriptor = FetchDescriptor<SwiftDataAccount>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
    
    /// Fetch emails for account with optional filter
    public func fetchEmails(for accountEmail: String, filter: EmailFilter?, limit: Int) throws -> [SwiftDataEmail] {
        var predicate = #Predicate<SwiftDataEmail> { email in
            email.accountEmail == accountEmail
        }
        
        // Apply filter if provided
        if let filter = filter {
            switch filter {
            case .all:
                // No additional filtering needed
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
                // Label filtering would require more complex predicate with JSON data
                // For now, we'll filter in memory after fetching
                break
            }
        }
        
        var descriptor = FetchDescriptor<SwiftDataEmail>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)] // Newest first
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
    
    /// Save context changes
    public func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
            print("✅ SwiftData context saved successfully")
        }
    }
    
    /// Get or create account
    public func getOrCreateAccount(email: String, displayName: String? = nil) throws -> SwiftDataAccount {
        if let existingAccount = try fetchAccount(email: email) {
            return existingAccount
        }
        
        let newAccount = SwiftDataAccount(
            email: email,
            displayName: displayName
        )
        modelContext.insert(newAccount)
        try save()
        
        print("📦 Created new account: \(email)")
        return newAccount
    }
    
    /// Delete emails for account
    public func deleteEmails(for accountEmail: String) throws {
        let emails = try fetchEmails(for: accountEmail, filter: nil, limit: Int.max)
        for email in emails {
            modelContext.delete(email)
        }
        
        // Update account email count
        if let account = try fetchAccount(email: accountEmail) {
            account.emailCount = 0
            account.updatedAt = Date()
        }
        
        try save()
        print("🗑️ Deleted all emails for account: \(accountEmail)")
    }
    
    /// Delete specific email
    public func deleteEmail(with emailId: String) throws -> Bool {
        let predicate = #Predicate<SwiftDataEmail> { email in
            email.id == emailId
        }
        let descriptor = FetchDescriptor<SwiftDataEmail>(predicate: predicate)
        
        if let email = try modelContext.fetch(descriptor).first {
            let accountEmail = email.accountEmail
            modelContext.delete(email)
            
            // Update account email count
            if let account = try fetchAccount(email: accountEmail) {
                account.emailCount = max(0, account.emailCount - 1)
                account.updatedAt = Date()
            }
            
            try save()
            print("🗑️ Deleted email: \(emailId)")
            return true
        }
        
        return false
    }
    
    /// Update account last sync date
    public func updateLastSyncDate(_ date: Date, for accountEmail: String) throws {
        if let account = try fetchAccount(email: accountEmail) {
            account.lastSyncDate = date
            account.updatedAt = Date()
            try save()
            print("📦 Updated last sync date for \(accountEmail): \(date)")
        }
    }
    
    /// Clear all data
    public func clearAllData() throws {
        // Delete all emails
        let allEmails = try modelContext.fetch(FetchDescriptor<SwiftDataEmail>())
        for email in allEmails {
            modelContext.delete(email)
        }
        
        // Delete all accounts
        let allAccounts = try modelContext.fetch(FetchDescriptor<SwiftDataAccount>())
        for account in allAccounts {
            modelContext.delete(account)
        }
        
        try save()
        print("🗑️ Cleared all persistent data")
    }
}