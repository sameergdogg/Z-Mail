import Foundation
import SwiftUI
import SwiftData
import Combine

/// Implementation of the Email Classification Service protocol
/// Follows MVVM + Service Layer architecture from CLAUDE.md
@MainActor
internal class EmailClassificationServiceImpl: EmailClassificationServiceProtocol {
    
    // MARK: - Published Properties
    
    @Published public private(set) var isClassifying = false
    @Published public private(set) var classificationProgress: Double = 0.0
    @Published public private(set) var classificationStatus = "Ready"
    
    // MARK: - Private Properties
    
    private let dependencies: EmailClassificationServiceDependencies
    private var classificationTask: Task<Void, Never>?
    private let changeEventsSubject = PassthroughSubject<EmailClassificationChangeEvent, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var classificationMetrics = ClassificationMetrics(
        totalClassified: 0,
        successfulClassifications: 0,
        failedClassifications: 0,
        averageProcessingTime: 0.0,
        averageConfidence: 0.0,
        categoryBreakdown: [:]
    )
    
    public var changeEvents: AnyPublisher<EmailClassificationChangeEvent, Never> {
        changeEventsSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    internal init(dependencies: EmailClassificationServiceDependencies) {
        self.dependencies = dependencies
        
        if dependencies.configuration.enableDebugLogging {
            setupDebugLogging()
        }
        
        validateConfiguration()
    }
    
    // MARK: - Public Methods
    
    public func classifyUnclassifiedEmails() async {
        guard !isClassifying else {
            if dependencies.configuration.enableDebugLogging {
                print("⚠️ Classification already in progress")
            }
            return
        }
        
        guard dependencies.classificationProvider.isConfigured() else {
            if dependencies.configuration.enableDebugLogging {
                print("⚠️ Classification provider not configured")
            }
            classificationStatus = dependencies.classificationProvider.getConfigurationError() ?? "Provider not configured"
            return
        }
        
        await startClassification()
    }
    
    public func classifyEmail(_ email: ClassifiableEmail) async throws -> EmailClassificationResult {
        let startTime = Date()
        
        if dependencies.configuration.enableDebugLogging {
            print("📧 Classifying email: \(email.subject)")
        }
        
        let emailData = EmailData(
            id: email.id,
            from: email.senderEmail,
            subject: email.subject,
            date: ISO8601DateFormatter().string(from: email.date),
            body: email.body
        )
        
        do {
            let result = try await withTimeout(self.dependencies.configuration.classificationTimeout) {
                try await self.dependencies.classificationProvider.classifyEmail(emailData)
            }
            
            let processingTime = Date().timeIntervalSince(startTime)
            let finalResult = EmailClassificationResult(
                emailId: email.id,
                category: result.category,
                confidence: result.confidence,
                rationale: result.rationale,
                summary: result.summary
            )
            
            // Update repository
            try await dependencies.emailRepository.updateEmailClassification(
                emailId: email.id,
                result: finalResult
            )
            
            // Update metrics
            updateMetrics(success: true, processingTime: processingTime, confidence: result.confidence)
            
            changeEventsSubject.send(.emailClassified(email.id, finalResult))
            
            if dependencies.configuration.enableDebugLogging {
                print("✅ Successfully classified email '\(email.subject)' as \(result.category.displayName)")
            }
            
            return finalResult
            
        } catch {
            let processingTime = Date().timeIntervalSince(startTime)
            updateMetrics(success: false, processingTime: processingTime, confidence: 0.0)
            
            // Mark as failed in repository
            try await dependencies.emailRepository.markClassificationFailed(emailId: email.id, error: error)
            
            if dependencies.configuration.enableDebugLogging {
                print("❌ Failed to classify email '\(email.subject)': \(error)")
            }
            
            throw EmailClassificationServiceError.classificationFailed(error.localizedDescription)
        }
    }
    
    public func cancelClassification() {
        classificationTask?.cancel()
        isClassifying = false
        classificationStatus = "Cancelled"
        changeEventsSubject.send(.classificationCancelled)
        
        if dependencies.configuration.enableDebugLogging {
            print("🛑 Classification cancelled")
        }
    }
    
    public func getClassificationStatistics() async -> EmailClassificationStatistics {
        do {
            return try await dependencies.emailRepository.getClassificationStatistics()
        } catch {
            if dependencies.configuration.enableDebugLogging {
                print("❌ Failed to get classification statistics: \(error)")
            }
            // Return empty statistics on error
            return EmailClassificationStatistics(
                totalEmails: 0,
                classifiedEmails: 0,
                unclassifiedEmails: 0,
                averageConfidence: 0.0,
                categoryDistribution: [:],
                lastClassificationDate: nil,
                totalProcessingTime: 0.0
            )
        }
    }
    
    public func retrainModel() async throws {
        // This would implement model retraining logic
        // For now, just throw not implemented
        throw EmailClassificationServiceError.classificationFailed("Model retraining not yet implemented")
    }
    
    // MARK: - Private Methods
    
    private func startClassification() async {
        isClassifying = true
        classificationProgress = 0.0
        classificationStatus = "Starting classification..."
        changeEventsSubject.send(.classificationStarted)
        
        defer {
            isClassifying = false
            if dependencies.configuration.enableDebugLogging {
                print("🏁 Classification process completed")
            }
        }
        
        do {
            let unclassifiedEmails = try await dependencies.emailRepository.fetchUnclassifiedEmails()
            
            if dependencies.configuration.enableDebugLogging {
                print("📧 Found \(unclassifiedEmails.count) emails to classify")
            }
            
            guard !unclassifiedEmails.isEmpty else {
                classificationStatus = "All emails classified"
                changeEventsSubject.send(.classificationCompleted(await getClassificationStatistics()))
                return
            }
            
            await classifyEmailsBatch(unclassifiedEmails)
            
        } catch {
            if dependencies.configuration.enableDebugLogging {
                print("❌ Classification failed: \(error)")
            }
            classificationStatus = "Error: \(error.localizedDescription)"
            changeEventsSubject.send(.classificationFailed(error))
        }
    }
    
    private func classifyEmailsBatch(_ emails: [ClassifiableEmail]) async {
        let totalEmails = emails.count
        var processedCount = 0
        
        let batches = emails.chunked(into: dependencies.configuration.batchSize)
        
        classificationTask = Task {
            for batch in batches {
                guard !Task.isCancelled else {
                    if dependencies.configuration.enableDebugLogging {
                        print("🛑 Batch classification cancelled")
                    }
                    break
                }
                
                await withTaskGroup(of: Void.self) { group in
                    for email in batch {
                        group.addTask {
                            do {
                                _ = try await self.classifyEmail(email)
                            } catch {
                                if self.dependencies.configuration.enableDebugLogging {
                                    print("❌ Failed to classify email in batch: \(error)")
                                }
                            }
                            
                            await MainActor.run {
                                processedCount += 1
                                self.classificationProgress = Double(processedCount) / Double(totalEmails)
                                self.classificationStatus = "Classified \(processedCount)/\(totalEmails) emails"
                                
                                self.changeEventsSubject.send(.classificationProgressUpdated(
                                    self.classificationProgress,
                                    self.classificationStatus
                                ))
                            }
                        }
                    }
                }
                
                // Delay between batches
                if dependencies.configuration.batchDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(dependencies.configuration.batchDelay * 1_000_000_000))
                }
            }
            
            await MainActor.run {
                self.classificationStatus = "Completed: \(processedCount) emails classified"
            }
            
            let finalStats = await self.getClassificationStatistics()
            self.changeEventsSubject.send(.classificationCompleted(finalStats))
        }
        
        await classificationTask?.value
    }
    
    private func validateConfiguration() {
        let config = dependencies.configuration
        
        if config.batchSize <= 0 {
            fatalError("Batch size must be greater than 0")
        }
        
        if config.maxConcurrentTasks <= 0 {
            fatalError("Max concurrent tasks must be greater than 0")
        }
        
        if config.minConfidenceThreshold < 0.0 || config.minConfidenceThreshold > 1.0 {
            fatalError("Confidence threshold must be between 0.0 and 1.0")
        }
        
        if config.classificationTimeout <= 0 {
            fatalError("Classification timeout must be greater than 0")
        }
    }
    
    private func updateMetrics(success: Bool, processingTime: TimeInterval, confidence: Double) {
        // This would update internal metrics tracking
        // Implementation details would depend on requirements
        if dependencies.configuration.enableDebugLogging {
            print("📊 Updated metrics - Success: \(success), Time: \(processingTime)s, Confidence: \(confidence)")
        }
    }
    
    private func setupDebugLogging() {
        changeEvents
            .sink { event in
                switch event {
                case .classificationStarted:
                    print("📧 Classification started")
                case .classificationProgressUpdated(let progress, let status):
                    print("📧 Progress: \(Int(progress * 100))% - \(status)")
                case .classificationCompleted(let stats):
                    print("📧 Classification completed - \(stats.classifiedEmails)/\(stats.totalEmails) emails")
                case .classificationCancelled:
                    print("📧 Classification cancelled")
                case .classificationFailed(let error):
                    print("📧 Classification failed: \(error)")
                case .emailClassified(let emailId, let result):
                    print("📧 Email classified: \(emailId) -> \(result.category.displayName)")
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Helper Functions

/// Timeout wrapper for async operations
private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw EmailClassificationServiceError.timeout
        }
        
        guard let result = try await group.next() else {
            throw EmailClassificationServiceError.timeout
        }
        
        group.cancelAll()
        return result
    }
}

// MARK: - Array Extension

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}