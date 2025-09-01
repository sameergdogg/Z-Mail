import Foundation
import SwiftData
import Combine

/// Service responsible for managing email classification operations
@MainActor
class EmailClassificationService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isClassifying = false
    @Published var classificationProgress: Double = 0.0
    @Published var classificationStatus = "Ready"
    
    // MARK: - Private Properties
    
    private let modelContext: ModelContext
    private let secureConfigManager = SecureConfigurationManager.shared
    private var classificationTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Public Methods
    
    /// Classifies all unclassified emails in the database
    func classifyUnclassifiedEmails() async {
        guard !isClassifying else {
            print("⚠️ Classification already in progress")
            return
        }
        
        guard secureConfigManager.hasOpenAIAPIKey() else {
            print("⚠️ No OpenAI API key configured")
            classificationStatus = "API key required"
            return
        }
        
        isClassifying = true
        classificationProgress = 0.0
        classificationStatus = "Starting classification..."
        
        do {
            let unclassifiedEmails = try await fetchUnclassifiedEmails()
            print("📧 Found \(unclassifiedEmails.count) emails to classify")
            
            guard !unclassifiedEmails.isEmpty else {
                classificationStatus = "All emails classified"
                isClassifying = false
                return
            }
            
            await classifyEmails(unclassifiedEmails)
            
        } catch {
            print("❌ Failed to fetch unclassified emails: \(error)")
            classificationStatus = "Error: \(error.localizedDescription)"
            isClassifying = false
        }
    }
    
    /// Cancels ongoing classification
    func cancelClassification() {
        classificationTask?.cancel()
        isClassifying = false
        classificationStatus = "Cancelled"
    }
    
    // MARK: - Private Methods
    
    private func fetchUnclassifiedEmails() async throws -> [SwiftDataEmail] {
        return try await Task.detached { [modelContext] in
            let descriptor = FetchDescriptor<SwiftDataEmail>(
                predicate: #Predicate { email in
                    email.isClassified == false
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
        }.value
    }
    
    private func classifyEmails(_ emails: [SwiftDataEmail]) async {
        classificationTask = Task {
            let totalEmails = emails.count
            var processedCount = 0
            
            // Process emails in batches to avoid overwhelming the API
            let batchSize = 3
            let batches = emails.chunked(into: batchSize)
            
            for batch in batches {
                guard !Task.isCancelled else {
                    print("🛑 Classification cancelled")
                    break
                }
                
                await withTaskGroup(of: Void.self) { group in
                    for email in batch {
                        group.addTask {
                            await self.classifyEmail(email)
                            await MainActor.run {
                                processedCount += 1
                                self.classificationProgress = Double(processedCount) / Double(totalEmails)
                                self.classificationStatus = "Classified \(processedCount)/\(totalEmails) emails"
                            }
                        }
                    }
                }
                
                // Small delay between batches to be respectful to the API
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
            
            await MainActor.run {
                self.isClassifying = false
                self.classificationStatus = "Completed: \(processedCount) emails classified"
            }
        }
        
        await classificationTask?.value
    }
    
    private func classifyEmail(_ email: SwiftDataEmail) async {
        do {
            // Convert to EmailData for classification
            let emailData = EmailData(
                id: email.id,
                from: email.senderEmail,
                subject: email.subject,
                date: ISO8601DateFormatter().string(from: email.date),
                body: email.body
            )
            
            // Perform classification
            let result = try await secureConfigManager.classifyEmail(emailData)
            
            // Update the email with classification results
            await MainActor.run {
                email.updateClassification(
                    category: result.category.rawValue,
                    confidence: result.confidence,
                    summary: result.summary
                )
                
                // Save the context
                do {
                    try self.modelContext.save()
                } catch {
                    print("❌ Failed to save classification for email \(email.id): \(error)")
                }
            }
            
            print("✅ Classified email '\(email.subject)' as \(result.category.rawValue) (confidence: \(result.confidence))")
            
        } catch {
            print("❌ Failed to classify email '\(email.subject)': \(error)")
            
            // Mark as classified with error to avoid retrying immediately
            await MainActor.run {
                // if we failed to classify we should set is classified to false
                email.isClassified = false
                email.classificationDate = Date()
                email.updatedAt = Date()
                
                do {
                    try self.modelContext.save()
                } catch {
                    print("❌ Failed to save error state for email \(email.id): \(error)")
                }
            }
        }
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
