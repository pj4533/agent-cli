import Foundation
import OSLog

// Reuse the logger from AgentMain
fileprivate func log(_ message: String, verbose: Bool = false) {
    // Only log if we've set AGENT_VERBOSE environment variable
    if verbose && ProcessInfo.processInfo.environment["AGENT_VERBOSE"] == "1" {
        let logger = AgentLogger(category: "OpenAI")
        
        // Truncate very long messages for console output
        var displayMessage = message
        if displayMessage.count > 1000 {
            displayMessage = String(displayMessage.prefix(1000)) + "... [truncated]"
        }
        
        logger.debug(displayMessage)
    }
}

// MARK: - OpenAI Models

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let response_format: ResponseFormat?
    
    struct ResponseFormat: Codable {
        let type: String
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

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

struct GPTActionResponse: Codable {
    let action: String
    let targetTile: Coordinate
}

// MARK: - OpenAI Service

actor OpenAIService {
    // MARK: - Properties
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    // MARK: - Initialization
    init(apiKey: String) {
        self.apiKey = apiKey
        log("🧠 OpenAI service initialized", verbose: true)
    }
    
    // MARK: - Chat Completion
    func chatCompletion(systemPrompt: String, userPrompt: String) async throws -> String {
        log("🤖 Sending chat completion request to OpenAI", verbose: true)
        
        // Log the prompts when verbose
        log("SYSTEM_PROMPT: \(systemPrompt)", verbose: true)
        log("USER_PROMPT: \(userPrompt)", verbose: true)
        
        // Create the request
        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: userPrompt)
        ]
        
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
        
        // Log raw response data when verbose
        if let responseStr = String(data: data, encoding: .utf8) {
            log("RAW_RESPONSE: \(responseStr)", verbose: true)
        }
        
        // Check for HTTP errors
        guard let httpResponse = response as? HTTPURLResponse else {
            let errorMsg = "Invalid response from OpenAI API"
            log("❌ \(errorMsg)", verbose: true)
            throw NSError(domain: "OpenAIService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: errorMsg
            ])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            let errorMsg = "HTTP error \(httpResponse.statusCode): \(errorMessage)"
            log("❌ \(errorMsg)", verbose: true)
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
            throw NSError(domain: "OpenAIService", code: 3, userInfo: [
                NSLocalizedDescriptionKey: errorMsg
            ])
        }
        
        // Log the model's response
        log("RESPONSE_CONTENT: \(choice.message.content)", verbose: true)
        log("FINISH_REASON: \(choice.finish_reason)", verbose: true)
        
        log("✅ Received response from OpenAI API", verbose: true)
        return choice.message.content
    }
    
    // MARK: - Decision Making
    func decideNextAction(observation: ServerResponse) async throws -> AgentAction {
        log("🧠 Deciding next action based on observation at time step \(observation.timeStep)", verbose: true)
        
        // Log the current agent position and surroundings
        log("Current position: (\(observation.currentLocation.x), \(observation.currentLocation.y)) - \(observation.currentLocation.type)", verbose: true)
        log("Surroundings: \(observation.surroundings.tiles.count) tiles, \(observation.surroundings.agents.count) agents", verbose: true)
        
        let systemPrompt = """
        You are an explorer in a new world. 
        Try to see as much of the world as you can, without revisiting areas you have already visited.

        You cannot pass through water or mountains, but you can move one tile in any direction.
        """
        
        // Create a user prompt with the current observation
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let observationData = try encoder.encode(observation)
        let observationString = String(data: observationData, encoding: .utf8) ?? "Unable to encode observation"
        
        let userPrompt = """
        Decide where to move next.
        
        Output your next move using JSON formatted like this:
        {"action": "move", "targetTile": {"x": 1, "y": 2}}
        
        Current Observation:
        \(observationString)
        """
        
        // Mark the start of LLM decision making 
        let decisionStartTime = Date()
        log("Starting LLM request for movement decision", verbose: true)
        
        // Get a response from the OpenAI API
        let jsonResponse = try await chatCompletion(systemPrompt: systemPrompt, userPrompt: userPrompt)
        
        // Log timing information
        let decisionDuration = Date().timeIntervalSince(decisionStartTime)
        log("Decision process took \(String(format: "%.2f", decisionDuration)) seconds", verbose: true)
        
        // Parse the JSON response
        let responseData = jsonResponse.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        do {
            let gptAction = try decoder.decode(GPTActionResponse.self, from: responseData)
            
            // Log the decision that was made
            log("Moving to position: (\(gptAction.targetTile.x), \(gptAction.targetTile.y))", verbose: true)
            
            // Convert to AgentAction
            return AgentAction(
                action: .move,
                targetTile: gptAction.targetTile,
                message: nil
            )
        } catch {
            // Log parsing error
            log("❌ Failed to decode OpenAI response: \(error.localizedDescription)", verbose: true)
            log("📄 Raw response: \(jsonResponse)", verbose: true)
            
            // Fallback to a simple action (stay in place)
            log("Using fallback action: staying in place at (\(observation.currentLocation.x), \(observation.currentLocation.y))", verbose: true)
            
            return AgentAction(
                action: .move,
                targetTile: Coordinate(x: observation.currentLocation.x, y: observation.currentLocation.y),
                message: nil
            )
        }
    }
}