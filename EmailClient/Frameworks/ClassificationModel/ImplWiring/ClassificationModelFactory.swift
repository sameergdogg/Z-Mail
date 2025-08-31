import Foundation

/// Factory for creating Classification Model instances
public class ClassificationModelFactory {
    
    /// Shared singleton instance of the factory
    public static let shared = ClassificationModelFactory()
    
    private init() {}
    
    /// Creates and returns a Classification Model instance
    /// - Parameters:
    ///   - dependencies: Dependencies required by the classification model
    /// - Returns: A configured Classification Model instance
    public func createClassificationModel(
        dependencies: ClassificationModelDependencies = ClassificationModelDependencies()
    ) -> ClassificationModelProtocol {
        print("🏭 Creating ClassificationModel with configuration...")
        return ClassificationModelImpl(dependencies: dependencies)
    }
    
    /// Creates a Classification Model instance with custom configuration
    /// - Parameter configuration: Custom configuration for the model
    /// - Returns: A configured Classification Model instance
    public func createClassificationModel(
        with configuration: ClassificationConfiguration
    ) -> ClassificationModelProtocol {
        let dependencies = ClassificationModelDependencies(configuration: configuration)
        return createClassificationModel(dependencies: dependencies)
    }
}

/// Dependencies container for Classification Model
public class ClassificationModelDependencies {
    public let configuration: ClassificationConfiguration
    public let urlSession: URLSession
    public let jsonEncoder: JSONEncoder
    public let jsonDecoder: JSONDecoder
    public let cache: ClassificationCache
    
    public init(
        configuration: ClassificationConfiguration = ClassificationConfiguration(),
        urlSession: URLSession? = nil,
        jsonEncoder: JSONEncoder = JSONEncoder(),
        jsonDecoder: JSONDecoder = JSONDecoder(),
        cache: ClassificationCache? = nil
    ) {
        self.configuration = configuration
        
        // Configure URLSession with timeout
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfig.timeoutIntervalForResource = configuration.requestTimeout * 2
        self.urlSession = urlSession ?? URLSession(configuration: sessionConfig)
        
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder
        self.cache = cache ?? (configuration.enableCaching ? InMemoryClassificationCache(
            expirationTime: configuration.cacheExpirationTime
        ) : NoOpClassificationCache())
    }
}

/// Dependency injection container for the Classification Model framework
public class ClassificationModelContainer {
    public static let shared = ClassificationModelContainer()
    
    private var modelInstance: ClassificationModelProtocol?
    private var dependencies: ClassificationModelDependencies?
    
    private init() {}
    
    /// Gets or creates the Classification Model instance
    /// - Returns: The Classification Model instance
    public func getClassificationModel() -> ClassificationModelProtocol {
        if let model = modelInstance {
            return model
        }
        
        let deps = dependencies ?? ClassificationModelDependencies()
        let model = ClassificationModelFactory.shared.createClassificationModel(dependencies: deps)
        
        modelInstance = model
        dependencies = deps
        
        return model
    }
    
    /// Gets or creates the Classification Model instance with custom configuration
    /// - Parameter configuration: Custom configuration for the model
    /// - Returns: The Classification Model instance
    public func getClassificationModel(with configuration: ClassificationConfiguration) -> ClassificationModelProtocol {
        // If configuration changed, create new instance
        if let deps = dependencies, deps.configuration.temperature != configuration.temperature ||
           deps.configuration.maxBodyLength != configuration.maxBodyLength {
            modelInstance = nil
            dependencies = nil
        }
        
        if let model = modelInstance {
            return model
        }
        
        let deps = ClassificationModelDependencies(configuration: configuration)
        let model = ClassificationModelFactory.shared.createClassificationModel(dependencies: deps)
        
        modelInstance = model
        dependencies = deps
        
        return model
    }
    
    /// Resets the container (useful for testing)
    public func reset() {
        modelInstance = nil
        dependencies = nil
    }
    
    /// Sets a custom model instance (useful for testing)
    /// - Parameter model: The model instance to set
    public func setModel(_ model: ClassificationModelProtocol) {
        modelInstance = model
        dependencies = nil // Clear dependencies since we have a custom instance
    }
}

// MARK: - Classification Cache Protocol

/// Protocol for caching classification results
public protocol ClassificationCache {
    /// Stores a classification result in the cache
    /// - Parameters:
    ///   - result: The classification result to cache
    ///   - emailId: The email ID as cache key
    func store(_ result: EmailClassificationResult, for emailId: String)
    
    /// Retrieves a cached classification result
    /// - Parameter emailId: The email ID to look up
    /// - Returns: Cached result or nil if not found/expired
    func retrieve(for emailId: String) -> EmailClassificationResult?
    
    /// Clears all cached results
    func clearAll()
    
    /// Removes expired cache entries
    func cleanup()
}

// MARK: - Cache Implementations

/// In-memory cache implementation
internal class InMemoryClassificationCache: ClassificationCache {
    private var cache: [String: (result: EmailClassificationResult, expiry: Date)] = [:]
    private let expirationTime: TimeInterval
    private let queue = DispatchQueue(label: "classification.cache", attributes: .concurrent)
    
    init(expirationTime: TimeInterval) {
        self.expirationTime = expirationTime
        
        // Setup periodic cleanup
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            self.cleanup()
        }
    }
    
    func store(_ result: EmailClassificationResult, for emailId: String) {
        let expiry = Date().addingTimeInterval(expirationTime)
        queue.async(flags: .barrier) {
            self.cache[emailId] = (result, expiry)
        }
    }
    
    func retrieve(for emailId: String) -> EmailClassificationResult? {
        return queue.sync {
            guard let cached = cache[emailId] else { return nil }
            
            if cached.expiry < Date() {
                cache.removeValue(forKey: emailId)
                return nil
            }
            
            return cached.result
        }
    }
    
    func clearAll() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
    
    func cleanup() {
        queue.async(flags: .barrier) {
            let now = Date()
            self.cache = self.cache.filter { _, value in
                value.expiry >= now
            }
        }
    }
}

/// No-op cache implementation (when caching is disabled)
internal class NoOpClassificationCache: ClassificationCache {
    func store(_ result: EmailClassificationResult, for emailId: String) {}
    func retrieve(for emailId: String) -> EmailClassificationResult? { return nil }
    func clearAll() {}
    func cleanup() {}
}

// MARK: - Testing Support

#if DEBUG
public extension ClassificationModelContainer {
    /// Creates an in-memory model for testing
    /// - Parameters:
    ///   - configuration: Custom configuration for testing
    ///   - mockCache: Custom cache implementation for testing
    /// - Returns: A test-configured Classification Model Container
    static func createForTesting(
        configuration: ClassificationConfiguration = ClassificationConfiguration(),
        mockCache: ClassificationCache? = nil
    ) -> ClassificationModelContainer {
        let container = ClassificationModelContainer()
        let dependencies = ClassificationModelDependencies(
            configuration: configuration,
            cache: mockCache
        )
        let model = ClassificationModelFactory.shared.createClassificationModel(dependencies: dependencies)
        container.setModel(model)
        return container
    }
}
#endif