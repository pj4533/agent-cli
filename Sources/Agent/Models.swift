import Foundation

// MARK: - ServerResponse
struct ServerResponse: Codable {
    let currentLocation: Location
    let timeStep: Int
    let surroundings: Surroundings
    let agent_id: String
    let responseType: String
}

// MARK: - ActionResponse
struct ActionResponse: Codable {
    let data: ActionResponseData
    let message: String
    let responseType: String
}

// MARK: - ActionResponseData
struct ActionResponseData: Codable {
    let currentTileType: String
    let x: String
    let y: String
}

// MARK: - Location
struct Location: Codable {
    let x: Int
    let y: Int
    let type: TileType
}

// MARK: - Surroundings
struct Surroundings: Codable {
    let agents: [Agent]
    let tiles: [Tile]
}

// MARK: - Tile
struct Tile: Codable {
    let x: Int
    let y: Int
    let type: TileType
}

// MARK: - Agent
struct Agent: Codable {
    let agent_id: String
    let x: Int
    let y: Int
}

// MARK: - TileType
enum TileType: String, Codable {
    case desert
    case water
    case grass
    case forest
    case mountain
    case snow
    
    // Handle unknown tile types by defaulting to a known type
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        
        if let type = TileType(rawValue: rawValue) {
            self = type
        } else {
            // Default to desert for unknown types
            self = .desert
        }
    }
}

// MARK: - AgentAction
struct AgentAction: Codable {
    let action: ActionType
    let targetTile: Coordinate?
    let message: String?
    
    // Only include non-nil fields in JSON
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        
        if let targetTile = targetTile {
            try container.encode(targetTile, forKey: .targetTile)
        }
        
        if let message = message {
            try container.encode(message, forKey: .message)
        }
    }
}

// MARK: - Coordinate
struct Coordinate: Codable {
    let x: Int
    let y: Int
}

// MARK: - ActionType
enum ActionType: String, Codable {
    case move
}