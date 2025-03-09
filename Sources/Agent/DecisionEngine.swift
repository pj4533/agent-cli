import Foundation

/// Structure for OpenAI's action response
struct GPTActionResponse: Codable {
    let action: String
    let targetTile: Coordinate
    let reason: String
}

/// Class responsible for making agent decisions
class DecisionEngine {
    private let openAIService: OpenAIService
    private let logger = AgentLogger(category: "Decision")
    
    /// Rules that govern agent behavior in the world
    private let worldRules = [
        "You cannot pass through water or mountains",
        "You can only move to one of the 8 adjacent tiles (up, down, left, right, or diagonals)",
        "You must move exactly one tile at a time"
    ]
    
    /// Agent traits that define its personality and preferences
    private var agentTraits: [String] = []
    
    init(openAIService: OpenAIService) {
        self.openAIService = openAIService
        loadAgentTraits()
    }
    
    /// Load agent traits from .agentTraits file if it exists
    private func loadAgentTraits() {
        let fileManager = FileManager.default
        let traitsFilePath = ".agentTraits"
        
        if fileManager.fileExists(atPath: traitsFilePath) {
            do {
                let traitsContent = try String(contentsOfFile: traitsFilePath, encoding: .utf8)
                let traits = traitsContent.components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                
                agentTraits = traits
                logger.info("Agent traits loaded: \(traits.count) traits found")
                for trait in traits {
                    log("Agent trait: \(trait)", verbose: true)
                }
            } catch {
                logger.error("Failed to read agent traits file: \(error.localizedDescription)")
                log("❌ Error reading .agentTraits file: \(error.localizedDescription)", verbose: true)
            }
        } else {
            logger.info("No agent traits file found (.agentTraits)")
            log("No agent traits file found. Using default personality.", verbose: true)
        }
    }
    
    /// Determine the next action based on observation using LLM
    func decideNextAction(basedOn response: ServerResponse) async throws -> AgentAction {
        log("🧠 Deciding next action based on observation at time step \(response.timeStep)", verbose: true)
        logger.info("Analyzing current state and making a decision... 🧠")
        
        // Log the current agent position and surroundings
        log("Current position: (\(response.currentLocation.x), \(response.currentLocation.y)) - \(response.currentLocation.type)", verbose: true)
        log("Surroundings: \(response.surroundings.tiles.count) tiles, \(response.surroundings.agents.count) agents", verbose: true)
        
        // Create system prompt with agent traits and world rules
        var systemPromptBuilder = ["You are an explorer in a new world."]
        
        // Add agent traits if available
        if !agentTraits.isEmpty {
            systemPromptBuilder.append("")
            systemPromptBuilder.append("You are guided by these traits:")
            for trait in agentTraits {
                systemPromptBuilder.append("- \(trait)")
            }
        }
        
        // Add world rules
        systemPromptBuilder.append("")
        systemPromptBuilder.append("The world has these rules you must follow:")
        for rule in worldRules {
            systemPromptBuilder.append("- \(rule)")
        }
        
        let systemPrompt = systemPromptBuilder.joined(separator: "\n")
        
        // Create a user prompt with the current observation
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let observationData = try encoder.encode(response)
        let observationString = String(data: observationData, encoding: .utf8) ?? "Unable to encode observation"
        
        let userPrompt = """
        Decide where to move next. You can only move to one of the 8 adjacent tiles.
        
        Output your next move using JSON formatted like this:
        {"action": "move", "targetTile": {"x": 1, "y": 2}, "reason": "Brief explanation of why you chose this move."}
        
        Remember:
        - You can only move to one of the 8 adjacent tiles (horizontal, vertical, or diagonal)
        - You must move exactly one tile at a time
        - You cannot move to water or mountain tiles
        
        Include a clear reason field explaining your decision-making process based on your traits and the current surroundings.
        
        Current Observation:
        \(observationString)
        """
        
        // Mark the start of LLM decision making 
        let decisionStartTime = Date()
        log("Starting LLM request for movement decision", verbose: true)
        
        // Get a response from the OpenAI API
        let jsonResponse = try await openAIService.chatCompletion(systemPrompt: systemPrompt, userPrompt: userPrompt)
        
        // Log timing information
        let decisionDuration = Date().timeIntervalSince(decisionStartTime)
        log("Decision process took \(String(format: "%.2f", decisionDuration)) seconds", verbose: true)
        
        // Parse the response and create an action
        let action = parseAndCreateAction(from: jsonResponse, fallbackLocation: response.currentLocation)
        
        // Validate the action
        return validateAction(action, basedOn: response)
    }
    
    /// Parse the AI response and create an agent action
    private func parseAndCreateAction(from jsonResponse: String, fallbackLocation: Location) -> AgentAction {
        // Parse the JSON response
        let responseData = jsonResponse.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        do {
            let gptAction = try decoder.decode(GPTActionResponse.self, from: responseData)
            
            // Log the decision and reasoning
            logger.info("🧠 AI's reasoning: \(gptAction.reason)")
            log("Moving to position: (\(gptAction.targetTile.x), \(gptAction.targetTile.y))", verbose: true)
            log("Reason: \(gptAction.reason)", verbose: true)
            
            // Convert to AgentAction - don't send reason to server
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
            logger.error("Failed to parse AI response, staying in place")
            log("Using fallback action: staying in place at (\(fallbackLocation.x), \(fallbackLocation.y))", verbose: true)
            
            return AgentAction(
                action: .move,
                targetTile: Coordinate(x: fallbackLocation.x, y: fallbackLocation.y),
                message: "Staying in place due to parsing error."
            )
        }
    }
    
    /// Validate action to ensure it's legal
    private func validateAction(_ action: AgentAction, basedOn response: ServerResponse) -> AgentAction {
        // Verify that the target tile is valid (adjacent and not water)
        if let targetTile = action.targetTile {
            let currentX = response.currentLocation.x
            let currentY = response.currentLocation.y
            let dx = abs(targetTile.x - currentX)
            let dy = abs(targetTile.y - currentY)
            
            // Check if the move is to one of the 8 adjacent tiles or staying in place
            // Adjacent means maximum distance of 1 in any direction (including diagonals)
            let isAdjacent = dx <= 1 && dy <= 1 && !(dx == 0 && dy == 0)
            
            // Find if the target is water or mountain
            let targetTileInfo = response.surroundings.tiles.first { 
                $0.x == targetTile.x && $0.y == targetTile.y 
            }
            let isInvalidTerrain = targetTileInfo?.type == .water || targetTileInfo?.type == .mountain
            
            if !isAdjacent || isInvalidTerrain {
                log("⚠️ LLM suggested invalid move to (\(targetTile.x), \(targetTile.y))", verbose: true)
                
                if !isAdjacent {
                    logger.error("Invalid move: (\(targetTile.x), \(targetTile.y)) - Not one of the 8 adjacent tiles")
                } else {
                    logger.error("Invalid move: (\(targetTile.x), \(targetTile.y)) - Cannot move to \(targetTileInfo?.type.rawValue ?? "unknown") terrain")
                }
                
                // Create a simple stay-in-place action as fallback
                return AgentAction(
                    action: .move,
                    targetTile: Coordinate(x: currentX, y: currentY),
                    message: "Staying in place due to validation error."
                )
            }
        }
        
        return action
    }
}