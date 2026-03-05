import Foundation
import SwiftUI
import GoogleSignIn
import Combine

// MARK: - GmailAccount model

public struct GmailAccount: Codable, Identifiable, Hashable {
    public let id: String
    public let email: String
    public let displayName: String?
    public var accessToken: String
    public var refreshToken: String
    public let createdAt: Date
    public var lastUsed: Date
    public var isActive: Bool

    public init(
        email: String,
        displayName: String?,
        accessToken: String,
        refreshToken: String
    ) {
        self.id = UUID().uuidString
        self.email = email
        self.displayName = displayName
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.createdAt = Date()
        self.lastUsed = Date()
        self.isActive = true
    }

    internal init(
        id: String,
        email: String,
        displayName: String?,
        accessToken: String,
        refreshToken: String,
        createdAt: Date,
        lastUsed: Date,
        isActive: Bool
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.createdAt = createdAt
        self.lastUsed = lastUsed
        self.isActive = isActive
    }

    public func updatingTokens(accessToken: String, refreshToken: String) -> GmailAccount {
        return GmailAccount(
            id: self.id, email: self.email, displayName: self.displayName,
            accessToken: accessToken, refreshToken: refreshToken,
            createdAt: self.createdAt, lastUsed: Date(), isActive: self.isActive
        )
    }

    public func markAsUsed() -> GmailAccount {
        return GmailAccount(
            id: self.id, email: self.email, displayName: self.displayName,
            accessToken: self.accessToken, refreshToken: self.refreshToken,
            createdAt: self.createdAt, lastUsed: Date(), isActive: self.isActive
        )
    }

    public func settingActive(_ active: Bool) -> GmailAccount {
        return GmailAccount(
            id: self.id, email: self.email, displayName: self.displayName,
            accessToken: self.accessToken, refreshToken: self.refreshToken,
            createdAt: self.createdAt, lastUsed: self.lastUsed, isActive: active
        )
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(email)
    }

    public static func == (lhs: GmailAccount, rhs: GmailAccount) -> Bool {
        return lhs.id == rhs.id && lhs.email == rhs.email
    }
}

// MARK: - AccountError

public enum AccountError: Error, LocalizedError {
    case noPresentingViewController
    case signInFailed
    case tokenRefreshFailed
    case reauthenticationRequired
    case networkError
    case invalidCredentials
    case accountNotFound(String)
    case duplicateAccount
    case persistenceError(Error)

    public var errorDescription: String? {
        switch self {
        case .noPresentingViewController: return "Unable to present sign-in view"
        case .signInFailed: return "Sign-in failed"
        case .tokenRefreshFailed: return "Failed to refresh authentication token"
        case .reauthenticationRequired: return "Please sign in again to continue"
        case .networkError: return "Network connection error"
        case .invalidCredentials: return "Invalid or expired credentials"
        case .accountNotFound(let email): return "Account '\(email)' not found"
        case .duplicateAccount: return "Account already exists"
        case .persistenceError(let error): return "Account data persistence error: \(error.localizedDescription)"
        }
    }
}

// MARK: - AccountManagerImpl

/// Manages Gmail account sign-in, sign-out, and token lifecycle.
/// Replaces the Frameworks/AccountManager/ three-layer pattern.
class AccountManagerImpl: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var accounts: [GmailAccount] = []
    @Published private(set) var isLoading = false
    @Published private(set) var signedInUsers: [GIDGoogleUser] = []

    // MARK: - Singleton

    static let shared = AccountManagerImpl()

    // MARK: - Private

    private let gmailScopes = ["https://www.googleapis.com/auth/gmail.readonly"]
    private let maxAccountLimit = 10
    private let userDefaultsKey = "gmail_accounts"

    // MARK: - Init

    init() {
        print("AccountManagerImpl initializing...")
        loadPersistedAccounts()
        checkExistingSignIn()
        print("AccountManagerImpl initialized with \(accounts.count) accounts")
    }

    // MARK: - Persistence

    private func loadPersistedAccounts() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let loaded = try? JSONDecoder().decode([GmailAccount].self, from: data) else {
            return
        }
        accounts = loaded
        print("Loaded \(loaded.count) persisted accounts")
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    // MARK: - Sign-In Restoration

    private func checkExistingSignIn() {
        if let user = GIDSignIn.sharedInstance.currentUser {
            if !signedInUsers.contains(where: { $0.profile?.email == user.profile?.email }) {
                signedInUsers.append(user)
            }
            return
        }

        for account in accounts {
            Task {
                do {
                    if let restoredUser = try await attemptRestoreSignIn(for: account) {
                        await MainActor.run {
                            if !self.signedInUsers.contains(where: { $0.profile?.email == restoredUser.profile?.email }) {
                                self.signedInUsers.append(restoredUser)
                            }
                        }
                    }
                } catch {
                    print("Failed to restore sign-in for \(account.email): \(error)")
                }
            }
        }
    }

    private func attemptRestoreSignIn(for account: GmailAccount) async throws -> GIDGoogleUser? {
        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error = error {
                    continuation.resume(throwing: AccountError.tokenRefreshFailed)
                    _ = error
                } else if let user = user, user.profile?.email == account.email {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Public API

    func signInWithGoogle() async throws {
        await MainActor.run { self.isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }

        if accounts.count >= maxAccountLimit {
            throw AccountError.signInFailed
        }

        guard let presentingViewController = await getPresentingViewController() else {
            throw AccountError.noPresentingViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            hint: nil,
            additionalScopes: gmailScopes
        )

        await MainActor.run {
            let user = result.user
            guard let email = user.profile?.email else { return }

            if self.accounts.contains(where: { $0.email == email }) {
                print("Account \(email) already exists")
                return
            }

            let account = GmailAccount(
                email: email,
                displayName: user.profile?.name,
                accessToken: user.accessToken.tokenString,
                refreshToken: user.refreshToken.tokenString
            )

            self.accounts.append(account)
            self.saveAccounts()

            if !self.signedInUsers.contains(where: { $0.profile?.email == email }) {
                self.signedInUsers.append(user)
            }

            print("Successfully signed in account: \(email)")
        }
    }

    func signOut(account: GmailAccount) {
        accounts.removeAll { $0.id == account.id }
        signedInUsers.removeAll { $0.profile?.email == account.email }

        if accounts.isEmpty {
            GIDSignIn.sharedInstance.signOut()
        }

        saveAccounts()
        print("Signed out account: \(account.email)")
    }

    func signOutAllAccounts() {
        GIDSignIn.sharedInstance.signOut()
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

    func refreshTokenForUser(_ user: GIDGoogleUser) async throws {
        do {
            try await user.refreshTokensIfNeeded()
            await MainActor.run {
                if let email = user.profile?.email,
                   let index = self.accounts.firstIndex(where: { $0.email == email }) {
                    self.accounts[index] = self.accounts[index].updatingTokens(
                        accessToken: user.accessToken.tokenString,
                        refreshToken: user.refreshToken.tokenString
                    )
                    self.saveAccounts()
                }
            }
        } catch {
            throw AccountError.tokenRefreshFailed
        }
    }

    func validateAndRefreshTokenForUser(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        do {
            try await user.refreshTokensIfNeeded()
            await MainActor.run {
                if let email = user.profile?.email,
                   let index = self.accounts.firstIndex(where: { $0.email == email }) {
                    self.accounts[index] = self.accounts[index].updatingTokens(
                        accessToken: user.accessToken.tokenString,
                        refreshToken: user.refreshToken.tokenString
                    )
                    self.saveAccounts()
                }
            }
            return user
        } catch {
            do {
                return try await reauthenticateUser(user)
            } catch {
                await MainActor.run {
                    if let email = user.profile?.email {
                        self.signedInUsers.removeAll { $0.profile?.email == email }
                    }
                }
                throw AccountError.reauthenticationRequired
            }
        }
    }

    func requiresReauthentication(for account: GmailAccount) -> Bool {
        return !signedInUsers.contains { $0.profile?.email == account.email }
    }

    func reauthenticateAccount(_ account: GmailAccount) async throws {
        await MainActor.run { self.isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }

        await MainActor.run {
            signedInUsers.removeAll { $0.profile?.email == account.email }
        }

        guard let presentingViewController = await getPresentingViewController() else {
            throw AccountError.noPresentingViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            hint: account.email,
            additionalScopes: gmailScopes
        )

        let user = result.user
        guard user.profile?.email == account.email else {
            throw AccountError.signInFailed
        }

        await MainActor.run {
            if let index = accounts.firstIndex(where: { $0.email == account.email }) {
                accounts[index] = accounts[index].updatingTokens(
                    accessToken: user.accessToken.tokenString,
                    refreshToken: user.refreshToken.tokenString
                )
                saveAccounts()
            }
            if !signedInUsers.contains(where: { $0.profile?.email == account.email }) {
                signedInUsers.append(user)
            }
        }

        print("Successfully re-authenticated account: \(account.email)")
    }

    // MARK: - Private helpers

    private func reauthenticateUser(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        do {
            try await GIDSignIn.sharedInstance.restorePreviousSignIn()

            if let restoredUser = GIDSignIn.sharedInstance.currentUser,
               restoredUser.profile?.email == user.profile?.email {
                try await restoredUser.refreshTokensIfNeeded()

                await MainActor.run {
                    if let index = self.signedInUsers.firstIndex(where: { $0.profile?.email == user.profile?.email }) {
                        self.signedInUsers[index] = restoredUser
                    } else {
                        self.signedInUsers.append(restoredUser)
                    }

                    if let accountIndex = self.accounts.firstIndex(where: { $0.email == user.profile?.email }) {
                        self.accounts[accountIndex] = self.accounts[accountIndex].updatingTokens(
                            accessToken: restoredUser.accessToken.tokenString,
                            refreshToken: restoredUser.refreshToken.tokenString
                        )
                        self.saveAccounts()
                    }
                }

                return restoredUser
            }
        } catch {
            print("Failed to restore previous sign-in: \(error)")
        }

        throw AccountError.reauthenticationRequired
    }

    private func getPresentingViewController() async -> UIViewController? {
        return await UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController
    }
}
