import Foundation
import SwiftData

/// Manages classification tasks that run at app launch
@MainActor
class LaunchClassificationManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var classificationProgress: Double = 0.0
    
    // MARK: - Private Properties
    
    private let modelContext: ModelContext
    private let classificationService: EmailClassificationServiceProtocol
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.classificationService = EmailClassificationServiceAPI.create(modelContext: modelContext)
        
        // Listen to classification service updates
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    /// Performs launch-time classification if needed
    func performLaunchClassificationIfNeeded() async {
        guard SecureConfigurationManager.shared.hasOpenAIAPIKey() else {
            print("📧 No API key configured - skipping initial classification")
            return
        }
        
        print("📧 Starting launch-time email classification...")
        
        do {
            let unclassifiedCount = try await getUnclassifiedEmailCount()
            
            if unclassifiedCount == 0 {
                print("📧 No unclassified emails found")
                return
            }
            
            print("📧 Found \(unclassifiedCount) emails to classify at launch")
            
            // Perform classification in background
            await classificationService.classifyUnclassifiedEmails()
            
        } catch {
            print("❌ Failed to perform launch classification: \(error)")
        }
    }
    
    /// Forces a re-classification of all emails (useful for testing or after API key changes)
    func forceFullClassification() async {
        // Clear all existing classifications
        await clearAllClassifications()
        
        // Run classification
        await performLaunchClassificationIfNeeded()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Note: With protocol-based services, we'll update progress manually during operations
        // rather than using publisher bindings
    }
    
    private func getUnclassifiedEmailCount() async throws -> Int {
        return try await Task.detached { [modelContext] in
            let descriptor = FetchDescriptor<SwiftDataEmail>(
                predicate: #Predicate { email in
                    email.isClassified == false
                }
            )
            return try modelContext.fetchCount(descriptor)
        }.value
    }
    
    private func clearAllClassifications() async {
        do {
            let descriptor = FetchDescriptor<SwiftDataEmail>()
            let allEmails = try modelContext.fetch(descriptor)
            
            for email in allEmails {
                email.isClassified = false
                email.classificationCategory = nil
                email.classificationConfidence = nil
                email.classificationDate = nil
            }
            
            try modelContext.save()
            print("🗑️ Cleared all existing classifications")
            
        } catch {
            print("❌ Failed to clear classifications: \(error)")
        }
    }
}

// MARK: - Background Classification Support

extension LaunchClassificationManager {
    /// Runs classification in background when app is active but not in foreground
    func runBackgroundClassification() async {
        guard SecureConfigurationManager.shared.hasOpenAIAPIKey() else {
            return
        }
        
        print("📧 Running background classification...")
        await classificationService.classifyUnclassifiedEmails()
    }
    
    /// Gets the current classification statistics
    func getClassificationStatistics() async -> ClassificationStatistics? {
        do {
            let descriptor = FetchDescriptor<SwiftDataEmail>()
            let allEmails = try modelContext.fetch(descriptor)
            
            var categoryCounts: [EmailCategory: Int] = [:]
            var totalClassified = 0
            var confidenceSum: Double = 0
            var highConfidenceCount = 0
            var lowConfidenceCount = 0
            
            for email in allEmails {
                guard email.isClassified,
                      let categoryString = email.classificationCategory,
                      let category = EmailCategory(rawValue: categoryString),
                      let confidence = email.classificationConfidence else {
                    continue
                }
                
                categoryCounts[category, default: 0] += 1
                totalClassified += 1
                confidenceSum += confidence
                
                if confidence > 0.8 {
                    highConfidenceCount += 1
                } else if confidence < 0.5 {
                    lowConfidenceCount += 1
                }
            }
            
            let averageConfidence = totalClassified > 0 ? confidenceSum / Double(totalClassified) : 0
            
            return ClassificationStatistics(
                totalEmails: totalClassified,
                categoryCounts: categoryCounts,
                averageConfidence: averageConfidence,
                highConfidenceCount: highConfidenceCount,
                lowConfidenceCount: lowConfidenceCount
            )
            
        } catch {
            print("❌ Failed to get classification statistics: \(error)")
            return nil
        }
    }
}
