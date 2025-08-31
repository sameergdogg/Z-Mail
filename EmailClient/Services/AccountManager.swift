import Foundation
import SwiftUI
import GoogleSignIn

class AccountManager: ObservableObject {
    @Published var accounts: [GmailAccount] = []
    @Published var isLoading = false
    @Published var signedInUsers: [GIDGoogleUser] = []
    
    private let userDefaults = UserDefaults.standard
    private let accountsKey = "gmail_accounts"
    
    init() {
        print("👤 AccountManager init() - Loading accounts...")
        loadAccounts()
        print("👤 Loaded \(accounts.count) accounts: \(accounts.map(\.email))")
        checkExistingSignIn()
    }
    
    func checkExistingSignIn() {
        print("👤 checkExistingSignIn() - Checking for existing Google sign-in...")
        
        // First check if there's already a current user
        if let user = GIDSignIn.sharedInstance.currentUser {
            print("👤 Found existing signed-in user: \(user.profile?.email ?? "unknown")")
            DispatchQueue.main.async {
                if !self.signedInUsers.contains(where: { $0.profile?.email == user.profile?.email }) {
                    print("👤 Adding user to signedInUsers array")
                    self.signedInUsers.append(user)
                } else {
                    print("👤 User already in signedInUsers array")
                }
            }
            return
        }
        
        print("👤 No current user found, attempting to restore previous sign-in...")
        
        // Try to restore previous sign-in for accounts we have stored
        for account in accounts {
            print("👤 Attempting to restore sign-in for \(account.email)")
            Task {
                do {
                    if let restoredUser = try await attemptRestoreSignIn(for: account) {
                        await MainActor.run {
                            print("✅ Successfully restored sign-in for \(account.email)")
                            if !self.signedInUsers.contains(where: { $0.profile?.email == restoredUser.profile?.email }) {
                                self.signedInUsers.append(restoredUser)
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
        print("👤 attemptRestoreSignIn() for \(account.email)")
        
        // Try to restore the previous sign-in using Google Sign-In SDK
        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error = error {
                    print("❌ Failed to restore previous sign-in: \(error)")
                    continuation.resume(throwing: error)
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
    
    func signInWithGoogle() async throws {
        await MainActor.run {
            self.isLoading = true
        }
        
        defer {
            Task { @MainActor in
                self.isLoading = false
            }
        }
        
        guard let presentingViewController = await UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first?.rootViewController else {
            throw AccountError.noPresentingViewController
        }
        
        print("👤 Starting Google Sign-In with Gmail readonly scope...")
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController, 
            hint: nil, 
            additionalScopes: ["https://www.googleapis.com/auth/gmail.readonly"]
        )
        print("✅ Google Sign-In completed successfully")
        
        await MainActor.run {
            let user = result.user
            
            if let email = user.profile?.email {
                let account = GmailAccount(
                    email: email,
                    displayName: user.profile?.name,
                    accessToken: user.accessToken.tokenString,
                    refreshToken: user.refreshToken.tokenString
                )
                
                if !self.accounts.contains(where: { $0.email == email }) {
                    self.accounts.append(account)
                    self.saveAccounts()
                }
                
                if !self.signedInUsers.contains(where: { $0.profile?.email == email }) {
                    self.signedInUsers.append(user)
                }
            }
        }
    }
    
    func refreshTokenForUser(_ user: GIDGoogleUser) async throws {
        do {
            try await user.refreshTokensIfNeeded()
            
            await MainActor.run {
                if let email = user.profile?.email,
                   let index = self.accounts.firstIndex(where: { $0.email == email }) {
                    var updatedAccount = self.accounts[index]
                    updatedAccount.accessToken = user.accessToken.tokenString
                    updatedAccount.refreshToken = user.refreshToken.tokenString
                    self.accounts[index] = updatedAccount
                    self.saveAccounts()
                }
            }
        } catch {
            print("Token refresh failed for user: \(user.profile?.email ?? "unknown"), error: \(error)")
            throw AccountError.tokenRefreshFailed
        }
    }
    
    func validateAndRefreshTokenForUser(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        do {
            try await user.refreshTokensIfNeeded()
            
            await MainActor.run {
                if let email = user.profile?.email,
                   let index = self.accounts.firstIndex(where: { $0.email == email }) {
                    var updatedAccount = self.accounts[index]
                    updatedAccount.accessToken = user.accessToken.tokenString
                    updatedAccount.refreshToken = user.refreshToken.tokenString
                    self.accounts[index] = updatedAccount
                    self.saveAccounts()
                }
            }
            
            return user
            
        } catch {
            print("Token validation failed for user: \(user.profile?.email ?? "unknown"), error: \(error)")
            
            // If refresh fails, try to sign in again silently
            do {
                let result = try await reauthenticateUser(user)
                return result
            } catch {
                // If silent re-auth also fails, mark user as needing full re-authentication
                await MainActor.run {
                    if let email = user.profile?.email {
                        self.signedInUsers.removeAll { $0.profile?.email == email }
                    }
                }
                throw AccountError.reauthenticationRequired
            }
        }
    }
    
    private func reauthenticateUser(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        print("Attempting to reauthenticate user: \(user.profile?.email ?? "unknown")")
        
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
                        var updatedAccount = self.accounts[accountIndex]
                        updatedAccount.accessToken = restoredUser.accessToken.tokenString
                        updatedAccount.refreshToken = restoredUser.refreshToken.tokenString
                        self.accounts[accountIndex] = updatedAccount
                        self.saveAccounts()
                    }
                }
                
                print("Successfully restored authentication for: \(user.profile?.email ?? "unknown")")
                return restoredUser
            }
        } catch {
            print("Failed to restore previous sign-in for \(user.profile?.email ?? "unknown"): \(error)")
        }
        
        // If restore fails, the user needs to manually sign in again
        throw AccountError.reauthenticationRequired
    }
    
    func requiresReauthentication(for account: GmailAccount) -> Bool {
        return !signedInUsers.contains { $0.profile?.email == account.email }
    }
    
    func reauthenticateAccount(_ account: GmailAccount) async throws {
        print("Starting re-authentication for account: \(account.email)")
        
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
        
        do {
            // Attempt to sign in the specific account
            guard let presentingViewController = await UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first?.rootViewController else {
                throw AccountError.noPresentingViewController
            }
            
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController,
                hint: account.email,
                additionalScopes: ["https://www.googleapis.com/auth/gmail.readonly"]
            )
            
            let user = result.user
            
            // Verify this is the correct account
            guard user.profile?.email == account.email else {
                throw AccountError.signInFailed
            }
            
            // Update the account with new tokens
            await MainActor.run {
                if let index = accounts.firstIndex(where: { $0.email == account.email }) {
                    var updatedAccount = accounts[index]
                    updatedAccount.accessToken = user.accessToken.tokenString
                    updatedAccount.refreshToken = user.refreshToken.tokenString
                    accounts[index] = updatedAccount
                    saveAccounts()
                }
                
                // Add the user to signed in users
                if !signedInUsers.contains(where: { $0.profile?.email == account.email }) {
                    signedInUsers.append(user)
                }
            }
            
            print("Successfully re-authenticated account: \(account.email)")
            
        } catch {
            print("Failed to re-authenticate account \(account.email): \(error)")
            throw error
        }
    }
    
    func signOut(account: GmailAccount) {
        // Remove the account from our local storage
        accounts.removeAll { $0.id == account.id }
        signedInUsers.removeAll { $0.profile?.email == account.email }
        
        // Only sign out from Google if this is the last account
        if accounts.isEmpty {
            GIDSignIn.sharedInstance.signOut()
        }
        
        saveAccounts()
        print("Signed out account: \(account.email)")
    }
    
    func signOutAllAccounts() {
        // Sign out from Google completely
        GIDSignIn.sharedInstance.signOut()
        
        // Clear all local data
        accounts.removeAll()
        signedInUsers.removeAll()
        
        saveAccounts()
        print("Signed out all accounts")
    }
    
    func removeAccount(_ account: GmailAccount) {
        accounts.removeAll { $0.id == account.id }
        signedInUsers.removeAll { $0.profile?.email == account.email }
        saveAccounts()
    }
    
    func getUserForAccount(_ account: GmailAccount) -> GIDGoogleUser? {
        return signedInUsers.first { $0.profile?.email == account.email }
    }
    
    
    private func loadAccounts() {
        print("👤 loadAccounts() - Checking UserDefaults for key: \(accountsKey)")
        guard let data = userDefaults.data(forKey: accountsKey) else {
            print("👤 No account data found in UserDefaults")
            return
        }
        
        guard let accounts = try? JSONDecoder().decode([GmailAccount].self, from: data) else {
            print("👤 Failed to decode account data")
            return
        }
        
        print("👤 Successfully loaded \(accounts.count) accounts from UserDefaults")
        self.accounts = accounts
    }
    
    private func saveAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        userDefaults.set(data, forKey: accountsKey)
    }
}

enum AccountError: Error, LocalizedError {
    case noPresentingViewController
    case signInFailed
    case tokenRefreshFailed
    case reauthenticationRequired
    case networkError
    case invalidCredentials
    
    var errorDescription: String? {
        switch self {
        case .noPresentingViewController:
            return "Unable to present sign-in view"
        case .signInFailed:
            return "Sign-in failed"
        case .tokenRefreshFailed:
            return "Failed to refresh authentication token"
        case .reauthenticationRequired:
            return "Please sign in again to continue"
        case .networkError:
            return "Network connection error"
        case .invalidCredentials:
            return "Invalid or expired credentials"
        }
    }
}