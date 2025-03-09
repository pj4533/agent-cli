import Foundation

// MARK: - OpenAI Models

/// Request structure for OpenAI chat completions
struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let response_format: ResponseFormat?
    
    struct ResponseFormat: Codable {
        let type: String
    }
}

/// Chat message for OpenAI completions
struct ChatMessage: Codable {
    let role: String
    let content: String
}

/// Response structure from OpenAI chat completions
struct ChatCompletionResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    
    struct Choice: Codable {
        let index: Int
        let message: ChatMessage
        let finish_reason: String
    }
}

// MARK: - OpenAI Service

/// Service responsible for communicating with the OpenAI API
actor OpenAIService {
    // MARK: - Properties
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let logger = AgentLogger(category: "OpenAI")
    private var conversationHistory: [ChatMessage] = []
    private let defaultMemorySize = 5
    
    // MARK: - Initialization
    init(apiKey: String) {
        self.apiKey = apiKey
        log("🧠 OpenAI service initialized", verbose: true)
    }
    
    // MARK: - Chat Completion
    
    /// Send a chat completion request to OpenAI API and return the response content
    /// - Parameters:
    ///   - systemPrompt: The system prompt for the chat
    ///   - userPrompt: The user prompt for the chat
    /// - Returns: The content of the model's response
    func chatCompletion(systemPrompt: String, userPrompt: String) async throws -> String {
        log("🤖 Sending chat completion request to OpenAI", verbose: true)
        
        // Log the prompts when verbose
        log("SYSTEM_PROMPT: \(systemPrompt)", verbose: true)
        log("USER_PROMPT: \(userPrompt)", verbose: true)
        
        // Add current user message to conversation history
        let userMessage = ChatMessage(role: "user", content: userPrompt)
        conversationHistory.append(userMessage)
        
        // Get memory size from environment or use default
        let memorySize = getMemorySize()
        log("Using thread memory size: \(memorySize)", verbose: true)
        
        // Create the request with system prompt and recent conversation history
        var messages = [ChatMessage(role: "system", content: systemPrompt)]
        
        // Add recent conversation messages (limited by memory size)
        if conversationHistory.count > 0 {
            let startIndex = max(0, conversationHistory.count - (memorySize * 2))
            let recentMessages = Array(conversationHistory[startIndex..<conversationHistory.count])
            messages.append(contentsOf: recentMessages)
        }
        
        log("Including \(messages.count - 1) previous messages in context", verbose: true)
        
        let requestBody = ChatCompletionRequest(
            model: "gpt-4o",
            messages: messages,
            response_format: ChatCompletionRequest.ResponseFormat(type: "json_object")
        )
        
        // Encode the request
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted]
        let requestData = try jsonEncoder.encode(requestBody)
        
        // Log the request payload when verbose
        if let requestStr = String(data: requestData, encoding: .utf8) {
            log("REQUEST: \(requestStr)", verbose: true)
        }
        
        // Create URL request
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = requestData
        
        // Send the request
        let requestStartTime = Date()
        log("📤 Sending request to OpenAI API", verbose: true)
        let (data, response) = try await URLSession.shared.data(for: request)
        let requestDuration = Date().timeIntervalSince(requestStartTime)
        
        log("Request took \(String(format: "%.2f", requestDuration)) seconds", verbose: true)
        
        // Log raw response data when verbose (truncated for readability)
        if let responseStr = String(data: data, encoding: .utf8) {
            let displayResponse = responseStr.count > 1000 
                ? String(responseStr.prefix(1000)) + "... [truncated]" 
                : responseStr
            log("RAW_RESPONSE: \(displayResponse)", verbose: true)
        }
        
        // Check for HTTP errors
        guard let httpResponse = response as? HTTPURLResponse else {
            let errorMsg = "Invalid response from OpenAI API"
            log("❌ \(errorMsg)", verbose: true)
            logger.error(errorMsg)
            throw NSError(domain: "OpenAIService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: errorMsg
            ])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            let errorMsg = "HTTP error \(httpResponse.statusCode): \(errorMessage)"
            log("❌ \(errorMsg)", verbose: true)
            logger.error("OpenAI API error: \(httpResponse.statusCode)")
            throw NSError(domain: "OpenAIService", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: errorMsg
            ])
        }
        
        // Parse the response
        let jsonDecoder = JSONDecoder()
        let apiResponse = try jsonDecoder.decode(ChatCompletionResponse.self, from: data)
        
        guard let choice = apiResponse.choices.first else {
            let errorMsg = "No choices in OpenAI API response"
            log("❌ \(errorMsg)", verbose: true)
            logger.error(errorMsg)
            throw NSError(domain: "OpenAIService", code: 3, userInfo: [
                NSLocalizedDescriptionKey: errorMsg
            ])
        }
        
        // Log the model's response
        log("RESPONSE_CONTENT: \(choice.message.content)", verbose: true)
        log("FINISH_REASON: \(choice.finish_reason)", verbose: true)
        
        // Add assistant's response to conversation history
        conversationHistory.append(choice.message)
        
        log("✅ Received response from OpenAI API", verbose: true)
        return choice.message.content
    }
    
    // MARK: - Helper Methods
    
    /// Get the memory size from environment or use default
    private func getMemorySize() -> Int {
        if let memorySizeStr = EnvironmentService.getEnvironmentVariable("THREAD_MEMORY_SIZE"),
           let memorySize = Int(memorySizeStr) {
            return memorySize
        }
        return defaultMemorySize
    }
}