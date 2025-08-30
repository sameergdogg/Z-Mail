import Foundation
import Combine

/// Implementation of Email Persistence Protocol using in-memory storage
/// This is a simplified implementation for demonstration. In production, you would use Core Data.
internal class EmailPersistenceStoreImpl: EmailPersistenceProtocol {
    
    // MARK: - Properties
    
    private let dependencies: EmailPersistenceDependencies
    private let configuration: PersistenceConfiguration
    
    // In-memory storage
    private var emails: [String: [Email]] = [:] // accountEmail -> [Email]
    private var lastSyncDates: [String: Date] = [:] // accountEmail -> Date
    private let queue = DispatchQueue(label: "email-persistence", attributes: .concurrent)
    
    private let emailChangesSubject = PassthroughSubject<EmailChangeEvent, Never>()
    
    public var emailChanges: AnyPublisher<EmailChangeEvent, Never> {
        emailChangesSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    internal init(dependencies: EmailPersistenceDependencies) {
        self.dependencies = dependencies
        self.configuration = dependencies.configuration
        
        setupAutoCleanup()
    }
    
    // MARK: - Public API Implementation
    
    public func fetchEmails(for accountEmail: String, filter: EmailFilter?) async throws -> [Email] {
        return await withCheckedContinuation { continuation in
            queue.async {
                let accountEmails = self.emails[accountEmail] ?? []
                
                let filteredEmails: [Email]
                if let filter = filter {
                    filteredEmails = accountEmails.filter { email in
                        switch filter {
                        case .all:
                            return true
                        case .unread:
                            return !email.isRead
                        case .starred:
                            return email.isStarred
                        case .account(let email):
                            return email == accountEmail
                        case .label(let label):
                            return email.labels.contains(label)
                        }
                    }
                } else {
                    filteredEmails = accountEmails
                }
                
                // Sort by date (newest first)
                let sortedEmails = filteredEmails.sorted { $0.date > $1.date }
                
                // Limit results
                let limitedEmails = Array(sortedEmails.prefix(self.configuration.maxEmailsPerAccount))
                
                continuation.resume(returning: limitedEmails)
            }
        }
    }
    
    public func saveEmails(_ emails: [Email], for accountEmail: String) async throws {
        guard !emails.isEmpty else { return }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) {
                // Get existing emails for this account
                var existingEmails = self.emails[accountEmail] ?? []
                let existingIds = Set(existingEmails.map { $0.id })
                
                // Add only new emails (avoid duplicates)
                let newEmails = emails.filter { !existingIds.contains($0.id) }
                existingEmails.append(contentsOf: newEmails)
                
                // Keep only the most recent emails up to the limit
                existingEmails.sort { $0.date > $1.date }
                existingEmails = Array(existingEmails.prefix(self.configuration.maxEmailsPerAccount))
                
                self.emails[accountEmail] = existingEmails
                
                // Emit change event
                Task { @MainActor in
                    self.emailChangesSubject.send(.emailsAdded(newEmails))
                }
                
                continuation.resume()
            }
        }
    }
    
    public func updateEmail(_ email: Email) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) {
                guard var accountEmails = self.emails[email.accountEmail],
                      let index = accountEmails.firstIndex(where: { $0.id == email.id }) else {
                    continuation.resume()
                    return
                }
                
                accountEmails[index] = email
                self.emails[email.accountEmail] = accountEmails
                
                // Emit change event
                Task { @MainActor in
                    self.emailChangesSubject.send(.emailUpdated(email))
                }
                
                continuation.resume()
            }
        }
    }
    
    public func deleteEmails(for accountEmail: String) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) {
                self.emails[accountEmail] = []
                self.lastSyncDates.removeValue(forKey: accountEmail)
                
                // Emit change event
                Task { @MainActor in
                    self.emailChangesSubject.send(.accountDataCleared(accountEmail))
                }
                
                continuation.resume()
            }
        }
    }
    
    public func deleteEmail(with emailId: String) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) {
                for (accountEmail, var accountEmails) in self.emails {
                    if let index = accountEmails.firstIndex(where: { $0.id == emailId }) {
                        accountEmails.remove(at: index)
                        self.emails[accountEmail] = accountEmails
                        
                        // Emit change event
                        Task { @MainActor in
                            self.emailChangesSubject.send(.emailDeleted(emailId))
                        }
                        break
                    }
                }
                
                continuation.resume()
            }
        }
    }
    
    public func hasEmails(for accountEmail: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            queue.async {
                let hasEmails = !(self.emails[accountEmail]?.isEmpty ?? true)
                continuation.resume(returning: hasEmails)
            }
        }
    }
    
    public func getLastSyncDate(for accountEmail: String) async -> Date? {
        return await withCheckedContinuation { continuation in
            queue.async {
                let date = self.lastSyncDates[accountEmail]
                continuation.resume(returning: date)
            }
        }
    }
    
    public func updateLastSyncDate(_ date: Date, for accountEmail: String) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) {
                self.lastSyncDates[accountEmail] = date
                continuation.resume()
            }
        }
    }
    
    public func getEmailCount(for accountEmail: String) async -> Int {
        return await withCheckedContinuation { continuation in
            queue.async {
                let count = self.emails[accountEmail]?.count ?? 0
                continuation.resume(returning: count)
            }
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
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) {
                self.emails.removeAll()
                self.lastSyncDates.removeAll()
                continuation.resume()
            }
        }
    }
}

// MARK: - Private Helper Methods

private extension EmailPersistenceStoreImpl {
    
    func setupAutoCleanup() {
        guard configuration.enableAutoCleanup else { return }
        
        // Schedule periodic cleanup
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 24 * 60 * 60 * 1_000_000_000) // 24 hours
                await performCleanup()
            }
        }
    }
    
    func performCleanup() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) {
                let cutoffDate = Date().addingTimeInterval(-self.configuration.emailRetentionPeriod)
                
                var totalRemovedCount = 0
                
                for (accountEmail, accountEmails) in self.emails {
                    let filteredEmails = accountEmails.filter { $0.date >= cutoffDate }
                    let removedCount = accountEmails.count - filteredEmails.count
                    
                    if removedCount > 0 {
                        self.emails[accountEmail] = filteredEmails
                        totalRemovedCount += removedCount
                    }
                }
                
                if totalRemovedCount > 0 {
                    print("Cleaned up \(totalRemovedCount) old emails")
                }
                
                continuation.resume()
            }
        }
    }
}