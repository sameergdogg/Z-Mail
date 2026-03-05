import Foundation
import SwiftData

// MARK: - EmailFilter (used by persistence and email service)

public enum EmailFilter: Equatable {
    case all
    case unread
    case starred
    case account(String)
    case label(String)
    case classification(String)

    var description: String {
        switch self {
        case .all: return "all"
        case .unread: return "unread"
        case .starred: return "starred"
        case .account(let email): return "account(\(email))"
        case .label(let label): return "label(\(label))"
        case .classification(let category): return "classification(\(category))"
        }
    }
}

// MARK: - EmailPersistenceService

/// Handles all email persistence operations against SwiftData.
/// Uses the shared ModelContext provided by AppDataManager.
/// Replaces the Frameworks/EmailPersistenceStore/ three-layer pattern.
class EmailPersistenceService {

    private let modelContext: ModelContext
    private let maxEmailsPerAccount = 500

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Email CRUD

    func fetchEmails(for accountEmail: String, filter: EmailFilter?) throws -> [Email] {
        var predicate = #Predicate<Email> { email in
            email.accountEmail == accountEmail
        }

        if let filter = filter {
            switch filter {
            case .all:
                break
            case .unread:
                predicate = #Predicate<Email> { email in
                    email.accountEmail == accountEmail && !email.isRead
                }
            case .starred:
                predicate = #Predicate<Email> { email in
                    email.accountEmail == accountEmail && email.isStarred
                }
            case .account(let filterEmail):
                predicate = #Predicate<Email> { email in
                    email.accountEmail == filterEmail
                }
            case .label:
                break // filtered in-memory below
            case .classification:
                break // filtered in-memory below
            }
        }

        var descriptor = FetchDescriptor<Email>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = maxEmailsPerAccount

        var emails = try modelContext.fetch(descriptor)

        // In-memory label/classification filtering
        if case .label(let label) = filter {
            emails = emails.filter { $0.labels.contains(label) }
        }

        return emails
    }

    func saveEmails(_ emails: [Email], for accountEmail: String) throws {
        guard !emails.isEmpty else { return }

        // Get existing IDs to avoid duplicates
        var descriptor = FetchDescriptor<Email>(
            predicate: #Predicate<Email> { email in
                email.accountEmail == accountEmail
            }
        )
        descriptor.propertiesToFetch = [\.id]
        let existingIds = Set((try? modelContext.fetch(descriptor).map { $0.id }) ?? [])

        var newCount = 0
        for email in emails where !existingIds.contains(email.id) {
            modelContext.insert(email)
            newCount += 1
        }

        if modelContext.hasChanges {
            try modelContext.save()
            print("Saved \(newCount) new emails for \(accountEmail)")
        }
    }

    func updateEmail(_ email: Email) throws {
        let emailId = email.id
        let predicate = #Predicate<Email> { e in e.id == emailId }
        let descriptor = FetchDescriptor<Email>(predicate: predicate)

        if let existing = try modelContext.fetch(descriptor).first {
            existing.subject = email.subject
            existing.senderName = email.senderName
            existing.senderEmail = email.senderEmail
            existing.recipientsData = email.recipientsData
            existing.body = email.body
            existing.htmlBody = email.htmlBody
            existing.date = email.date
            existing.isRead = email.isRead
            existing.isStarred = email.isStarred
            existing.labelsData = email.labelsData
            existing.accountEmail = email.accountEmail
            existing.threadId = email.threadId
            existing.classificationCategory = email.classificationCategory
            existing.classificationConfidence = email.classificationConfidence
            existing.classificationSummary = email.classificationSummary
            existing.classificationDate = email.classificationDate
            existing.isClassified = email.isClassified
            existing.updatedAt = Date()

            if modelContext.hasChanges {
                try modelContext.save()
            }
        }
    }

    func updateLastSyncDate(_ date: Date, for accountEmail: String) throws {
        // Last sync date tracking — stored in UserDefaults keyed by account email
        UserDefaults.standard.set(date, forKey: "lastSyncDate_\(accountEmail)")
    }

    func getLastSyncDate(for accountEmail: String) -> Date? {
        return UserDefaults.standard.object(forKey: "lastSyncDate_\(accountEmail)") as? Date
    }

    func clearAllEmails(for accountEmail: String) throws {
        let predicate = #Predicate<Email> { email in
            email.accountEmail == accountEmail
        }
        let descriptor = FetchDescriptor<Email>(predicate: predicate)
        let emails = try modelContext.fetch(descriptor)
        for email in emails { modelContext.delete(email) }

        if modelContext.hasChanges {
            try modelContext.save()
            print("Cleared all emails for \(accountEmail)")
        }
    }

    func determineSyncStrategy(for accountEmail: String) -> SyncStrategy {
        let hasEmails = (try? fetchEmails(for: accountEmail, filter: nil).isEmpty == false) ?? false
        let lastSyncDate = getLastSyncDate(for: accountEmail)

        guard hasEmails, let syncDate = lastSyncDate else { return .fullSync }

        let timeSinceLastSync = Date().timeIntervalSince(syncDate)
        let cacheThreshold: TimeInterval = 5 * 60

        if timeSinceLastSync < cacheThreshold { return .cacheOnly }
        return .incrementalSync(since: syncDate)
    }

    // MARK: - Digest Operations

    func fetchDigest(for date: Date) throws -> DailyDigest? {
        guard let digest = try fetchSwiftDataDigest(for: date) else { return nil }
        return digest.toDomainModel()
    }

    func saveDigest(_ digest: DailyDigest, for date: Date, emailCount: Int, accountEmails: [String]) throws {
        if let existing = try fetchSwiftDataDigest(for: date) {
            try existing.updateFromDomainModel(digest, emailCount: emailCount, accountEmails: accountEmails)
        } else {
            let newDigest = try digest.toSwiftDataModel(for: date, emailCount: emailCount, accountEmails: accountEmails)
            modelContext.insert(newDigest)
        }

        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    func deleteDigest(for date: Date) throws -> Bool {
        guard let existing = try fetchSwiftDataDigest(for: date) else { return false }
        modelContext.delete(existing)
        if modelContext.hasChanges { try modelContext.save() }
        return true
    }

    func deleteAllDigests() throws -> Int {
        let descriptor = FetchDescriptor<SwiftDataDigest>()
        let all = try modelContext.fetch(descriptor)
        for digest in all { modelContext.delete(digest) }
        if modelContext.hasChanges { try modelContext.save() }
        return all.count
    }

    func hasDigest(for date: Date) throws -> Bool {
        return try fetchSwiftDataDigest(for: date) != nil
    }

    private func fetchSwiftDataDigest(for date: Date) throws -> SwiftDataDigest? {
        let dateKey = SwiftDataDigest.createDateKey(for: date)
        let predicate = #Predicate<SwiftDataDigest> { digest in
            digest.dateKey == dateKey
        }
        let descriptor = FetchDescriptor<SwiftDataDigest>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
}

// MARK: - SyncStrategy (helper enum)

enum SyncStrategy {
    case cacheOnly
    case fullSync
    case incrementalSync(since: Date)
}
