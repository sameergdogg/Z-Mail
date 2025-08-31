import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var accountManager: AccountManager
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingSignOutAlert = false
    @State private var accountToSignOut: GmailAccount?
    @State private var isReauthenticating = false
    @State private var reauthenticationError: String?
    @State private var showingReauthAlert = false
    
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
}

struct AccountRowView: View {
    let account: GmailAccount
    let onSignOut: () -> Void
    let onReauthenticate: () -> Void
    @EnvironmentObject var accountManager: AccountManager
    
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
        .environmentObject(AccountManager())
        .environmentObject(SettingsManager())
}