// MARK: - Gmail API Service Framework
// This file exports the public API of the Gmail API Service framework

// Public API
@_exported import Foundation
@_exported import GoogleSignIn

// Export Public API
public typealias GmailService = GmailAPIServiceProtocol

// Export Factory and Container
public typealias GmailServiceFactory = GmailAPIServiceFactory
public typealias GmailServiceContainer = GmailAPIServiceContainer
public typealias GmailServiceDependencies = GmailAPIServiceDependencies

// Export Data Models
// (All public structs and enums from GmailDataModels.swift are automatically available)

/// Convenience accessor for the Gmail API Service
public struct GmailAPI {
    /// Gets the shared Gmail API Service instance
    public static var shared: GmailAPIServiceProtocol {
        return GmailAPIServiceContainer.shared.getGmailAPIService()
    }
    
    /// Creates a new Gmail API Service instance with custom dependencies
    /// - Parameter dependencies: Custom dependencies for the service
    /// - Returns: A new Gmail API Service instance
    public static func create(with dependencies: GmailAPIServiceDependencies = GmailAPIServiceDependencies()) -> GmailAPIServiceProtocol {
        return GmailAPIServiceFactory.shared.createGmailAPIService(dependencies: dependencies)
    }
}