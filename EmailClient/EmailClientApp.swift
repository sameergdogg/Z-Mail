import SwiftUI
import GoogleSignIn
import SwiftData

@main
struct EmailClientApp: App {
    @StateObject private var appDataManager = AppDataManager.shared
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var accountManager = AccountManagerImpl()

    init() {
        configureGoogleSignIn()
        print("EmailClient app initializing")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appDataManager, appDataManager)
                .environmentObject(appDataManager)
                .environmentObject(settingsManager)
                .environmentObject(accountManager)
                .onAppear {
                    Task {
                        await appDataManager.initialize()
                    }
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }

    // MARK: - Google Sign-In Configuration

    private func configureGoogleSignIn() {
        print("Configuring Google Sign-In...")

        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            fatalError("GoogleService-Info.plist file not found or CLIENT_ID missing")
        }

        let config = GIDConfiguration(clientID: clientId)
        GIDSignIn.sharedInstance.configuration = config
        print("Google Sign-In configured with client ID: \(String(clientId.prefix(20)))...")

        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            if let user = user {
                print("Previous sign-in restored for: \(user.profile?.email ?? "unknown")")
            } else if let error = error {
                print("No previous sign-in to restore: \(error.localizedDescription)")
            }
        }
    }
}
