import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var accountManager: AccountManagerImpl
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appDataManager) var appDataManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingSignOutAlert = false
    @State private var accountToSignOut: GmailAccount?
    @State private var isReauthenticating = false
    @State private var reauthenticationError: String?
    @State private var showingReauthAlert = false
    @State private var isRunningFullClassification = false
    @State private var classificationResultMessage: String?
    @State private var showingClassificationAlert = false
    @State private var addAccountError: String?
    @State private var showingAddAccountAlert = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Email Display") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Email Rendering")
                                .font(.body)
                            Text("Choose how emails are displayed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Picker("Email Rendering", selection: $settingsManager.useRichEmailRendering) {
                            Text("Plain Text").tag(false)
                            Text("Rich HTML").tag(true)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 140)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        RenderingPreviewView(useRichRendering: settingsManager.useRichEmailRendering)
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Accounts") {
                    ForEach(accountManager.accounts, id: \.id) { account in
                        AccountRowView(
                            account: account,
                            onSignOut: {
                                accountToSignOut = account
                                showingSignOutAlert = true
                            },
                            onReauthenticate: {
                                reauthenticateAccount(account)
                            }
                        )
                    }
                    
                    Button(action: {
                        addNewAccount()
                    }) {
                        HStack {
                            Image(systemName: "person.badge.plus")
                                .foregroundColor(.blue)
                            Text("Add Account")
                                .foregroundColor(.blue)
                            
                            if accountManager.isLoading {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(accountManager.isLoading)
                    
                    if accountManager.accounts.count > 1 {
                        Button(action: {
                            showingSignOutAlert = true
                        }) {
                            HStack {
                                Image(systemName: "person.2.slash")
                                    .foregroundColor(.red)
                                Text("Sign Out All Accounts")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                
                Section("AI Features") {
                    NavigationLink(destination: ClassificationSettingsView()) {
                        HStack {
                            Image(systemName: "brain")
                                .foregroundColor(.purple)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Email Classification")
                                    .font(.body)
                                Text("AI-powered email categorization")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if SecureConfigurationManager.shared.hasOpenAIAPIKey() {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    
                    if SecureConfigurationManager.shared.hasOpenAIAPIKey() && appDataManager.isInitialized {
                        Button(action: {
                            runFullClassification()
                        }) {
                            HStack {
                                Image(systemName: isRunningFullClassification ? "arrow.clockwise" : "wand.and.stars")
                                    .foregroundColor(.blue)
                                    .font(.title2)
                                    .rotationEffect(.degrees(isRunningFullClassification ? 360 : 0))
                                    .animation(isRunningFullClassification ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRunningFullClassification)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Run Full Classification")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(isRunningFullClassification ? "Classifying all emails..." : "Re-classify all emails with AI")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if isRunningFullClassification {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .disabled(isRunningFullClassification)
                    }
                }
                
                Section("App Information") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com")!) {
                        HStack {
                            Text("Source Code")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                if let account = accountToSignOut {
                    Button("Cancel", role: .cancel) {
                        accountToSignOut = nil
                    }
                    Button("Sign Out", role: .destructive) {
                        signOutAccount(account)
                        accountToSignOut = nil
                    }
                } else {
                    Button("Cancel", role: .cancel) { }
                    Button("Sign Out All", role: .destructive) {
                        signOutAllAccounts()
                    }
                }
            } message: {
                if let account = accountToSignOut {
                    Text("Are you sure you want to sign out of \(account.email)?")
                } else {
                    Text("Are you sure you want to sign out of all accounts?")
                }
            }
            .alert(
                reauthenticationError == nil ? "Reauthentication Successful" : "Reauthentication Failed",
                isPresented: $showingReauthAlert
            ) {
                Button("OK") {
                    reauthenticationError = nil
                }
            } message: {
                if let error = reauthenticationError {
                    Text("Failed to reauthenticate: \(error)")
                } else {
                    Text("Account has been successfully reauthenticated with Google.")
                }
            }
            .alert("Classification Complete", isPresented: $showingClassificationAlert) {
                Button("OK") {
                    classificationResultMessage = nil
                }
            } message: {
                if let message = classificationResultMessage {
                    Text(message)
                } else {
                    Text("Full email classification has been completed successfully.")
                }
            }
            .alert("Add Account Failed", isPresented: $showingAddAccountAlert) {
                Button("OK") {
                    addAccountError = nil
                }
            } message: {
                if let error = addAccountError {
                    Text("Failed to add account: \(error)")
                } else {
                    Text("An unknown error occurred while adding the account.")
                }
            }
            .disabled(isReauthenticating || accountManager.isLoading)
        }
    }
    
    private func signOutAccount(_ account: GmailAccount) {
        accountManager.signOut(account: account)
    }
    
    private func signOutAllAccounts() {
        accountManager.signOutAllAccounts()
    }
    
    private func reauthenticateAccount(_ account: GmailAccount) {
        Task {
            await MainActor.run {
                isReauthenticating = true
                reauthenticationError = nil
            }
            
            do {
                try await accountManager.reauthenticateAccount(account)
                
                await MainActor.run {
                    isReauthenticating = false
                    reauthenticationError = nil
                    showingReauthAlert = true
                }
                
            } catch {
                await MainActor.run {
                    isReauthenticating = false
                    reauthenticationError = error.localizedDescription
                    showingReauthAlert = true
                }
            }
        }
    }
    
    private func addNewAccount() {
        Task {
            do {
                print("🔐 Adding new Google account from Settings...")
                try await accountManager.signInWithGoogle()
                print("✅ Successfully added new account")
                
            } catch {
                await MainActor.run {
                    addAccountError = error.localizedDescription
                    showingAddAccountAlert = true
                }
                print("❌ Failed to add account: \(error)")
            }
        }
    }
    
    private func runFullClassification() {
        Task {
            await MainActor.run {
                isRunningFullClassification = true
                classificationResultMessage = nil
            }
            
            do {
                print("🤖 Starting full email classification from Settings...")
                await appDataManager.forceFullClassification()
                
                // Get classification statistics if available
                if let stats = await appDataManager.getClassificationStatistics() {
                    await MainActor.run {
                        isRunningFullClassification = false
                        classificationResultMessage = "Successfully classified \(stats.totalEmails) emails across \(stats.categoryCounts.count) categories."
                        showingClassificationAlert = true
                    }
                    print("✅ Full classification completed - Total: \(stats.totalEmails) emails")
                } else {
                    await MainActor.run {
                        isRunningFullClassification = false
                        classificationResultMessage = "Full email classification completed successfully."
                        showingClassificationAlert = true
                    }
                    print("✅ Full classification completed")
                }
                
            } catch {
                await MainActor.run {
                    isRunningFullClassification = false
                    classificationResultMessage = "Classification failed: \(error.localizedDescription)"
                    showingClassificationAlert = true
                }
                print("❌ Full classification failed: \(error)")
            }
        }
    }
}

struct AccountRowView: View {
    let account: GmailAccount
    let onSignOut: () -> Void
    let onReauthenticate: () -> Void
    @EnvironmentObject var accountManager: AccountManagerImpl
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName ?? "Unknown")
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(account.email)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                Button(action: onReauthenticate) {
                    if accountManager.isLoading {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Authenticating...")
                        }
                    } else {
                        Text("Reauthenticate")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(accountManager.isLoading)
                
                Button("Sign Out") {
                    onSignOut()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .disabled(accountManager.isLoading)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RenderingPreviewView: View {
    let useRichRendering: Bool
    
    private let sampleHTML = """
    <p>This is a <strong>sample email</strong> with <em>formatting</em>.</p>
    <p><a href="#">Click here</a> for more information.</p>
    """
    
    private let samplePlain = "This is a sample email with formatting.\nClick here for more information."
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if useRichRendering {
                Text("Rich HTML rendering with links, bold text, and formatting")
                    .font(.caption2)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(6)
            } else {
                Text("Plain text rendering - all formatting removed")
                    .font(.caption2)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(6)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AccountManagerAPI.shared as! AccountManagerImpl)
        .environmentObject(SettingsManager())
}