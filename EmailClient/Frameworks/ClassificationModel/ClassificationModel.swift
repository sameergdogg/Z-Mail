// MARK: - Classification Model Framework
// This file exports the public API of the Classification Model framework

// Public API
@_exported import Foundation
@_exported import Combine

// Export Factory and Container
public typealias ClassificationModel = ClassificationModelProtocol
public typealias ClassificationFactory = ClassificationModelFactory
public typealias ClassificationContainer = ClassificationModelContainer
public typealias ClassificationDependencies = ClassificationModelDependencies

// Export Configuration and Models
public typealias ClassificationConfig = ClassificationConfiguration

/// Convenience accessor for the Classification Model
public struct ClassificationModelAPI {
    /// Gets the shared Classification Model instance
    /// - Returns: The Classification Model instance
    public static var shared: ClassificationModelProtocol {
        return ClassificationModelContainer.shared.getClassificationModel()
    }
    
    /// Gets or creates a Classification Model instance with custom configuration
    /// - Parameter configuration: Custom configuration for the model
    /// - Returns: The Classification Model instance
    public static func shared(with configuration: ClassificationConfiguration) -> ClassificationModelProtocol {
        return ClassificationModelContainer.shared.getClassificationModel(with: configuration)
    }
    
    /// Creates a new Classification Model instance with default dependencies
    /// - Returns: A new Classification Model instance
    public static func create() -> ClassificationModelProtocol {
        return ClassificationModelFactory.shared.createClassificationModel()
    }
    
    /// Creates a new Classification Model instance with custom configuration
    /// - Parameter configuration: Custom configuration for the model
    /// - Returns: A new Classification Model instance
    public static func create(with configuration: ClassificationConfiguration) -> ClassificationModelProtocol {
        return ClassificationModelFactory.shared.createClassificationModel(with: configuration)
    }
    
    /// Creates a new Classification Model instance with custom dependencies
    /// - Parameter dependencies: Custom dependencies for the model
    /// - Returns: A new Classification Model instance
    public static func create(with dependencies: ClassificationModelDependencies) -> ClassificationModelProtocol {
        return ClassificationModelFactory.shared.createClassificationModel(dependencies: dependencies)
    }
    
    /// Creates a test instance with custom dependencies
    /// - Parameters:
    ///   - configuration: Custom configuration for testing
    ///   - mockCache: Custom cache implementation for testing
    /// - Returns: A Classification Model instance configured for testing
    #if DEBUG
    public static func createForTesting(
        configuration: ClassificationConfiguration = ClassificationConfiguration(),
        mockCache: ClassificationCache? = nil
    ) -> ClassificationModelProtocol {
        return ClassificationModelContainer.createForTesting(
            configuration: configuration,
            mockCache: mockCache
        ).getClassificationModel()
    }
    #endif
}

// MARK: - Extension for Email Integration

public extension EmailData {
    /// Convenience initializer from Email model
    /// - Parameter email: Email instance from the main app
    init(from email: Email) {
        let dateFormatter = ISO8601DateFormatter()
        
        self.init(
            id: email.id,
            from: email.sender.email,
            subject: email.subject,
            date: dateFormatter.string(from: email.date),
            body: email.body
        )
    }
}

// MARK: - Batch Classification Helpers

public extension ClassificationModelProtocol {
    /// Classifies multiple emails with progress tracking
    /// - Parameters:
    ///   - emails: Array of emails to classify
    ///   - apiKey: OpenAI API key for authentication
    ///   - progressHandler: Optional progress callback (progress: 0.0-1.0)
    /// - Returns: Array of classification results
    func classifyEmailsWithProgress(
        _ emails: [EmailData],
        apiKey: String,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> [EmailClassificationResult] {
        var results: [EmailClassificationResult] = []
        let total = emails.count
        
        for (index, email) in emails.enumerated() {
            let result = try await classifyEmail(email, apiKey: apiKey)
            results.append(result)
            
            let progress = Double(index + 1) / Double(total)
            await MainActor.run {
                progressHandler?(progress)
            }
        }
        
        return results
    }
    
    /// Gets classification statistics for an array of results
    /// - Parameter results: Array of classification results
    /// - Returns: Dictionary with category counts and confidence statistics
    func getClassificationStatistics(_ results: [EmailClassificationResult]) -> ClassificationStatistics {
        var categoryCounts: [EmailCategory: Int] = [:]
        var confidenceSum: Double = 0
        var highConfidenceCount = 0
        var lowConfidenceCount = 0
        
        for result in results {
            categoryCounts[result.category, default: 0] += 1
            confidenceSum += result.confidence
            
            if result.isHighConfidence {
                highConfidenceCount += 1
            } else if result.needsReview {
                lowConfidenceCount += 1
            }
        }
        
        let averageConfidence = results.isEmpty ? 0 : confidenceSum / Double(results.count)
        
        return ClassificationStatistics(
            totalEmails: results.count,
            categoryCounts: categoryCounts,
            averageConfidence: averageConfidence,
            highConfidenceCount: highConfidenceCount,
            lowConfidenceCount: lowConfidenceCount
        )
    }
}

/// Statistics about classification results
public struct ClassificationStatistics {
    public let totalEmails: Int
    public let categoryCounts: [EmailCategory: Int]
    public let averageConfidence: Double
    public let highConfidenceCount: Int
    public let lowConfidenceCount: Int
    
    /// Most common category
    public var mostCommonCategory: EmailCategory? {
        return categoryCounts.max(by: { $0.value < $1.value })?.key
    }
    
    /// Percentage of high confidence classifications
    public var highConfidencePercentage: Double {
        guard totalEmails > 0 else { return 0 }
        return Double(highConfidenceCount) / Double(totalEmails) * 100
    }
    
    /// Percentage of low confidence classifications that need review
    public var needsReviewPercentage: Double {
        guard totalEmails > 0 else { return 0 }
        return Double(lowConfidenceCount) / Double(totalEmails) * 100
    }
}

// MARK: - Preset Configurations

public extension ClassificationConfiguration {
    /// High accuracy configuration (slower but more accurate)
    static let highAccuracy = ClassificationConfiguration(
        temperature: 0.0,
        maxBodyLength: 6000,
        enableCaching: true,
        maxConcurrentRequests: 2,
        requestTimeout: 45.0
    )
    
    /// Fast processing configuration (faster but potentially less accurate)
    static let fastProcessing = ClassificationConfiguration(
        temperature: 0.1,
        maxBodyLength: 2000,
        enableCaching: true,
        maxConcurrentRequests: 5,
        requestTimeout: 20.0
    )
    
    /// Debug configuration with detailed logging
    static let debug = ClassificationConfiguration(
        temperature: 0.0,
        maxBodyLength: 4000,
        enableCaching: false,
        maxConcurrentRequests: 1,
        requestTimeout: 60.0
    )
}