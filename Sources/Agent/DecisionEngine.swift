import Foundation

/// Class responsible for making agent decisions
class DecisionEngine {
    private let openAIService: OpenAIService?
    private let logger = AgentLogger(category: "Decision")
    
    init(openAIService: OpenAIService?) {
        self.openAIService = openAIService
    }
    
    /// Determine the next action based on observation, using LLM or random movement
    func decideNextAction(basedOn response: ServerResponse, useRandom: Bool = false) async throws -> AgentAction {
        if useRandom || openAIService == nil {
            return createRandomAction(basedOn: response)
        } else {
            return try await decideLLMAction(basedOn: response)
        }
    }
    
    /// Use LLM for decision making
    private func decideLLMAction(basedOn response: ServerResponse) async throws -> AgentAction {
        log("🤖 Using LLM to decide next action at time step \(response.timeStep)", verbose: true)
        
        guard let openAIService = openAIService else {
            throw NSError(domain: "DecisionEngine", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "OpenAI service not initialized"
            ])
        }
        
        logger.info("Asking AI for next move... 🧠")
        let action = try await openAIService.decideNextAction(observation: response)
        
        // Verify that the target tile is valid (adjacent and not water)
        if let targetTile = action.targetTile {
            let currentX = response.currentLocation.x
            let currentY = response.currentLocation.y
            let dx = abs(targetTile.x - currentX)
            let dy = abs(targetTile.y - currentY)
            
            // If not adjacent or if water, fall back to random
            let isAdjacent = (dx == 1 && dy == 0) || (dx == 0 && dy == 1) || (dx == 0 && dy == 0)
            
            // Find if the target is water
            let targetTileInfo = response.surroundings.tiles.first { 
                $0.x == targetTile.x && $0.y == targetTile.y 
            }
            let isWater = targetTileInfo?.type == .water
            
            if !isAdjacent || isWater {
                log("⚠️ LLM suggested invalid move to (\(targetTile.x), \(targetTile.y)), using fallback", verbose: true)
                return createRandomAction(basedOn: response)
            }
        }
        
        return action
    }
    
    /// Generate a random action (for fallback or when random movement is enabled)
    private func createRandomAction(basedOn response: ServerResponse) -> AgentAction {
        // Get current position
        let currentX = response.currentLocation.x
        let currentY = response.currentLocation.y
        
        // Find immediately adjacent tiles that aren't water (no diagonals)
        let walkableTiles = response.surroundings.tiles.filter { tile in
            // Calculate Manhattan distance to check adjacency (only direct neighbors)
            let dx = abs(tile.x - currentX)
            let dy = abs(tile.y - currentY)
            
            // Only one step in one direction (up, down, left, right)
            let isAdjacent = (dx == 1 && dy == 0) || (dx == 0 && dy == 1)
            
            // Must not be water
            let isWalkable = tile.type != .water
            
            return isAdjacent && isWalkable
        }
        
        // Choose a random walkable tile
        if let targetTile = walkableTiles.randomElement() {
            return AgentAction(
                action: .move,
                targetTile: Coordinate(x: targetTile.x, y: targetTile.y),
                message: nil
            )
        } else {
            // If no walkable tiles, stay in place but using move action
            return AgentAction(
                action: .move,
                targetTile: Coordinate(x: currentX, y: currentY),
                message: nil
            )
        }
    }
}