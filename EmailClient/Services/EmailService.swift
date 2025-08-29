import Foundation
import SwiftUI
import GoogleSignIn

class EmailService: ObservableObject {
    @Published var emails: [Email] = []
    @Published var filteredEmails: [Email] = []
    @Published var isLoading = false
    @Published var currentFilter: EmailFilter = .all
    @Published var sortOrder: SortOrder = .dateDescending
    @Published var errorMessage: String?
    
    private let accountManager: AccountManager
    private let gmailAPIService = GmailAPIService()
    
    init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }
    
    func refreshEmails() async {
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        defer {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
        
        await fetchEmailsFromAllAccounts()
        applyCurrentFilter()
    }
    
    private func fetchEmailsFromAllAccounts() async {
        var allEmails: [Email] = []
        
        await MainActor.run {
            self.errorMessage = nil
        }
        
        for account in accountManager.accounts {
            do {
                let accountEmails = try await fetchEmailsForAccount(account)
                allEmails.append(contentsOf: accountEmails)
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to fetch emails for \(account.email): \(error.localizedDescription)"
                }
                print("Error fetching emails for \(account.email): \(error)")
            }
        }
        
        DispatchQueue.main.async {
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
        }
    }
    
    private func fetchEmailsForAccount(_ account: GmailAccount) async throws -> [Email] {
        guard let user = accountManager.getUserForAccount(account) else {
            throw EmailServiceError.noSignedInUser
        }
        
        try await accountManager.refreshTokenForUser(user)
        
        let gmailMessages = try await gmailAPIService.fetchMessages(for: user, maxResults: 50)
        
        return gmailMessages.map { gmailMessage in
            gmailAPIService.convertGmailMessageToEmail(gmailMessage, accountEmail: account.email)
        }
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
            emails[index] = Email(
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
            applyCurrentFilter()
        }
    }
    
    func toggleStar(_ email: Email) {
        if let index = emails.firstIndex(where: { $0.id == email.id }) {
            emails[index] = Email(
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
            applyCurrentFilter()
        }
    }
    
}

enum EmailServiceError: Error {
    case noSignedInUser
    case fetchFailed
}

enum EmailFilter {
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