import SwiftUI

struct EmailListView: View {
    @EnvironmentObject var accountManager: AccountManagerImpl
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var emailService: EmailServiceImpl
    @State private var showingFilters = false
    @State private var showingSettings = false
    @State private var hasInitialized = false
    @State private var selectedTopFilter: TopLevelFilter = .inbox
    
    init() {
        // Initialize with a temporary AccountManager - will be updated in onAppear
        self._emailService = StateObject(wrappedValue: EmailServiceAPI.create(with: AccountManagerAPI.shared) as! EmailServiceImpl)
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
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // iPhone 16 optimized header
                VStack(spacing: 0) {
                    // Header with proper Dynamic Island spacing
                    HStack(alignment: .center) {
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Text(navigationTitle)
                            .font(.system(size: 34, weight: .bold, design: .default))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: { showingFilters = true }) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .background(Color(UIColor.systemBackground))
                    
                    // Filter pills optimized for iPhone 16
                    EmailFilterScrollView(
                        selectedFilter: $selectedTopFilter,
                        emailService: emailService
                    )
                }
                .background(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
                
                // Content area with proper iPhone 16 spacing
                Group {
                    switch selectedTopFilter {
                    case .inbox:
                        inboxContentView
                    case .senders:
                        SenderListView(emailService: emailService)
                    case .categories:
                        ClassificationCategoriesView()
                            .environmentObject(accountManager)
                            .environmentObject(settingsManager)
                    case .summary:
                        SummaryView(emailService: emailService)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarHidden(true)
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showingFilters) {
                FilterView(emailService: emailService, accountManager: accountManager)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onAppear {
                setupEmailService()
            }
        }
    }
    
    private var navigationTitle: String {
        switch selectedTopFilter {
        case .inbox:
            return "Inbox"
        case .senders:
            return "Senders"
        case .categories:
            return "Categories"
        case .summary:
            return "Summary"
        }
    }
    
    @ViewBuilder
    private var inboxContentView: some View {
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
                        Image(systemName: accountManager.accounts.isEmpty ? "person.badge.plus" : "tray")
                            .font(.system(size: 50))
                            .foregroundColor(accountManager.accounts.isEmpty ? .blue : .gray)
                        
                        Text(accountManager.accounts.isEmpty ? "No Accounts Connected" : "No Emails")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(accountManager.accounts.isEmpty ? 
                             "Connect your Gmail account to see your emails" : 
                             "Pull to refresh or check your filter settings")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        if accountManager.accounts.isEmpty {
                            Button("Add Gmail Account") {
                                showingSettings = true
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Refresh") {
                                Task {
                                    await emailService.refreshEmails()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(emailService.filteredEmails) { email in
                            NavigationLink(destination: EmailDetailView(email: email, emailService: emailService).environmentObject(settingsManager)) {
                                EmailRowView(email: email, emailService: emailService)
                            }
                        }
                    }
                    .refreshable {
                        await emailService.refreshEmails()
                    }
                }
            }
        }
    
    private func setupEmailService() {
        if !hasInitialized {
            hasInitialized = true
            
            // Update the emailService to use the environment's accountManager
            print("📧 EmailListView onAppear - Updating accountManager")
            emailService.updateAccountManager(accountManager)
            
            Task {
                print("📧 EmailListView - Loading emails for \(accountManager.accounts.count) accounts")
                if accountManager.accounts.isEmpty {
                    print("❌ No accounts found - user should see account setup")
                    await MainActor.run {
                        emailService.errorMessage = "No Gmail accounts connected. Please add an account to continue."
                    }
                } else {
                    print("✅ Found accounts: \(accountManager.accounts.map(\.email))")
                    print("📧 Loading emails from persistence on startup...")
                    await emailService.loadEmailsOnLaunch()
                    print("📧 Email load from persistence completed")
                }
            }
        }
    }
}

struct EmailRowView: View {
    let email: Email
    let emailService: EmailServiceProtocol
    
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
                Task {
                    await emailService.toggleStar(email)
                }
            }) {
                Image(systemName: email.isStarred ? "star.slash" : "star")
            }
            .tint(.yellow)
            
            Button(action: {
                if !email.isRead {
                    Task {
                        await emailService.markAsRead(email)
                    }
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
        .environmentObject(AccountManagerAPI.shared as! AccountManagerImpl)
        .environmentObject(SettingsManager())
}