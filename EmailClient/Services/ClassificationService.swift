import Foundation
import SwiftData
import Combine

// MARK: - ClassificationService

/// Handles all email classification using the OpenAI API.
/// Merges Frameworks/ClassificationModel/, Frameworks/EmailClassificationService/,
/// and Services/LaunchClassificationManager.swift into a single flat class.
@MainActor
class ClassificationService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isClassifying = false
    @Published private(set) var classificationProgress: Double = 0.0
    @Published private(set) var classificationStatus = "Ready"

    // MARK: - Private Properties

    private let modelContext: ModelContext
    private let urlSession = URLSession.shared
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    private let configuration = ClassificationConfiguration()
    private var classificationCache: [String: EmailClassificationResult] = [:]
    private let semaphore: DispatchSemaphore

    // MARK: - Initializer

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.semaphore = DispatchSemaphore(value: ClassificationConfiguration().maxConcurrentRequests)
    }

    // MARK: - Public API (mirrors LaunchClassificationManager)

    /// Classifies any unclassified emails.  Call this at app launch.
    func classifyUnclassifiedEmails() async {
        guard !isClassifying else {
            print("Classification already in progress")
            return
        }

        guard SecureConfigurationManager.shared.hasOpenAIAPIKey() else {
            print("No API key configured — skipping classification")
            classificationStatus = "No API key configured"
            return
        }

        await startClassification()
    }

    /// Force re-classification of every email.
    func forceFullClassification() async {
        await clearAllClassifications()
        await classifyUnclassifiedEmails()
    }

    /// Wipe all classification data from the store.
    func clearAllClassifications() async {
        do {
            let descriptor = FetchDescriptor<Email>()
            let allEmails = try modelContext.fetch(descriptor)

            for email in allEmails {
                email.isClassified = false
                email.classificationCategory = nil
                email.classificationConfidence = nil
                email.classificationDate = nil
            }

            if modelContext.hasChanges {
                try modelContext.save()
            }
            classificationCache.removeAll()
            print("Cleared all existing classifications")
        } catch {
            print("Failed to clear classifications: \(error)")
        }
    }

    /// Returns the current classification statistics derived from the store.
    func getClassificationStatistics() async -> ClassificationStatistics? {
        do {
            let descriptor = FetchDescriptor<Email>()
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
                      let confidence = email.classificationConfidence else { continue }

                categoryCounts[category, default: 0] += 1
                totalClassified += 1
                confidenceSum += confidence
                if confidence > 0.8 { highConfidenceCount += 1 }
                else if confidence < 0.5 { lowConfidenceCount += 1 }
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
            print("Failed to get classification statistics: \(error)")
            return nil
        }
    }

    // MARK: - Core classification flow

    private func startClassification() async {
        isClassifying = true
        classificationProgress = 0.0
        classificationStatus = "Starting classification..."

        defer { isClassifying = false }

        do {
            let unclassified = try await fetchUnclassifiedEmails()

            guard !unclassified.isEmpty else {
                classificationStatus = "All emails classified"
                return
            }

            print("Found \(unclassified.count) emails to classify")
            await classifyBatch(unclassified)

        } catch {
            print("Classification failed: \(error)")
            classificationStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func classifyBatch(_ emails: [Email]) async {
        let total = emails.count
        var processed = 0

        // Process in chunks of maxConcurrentRequests
        let chunkSize = configuration.maxConcurrentRequests
        let chunks = emails.chunked(into: chunkSize)

        for chunk in chunks {
            await withTaskGroup(of: Void.self) { group in
                for email in chunk {
                    group.addTask {
                        await self.classifySingleEmail(email)
                    }
                }
            }

            processed += chunk.count
            classificationProgress = Double(processed) / Double(total)
            classificationStatus = "Classified \(processed)/\(total) emails"
        }

        classificationStatus = "Completed: \(processed) emails classified"
    }

    private func classifySingleEmail(_ email: Email) async {
        guard let apiKey = SecureConfigurationManager.shared.getOpenAIAPIKey() else { return }

        let emailData = EmailData(from: email)

        do {
            let result = try await performClassification(email: emailData, apiKey: apiKey)

            // Write back into the model context on main actor
            let emailId = email.id
            let category = result.category.rawValue
            let confidence = result.confidence
            let summary = result.summary

            do {
                let predicate = #Predicate<Email> { e in e.id == emailId }
                let descriptor = FetchDescriptor<Email>(predicate: predicate)
                if let found = try modelContext.fetch(descriptor).first {
                    found.updateClassification(category: category, confidence: confidence, summary: summary)
                    if modelContext.hasChanges {
                        try modelContext.save()
                    }
                }
            } catch {
                print("Failed to save classification for \(emailId): \(error)")
            }

        } catch {
            print("Failed to classify email \(email.id): \(error)")
        }
    }

    private func fetchUnclassifiedEmails() async throws -> [Email] {
        return try await Task.detached { [modelContext] in
            let descriptor = FetchDescriptor<Email>(
                predicate: #Predicate { email in
                    email.isClassified == false
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
        }.value
    }

    // MARK: - OpenAI API call

    private func performClassification(email: EmailData, apiKey: String) async throws -> EmailClassificationResult {
        // Check in-memory cache
        if let cached = classificationCache[email.id] { return cached }

        guard !apiKey.isEmpty else { throw ClassificationError.invalidAPIKey }

        // Rate limiting via semaphore
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.semaphore.wait()
                continuation.resume()
            }
        }
        defer { semaphore.signal() }

        let truncatedBody = intelligentTruncate(email.body, maxLength: configuration.maxBodyLength)

        let responseFormat = OpenAIRequest.ResponseFormat(type: "json_object", json_schema: nil)
        let prompt = """
        You are a precise email classifier. Analyze the email and classify it into one of these categories:

        Categories:
        - promotions: Marketing emails, deals, newsletters, advertisements, promotional content
        - order_history: Purchase receipts, shipping updates, order confirmations, delivery notifications
        - finance: Banking, investments, bills, payments, financial statements, credit cards
        - personal: Personal communication, family, friends, social messages
        - work: Work-related emails, meetings, projects, professional communication
        - appointments: Scheduling, reminders, calendar invites, bookings, events
        - sign_in_alerts: Security alerts, login notifications, suspicious activity, account access warnings
        - other: Everything else that doesn't fit the above categories

        Respond with valid JSON in this exact format:
        {
            "category": "promotions|order_history|finance|personal|work|appointments|sign_in_alerts|other",
            "confidence": 0.95,
            "rationale": "Brief explanation",
            "summary": "Short summary under 15 words describing the email content"
        }

        Email to classify:
        From: \(email.from)
        Subject: \(email.subject)
        Date: \(email.date)
        Body:
        \(truncatedBody)
        """

        let requestBody = OpenAIRequest(
            model: "gpt-4o-mini",
            temperature: configuration.temperature,
            response_format: responseFormat,
            messages: [OpenAIRequest.Message(role: "user", content: prompt)]
        )

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(requestBody)

        let (data, response) = try await urlSession.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200: break
            case 401: throw ClassificationError.invalidAPIKey
            case 429: throw ClassificationError.apiRateLimitExceeded
            default: throw ClassificationError.classificationFailed("HTTP \(httpResponse.statusCode)")
            }
        }

        let apiResponse = try jsonDecoder.decode(OpenAIResponse.self, from: data)
        guard let choice = apiResponse.choices.first,
              let content = choice.message.content else {
            throw ClassificationError.invalidResponse
        }

        let classificationData = content.data(using: .utf8) ?? Data()
        let parsed = try jsonDecoder.decode(ClassificationResponseData.self, from: classificationData)

        guard let category = EmailCategory(rawValue: parsed.category) else {
            throw ClassificationError.invalidResponse
        }

        let result = EmailClassificationResult(
            emailId: email.id,
            category: category,
            confidence: parsed.confidence,
            rationale: parsed.rationale,
            summary: parsed.summary
        )

        classificationCache[email.id] = result
        return result
    }

    // MARK: - Daily Digest generation

    func generateDailyDigest(_ emails: [ClassifiedEmail], period: String, apiKey: String) async throws -> DailyDigest {
        guard !apiKey.isEmpty else { throw ClassificationError.invalidAPIKey }

        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.semaphore.wait()
                continuation.resume()
            }
        }
        defer { semaphore.signal() }

        let emailsJSON = (try? String(data: jsonEncoder.encode(emails), encoding: .utf8)) ?? "[]"

        let prompt = """
        System:
        You are a precise email digest generator. Write factual, concise summaries.
        Never invent details not present in the inputs. Keep PII minimal.

        User:
        Aggregate these emails for the period "\(period)" into a single digest JSON.

        Output JSON schema:
        {  "headline": string,
           "pillars": { "power": string[], "pressure": string[], "trouble": string[] },
           "highlights": [{ "summary": string, "category": string, "source": string, "id": string }],
           "actions": [{ "title": string, "due": string|null, "source": string, "msg_ids": string[], "priority": "low|med|high"}],
           "money": { "charges": [...], "payouts": [...], "bills_due": [...], "balances": [...] },
           "packages": [...],
           "calendar": [...],
           "security": [...],
           "stats": { "totals": object, "top_senders": [{ "sender": string, "count": number }], "threads": number },
           "narrative": { "long": string, "microcopy": { "power": string, "pressure": string, "trouble": string } }
        }

        Constraints:
        - Headline <= 10 words, evocative but grounded.
        - Highlights: <= 8 items; each <= 15 words.
        - Actions: <= 8 items; titles begin with a verb.
        - Pillars arrays: 1-3 bullets each.
        - Do not leak passwords/codes. Redact to "****".

        Input array (email_item):
        \(emailsJSON)
        """

        let responseFormat = OpenAIRequest.ResponseFormat(type: "json_object", json_schema: nil)
        let requestBody = OpenAIRequest(
            model: "gpt-4o-mini",
            temperature: configuration.temperature,
            response_format: responseFormat,
            messages: [OpenAIRequest.Message(role: "user", content: prompt)]
        )

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(requestBody)

        let (data, response) = try await urlSession.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200: break
            case 401: throw ClassificationError.invalidAPIKey
            case 429: throw ClassificationError.apiRateLimitExceeded
            default: throw ClassificationError.classificationFailed("HTTP \(httpResponse.statusCode)")
            }
        }

        let apiResponse = try jsonDecoder.decode(OpenAIResponse.self, from: data)
        guard let choice = apiResponse.choices.first,
              let content = choice.message.content else {
            throw ClassificationError.invalidResponse
        }

        let digestData = content.data(using: .utf8) ?? Data()
        return try jsonDecoder.decode(DailyDigest.self, from: digestData)
    }

    // MARK: - Helpers

    private func intelligentTruncate(_ body: String, maxLength: Int) -> String {
        guard body.count > maxLength else { return body }
        guard maxLength > 500 else { return String(body.prefix(maxLength)) }

        let beginningLength = Int(Double(maxLength) * 0.7)
        let endLength = maxLength - beginningLength
        return String(body.prefix(beginningLength)) + "\n\n[... content truncated ...]\n\n" + String(body.suffix(endLength))
    }
}

// MARK: - Request / Response private models

private struct OpenAIRequest: Encodable {
    struct ResponseFormat: Encodable {
        struct JSONSchema: Encodable {
            let name: String
        }
        let type: String
        let json_schema: JSONSchema?
    }
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let temperature: Double
    let response_format: ResponseFormat
    let messages: [Message]
}

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct ClassificationResponseData: Decodable {
    let category: String
    let confidence: Double
    let rationale: String?
    let summary: String?
}

// MARK: - Array chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
