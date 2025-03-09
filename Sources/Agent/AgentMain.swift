import Foundation
import ArgumentParser
import OSLog

// MARK: - Logger setup
// Avoid direct mutable state by using environment variables only
fileprivate func setVerboseMode(_ verbose: Bool) {
    if verbose {
        setenv("AGENT_VERBOSE", "1", 1)
    } else {
        unsetenv("AGENT_VERBOSE")
    }
}

// Check if verbose mode is enabled
fileprivate func isVerboseMode() -> Bool {
    return ProcessInfo.processInfo.environment["AGENT_VERBOSE"] == "1"
}

// Agent logger struct that uses OSLog but also prints to terminal for CLI usage
struct AgentLogger {
    private let logger: Logger
    private let category: String
    
    init(category: String) {
        self.logger = Logger(subsystem: "com.agentworld.Agent", category: category)
        self.category = category
    }
    
    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        // Also print to terminal for CLI visibility
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] [\(category)] DEBUG: \(message)")
    }
    
    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        // Also print to terminal for CLI visibility
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] [\(category)] INFO: \(message)")
    }
    
    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        // Also print to terminal for CLI visibility
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] [\(category)] ERROR: \(message)")
    }
}

// Central logging function that respects verbose flag
fileprivate func log(_ message: String, verbose: Bool = false, forceShow: Bool = false) {
    // Only log if we're in verbose mode OR this is a message that should always be shown
    if forceShow || (verbose && isVerboseMode()) {
        let logger = AgentLogger(category: "Agent")
        logger.debug(message)
    }
}

// MARK: - Agent Command
struct AgentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent",
        abstract: "A client agent for AgentWorld 🌎",
        version: "1.0.0"
    )
    
    // MARK: - Command Arguments
    @Option(name: .long, help: "The host to connect to 🖥️")
    var host: String = "localhost"
    
    @Option(name: .long, help: "The port to connect to 🔌")
    var port: UInt16 = 8000
    
    @Option(name: .long, help: "Path to .env file 📄")
    var envFile: String = ".env"
    
    @Flag(name: .long, help: "Use random movement instead of LLM 🎲")
    var randomMovement: Bool = false
    
    @Flag(name: .long, help: "Enable verbose logging output 📝")
    var verbose: Bool = false
    
    // MARK: - Command execution
    func run() async throws {
        // Set verbose mode if flag is enabled
        setVerboseMode(verbose)
        
        if verbose {
            let logger = AgentLogger(category: "Agent")
            logger.info("Verbose logging enabled 📝")
        }
        
        log("🚀 Agent starting up!", verbose: true, forceShow: true)
        
        // Load environment variables from .env file
        EnvironmentService.loadEnvironment(from: envFile)
        
        // Initialize OpenAI service if we're using LLM-based decisions
        let openAIService: OpenAIService?
        
        if !randomMovement {
            // Get OpenAI API key from environment
            guard let apiKey = EnvironmentService.getEnvironmentVariable("OPENAI_API_KEY") else {
                log("❌ OPENAI_API_KEY not found in environment or .env file", verbose: true)
                let logger = AgentLogger(category: "Agent")
                logger.error("OPENAI_API_KEY environment variable is required")
                logger.error("Please add it to your .env file or set it in your environment")
                throw NSError(domain: "AgentCommand", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "OPENAI_API_KEY not found"
                ])
            }
            
            // Initialize OpenAI service
            openAIService = OpenAIService(apiKey: apiKey)
            log("🧠 LLM-based decision making enabled", verbose: true)
            let logger = AgentLogger(category: "Agent")
            logger.info("LLM-based decision making enabled 🧠")
        } else {
            openAIService = nil
            log("🎲 Random movement enabled", verbose: true)
            let logger = AgentLogger(category: "Agent")
            logger.info("Random movement enabled 🎲")
        }
        
        log("🔌 Connecting to \(self.host):\(self.port)", verbose: true)
        let logger = AgentLogger(category: "Agent")
        logger.info("Connecting to \(host):\(port)...")
        
        // Create network service and establish connection
        let networkService = NetworkService(host: host, port: port)
        
        do {
            // Connect to the server
            try await networkService.connect()
            let logger = AgentLogger(category: "Agent")
            logger.info("Connected to server! 🎉")
            
            // Keep receiving data in a loop
            try await receiveDataLoop(using: networkService, openAIService: openAIService)
        } catch {
            log("❌ Connection error: \(error.localizedDescription)", verbose: true)
            let logger = AgentLogger(category: "Agent")
            logger.error("Failed to connect: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func receiveDataLoop(using networkService: NetworkService, openAIService: OpenAIService?) async throws {
        let logger = AgentLogger(category: "Agent")
        logger.info("Listening for server messages... 👂")
        
        // Start an infinite loop to receive data
        while true {
            do {
                let data = try await networkService.receiveData()
                
                do {
                    let decoder = JSONDecoder()
                    
                    // Try to parse the data as either a ServerResponse or ActionResponse
                    if let actionResponse = try? decoder.decode(ActionResponse.self, from: data) {
                        // Handle action response
                        let logger = AgentLogger(category: "Agent")
                        logger.info("📩 Received action response: \(actionResponse.message)")
                        logger.info("🧭 Current position: (\(actionResponse.data.x), \(actionResponse.data.y)) - \(actionResponse.data.currentTileType)")
                        
                        log("📨 Received action response: \(actionResponse.responseType)", verbose: true)
                    } else {
                        // Try to parse as regular ServerResponse for observations
                        let response = try decoder.decode(ServerResponse.self, from: data)
                        
                        // Process the server response
                        let logger = AgentLogger(category: "Agent")
                        logger.info("📩 Received observation at time step \(response.timeStep)")
                        logger.info("🧭 Current location: (\(response.currentLocation.x), \(response.currentLocation.y)) - \(response.currentLocation.type)")
                        logger.info("👀 Surroundings: \(response.surroundings.tiles.count) tiles and \(response.surroundings.agents.count) agents visible")
                        
                        log("📨 Received response: \(response.responseType) for agent \(response.agent_id)", verbose: true)
                        
                        // Only send an action if this is an observation message
                        if response.responseType == "observation" {
                            // Decide on the next action
                            let action: AgentAction
                            
                            if randomMovement || openAIService == nil {
                                // Use simple random movement logic
                                action = createRandomAction(basedOn: response)
                            } else {
                                // Use LLM for decision making
                                do {
                                    action = try await decideNextAction(basedOn: response, using: openAIService)
                                } catch {
                                    log("❌ LLM decision error: \(error.localizedDescription), falling back to random", verbose: true)
                                    action = createRandomAction(basedOn: response)
                                }
                            }
                            
                            // Send the action to the server
                            try await networkService.sendAction(action)
                            let logger = AgentLogger(category: "Agent")
                            logger.info("🚀 Sent action: \(action.action.rawValue) to \(action.targetTile?.x ?? 0), \(action.targetTile?.y ?? 0)")
                        } else {
                            let logger = AgentLogger(category: "Agent")
                            logger.info("📝 Received \(response.responseType) message, not sending an action")
                        }
                    }
                } catch {
                    // If parsing fails, show the raw data
                    let logger = AgentLogger(category: "Agent")
                    if let message = String(data: data, encoding: .utf8) {
                        logger.info("📩 Received (unparsed): \(message)")
                        log("📨 Received unparsed message: \(message)", verbose: true)
                    } else {
                        // For binary data, show size and first few bytes
                        let preview = data.prefix(min(10, data.count))
                            .map { String(format: "%02x", $0) }
                            .joined(separator: " ")
                        
                        logger.info("📦 Received \(data.count) bytes: \(preview)...")
                        log("📦 Received binary data: \(data.count) bytes", verbose: true)
                    }
                    
                    log("🔄 JSON parsing error: \(error.localizedDescription)", verbose: true)
                }
            } catch {
                log("📡 Data reception error: \(error.localizedDescription)", verbose: true)
                let logger = AgentLogger(category: "Agent")
                logger.error("❌ Connection error: \(error.localizedDescription)")
                throw error
            }
        }
    }
    
    // MARK: - Agent Decision Logic
    
    // LLM-based decision making
    private func decideNextAction(basedOn response: ServerResponse, using openAIService: OpenAIService?) async throws -> AgentAction {
        log("🤖 Using LLM to decide next action at time step \(response.timeStep)", verbose: true)
        
        guard let openAIService = openAIService else {
            throw NSError(domain: "AgentCommand", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "OpenAI service not initialized"
            ])
        }
        
        let logger = AgentLogger(category: "Agent")
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
    
    // Random action for fallback
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

// MARK: - Main entry point
@main
struct AgentMain {
    static func main() async {
        // Check for direct command line flag usage
        if ProcessInfo.processInfo.arguments.contains("--verbose") {
            setVerboseMode(true)
            let logger = AgentLogger(category: "Agent")
            logger.info("Verbose logging enabled")
        }
        
        log("📱 Agent program starting", verbose: true, forceShow: true)
        await AgentCommand.main()
    }
}