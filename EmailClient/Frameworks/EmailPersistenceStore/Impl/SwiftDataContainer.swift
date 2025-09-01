import Foundation
import SwiftData

/// SwiftData container manager for email persistence
public class SwiftDataContainer {
    public let modelContainer: ModelContainer
    public let modelContext: ModelContext
    
    public init(configuration: PersistenceConfiguration) throws {
        let schema = Schema([
            SwiftDataEmail.self,
            SwiftDataAccount.self,
            SwiftDataDigest.self
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
            case .classification(_):
                // Classification filtering requires complex logic with classification data
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
        
        // Delete all digests
        let allDigests = try modelContext.fetch(FetchDescriptor<SwiftDataDigest>())
        for digest in allDigests {
            modelContext.delete(digest)
        }
        
        try save()
        print("🗑️ Cleared all persistent data")
    }
    
    // MARK: - Digest Operations
    
    /// Fetch digest for a specific date
    public func fetchDigest(for date: Date) throws -> SwiftDataDigest? {
        let dateKey = SwiftDataDigest.createDateKey(for: date)
        let predicate = #Predicate<SwiftDataDigest> { digest in
            digest.dateKey == dateKey
        }
        let descriptor = FetchDescriptor<SwiftDataDigest>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
    
    /// Fetch digests for a date range
    public func fetchDigests(from startDate: Date, to endDate: Date) throws -> [SwiftDataDigest] {
        let predicate = #Predicate<SwiftDataDigest> { digest in
            digest.digestDate >= startDate && digest.digestDate <= endDate
        }
        let descriptor = FetchDescriptor<SwiftDataDigest>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.digestDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Save or update digest for a specific date
    public func saveDigest(_ digest: DailyDigest, for date: Date, emailCount: Int, accountEmails: [String]) throws {
        let dateKey = SwiftDataDigest.createDateKey(for: date)
        
        // Check if digest already exists for this date
        if let existingDigest = try fetchDigest(for: date) {
            // Update existing digest
            try existingDigest.updateFromDomainModel(digest, emailCount: emailCount, accountEmails: accountEmails)
            print("📊 Updated existing digest for \(dateKey)")
        } else {
            // Create new digest
            let newDigest = try digest.toSwiftDataModel(for: date, emailCount: emailCount, accountEmails: accountEmails)
            modelContext.insert(newDigest)
            print("📊 Created new digest for \(dateKey)")
        }
        
        try save()
    }
    
    /// Delete digest for a specific date
    public func deleteDigest(for date: Date) throws -> Bool {
        if let existingDigest = try fetchDigest(for: date) {
            let dateKey = SwiftDataDigest.createDateKey(for: date)
            modelContext.delete(existingDigest)
            try save()
            print("🗑️ Deleted digest for \(dateKey)")
            return true
        }
        return false
    }
    
    /// Check if digest exists for a specific date
    public func hasDigest(for date: Date) throws -> Bool {
        return try fetchDigest(for: date) != nil
    }
}