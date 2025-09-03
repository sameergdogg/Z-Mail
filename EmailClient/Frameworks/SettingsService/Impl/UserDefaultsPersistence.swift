import Foundation

/// UserDefaults-based implementation of SettingsPersistenceProtocol
internal class UserDefaultsPersistence: SettingsPersistenceProtocol {
    
    private let userDefaults: UserDefaults
    
    internal init(suiteName: String? = nil) {
        if let suiteName = suiteName {
            self.userDefaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        } else {
            self.userDefaults = UserDefaults.standard
        }
    }
    
    func setValue<T>(_ value: T, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    func value<T>(forKey key: String, defaultValue: T) -> T {
        // Handle different types appropriately
        if let stringDefault = defaultValue as? String {
            return userDefaults.string(forKey: key) as? T ?? defaultValue
        } else if let boolDefault = defaultValue as? Bool {
            return userDefaults.bool(forKey: key) as? T ?? defaultValue
        } else if let intDefault = defaultValue as? Int {
            return userDefaults.integer(forKey: key) as? T ?? defaultValue
        } else if let doubleDefault = defaultValue as? Double {
            return userDefaults.double(forKey: key) as? T ?? defaultValue
        } else {
            // For other types, use object(forKey:)
            return userDefaults.object(forKey: key) as? T ?? defaultValue
        }
    }
    
    func removeValue(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
    
    func synchronize() {
        userDefaults.synchronize()
    }
}