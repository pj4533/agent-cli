import Foundation

/// Class responsible for making agent decisions
class DecisionEngine {
    private let openAIService: OpenAIService
    private let logger = AgentLogger(category: "Decision")
    
    init(openAIService: OpenAIService) {
        self.openAIService = openAIService
    }
    
    /// Determine the next action based on observation using LLM
    func decideNextAction(basedOn response: ServerResponse) async throws -> AgentAction {
        log("🤖 Using LLM to decide next action at time step \(response.timeStep)", verbose: true)
        logger.info("Asking AI for next move... 🧠")
        
        // Get action from OpenAI
        let action = try await openAIService.decideNextAction(observation: response)
        
        // Verify that the target tile is valid (adjacent and not water)
        if let targetTile = action.targetTile {
            let currentX = response.currentLocation.x
            let currentY = response.currentLocation.y
            let dx = abs(targetTile.x - currentX)
            let dy = abs(targetTile.y - currentY)
            
            // Check if the move is adjacent
            let isAdjacent = (dx == 1 && dy == 0) || (dx == 0 && dy == 1) || (dx == 0 && dy == 0)
            
            // Find if the target is water
            let targetTileInfo = response.surroundings.tiles.first { 
                $0.x == targetTile.x && $0.y == targetTile.y 
            }
            let isWater = targetTileInfo?.type == .water
            
            if !isAdjacent || isWater {
                log("⚠️ LLM suggested invalid move to (\(targetTile.x), \(targetTile.y))", verbose: true)
                logger.error("Invalid move suggested by LLM: \(targetTile.x), \(targetTile.y). Not adjacent or water.")
                
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