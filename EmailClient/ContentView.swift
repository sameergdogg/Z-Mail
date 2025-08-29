import SwiftUI

struct ContentView: View {
    @StateObject private var accountManager = AccountManager()
    @State private var showingAccountSetup = false
    
    var body: some View {
        NavigationView {
            if accountManager.accounts.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "envelope")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Welcome to Email Client")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Add your Gmail accounts to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Add Gmail Account") {
                        showingAccountSetup = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                EmailListView()
                    .environmentObject(accountManager)
            }
        }
        .sheet(isPresented: $showingAccountSetup) {
            AccountSetupView()
                .environmentObject(accountManager)
        }
    }
}

struct AccountSetupView: View {
    @EnvironmentObject var accountManager: AccountManager
    @Environment(\.dismiss) private var dismiss
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                VStack(spacing: 16) {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Sign in with Google")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Connect your Gmail account to access your emails")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                VStack(spacing: 16) {
                    Button(action: {
                        Task {
                            do {
                                try await accountManager.signInWithGoogle()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "globe")
                            Text("Sign in with Google")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(accountManager.isLoading)
                    
                    if accountManager.isLoading {
                        ProgressView("Signing in...")
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Sign-in Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
}

#Preview {
    ContentView()
}