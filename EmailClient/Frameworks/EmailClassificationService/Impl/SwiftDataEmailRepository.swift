import Foundation
import SwiftData

/// SwiftData implementation of EmailRepositoryProtocol
internal class SwiftDataEmailRepository: EmailRepositoryProtocol {
    
    private let modelContext: ModelContext
    private let enableDebugLogging: Bool
    
    internal init(modelContext: ModelContext, enableDebugLogging: Bool = false) {
        self.modelContext = modelContext
        self.enableDebugLogging = enableDebugLogging
    }
    
    func fetchUnclassifiedEmails() async throws -> [ClassifiableEmail] {
        return try await Task.detached { [modelContext] in
            let descriptor = FetchDescriptor<SwiftDataEmail>(
                predicate: #Predicate { email in
                    email.isClassified == false
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            
            let emails = try modelContext.fetch(descriptor)
            return emails.map { SwiftDataEmailAdapter(email: $0) }
        }.value
    }
    
    func updateEmailClassification(emailId: String, result: EmailClassificationResult) async throws {
        try await Task.detached { [modelContext] in
            let descriptor = FetchDescriptor<SwiftDataEmail>(
                predicate: #Predicate { email in
                    email.id == emailId
                }
            )
            
            let emails = try modelContext.fetch(descriptor)
            guard let email = emails.first else {
                throw EmailClassificationServiceError.classificationFailed("Email not found: \(emailId)")
            }
            
            try await MainActor.run {
                email.updateClassification(
                    category: result.category.rawValue,
                    confidence: result.confidence,
                    summary: result.summary
                )
                
                do {
                    try modelContext.save()
                } catch {
                    if self.enableDebugLogging {
                        print("❌ Failed to save classification for email \(emailId): \(error)")
                    }
                    throw error
                }
            }
        }.value
    }
    
    func getClassificationStatistics() async throws -> EmailClassificationStatistics {
        return try await Task.detached { [modelContext] in
            // Get total emails
            let totalDescriptor = FetchDescriptor<SwiftDataEmail>()
            let totalEmails = try modelContext.fetch(totalDescriptor)
            
            // Get classified emails
            let classifiedDescriptor = FetchDescriptor<SwiftDataEmail>(
                predicate: #Predicate { email in
                    email.isClassified == true
                }
            )
            let classifiedEmails = try modelContext.fetch(classifiedDescriptor)
            
            // Calculate statistics
            let totalCount = totalEmails.count
            let classifiedCount = classifiedEmails.count
            let unclassifiedCount = totalCount - classifiedCount
            
            // Calculate average confidence
            let totalConfidence = classifiedEmails.compactMap { $0.classificationConfidence }.reduce(0.0, +)
            let averageConfidence = classifiedCount > 0 ? totalConfidence / Double(classifiedCount) : 0.0
            
            // Calculate category distribution
            var categoryDistribution: [String: Int] = [:]
            for email in classifiedEmails {
                if let category = email.classificationCategory {
                    categoryDistribution[category, default: 0] += 1
                }
            }
            
            // Get last classification date
            let lastClassificationDate = classifiedEmails
                .compactMap { $0.classificationDate }
                .max()
            
            return EmailClassificationStatistics(
                totalEmails: totalCount,
                classifiedEmails: classifiedCount,
                unclassifiedEmails: unclassifiedCount,
                averageConfidence: averageConfidence,
                categoryDistribution: categoryDistribution,
                lastClassificationDate: lastClassificationDate,
                totalProcessingTime: 0.0 // This would need to be tracked separately
            )
        }.value
    }
    
    func markClassificationFailed(emailId: String, error: Error) async throws {
        try await Task.detached { [modelContext] in
            let descriptor = FetchDescriptor<SwiftDataEmail>(
                predicate: #Predicate { email in
                    email.id == emailId
                }
            )
            
            let emails = try modelContext.fetch(descriptor)
            guard let email = emails.first else {
                if self.enableDebugLogging {
                    print("⚠️ Email not found when marking classification failed: \(emailId)")
                }
                return
            }
            
            await MainActor.run {
                // Mark as not classified so it can be retried later
                email.isClassified = false
                email.classificationDate = Date()
                email.updatedAt = Date()
                
                do {
                    try modelContext.save()
                    if self.enableDebugLogging {
                        print("📧 Marked email \(emailId) as classification failed")
                    }
                } catch {
                    if self.enableDebugLogging {
                        print("❌ Failed to save error state for email \(emailId): \(error)")
                    }
                }
            }
        }.value
    }
}

/// Adapter to make SwiftDataEmail conform to ClassifiableEmail
internal struct SwiftDataEmailAdapter: ClassifiableEmail {
    private let email: SwiftDataEmail
    
    internal init(email: SwiftDataEmail) {
        self.email = email
    }
    
    var id: String { email.id }
    var subject: String { email.subject }
    var senderEmail: String { email.senderEmail }
    var body: String { email.body }
    var date: Date { email.date }
}