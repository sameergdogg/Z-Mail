import Foundation
import Combine

/// Implementation of the Classification Model protocol
/// Uses ChatGPT o1-mini via OpenAI's Responses API for email classification
internal class ClassificationModelImpl: ClassificationModelProtocol {
    
    // MARK: - Published Properties
    
    private let classificationUpdatesSubject = PassthroughSubject<EmailClassificationResult, Never>()
    public var classificationUpdates: AnyPublisher<EmailClassificationResult, Never> {
        classificationUpdatesSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Private Properties
    
    private let dependencies: ClassificationModelDependencies
    private let configuration: ClassificationConfiguration
    private let urlSession: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private let cache: ClassificationCache
    
    // Rate limiting
    private let semaphore: DispatchSemaphore
    
    // MARK: - Initialization
    
    init(dependencies: ClassificationModelDependencies) {
        self.dependencies = dependencies
        self.configuration = dependencies.configuration
        self.urlSession = dependencies.urlSession
        self.jsonEncoder = dependencies.jsonEncoder
        self.jsonDecoder = dependencies.jsonDecoder
        self.cache = dependencies.cache
        self.semaphore = DispatchSemaphore(value: configuration.maxConcurrentRequests)
    }
    
    // MARK: - Public Methods
    
    public func classifyEmail(_ email: EmailData, apiKey: String) async throws -> EmailClassificationResult {
        // Check cache first
        if let cachedResult = cache.retrieve(for: email.id) {
            print("📋 Using cached classification for email: \(email.id)")
            return cachedResult
        }
        
        // Log if email is very large but don't fail - we'll truncate it intelligently
        if email.body.count > configuration.maxBodyLength * 3 {
            print("⚠️ Very large email detected (\(email.body.count) chars), will truncate for classification: \(email.subject)")
        }
        
        // Rate limiting
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.semaphore.wait()
                continuation.resume()
            }
        }
        
        defer {
            semaphore.signal()
        }
        
        do {
            let result = try await performClassification(email: email, apiKey: apiKey)
            
            // Cache the result
            cache.store(result, for: email.id)
            
            // Publish update
            classificationUpdatesSubject.send(result)
            
            print("✅ Successfully classified email: \(email.id) as \(result.category.rawValue) with confidence \(result.confidence)")
            
            return result
            
        } catch {
            print("❌ Failed to classify email: \(email.id) - \(error)")
            throw error
        }
    }
    
    public func classifyEmails(_ emails: [EmailData], apiKey: String, batchSize: Int = 3) async throws -> [EmailClassificationResult] {
        var results: [EmailClassificationResult] = []
        var errors: [String] = []
        
        // Process emails in batches
        for chunk in emails.chunked(into: min(batchSize, configuration.maxConcurrentRequests)) {
            let chunkResults = await withTaskGroup(of: Result<EmailClassificationResult, Error>.self) { group in
                for email in chunk {
                    group.addTask {
                        do {
                            let result = try await self.classifyEmail(email, apiKey: apiKey)
                            return .success(result)
                        } catch {
                            return .failure(error)
                        }
                    }
                }
                
                var chunkResults: [EmailClassificationResult] = []
                for await result in group {
                    switch result {
                    case .success(let classification):
                        chunkResults.append(classification)
                    case .failure(let error):
                        print("❌ Batch classification error: \(error)")
                        if let classificationError = error as? ClassificationError,
                           case .classificationFailed(let message) = classificationError {
                            errors.append(message)
                        } else {
                            errors.append(error.localizedDescription)
                        }
                    }
                }
                return chunkResults
            }
            
            results.append(contentsOf: chunkResults)
        }
        
        // Throw batch error if any failed
        if !errors.isEmpty && results.isEmpty {
            throw ClassificationError.batchProcessingFailed(errors)
        }
        
        return results
    }
    
    public func getCachedClassification(for emailId: String) -> EmailClassificationResult? {
        return cache.retrieve(for: emailId)
    }
    
    public func clearCache() {
        cache.clearAll()
        print("🗑️ Cleared classification cache")
    }
    
    public func generateDailyDigest(_ emails: [ClassifiedEmail], period: String, apiKey: String) async throws -> DailyDigest {
        guard !apiKey.isEmpty else {
            throw ClassificationError.invalidAPIKey
        }
        
        print("📊 Generating daily digest for \(emails.count) emails for period: \(period)")
        
        // Rate limiting
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.semaphore.wait()
                continuation.resume()
            }
        }
        
        defer {
            semaphore.signal()
        }
        
        do {
            let digest = try await performDigestGeneration(emails: emails, period: period, apiKey: apiKey)
            print("✅ Successfully generated daily digest with headline: \(digest.headline)")
            return digest
            
        } catch {
            print("❌ Failed to generate daily digest: \(error)")
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    private func performClassification(email: EmailData, apiKey: String) async throws -> EmailClassificationResult {
        guard !apiKey.isEmpty else {
            throw ClassificationError.invalidAPIKey
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        
        // Prepare the request body using your provided structure
        let classificationRequest = try createClassificationRequest(email: email)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(classificationRequest)
        
        print("🌐 Sending classification request for email: \(email.id)")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 HTTP Response Status: \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📡 Response Body: \(responseString)")
                }
                
                switch httpResponse.statusCode {
                case 200:
                    break // Success
                case 401:
                    print("🔑 Authentication failed - check API key")
                    throw ClassificationError.invalidAPIKey
                case 429:
                    print("🚦 Rate limit exceeded")
                    throw ClassificationError.apiRateLimitExceeded
                default:
                    print("❌ HTTP Error \(httpResponse.statusCode)")
                    throw ClassificationError.classificationFailed("HTTP \(httpResponse.statusCode)")
                }
            }
            
            let apiResponse = try jsonDecoder.decode(OpenAIResponse.self, from: data)
            return try parseClassificationResponse(apiResponse, emailId: email.id)
            
        } catch let error as ClassificationError {
            throw error
        } catch let urlError as URLError {
            print("🌐 URLError: \(urlError.localizedDescription) (Code: \(urlError.code.rawValue))")
            throw ClassificationError.networkError
        } catch {
            print("⚠️ Unexpected error: \(error)")
            throw ClassificationError.classificationFailed(error.localizedDescription)
        }
    }
    
    private func createClassificationRequest(email: EmailData) throws -> OpenAIClassificationRequest {
        // Intelligently truncate email body to max length
        let truncatedBody = intelligentTruncate(email.body, maxLength: configuration.maxBodyLength)
        
        // Use simple JSON mode instead of structured schema for better compatibility
        let responseFormat = OpenAIClassificationRequest.ResponseFormat(
            type: "json_object",
            json_schema: nil
        )
        
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
        
        return OpenAIClassificationRequest(
            model: "gpt-4o-mini",
            temperature: configuration.temperature,
            response_format: responseFormat,
            messages: [
                OpenAIClassificationRequest.Message(role: "user", content: prompt)
            ]
        )
    }
    
    private func parseClassificationResponse(_ response: OpenAIResponse, emailId: String) throws -> EmailClassificationResult {
        guard let choice = response.choices.first,
              let content = choice.message.content else {
            throw ClassificationError.invalidResponse
        }
        
        do {
            let classificationData = content.data(using: .utf8) ?? Data()
            let parsedResult = try jsonDecoder.decode(ClassificationResponseData.self, from: classificationData)
            
            guard let category = EmailCategory(rawValue: parsedResult.category) else {
                throw ClassificationError.invalidResponse
            }
            
            return EmailClassificationResult(
                emailId: emailId,
                category: category,
                confidence: parsedResult.confidence,
                rationale: parsedResult.rationale,
                summary: parsedResult.summary
            )
            
        } catch {
            print("❌ Failed to parse classification response: \(content)")
            throw ClassificationError.invalidResponse
        }
    }
    
    /// Intelligently truncates email body while preserving key content for classification
    private func intelligentTruncate(_ body: String, maxLength: Int) -> String {
        guard body.count > maxLength else { return body }
        
        // For very short limits, just take the beginning
        guard maxLength > 500 else {
            return String(body.prefix(maxLength))
        }
        
        // For longer emails, take the beginning (which often contains key info)
        // and a smaller sample from the middle/end
        let beginningLength = Int(Double(maxLength) * 0.7) // 70% from beginning
        let endLength = maxLength - beginningLength // 30% from end
        
        let beginning = String(body.prefix(beginningLength))
        let ending = String(body.suffix(endLength))
        
        // Add a separator to indicate truncation
        return beginning + "\n\n[... content truncated ...]\n\n" + ending
    }
    
    private func performDigestGeneration(emails: [ClassifiedEmail], period: String, apiKey: String) async throws -> DailyDigest {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        
        // Create the digest request
        let digestRequest = try createDigestRequest(emails: emails, period: period)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(digestRequest)
        
        print("🌐 Sending daily digest generation request for \(emails.count) emails")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 HTTP Response Status: \(httpResponse.statusCode)")
                
                switch httpResponse.statusCode {
                case 200:
                    break // Success
                case 401:
                    print("🔑 Authentication failed - check API key")
                    throw ClassificationError.invalidAPIKey
                case 429:
                    print("🚦 Rate limit exceeded")
                    throw ClassificationError.apiRateLimitExceeded
                default:
                    print("❌ HTTP Error \(httpResponse.statusCode)")
                    throw ClassificationError.classificationFailed("HTTP \(httpResponse.statusCode)")
                }
            }
            
            let apiResponse = try jsonDecoder.decode(OpenAIResponse.self, from: data)
            return try parseDigestResponse(apiResponse)
            
        } catch let error as ClassificationError {
            throw error
        } catch let urlError as URLError {
            print("🌐 URLError: \(urlError.localizedDescription) (Code: \(urlError.code.rawValue))")
            throw ClassificationError.networkError
        } catch {
            print("⚠️ Unexpected digest generation error: \(error)")
            throw ClassificationError.classificationFailed(error.localizedDescription)
        }
    }
    
    private func createDigestRequest(emails: [ClassifiedEmail], period: String) throws -> OpenAIDigestRequest {
        let responseFormat = OpenAIDigestRequest.ResponseFormat(
            type: "json_object",
            json_schema: nil
        )
        
        // Convert emails to JSON for the prompt
        let emailsJSON = try String(data: jsonEncoder.encode(emails), encoding: .utf8) ?? "[]"
        
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
        - Headline ≤ 10 words, evocative but grounded (no astrology, no feelings beyond email facts).
        - Highlights: ≤ 8 items; each ≤ 15 words.
        - Actions: ≤ 8 items; titles begin with a verb ("Pay", "Reply", "Approve", "Schedule").
        - Pillars arrays: 1–3 bullets each.
        - Do not leak passwords/codes. Redact to "••••".
        
        Input array (email_item):
        \(emailsJSON)
        """
        
        return OpenAIDigestRequest(
            model: "gpt-4o-mini",
            temperature: configuration.temperature,
            response_format: responseFormat,
            messages: [
                OpenAIDigestRequest.Message(role: "user", content: prompt)
            ]
        )
    }
    
    private func parseDigestResponse(_ response: OpenAIResponse) throws -> DailyDigest {
        guard let choice = response.choices.first,
              let content = choice.message.content else {
            throw ClassificationError.invalidResponse
        }
        
        do {
            let digestData = content.data(using: .utf8) ?? Data()
            let digest = try jsonDecoder.decode(DailyDigest.self, from: digestData)
            return digest
            
        } catch {
            print("❌ Failed to parse daily digest response: \(content)")
            print("❌ Decode error: \(error)")
            throw ClassificationError.invalidResponse
        }
    }
}

// MARK: - Request/Response Models

private struct OpenAIClassificationRequest: Encodable {
    struct ResponseFormat: Encodable {
        struct JSONSchema: Encodable {
            let name: String
            let schema: [String: AnyEncodable]
            let strict: Bool
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

private struct OpenAIDigestRequest: Encodable {
    struct ResponseFormat: Encodable {
        struct JSONSchema: Encodable {
            let name: String
            let schema: [String: AnyEncodable]
            let strict: Bool
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

private struct ClassificationResponseData: Decodable {
    let category: String
    let confidence: Double
    let rationale: String?
    let summary: String?
}

/// Helper for encoding Any values
internal struct AnyEncodable: Encodable {
    let value: Any
    
    init(value: Any) {
        self.value = value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map(AnyEncodable.init))
        case let dict as [String: Any]:
            try container.encode(dict.mapValues(AnyEncodable.init))
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Cannot encode value of type \(type(of: value))"
                )
            )
        }
    }
}

// MARK: - Array Extensions

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}