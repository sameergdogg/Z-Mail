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
    @State private var showingClearSummariesAlert = false
    @State private var clearSummariesMessage: String?
    @State private var showingClearSummariesResult = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.clear.background(.ultraThinMaterial)
                List {
                    emailDisplaySection
                    accountsSection
                    aiFeaturesSection
                    appInformationSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                if let account = accountToSignOut {
                    signOutAccount(account)
                    accountToSignOut = nil
                } else {
                    signOutAllAccounts()
                }
            }
        } message: {
            Text(accountToSignOut != nil ? 
                "Are you sure you want to sign out of \(accountToSignOut!.email)?" :
                "Are you sure you want to sign out of all accounts?")
        }
        .alert("Classification Complete", isPresented: $showingClassificationAlert) {
            Button("OK") { }
        } message: {
            Text("Email classification has been completed!")
        }
        .alert("Add Account Error", isPresented: $showingAddAccountAlert) {
            Button("OK") { }
        } message: {
            Text(addAccountError ?? "Unknown error")
        }
        .alert("Clear All Summaries", isPresented: $showingClearSummariesAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearAllSummaries()
            }
        } message: {
            Text("This will permanently delete all saved daily digests. This cannot be undone.")
        }
        .alert("Summaries Cleared", isPresented: $showingClearSummariesResult) {
            Button("OK") { }
        } message: {
            Text(clearSummariesMessage ?? "All summaries have been deleted.")
        }
    }
    
    // MARK: - View Sections
    
    private var emailDisplaySection: some View {
        Section("Email Display") {
            emailRenderingPicker
            renderingPreview
        }
    }
    
    private var emailRenderingPicker: some View {
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
    }
    
    private var renderingPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            RenderingPreviewView(useRichRendering: settingsManager.useRichEmailRendering)
        }
        .padding(.vertical, 8)
    }
    
    private var accountsSection: some View {
        Section("Accounts") {
            accountsList
            addAccountButton
            signOutAllButton
        }
    }
    
    private var accountsList: some View {
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
    }
    
    private var addAccountButton: some View {
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
    }
    
    @ViewBuilder
    private var signOutAllButton: some View {
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
    
    private var aiFeaturesSection: some View {
        Section("AI Features") {
            classificationSettingsLink
            fullClassificationButton
            clearSummariesButton
        }
    }
    
    private var classificationSettingsLink: some View {
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
    }
    
    @ViewBuilder
    private var fullClassificationButton: some View {
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
    
    private var clearSummariesButton: some View {
        Button(action: {
            showingClearSummariesAlert = true
        }) {
            HStack {
                Image(systemName: "text.badge.minus")
                    .foregroundColor(.red)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clear All Summaries")
                        .font(.body)
                        .foregroundColor(.primary)
                    Text("Delete all saved daily digests")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var appInformationSection: some View {
        Section("App Information") {
            versionRow
            githubLink
        }
    }
    
    private var versionRow: some View {
        HStack {
            Text("Version")
            Spacer()
            Text("1.0.0")
                .foregroundColor(.secondary)
        }
    }
    
    private var githubLink: some View {
        Link(destination: URL(string: "https://github.com")!) {
            HStack {
                Text("Source Code")
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.blue)
            }
        }
    }
    
    // MARK: - Action Methods
    
    private func addNewAccount() {
        Task { @MainActor in
            do {
                try await accountManager.signInWithGoogle()
                addAccountError = nil
            } catch {
                addAccountError = error.localizedDescription
                showingAddAccountAlert = true
            }
        }
    }
    
    private func signOutAccount(_ account: GmailAccount) {
        accountManager.signOut(account: account)
    }
    
    private func signOutAllAccounts() {
        accountManager.signOutAllAccounts()
    }
    
    private func reauthenticateAccount(_ account: GmailAccount) {
        Task { @MainActor in
            do {
                try await accountManager.signInWithGoogle()
            } catch {
                reauthenticationError = error.localizedDescription
                showingReauthAlert = true
            }
        }
    }
    
    private func clearAllSummaries() {
        do {
            let count = try appDataManager.clearAllSummaries()
            clearSummariesMessage = count == 0
                ? "No summaries were found to delete."
                : "Deleted \(count) saved \(count == 1 ? "summary" : "summaries")."
        } catch {
            clearSummariesMessage = "Failed to clear summaries: \(error.localizedDescription)"
        }
        showingClearSummariesResult = true
    }

    private func runFullClassification() {
        print("🧠 SettingsView.runFullClassification() — button tapped")
        Task { @MainActor in
            isRunningFullClassification = true

            do {
                print("🧠 SettingsView — calling appDataManager.forceFullClassification()")
                await appDataManager.forceFullClassification()
                print("🧠 SettingsView — forceFullClassification() returned")

                // Get statistics after classification
                let stats = await appDataManager.getClassificationStatistics()
                print("🧠 SettingsView — stats: \(stats != nil ? "got stats, total=\(stats!.totalEmails)" : "nil")")

                classificationResultMessage = stats != nil ?
                "Successfully classified emails!" :
                "Classification completed!"

                showingClassificationAlert = true
            }

            isRunningFullClassification = false
        }
    }
}

// MARK: - Supporting Views

struct AccountRowView: View {
    let account: GmailAccount
    let onSignOut: () -> Void
    let onReauthenticate: () -> Void
    @EnvironmentObject var accountManager: AccountManagerImpl
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.email)
                    .font(.body)
                    .lineLimit(1)
                
                Text(account.isActive ? "Active" : "Needs Re-authentication")
                    .font(.caption)
                    .foregroundColor(account.isActive ? .green : .orange)
            }
            
            Spacer()
            
            if !account.isActive {
                Button("Re-authenticate") {
                    onReauthenticate()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(accountManager.isLoading)
            }
            
            Button("Sign Out") {
                onSignOut()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
            .disabled(accountManager.isLoading)
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
        .environmentObject(AccountManagerImpl.shared)
        .environmentObject(SettingsManager())
}
