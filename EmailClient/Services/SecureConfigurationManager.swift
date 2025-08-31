import Foundation
import Security

/// Secure configuration manager for API keys and sensitive data
class SecureConfigurationManager {
    static let shared = SecureConfigurationManager()
    
    private init() {}
    
    // MARK: - OpenAI API Key Management
    
    private let openAIKeyIdentifier = "com.emailclient.openai.apikey"
    
    /// Stores the OpenAI API key securely in the Keychain
    /// - Parameter apiKey: The OpenAI API key to store
    /// - Returns: True if successful, false otherwise
    func storeOpenAIAPIKey(_ apiKey: String) -> Bool {
        let data = apiKey.data(using: .utf8) ?? Data()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: openAIKeyIdentifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Retrieves the OpenAI API key from the Keychain
    /// - Returns: The stored API key or nil if not found
    func getOpenAIAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: openAIKeyIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return apiKey
    }
    
    /// Removes the OpenAI API key from the Keychain
    /// - Returns: True if successful, false otherwise
    func removeOpenAIAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: openAIKeyIdentifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Checks if an OpenAI API key is stored
    /// - Returns: True if key exists, false otherwise
    func hasOpenAIAPIKey() -> Bool {
        return getOpenAIAPIKey() != nil
    }
}

// MARK: - Classification Integration

extension SecureConfigurationManager {
    /// Gets a configured ClassificationModel instance with the stored API key
    /// - Parameter configuration: Optional custom configuration
    /// - Returns: Configured ClassificationModel or nil if no API key is stored
    func getClassificationModel(with configuration: ClassificationConfiguration = ClassificationConfiguration()) -> ClassificationModelProtocol? {
        guard hasOpenAIAPIKey() else {
            print("⚠️ No OpenAI API key found. Please configure the API key first.")
            return nil
        }
        
        return ClassificationModelAPI.shared(with: configuration)
    }
    
    /// Classifies an email using the stored API key
    /// - Parameters:
    ///   - email: The email to classify
    ///   - configuration: Optional custom configuration
    /// - Returns: Classification result
    /// - Throws: ClassificationError if API key is missing or classification fails
    func classifyEmail(_ email: EmailData, configuration: ClassificationConfiguration = ClassificationConfiguration()) async throws -> EmailClassificationResult {
        guard let apiKey = getOpenAIAPIKey() else {
            throw ClassificationError.invalidAPIKey
        }
        
        let classifier = ClassificationModelAPI.shared(with: configuration)
        return try await classifier.classifyEmail(email, apiKey: apiKey)
    }
}

// MARK: - Settings View Integration

/// Protocol for managing classification settings
protocol ClassificationSettingsProtocol {
    var isClassificationEnabled: Bool { get set }
    var classificationConfiguration: ClassificationConfiguration { get set }
    func configureAPIKey(_ apiKey: String) -> Bool
    func removeAPIKey() -> Bool
    func testAPIConnection() async -> Bool
}

class ClassificationSettings: ObservableObject, ClassificationSettingsProtocol {
    @Published var isClassificationEnabled: Bool = false
    @Published var classificationConfiguration: ClassificationConfiguration = .init()
    
    private let secureConfig = SecureConfigurationManager.shared
    
    init() {
        // Check if API key is already configured
        isClassificationEnabled = secureConfig.hasOpenAIAPIKey()
    }
    
    func configureAPIKey(_ apiKey: String) -> Bool {
        let success = secureConfig.storeOpenAIAPIKey(apiKey)
        if success {
            isClassificationEnabled = true
        }
        return success
    }
    
    func removeAPIKey() -> Bool {
        let success = secureConfig.removeOpenAIAPIKey()
        if success {
            isClassificationEnabled = false
        }
        return success
    }
    
    func testAPIConnection() async -> Bool {
        do {
            // Test with a simple email
            let testEmail = EmailData(
                id: "test",
                from: "test@example.com",
                subject: "Test Classification",
                date: ISO8601DateFormatter().string(from: Date()),
                body: "This is a test email for classification."
            )
            
            _ = try await secureConfig.classifyEmail(testEmail, configuration: ClassificationConfiguration.debug)
            return true
        } catch {
            print("🚨 API connection test failed with detailed error:")
            print("Error type: \(type(of: error))")
            print("Error description: \(error.localizedDescription)")
            if let classificationError = error as? ClassificationError {
                print("Classification error: \(classificationError)")
            }
            if let urlError = error as? URLError {
                print("URL error code: \(urlError.code)")
                print("URL error description: \(urlError.localizedDescription)")
            }
            return false
        }
    }
}