import Foundation

/// Factory for creating Gmail API Service instances
public class GmailAPIServiceFactory {
    
    /// Shared singleton instance of the factory
    public static let shared = GmailAPIServiceFactory()
    
    private init() {}
    
    /// Creates and returns a Gmail API Service instance
    /// - Parameters:
    ///   - dependencies: Dependencies required by the service
    /// - Returns: A configured Gmail API Service instance
    public func createGmailAPIService(dependencies: GmailAPIServiceDependencies = GmailAPIServiceDependencies()) -> GmailAPIServiceProtocol {
        return GmailAPIServiceImpl(dependencies: dependencies)
    }
}

/// Dependencies container for Gmail API Service
public class GmailAPIServiceDependencies {
    public let baseURL: String
    public let urlSession: URLSession
    public let jsonDecoder: JSONDecoder
    public let jsonEncoder: JSONEncoder
    
    public init(
        baseURL: String = "https://www.googleapis.com/gmail/v1",
        urlSession: URLSession = .shared,
        jsonDecoder: JSONDecoder = JSONDecoder(),
        jsonEncoder: JSONEncoder = JSONEncoder()
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.jsonDecoder = jsonDecoder
        self.jsonEncoder = jsonEncoder
    }
}

/// Dependency injection container for the Gmail API Service framework
public class GmailAPIServiceContainer {
    public static let shared = GmailAPIServiceContainer()
    
    private var serviceInstance: GmailAPIServiceProtocol?
    private let dependencies: GmailAPIServiceDependencies
    
    private init(dependencies: GmailAPIServiceDependencies = GmailAPIServiceDependencies()) {
        self.dependencies = dependencies
    }
    
    /// Gets or creates the Gmail API Service instance
    public func getGmailAPIService() -> GmailAPIServiceProtocol {
        if let service = serviceInstance {
            return service
        }
        
        let service = GmailAPIServiceFactory.shared.createGmailAPIService(dependencies: dependencies)
        serviceInstance = service
        return service
    }
    
    /// Resets the container (useful for testing)
    public func reset() {
        serviceInstance = nil
    }
    
    /// Sets a custom service instance (useful for testing)
    public func setService(_ service: GmailAPIServiceProtocol) {
        serviceInstance = service
    }
}