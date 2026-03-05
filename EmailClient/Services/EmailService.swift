import Foundation
import SwiftUI
import GoogleSignIn
import Combine

// MARK: - Supporting types

/// Email sender model for grouping emails by sender
public struct EmailSender: Identifiable, Hashable {
    public let id = UUID()
    public let email: String
    public let name: String?
    public let emailCount: Int

    public var displayName: String { name ?? email }

    public init(email: String, name: String? = nil, emailCount: Int = 0) {
        self.email = email
        self.name = name
        self.emailCount = emailCount
    }
}

/// Sort order options
public enum SortOrder {
    case dateAscending
    case dateDescending
    case senderAscending
    case senderDescending
}

/// Sync progress state
public enum SyncProgress {
    case idle
    case syncing(accountEmail: String, progress: Double)
    case completed
    case failed(error: String)
}

/// Email service specific errors
public enum EmailServiceError: Error, LocalizedError {
    case noSignedInUser(String)
    case fetchFailed(String)
    case reauthenticationRequired(String)
    case authenticationFailed(String)
    case networkError
    case gmailAPIError(String)

    public var errorDescription: String? {
        switch self {
        case .noSignedInUser(let email): return "No signed-in user found for \(email). Please sign in again."
        case .fetchFailed(let message): return "Failed to fetch emails: \(message)"
        case .reauthenticationRequired(let email): return "Authentication expired for \(email). Please sign in again."
        case .authenticationFailed(let email): return "Authentication failed for \(email). Please try signing in again."
        case .networkError: return "Network connection error. Please check your internet connection and try again."
        case .gmailAPIError(let message): return message
        }
    }

    public var isAuthenticationError: Bool {
        switch self {
        case .reauthenticationRequired, .authenticationFailed, .noSignedInUser: return true
        case .fetchFailed, .networkError, .gmailAPIError: return false
        }
    }
}

// MARK: - EmailServiceImpl

/// Manages the email list, filtering, sorting, and Gmail API sync.
/// Replaces the Frameworks/EmailService/ three-layer pattern.
class EmailServiceImpl: ObservableObject {

    // MARK: - Published Properties

    @Published var emails: [Email] = []
    @Published var filteredEmails: [Email] = []
    @Published var isLoading = false
    @Published var currentFilter: EmailFilter = .all
    @Published var sortOrder: SortOrder = .dateDescending
    @Published var errorMessage: String?
    @Published var authenticationErrors: [String: EmailServiceError] = [:]
    @Published var syncProgress: SyncProgress = .idle

    // MARK: - Dependencies

    private let accountManager: AccountManagerImpl
    private let gmailAPIService = GmailAPIService()
    private let enableGmailAPISync = true
    private let maxEmailsPerSync = 50

    private var persistenceService: EmailPersistenceService? {
        guard let ctx = AppDataManager.shared.modelContext else { return nil }
        return EmailPersistenceService(modelContext: ctx)
    }

    // MARK: - Init

    init(accountManager: AccountManagerImpl) {
        self.accountManager = accountManager
    }

    /// Called by views on appear — triggers a reload with the current account manager.
    func updateAccountManager(_ newAccountManager: AccountManagerImpl) {
        Task {
            await loadEmailsOnLaunch()
        }
    }

    // MARK: - Public Methods

    func loadEmailsOnLaunch() async {
        print("EmailServiceImpl.loadEmailsOnLaunch() started")

        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        defer { Task { @MainActor in self.isLoading = false } }

        await loadEmailsFromPersistence()
        applyCurrentFilter()

        // Auto-sync from Gmail if DB is empty (e.g. first launch or after schema migration)
        if emails.isEmpty && !accountManager.accounts.isEmpty {
            print("loadEmailsOnLaunch: DB empty, auto-syncing from Gmail...")
            await forceSyncFromServer()
            await loadEmailsFromPersistence()
            applyCurrentFilter()
        }

        print("loadEmailsOnLaunch: total=\(emails.count) filtered=\(filteredEmails.count)")
    }

    func refreshEmails() async {
        print("EmailServiceImpl.refreshEmails() started")

        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        defer { Task { @MainActor in self.isLoading = false } }

        await forceSyncFromServer()
        await loadEmailsFromPersistence()
        applyCurrentFilter()

        print("refreshEmails: total=\(emails.count) filtered=\(filteredEmails.count)")
    }

    func applyFilter(_ filter: EmailFilter) {
        currentFilter = filter
        applyCurrentFilter()
    }

    func applySortOrder(_ order: SortOrder) {
        sortOrder = order
        DispatchQueue.main.async {
            self.sortEmails()
            self.applyCurrentFilter()
        }
    }

    func markAsRead(_ email: Email) async {
        await updateEmailStatus(email, isRead: true)
    }

    func markAsUnread(_ email: Email) async {
        await updateEmailStatus(email, isRead: false)
    }

    func toggleStar(_ email: Email) async {
        let newStarredState = !email.isStarred

        await MainActor.run {
            email.isStarred = newStarredState
            email.updatedAt = Date()
            applyCurrentFilter()
        }

        do {
            try persistenceService?.updateEmail(email)
        } catch {
            print("Failed to update email star in persistence: \(error)")
        }

        if enableGmailAPISync {
            await syncEmailStarWithGmailAPI(email, isStarred: newStarredState)
        }
    }

    func getUniqueSenders() -> [EmailSender] {
        let senderGroups = Dictionary(grouping: filteredEmails) { $0.senderEmail }
        let uniqueSenders = senderGroups.map { (senderEmail, emails) in
            let first = emails.first!
            return EmailSender(email: senderEmail, name: first.senderName, emailCount: emails.count)
        }
        return uniqueSenders.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func getEmailsFromSender(_ sender: EmailSender) -> [Email] {
        return filteredEmails.filter { $0.senderEmail == sender.email }
            .sorted { email1, email2 in
                switch sortOrder {
                case .dateAscending: return email1.date < email2.date
                case .dateDescending: return email1.date > email2.date
                case .senderAscending: return email1.sender.displayName < email2.sender.displayName
                case .senderDescending: return email1.sender.displayName > email2.sender.displayName
                }
            }
    }

    // MARK: - Digest Methods

    func hasDigest(for date: Date) -> Bool {
        return (try? persistenceService?.hasDigest(for: date)) ?? false
    }

    func loadDigest(for date: Date) -> DailyDigest? {
        return try? persistenceService?.fetchDigest(for: date)
    }

    func saveDigest(_ digest: DailyDigest, for date: Date, emailCount: Int, accountEmails: [String]) throws {
        try persistenceService?.saveDigest(digest, for: date, emailCount: emailCount, accountEmails: accountEmails)
    }

    func deleteDigest(for date: Date) throws -> Bool {
        return try persistenceService?.deleteDigest(for: date) ?? false
    }

    // MARK: - Private: Status updates

    private func updateEmailStatus(_ email: Email, isRead: Bool) async {
        await MainActor.run {
            email.isRead = isRead
            email.updatedAt = Date()
            applyCurrentFilter()
        }

        do {
            try persistenceService?.updateEmail(email)
        } catch {
            print("Failed to update email read status in persistence: \(error)")
        }

        if enableGmailAPISync {
            await syncEmailStatusWithGmailAPI(email, isRead: isRead)
        }
    }

    // MARK: - Private: Filtering / Sorting

    private func applyCurrentFilter() {
        DispatchQueue.main.async {
            switch self.currentFilter {
            case .all:
                self.filteredEmails = self.emails
            case .unread:
                self.filteredEmails = self.emails.filter { !$0.isRead }
            case .starred:
                self.filteredEmails = self.emails.filter { $0.isStarred }
            case .account(let accountEmail):
                self.filteredEmails = self.emails.filter { $0.accountEmail == accountEmail }
            case .label(let label):
                self.filteredEmails = self.emails.filter { $0.labels.contains(label) }
            case .classification(let category):
                self.filteredEmails = self.emails.filter { email in
                    email.isClassified && email.classificationCategory == category
                }
            }
        }
    }

    private func sortEmails() {
        emails.sort { e1, e2 in
            switch sortOrder {
            case .dateAscending: return e1.date < e2.date
            case .dateDescending: return e1.date > e2.date
            case .senderAscending: return e1.sender.displayName < e2.sender.displayName
            case .senderDescending: return e1.sender.displayName > e2.sender.displayName
            }
        }
    }

    // MARK: - Private: Gmail API sync

    private func syncEmailStatusWithGmailAPI(_ email: Email, isRead: Bool) async {
        guard let account = accountManager.accounts.first(where: { $0.email == email.accountEmail }),
              let user = accountManager.getUserForAccount(account) else { return }

        do {
            let validatedUser = try await accountManager.validateAndRefreshTokenForUser(user)
            if isRead {
                try await gmailAPIService.markMessageAsRead(messageId: email.id, user: validatedUser)
            }
        } catch {
            print("Failed to sync email status with Gmail API: \(error)")
        }
    }

    private func syncEmailStarWithGmailAPI(_ email: Email, isStarred: Bool) async {
        guard let account = accountManager.accounts.first(where: { $0.email == email.accountEmail }),
              let user = accountManager.getUserForAccount(account) else { return }

        do {
            let validatedUser = try await accountManager.validateAndRefreshTokenForUser(user)
            try await gmailAPIService.toggleMessageStar(messageId: email.id, user: validatedUser, isStarred: isStarred)
        } catch {
            print("Failed to sync email star with Gmail API: \(error)")
        }
    }

    // MARK: - Private: Persistence load

    private func loadEmailsFromPersistence() async {
        guard let service = persistenceService else { return }

        var allEmails: [Email] = []

        for account in accountManager.accounts {
            do {
                let accountEmails = try service.fetchEmails(for: account.email, filter: nil)
                allEmails.append(contentsOf: accountEmails)
            } catch {
                print("Failed to load emails for \(account.email): \(error)")
            }
        }

        await MainActor.run {
            self.emails = allEmails
            self.sortEmails()
        }
    }

    // MARK: - Private: Server sync

    private func forceSyncFromServer() async {
        if accountManager.accounts.isEmpty {
            await MainActor.run {
                self.errorMessage = "No Gmail accounts connected. Please add an account to continue."
            }
            return
        }

        for account in accountManager.accounts {
            await performFullSync(for: account)
        }
    }

    private func performFullSync(for account: GmailAccount) async {
        print("performFullSync for \(account.email)")

        await MainActor.run {
            self.syncProgress = .syncing(accountEmail: account.email, progress: 0.0)
        }

        do {
            await MainActor.run {
                self.syncProgress = .syncing(accountEmail: account.email, progress: 0.3)
            }

            let accountEmails = try await fetchEmailsForAccount(account)

            await MainActor.run {
                self.syncProgress = .syncing(accountEmail: account.email, progress: 0.7)
            }

            try persistenceService?.saveEmails(accountEmails, for: account.email)
            try persistenceService?.updateLastSyncDate(Date(), for: account.email)

            await MainActor.run {
                self.syncProgress = .completed
            }

        } catch {
            print("performFullSync failed for \(account.email): \(error)")

            await MainActor.run {
                self.syncProgress = .failed(error: error.localizedDescription)

                if let serviceError = error as? EmailServiceError {
                    if serviceError.isAuthenticationError {
                        self.authenticationErrors[account.email] = serviceError
                    } else {
                        self.errorMessage = serviceError.errorDescription
                    }
                } else {
                    self.errorMessage = "Failed to sync \(account.email): \(error.localizedDescription)"
                }
            }
        }
    }

    private func fetchEmailsForAccount(_ account: GmailAccount) async throws -> [Email] {
        if accountManager.requiresReauthentication(for: account) {
            throw EmailServiceError.reauthenticationRequired(account.email)
        }

        guard let user = accountManager.getUserForAccount(account) else {
            throw EmailServiceError.noSignedInUser(account.email)
        }

        do {
            let validatedUser = try await accountManager.validateAndRefreshTokenForUser(user)
            let gmailMessages = try await gmailAPIService.fetchMessages(for: validatedUser, maxResults: maxEmailsPerSync)

            return gmailMessages.map { msg in
                gmailAPIService.convertGmailMessageToEmail(msg, accountEmail: account.email)
            }

        } catch AccountError.reauthenticationRequired {
            throw EmailServiceError.reauthenticationRequired(account.email)
        } catch AccountError.tokenRefreshFailed {
            throw EmailServiceError.authenticationFailed(account.email)
        } catch AccountError.networkError {
            throw EmailServiceError.networkError
        } catch {
            if let errorMessage = parseGmailAPIError(error) {
                throw EmailServiceError.gmailAPIError(errorMessage)
            }
            throw EmailServiceError.fetchFailed(error.localizedDescription)
        }
    }

    private func parseGmailAPIError(_ error: Error) -> String? {
        let desc = error.localizedDescription.lowercased()
        if desc.contains("401") || desc.contains("unauthorized") {
            return "Authentication expired. Please sign in again."
        } else if desc.contains("403") || desc.contains("forbidden") {
            return "Access denied. Please check your account permissions."
        } else if desc.contains("404") || desc.contains("not found") {
            return "Gmail service temporarily unavailable."
        } else if desc.contains("429") || desc.contains("quota") {
            return "Gmail API quota exceeded. Please try again later."
        } else if desc.contains("network") || desc.contains("connection") {
            return "Network connection error. Please check your internet connection."
        }
        return nil
    }
}
