import Foundation
import SwiftUI
import GoogleSignIn
import Combine

/// Implementation of Account Manager Protocol
internal class AccountManagerImpl: AccountManagerProtocol {
    
    // MARK: - Published Properties
    
    @Published public private(set) var accounts: [GmailAccount] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var signedInUsers: [GIDGoogleUser] = []
    
    // MARK: - Private Properties
    
    private let dependencies: AccountManagerDependencies
    private let configuration: AccountManagerConfiguration
    private let persistenceStore: AccountPersistenceProtocol
    private let accountChangesSubject = PassthroughSubject<AccountChangeEvent, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    public var accountChanges: AnyPublisher<AccountChangeEvent, Never> {
        accountChangesSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    internal init(dependencies: AccountManagerDependencies) {
        self.dependencies = dependencies
        self.configuration = dependencies.configuration
        self.persistenceStore = dependencies.persistenceStore
        
        print("🏗️ AccountManagerImpl initializing...")
        
        setupGoogleSignIn()
        loadPersistedAccounts()
        
        if configuration.enableAutoSignInRestore {
            checkExistingSignIn()
        }
        
        print("✅ AccountManagerImpl initialized with \(accounts.count) accounts")
    }
    
    // MARK: - Setup Methods
    
    private func setupGoogleSignIn() {
        if let config = dependencies.googleSignInConfig {
            GIDSignIn.sharedInstance.configuration = config
        }
    }
    
    private func loadPersistedAccounts() {
        guard configuration.enableAccountPersistence else {
            print("📱 Account persistence disabled")
            return
        }
        
        do {
            let loadedAccounts = try persistenceStore.loadAccounts()
            DispatchQueue.main.async {
                self.accounts = loadedAccounts
            }
            print("📱 Loaded \(loadedAccounts.count) persisted accounts")
        } catch {
            print("❌ Failed to load persisted accounts: \(error)")
        }
    }
    
    private func saveAccountsIfNeeded() {
        guard configuration.enableAccountPersistence else { return }
        
        do {
            try persistenceStore.saveAccounts(accounts)
        } catch {
            print("❌ Failed to save accounts: \(error)")
        }
    }
    
    // MARK: - Sign-In Restoration
    
    private func checkExistingSignIn() {
        print("👤 Checking for existing Google sign-in...")
        
        // First check if there's already a current user
        if let user = GIDSignIn.sharedInstance.currentUser {
            print("👤 Found existing signed-in user: \(user.profile?.email ?? "unknown")")
            DispatchQueue.main.async {
                if !self.signedInUsers.contains(where: { $0.profile?.email == user.profile?.email }) {
                    self.signedInUsers.append(user)
                    self.accountChangesSubject.send(.userSignedIn(user))
                }
            }
            return
        }
        
        print("👤 No current user found, attempting to restore previous sign-in...")
        
        // Try to restore previous sign-in for accounts we have stored
        for account in accounts {
            Task {
                do {
                    if let restoredUser = try await attemptRestoreSignIn(for: account) {
                        await MainActor.run {
                            print("✅ Successfully restored sign-in for \(account.email)")
                            if !self.signedInUsers.contains(where: { $0.profile?.email == restoredUser.profile?.email }) {
                                self.signedInUsers.append(restoredUser)
                                self.accountChangesSubject.send(.userSignedIn(restoredUser))
                            }
                        }
                    }
                } catch {
                    print("❌ Failed to restore sign-in for \(account.email): \(error)")
                }
            }
        }
    }
    
    private func attemptRestoreSignIn(for account: GmailAccount) async throws -> GIDGoogleUser? {
        print("👤 Attempting to restore sign-in for \(account.email)")
        
        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error = error {
                    print("❌ Failed to restore previous sign-in: \(error)")
                    continuation.resume(throwing: AccountError.tokenRefreshFailed)
                } else if let user = user, user.profile?.email == account.email {
                    print("✅ Restored previous sign-in for \(account.email)")
                    continuation.resume(returning: user)
                } else {
                    print("❌ No matching user found for \(account.email)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    // MARK: - Public API Implementation
    
    public func signInWithGoogle() async throws {
        print("🔐 Starting Google sign-in process...")
        
        await MainActor.run {
            self.isLoading = true
        }
        
        defer {
            Task { @MainActor in
                self.isLoading = false
            }
        }
        
        // Check account limit
        if accounts.count >= configuration.maxAccountLimit {
            throw AccountError.signInFailed // Could add a specific error for account limit
        }
        
        guard let presentingViewController = await getPresentingViewController() else {
            throw AccountError.noPresentingViewController
        }
        
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            hint: nil,
            additionalScopes: configuration.gmailScopes
        )
        
        await MainActor.run {
            let user = result.user
            
            guard let email = user.profile?.email else {
                print("❌ No email found in user profile")
                return
            }
            
            // Check for duplicate account
            if self.accounts.contains(where: { $0.email == email }) {
                print("⚠️ Account \(email) already exists")
                return
            }
            
            let account = GmailAccount(
                email: email,
                displayName: user.profile?.name,
                accessToken: user.accessToken.tokenString,
                refreshToken: user.refreshToken.tokenString
            )
            
            self.accounts.append(account)
            self.saveAccountsIfNeeded()
            
            if !self.signedInUsers.contains(where: { $0.profile?.email == email }) {
                self.signedInUsers.append(user)
            }
            
            print("✅ Successfully signed in account: \(email)")
            self.accountChangesSubject.send(.accountAdded(account))
            self.accountChangesSubject.send(.userSignedIn(user))
        }
    }
    
    public func signOut(account: GmailAccount) {
        print("🚪 Signing out account: \(account.email)")
        
        // Remove from arrays
        accounts.removeAll { $0.id == account.id }
        signedInUsers.removeAll { $0.profile?.email == account.email }
        
        // Only sign out from Google if this is the last account
        if accounts.isEmpty {
            GIDSignIn.sharedInstance.signOut()
        }
        
        saveAccountsIfNeeded()
        accountChangesSubject.send(.accountRemoved(account.email))
        accountChangesSubject.send(.userSignedOut(account.email))
        
        print("✅ Signed out account: \(account.email)")
    }
    
    public func signOutAllAccounts() {
        print("🚪 Signing out all accounts...")
        
        // Sign out from Google completely
        GIDSignIn.sharedInstance.signOut()
        
        let accountEmails = accounts.map { $0.email }
        
        // Clear all local data
        accounts.removeAll()
        signedInUsers.removeAll()
        
        saveAccountsIfNeeded()
        
        for email in accountEmails {
            accountChangesSubject.send(.accountRemoved(email))
            accountChangesSubject.send(.userSignedOut(email))
        }
        
        accountChangesSubject.send(.allAccountsCleared)
        print("✅ Signed out all accounts")
    }
    
    public func removeAccount(_ account: GmailAccount) {
        print("🗑️ Removing account: \(account.email)")
        
        accounts.removeAll { $0.id == account.id }
        signedInUsers.removeAll { $0.profile?.email == account.email }
        
        saveAccountsIfNeeded()
        accountChangesSubject.send(.accountRemoved(account.email))
        
        print("✅ Removed account: \(account.email)")
    }
    
    public func getUserForAccount(_ account: GmailAccount) -> GIDGoogleUser? {
        return signedInUsers.first { $0.profile?.email == account.email }
    }
    
    public func refreshTokenForUser(_ user: GIDGoogleUser) async throws {
        print("🔄 Refreshing token for user: \(user.profile?.email ?? "unknown")")
        
        do {
            try await user.refreshTokensIfNeeded()
            
            await MainActor.run {
                if let email = user.profile?.email,
                   let index = self.accounts.firstIndex(where: { $0.email == email }) {
                    let updatedAccount = self.accounts[index].updatingTokens(
                        accessToken: user.accessToken.tokenString,
                        refreshToken: user.refreshToken.tokenString
                    )
                    self.accounts[index] = updatedAccount
                    self.saveAccountsIfNeeded()
                    self.accountChangesSubject.send(.accountUpdated(updatedAccount))
                }
            }
            
            print("✅ Successfully refreshed token for: \(user.profile?.email ?? "unknown")")
        } catch {
            print("❌ Token refresh failed: \(error)")
            throw AccountError.tokenRefreshFailed
        }
    }
    
    public func validateAndRefreshTokenForUser(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        do {
            try await user.refreshTokensIfNeeded()
            
            await MainActor.run {
                if let email = user.profile?.email,
                   let index = self.accounts.firstIndex(where: { $0.email == email }) {
                    let updatedAccount = self.accounts[index].updatingTokens(
                        accessToken: user.accessToken.tokenString,
                        refreshToken: user.refreshToken.tokenString
                    )
                    self.accounts[index] = updatedAccount
                    self.saveAccountsIfNeeded()
                    self.accountChangesSubject.send(.accountUpdated(updatedAccount))
                }
            }
            
            return user
            
        } catch {
            print("❌ Token validation failed: \(error)")
            
            // Try to reauthenticate
            do {
                let reauthenticatedUser = try await reauthenticateUser(user)
                return reauthenticatedUser
            } catch {
                // Remove user if reauthentication fails
                await MainActor.run {
                    if let email = user.profile?.email {
                        self.signedInUsers.removeAll { $0.profile?.email == email }
                        self.accountChangesSubject.send(.userSignedOut(email))
                    }
                }
                throw AccountError.reauthenticationRequired
            }
        }
    }
    
    public func requiresReauthentication(for account: GmailAccount) -> Bool {
        return !signedInUsers.contains { $0.profile?.email == account.email }
    }
    
    public func reauthenticateAccount(_ account: GmailAccount) async throws {
        print("🔑 Re-authenticating account: \(account.email)")
        
        await MainActor.run {
            self.isLoading = true
        }
        
        defer {
            Task { @MainActor in
                self.isLoading = false
            }
        }
        
        // Remove the failed user from signed in users
        await MainActor.run {
            signedInUsers.removeAll { $0.profile?.email == account.email }
        }
        
        guard let presentingViewController = await getPresentingViewController() else {
            throw AccountError.noPresentingViewController
        }
        
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            hint: account.email,
            additionalScopes: configuration.gmailScopes
        )
        
        let user = result.user
        
        // Verify this is the correct account
        guard user.profile?.email == account.email else {
            throw AccountError.signInFailed
        }
        
        // Update the account with new tokens
        await MainActor.run {
            if let index = accounts.firstIndex(where: { $0.email == account.email }) {
                let updatedAccount = accounts[index].updatingTokens(
                    accessToken: user.accessToken.tokenString,
                    refreshToken: user.refreshToken.tokenString
                )
                accounts[index] = updatedAccount
                saveAccountsIfNeeded()
                accountChangesSubject.send(.accountUpdated(updatedAccount))
            }
            
            // Add the user to signed in users
            if !signedInUsers.contains(where: { $0.profile?.email == account.email }) {
                signedInUsers.append(user)
                accountChangesSubject.send(.userSignedIn(user))
            }
        }
        
        print("✅ Successfully re-authenticated account: \(account.email)")
    }
    
    // MARK: - Private Helper Methods
    
    private func reauthenticateUser(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        print("🔄 Attempting to reauthenticate user: \(user.profile?.email ?? "unknown")")
        
        // First try to restore previous sign-in state
        do {
            try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            
            if let restoredUser = GIDSignIn.sharedInstance.currentUser,
               restoredUser.profile?.email == user.profile?.email {
                
                // Test if the restored user actually has valid tokens
                try await restoredUser.refreshTokensIfNeeded()
                
                // Update the user in our array
                await MainActor.run {
                    if let index = self.signedInUsers.firstIndex(where: { $0.profile?.email == user.profile?.email }) {
                        self.signedInUsers[index] = restoredUser
                    } else {
                        self.signedInUsers.append(restoredUser)
                    }
                    
                    // Update stored account info
                    if let accountIndex = self.accounts.firstIndex(where: { $0.email == user.profile?.email }) {
                        let updatedAccount = self.accounts[accountIndex].updatingTokens(
                            accessToken: restoredUser.accessToken.tokenString,
                            refreshToken: restoredUser.refreshToken.tokenString
                        )
                        self.accounts[accountIndex] = updatedAccount
                        self.saveAccountsIfNeeded()
                        self.accountChangesSubject.send(.accountUpdated(updatedAccount))
                    }
                }
                
                print("✅ Successfully restored authentication for: \(user.profile?.email ?? "unknown")")
                return restoredUser
            }
        } catch {
            print("❌ Failed to restore previous sign-in: \(error)")
        }
        
        // If restore fails, the user needs to manually sign in again
        throw AccountError.reauthenticationRequired
    }
    
    private func getPresentingViewController() async -> UIViewController? {
        return await UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first?.rootViewController
    }
}