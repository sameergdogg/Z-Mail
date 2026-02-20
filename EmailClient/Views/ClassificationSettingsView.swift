import SwiftUI

struct ClassificationSettingsView: View {
    @StateObject private var settings = ClassificationSettings()
    @State private var apiKeyInput = ""
    @State private var showingAPIKeyInput = false
    @State private var isTestingConnection = false
    @State private var testResult: TestResult?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    enum TestResult {
        case success
        case failure
    }
    
    var body: some View {
        ZStack {
            Color.clear.background(.ultraThinMaterial)
            Form {
                Section {
                    HStack {
                        Image(systemName: "brain")
                                .foregroundColor(.purple)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("AI Email Classification")
                                    .font(.headline)
                                Text("Automatically categorize emails using ChatGPT")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $settings.isClassificationEnabled)
                                .disabled(!SecureConfigurationManager.shared.hasOpenAIAPIKey())
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("AI Classification")
                    } footer: {
                        if !SecureConfigurationManager.shared.hasOpenAIAPIKey() {
                            Text("Configure your OpenAI API key to enable classification")
                        }
                    }
                    
                    if SecureConfigurationManager.shared.hasOpenAIAPIKey() {
                        Section {
                            HStack {
                                Image(systemName: "key.fill")
                                    .foregroundColor(.green)
                                Text("API Key Configured")
                                Spacer()
                                Button("Test Connection") {
                                    testAPIConnection()
                                }
                                .disabled(isTestingConnection)
                            }
                            
                            if isTestingConnection {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Testing connection...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let result = testResult {
                                HStack {
                                    Image(systemName: result == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(result == .success ? .green : .red)
                                    Text(result == .success ? "Connection successful" : "Connection failed")
                                        .font(.caption)
                                }
                            }
                            
                            Button("Remove API Key", role: .destructive) {
                                removeAPIKey()
                            }
                        } header: {
                            Text("API Configuration")
                        }
                        
                        Section {
                            Picker("Processing Speed", selection: $settings.classificationConfiguration) {
                                Text("High Accuracy").tag(ClassificationConfiguration.highAccuracy)
                                Text("Balanced").tag(ClassificationConfiguration())
                                Text("Fast Processing").tag(ClassificationConfiguration.fastProcessing)
                            }
                            .pickerStyle(.segmented)
                            
                            HStack {
                                Text("Max Body Length")
                                Spacer()
                                Text("\(settings.classificationConfiguration.maxBodyLength) chars")
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Concurrent Requests")
                                Spacer()
                                Text("\(settings.classificationConfiguration.maxConcurrentRequests)")
                                    .foregroundColor(.secondary)
                            }
                        } header: {
                            Text("Classification Settings")
                        }
                        
                        Section {
                            ForEach(EmailCategory.allCases, id: \.self) { category in
                                HStack {
                                    Image(systemName: category.iconName)
                                        .foregroundColor(colorForCategory(category))
                                        .frame(width: 20)
                                    
                                    VStack(alignment: .leading) {
                                        Text(category.displayName)
                                            .font(.body)
                                        Text(descriptionForCategory(category))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Text("Email Categories")
                        } footer: {
                            Text("These are the categories that AI will use to classify your emails")
                        }
                        
                    } else {
                        Section {
                            HStack {
                                if showingAPIKeyInput {
                                    TextField("sk-proj-...", text: $apiKeyInput)
                                        .textContentType(.none)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                } else {
                                    Button("Configure OpenAI API Key") {
                                        showingAPIKeyInput = true
                                    }
                                    .foregroundColor(.blue)
                                }
                            }

                            if showingAPIKeyInput {
                                Button("Save API Key") {
                                    configureAPIKey(apiKeyInput)
                                }
                                .disabled(apiKeyInput.isEmpty || !apiKeyInput.hasPrefix("sk-") || apiKeyInput.count <= 20)

                                Button("Cancel", role: .destructive) {
                                    apiKeyInput = ""
                                    showingAPIKeyInput = false
                                }
                            }
                        } header: {
                            Text("Setup Required")
                        } footer: {
                            if showingAPIKeyInput {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Your API key will be stored securely in the device keychain.")
                                    Text("Get your API key from: platform.openai.com")
                                        .foregroundColor(.blue)
                                }
                            } else {
                                Text("An OpenAI API key is required for email classification. The key is stored securely in your device's keychain.")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        .navigationTitle("AI Classification")
        .navigationBarTitleDisplayMode(.large)
        .alert("Configuration", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    private func configureAPIKey(_ apiKey: String) {
        let success = settings.configureAPIKey(apiKey)
        alertMessage = success ? "API key configured successfully" : "Failed to configure API key"
        showingAlert = true
        
        if success {
            apiKeyInput = ""
            showingAPIKeyInput = false
        }
    }
    
    private func removeAPIKey() {
        let success = settings.removeAPIKey()
        alertMessage = success ? "API key removed successfully" : "Failed to remove API key"
        showingAlert = true
        testResult = nil
    }
    
    private func testAPIConnection() {
        isTestingConnection = true
        testResult = nil
        
        Task {
            let success = await settings.testAPIConnection()
            
            await MainActor.run {
                isTestingConnection = false
                testResult = success ? .success : .failure
            }
        }
    }
    
    private func colorForCategory(_ category: EmailCategory) -> Color {
        switch category.color {
        case "orange": return .orange
        case "brown": return .brown
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "red": return .red
        case "yellow": return .yellow
        default: return .gray
        }
    }
    
    private func descriptionForCategory(_ category: EmailCategory) -> String {
        switch category {
        case .promotions:
            return "Marketing emails, deals, newsletters, advertisements"
        case .orderHistory:
            return "Purchase receipts, shipping updates, order confirmations"
        case .finance:
            return "Banking, bills, payments, investments"
        case .personal:
            return "Personal communication, family, friends"
        case .work:
            return "Work emails, meetings, projects"
        case .appointments:
            return "Scheduling, reminders, calendar invites"
        case .signInAlerts:
            return "Security alerts, login notifications, account access"
        case .other:
            return "Everything else"
        }
    }
}

#Preview {
    ClassificationSettingsView()
}
