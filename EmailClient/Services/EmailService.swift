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
    
    private var accountManager: AccountManager
    private let gmailAPIService = GmailAPIService()
    
    init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }
    
    func updateAccountManager(_ newAccountManager: AccountManager) {
        self.accountManager = newAccountManager
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
        // Check if account requires re-authentication
        if accountManager.requiresReauthentication(for: account) {
            throw EmailServiceError.reauthenticationRequired(account.email)
        }
        
        guard let user = accountManager.getUserForAccount(account) else {
            throw EmailServiceError.noSignedInUser(account.email)
        }
        
        do {
            // Use the new validation method that handles re-authentication gracefully
            let validatedUser = try await accountManager.validateAndRefreshTokenForUser(user)
            
            let gmailMessages = try await gmailAPIService.fetchMessages(for: validatedUser, maxResults: 50)
            
            return gmailMessages.map { gmailMessage in
                gmailAPIService.convertGmailMessageToEmail(gmailMessage, accountEmail: account.email)
            }
            
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