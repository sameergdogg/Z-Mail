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
        loadAccounts()
        checkExistingSignIn()
    }
    
    func checkExistingSignIn() {
        if let user = GIDSignIn.sharedInstance.currentUser {
            DispatchQueue.main.async {
                if !self.signedInUsers.contains(where: { $0.profile?.email == user.profile?.email }) {
                    self.signedInUsers.append(user)
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
        
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController, hint: nil, additionalScopes: ["https://www.googleapis.com/auth/gmail.readonly"])
        
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
    
    @MainActor
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
        signedInUsers.removeAll { $0.profile?.email == account.email }
        
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
        guard let data = userDefaults.data(forKey: accountsKey),
              let accounts = try? JSONDecoder().decode([GmailAccount].self, from: data) else {
            return
        }
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