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
    }
    
    func signOut(account: GmailAccount) {
        GIDSignIn.sharedInstance.signOut()
        
        accounts.removeAll { $0.id == account.id }
        signedInUsers.removeAll { $0.profile?.email == account.email }
        
        saveAccounts()
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

enum AccountError: Error {
    case noPresentingViewController
    case signInFailed
    case tokenRefreshFailed
}