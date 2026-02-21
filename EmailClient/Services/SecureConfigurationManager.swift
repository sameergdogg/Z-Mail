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
        guard let apiKey = secureConfig.getOpenAIAPIKey(), !apiKey.isEmpty else {
            print("API connection test: no API key stored")
            return false
        }

        do {
            // Simple HTTP check against OpenAI's models endpoint with the stored key
            let url = URL(string: "https://api.openai.com/v1/models")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let success = httpResponse.statusCode == 200
                if !success {
                    print("API connection test failed with HTTP \(httpResponse.statusCode)")
                }
                return success
            }
            return false
        } catch {
            print("API connection test failed: \(error.localizedDescription)")
            return false
        }
    }
}