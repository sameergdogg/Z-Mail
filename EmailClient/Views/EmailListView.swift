import SwiftUI

struct EmailListView: View {
    @EnvironmentObject var accountManager: AccountManager
    @StateObject private var emailService: EmailService
    @State private var showingFilters = false
    @State private var showingReauth = false
    @State private var hasInitialized = false
    
    init() {
        // We'll update this in onAppear to use the environment's accountManager
        self._emailService = StateObject(wrappedValue: EmailService(accountManager: AccountManager()))
    }
    
    private var hasAuthenticationErrors: Bool {
        !emailService.authenticationErrors.isEmpty
    }
    
    private func reauthenticateAccounts() async {
        let authErrorEmails = Array(emailService.authenticationErrors.keys)
        
        for emailAddress in authErrorEmails {
            // Find the account that needs re-authentication
            if let account = accountManager.accounts.first(where: { $0.email == emailAddress }) {
                do {
                    print("Re-authenticating account: \(emailAddress)")
                    try await accountManager.reauthenticateAccount(account)
                    print("Successfully re-authenticated: \(emailAddress)")
                } catch {
                    print("Re-authentication failed for \(emailAddress): \(error)")
                    
                    // Show specific error message to user
                    await MainActor.run {
                        if let accountError = error as? AccountError {
                            emailService.errorMessage = accountError.errorDescription
                        } else {
                            emailService.errorMessage = "Failed to sign in to \(emailAddress). Please try again."
                        }
                    }
                    return // Don't continue if re-auth fails
                }
            }
        }
        
        // After successful re-authentication, try to refresh emails
        print("Re-authentication completed, refreshing emails...")
        await emailService.refreshEmails()
    }
    
    private func signOutAccount(_ account: GmailAccount) {
        accountManager.signOut(account: account)
        
        // Clear any existing emails and errors
        emailService.emails.removeAll()
        emailService.filteredEmails.removeAll()
        emailService.errorMessage = nil
        emailService.authenticationErrors.removeValue(forKey: account.email)
    }
    
    private func signOutAllAccounts() {
        accountManager.signOutAllAccounts()
        
        // Clear all email data
        emailService.emails.removeAll()
        emailService.filteredEmails.removeAll()
        emailService.errorMessage = nil
        emailService.authenticationErrors.removeAll()
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if emailService.isLoading {
                    ProgressView("Loading emails...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = emailService.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: hasAuthenticationErrors ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(hasAuthenticationErrors ? .blue : .orange)
                        
                        Text(hasAuthenticationErrors ? "Authentication Required" : "Unable to Load Emails")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(errorMessage)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        if hasAuthenticationErrors {
                            VStack(spacing: 12) {
                                Button("Sign In Again") {
                                    Task {
                                        await reauthenticateAccounts()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Button("Retry") {
                                    Task {
                                        await emailService.refreshEmails()
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            Button("Retry") {
                                Task {
                                    await emailService.refreshEmails()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if emailService.filteredEmails.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("No Emails")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Pull to refresh or check your filter settings")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(emailService.filteredEmails) { email in
                            NavigationLink(destination: EmailDetailView(email: email, emailService: emailService)) {
                                EmailRowView(email: email, emailService: emailService)
                            }
                        }
                    }
                    .refreshable {
                        await emailService.refreshEmails()
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingFilters = true
                    }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: {
                            Task {
                                await emailService.refreshEmails()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        
                        Menu {
                            Section {
                                ForEach(accountManager.accounts, id: \.id) { account in
                                    Button("Sign out \(account.email)") {
                                        signOutAccount(account)
                                    }
                                }
                            }
                            
                            if accountManager.accounts.count > 1 {
                                Divider()
                                Button("Sign out all accounts", role: .destructive) {
                                    signOutAllAccounts()
                                }
                            }
                        } label: {
                            Image(systemName: "person.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterView(emailService: emailService, accountManager: accountManager)
            }
        }
        .onAppear {
            if !hasInitialized {
                hasInitialized = true
                
                // Update the emailService to use the environment's accountManager
                emailService.updateAccountManager(accountManager)
                
                Task {
                    print("EmailListView onAppear - Loading emails for \(accountManager.accounts.count) accounts")
                    if accountManager.accounts.isEmpty {
                        print("No accounts found - user should be redirected to setup")
                    } else {
                        print("Found accounts: \(accountManager.accounts.map(\.email))")
                        await emailService.refreshEmails()
                    }
                }
            }
        }
    }
}

struct EmailRowView: View {
    let email: Email
    let emailService: EmailService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(email.sender.displayName)
                            .font(.headline)
                            .fontWeight(email.isRead ? .regular : .semibold)
                        
                        Spacer()
                        
                        if email.isStarred {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                        
                        Text(email.date, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(email.subject)
                        .font(.subheadline)
                        .fontWeight(email.isRead ? .regular : .medium)
                        .lineLimit(1)
                    
                    Text(email.body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                if !email.isRead {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                }
            }
            
            HStack {
                Text(email.accountEmail)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
                
                Spacer()
                
                ForEach(email.labels.prefix(2), id: \.self) { label in
                    Text(label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.gray.opacity(0.1))
                        .foregroundColor(.gray)
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(action: {
                emailService.toggleStar(email)
            }) {
                Image(systemName: email.isStarred ? "star.slash" : "star")
            }
            .tint(.yellow)
            
            Button(action: {
                if !email.isRead {
                    emailService.markAsRead(email)
                }
            }) {
                Image(systemName: email.isRead ? "envelope.badge" : "envelope.open")
            }
            .tint(.blue)
        }
    }
}

#Preview {
    EmailListView()
        .environmentObject(AccountManager())
}