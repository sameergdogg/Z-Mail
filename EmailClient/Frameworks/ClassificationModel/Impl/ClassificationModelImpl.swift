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
            if configuration.enableDetailedLogging {
                print("📋 Using cached classification for email: \(email.id)")
            }
            return cachedResult
        }
        
        // Validate email size
        if email.body.count > configuration.maxBodyLength * 2 {
            throw ClassificationError.emailTooLarge
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
            
            if configuration.enableDetailedLogging {
                print("✅ Successfully classified email: \(email.id) as \(result.category.rawValue) with confidence \(result.confidence)")
            }
            
            return result
            
        } catch {
            if configuration.enableDetailedLogging {
                print("❌ Failed to classify email: \(email.id) - \(error)")
            }
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
                        if configuration.enableDetailedLogging {
                            print("❌ Batch classification error: \(error)")
                        }
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
        if configuration.enableDetailedLogging {
            print("🗑️ Cleared classification cache")
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
        
        if configuration.enableDetailedLogging {
            print("🌐 Sending classification request for email: \(email.id)")
        }
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if configuration.enableDetailedLogging {
                    print("📡 HTTP Response Status: \(httpResponse.statusCode)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("📡 Response Body: \(responseString)")
                    }
                }
                
                switch httpResponse.statusCode {
                case 200:
                    break // Success
                case 401:
                    if configuration.enableDetailedLogging {
                        print("🔑 Authentication failed - check API key")
                    }
                    throw ClassificationError.invalidAPIKey
                case 429:
                    if configuration.enableDetailedLogging {
                        print("🚦 Rate limit exceeded")
                    }
                    throw ClassificationError.apiRateLimitExceeded
                default:
                    if configuration.enableDetailedLogging {
                        print("❌ HTTP Error \(httpResponse.statusCode)")
                    }
                    throw ClassificationError.classificationFailed("HTTP \(httpResponse.statusCode)")
                }
            }
            
            let apiResponse = try jsonDecoder.decode(OpenAIResponse.self, from: data)
            return try parseClassificationResponse(apiResponse, emailId: email.id)
            
        } catch let error as ClassificationError {
            throw error
        } catch let urlError as URLError {
            if configuration.enableDetailedLogging {
                print("🌐 URLError: \(urlError.localizedDescription) (Code: \(urlError.code.rawValue))")
            }
            throw ClassificationError.networkError
        } catch {
            if configuration.enableDetailedLogging {
                print("⚠️ Unexpected error: \(error)")
            }
            throw ClassificationError.classificationFailed(error.localizedDescription)
        }
    }
    
    private func createClassificationRequest(email: EmailData) throws -> OpenAIClassificationRequest {
        // Truncate email body to max length
        let truncatedBody = String(email.body.prefix(configuration.maxBodyLength))
        
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
            "rationale": "Brief explanation"
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
                rationale: parsedResult.rationale
            )
            
        } catch {
            if configuration.enableDetailedLogging {
                print("❌ Failed to parse classification response: \(content)")
            }
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

private struct ClassificationResponseData: Decodable {
    let category: String
    let confidence: Double
    let rationale: String?
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