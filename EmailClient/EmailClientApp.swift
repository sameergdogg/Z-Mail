import SwiftUI
import GoogleSignIn

@main
struct EmailClientApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
                          let plist = NSDictionary(contentsOfFile: path),
                          let clientId = plist["CLIENT_ID"] as? String else {
                        fatalError("GoogleService-Info.plist file not found or CLIENT_ID missing")
                    }
                    
                    let config = GIDConfiguration(clientID: clientId)
                    
                    GIDSignIn.sharedInstance.configuration = config
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}