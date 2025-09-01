import Foundation
import SwiftData

/// Manages classification tasks that run at app launch
@MainActor
class LaunchClassificationManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isInitialClassificationComplete = false
    @Published var classificationProgress: Double = 0.0
    
    // MARK: - Private Properties
    
    private let modelContext: ModelContext
    private let classificationService: EmailClassificationService
    private var hasRunInitialClassification = false
    
    // UserDefaults key to track if we've run initial classification
    private let initialClassificationKey = "hasRunInitialClassification"
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.classificationService = EmailClassificationService(modelContext: modelContext)
        
        // Check if we've already run initial classification
        hasRunInitialClassification = UserDefaults.standard.bool(forKey: initialClassificationKey)
        isInitialClassificationComplete = hasRunInitialClassification
        
        // Listen to classification service updates
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    /// Performs launch-time classification if needed
    func performLaunchClassificationIfNeeded() async {
        guard !hasRunInitialClassification else {
            print("📧 Initial classification already completed")
            return
        }
        
        guard SecureConfigurationManager.shared.hasOpenAIAPIKey() else {
            print("📧 No API key configured - skipping initial classification")
            markInitialClassificationComplete()
            return
        }
        
        print("📧 Starting launch-time email classification...")
        
        do {
            let unclassifiedCount = try await getUnclassifiedEmailCount()
            
            if unclassifiedCount == 0 {
                print("📧 No unclassified emails found")
                markInitialClassificationComplete()
                return
            }
            
            print("📧 Found \(unclassifiedCount) emails to classify at launch")
            
            // Perform classification in background
            await classificationService.classifyUnclassifiedEmails()
            
            // Mark as complete
            markInitialClassificationComplete()
            
        } catch {
            print("❌ Failed to perform launch classification: \(error)")
            // Still mark as complete to avoid retrying every launch
            markInitialClassificationComplete()
        }
    }
    
    /// Forces a re-classification of all emails (useful for testing or after API key changes)
    func forceFullClassification() async {
        // Reset the flag
        UserDefaults.standard.set(false, forKey: initialClassificationKey)
        hasRunInitialClassification = false
        isInitialClassificationComplete = false
        
        // Clear all existing classifications
        await clearAllClassifications()
        
        // Run classification
        await performLaunchClassificationIfNeeded()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Forward classification service progress to our published properties
        classificationService.$classificationProgress
            .assign(to: &$classificationProgress)
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
    
    private func markInitialClassificationComplete() {
        UserDefaults.standard.set(true, forKey: initialClassificationKey)
        hasRunInitialClassification = true
        isInitialClassificationComplete = true
        print("✅ Initial classification marked as complete")
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