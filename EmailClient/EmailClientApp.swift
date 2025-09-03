import SwiftUI
import GoogleSignIn
import SwiftData

@main
struct EmailClientApp: App {
    // New AppDataService replacing legacy AppDataManager
    // Legacy approach - keep the old managers temporarily for working build
    @StateObject private var legacyAppDataManager = AppDataManager.shared
    @StateObject private var legacySettingsManager = SettingsManager()
    @StateObject private var accountManager = AccountManagerImpl(dependencies: AccountManagerDependencies())
    
    // Prepare for new service registry (when framework files are compiled)
    @State private var isServiceRegistryReady = false
    
    init() {
        configureGoogleSignIn()
        print("🏗️ EmailClient app initializing with hybrid service approach")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Provide existing services that views expect  
                .environment(\.appDataManager, legacyAppDataManager)
                .environmentObject(legacyAppDataManager)
                .environmentObject(legacySettingsManager)
                .environmentObject(accountManager)
                .onAppear {
                    Task {
                        // Initialize legacy system
                        await legacyAppDataManager.initialize()
                        
                        // Prepare for service registry integration
                        await prepareServiceRegistryMigration()
                    }
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
    
    // MARK: - Service Registry Migration Preparation
    
    private func prepareServiceRegistryMigration() async {
        print("🚀 Preparing for service registry migration...")
        
        // Log current services that are available
        print("✅ Current services ready:")
        print("   - AccountManager: \(type(of: accountManager))")
        print("   - AppDataManager: \(type(of: legacyAppDataManager))")
        print("   - SettingsManager: \(type(of: legacySettingsManager))")
        
        // When framework files are compiled, this is where we'll create the service registry
        // and register all services for dependency injection
        isServiceRegistryReady = true
        
        print("✅ Service registry migration preparation complete")
        print("ℹ️ Framework services will be integrated when compiled files are available")
    }
    
    // MARK: - Google Sign-In Configuration
    
    private func configureGoogleSignIn() {
        print("🔧 Configuring Google Sign-In...")
        
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            fatalError("GoogleService-Info.plist file not found or CLIENT_ID missing")
        }
        
        let config = GIDConfiguration(clientID: clientId)
        GIDSignIn.sharedInstance.configuration = config
        print("✅ Google Sign-In configured with client ID: \(String(clientId.prefix(20)))...")
        
        // Try to restore previous sign-in immediately
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            if let user = user {
                print("✅ Previous sign-in restored for: \(user.profile?.email ?? "unknown")")
            } else if let error = error {
                print("ℹ️ No previous sign-in to restore: \(error.localizedDescription)")
            }
        }
    }
}