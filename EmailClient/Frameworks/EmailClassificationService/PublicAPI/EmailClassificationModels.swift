import Foundation
import SwiftData

/// Protocol for classification provider abstraction
public protocol EmailClassificationProviderProtocol {
    /// Classifies a single email
    /// - Parameter emailData: The email data to classify
    /// - Returns: The classification result
    func classifyEmail(_ emailData: EmailData) async throws -> EmailClassificationResult
    
    /// Checks if the provider has valid configuration
    /// - Returns: True if properly configured, false otherwise
    func isConfigured() -> Bool
    
    /// Gets provider-specific error information
    /// - Returns: Error message if not configured, nil otherwise
    func getConfigurationError() -> String?
}

/// Protocol for email repository abstraction
public protocol EmailRepositoryProtocol {
    /// Fetches unclassified emails from the repository
    /// - Returns: Array of unclassified emails
    func fetchUnclassifiedEmails() async throws -> [ClassifiableEmail]
    
    /// Updates email classification in the repository
    /// - Parameters:
    ///   - emailId: The email ID to update
    ///   - result: The classification result
    func updateEmailClassification(emailId: String, result: EmailClassificationResult) async throws
    
    /// Gets classification statistics from the repository
    /// - Returns: Classification statistics
    func getClassificationStatistics() async throws -> EmailClassificationStatistics
    
    /// Marks email as classification failed
    /// - Parameters:
    ///   - emailId: The email ID
    ///   - error: The error that occurred
    func markClassificationFailed(emailId: String, error: Error) async throws
}

// EmailData is imported from ClassificationModel framework - no duplication needed

/// Email classification service dependencies for dependency injection
public struct EmailClassificationServiceDependencies {
    /// Classification provider for AI/ML operations
    public let classificationProvider: EmailClassificationProviderProtocol
    
    /// Email repository for data access
    public let emailRepository: EmailRepositoryProtocol
    
    /// Configuration options
    public let configuration: EmailClassificationServiceConfiguration
    
    public init(
        classificationProvider: EmailClassificationProviderProtocol,
        emailRepository: EmailRepositoryProtocol,
        configuration: EmailClassificationServiceConfiguration = EmailClassificationServiceConfiguration()
    ) {
        self.classificationProvider = classificationProvider
        self.emailRepository = emailRepository
        self.configuration = configuration
    }
}

/// Classification metrics for monitoring and analytics
public struct ClassificationMetrics {
    public let totalClassified: Int
    public let successfulClassifications: Int
    public let failedClassifications: Int
    public let averageProcessingTime: TimeInterval
    public let averageConfidence: Double
    public let categoryBreakdown: [String: Int]
    
    public init(
        totalClassified: Int,
        successfulClassifications: Int,
        failedClassifications: Int,
        averageProcessingTime: TimeInterval,
        averageConfidence: Double,
        categoryBreakdown: [String: Int]
    ) {
        self.totalClassified = totalClassified
        self.successfulClassifications = successfulClassifications
        self.failedClassifications = failedClassifications
        self.averageProcessingTime = averageProcessingTime
        self.averageConfidence = averageConfidence
        self.categoryBreakdown = categoryBreakdown
    }
    
    public var successRate: Double {
        guard totalClassified > 0 else { return 0.0 }
        return Double(successfulClassifications) / Double(totalClassified)
    }
}