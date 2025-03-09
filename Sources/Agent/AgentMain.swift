import Foundation
import ArgumentParser

/// Main entry point for the agent CLI application
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

// MARK: - Agent Command
struct AgentCommand: AsyncParsableCommand {
    // MARK: - Command Configuration
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
    
    @Flag(name: .long, help: "Enable verbose logging output 📝")
    var verbose: Bool = false
    
    // MARK: - Command execution
    func run() async throws {
        // Set up logging
        configureLogging()
        
        // Load environment variables
        EnvironmentService.loadEnvironment(from: envFile)
        
        // Set up OpenAI service if needed
        let openAIService = try setupOpenAIService()
        
        // Initialize memory engine
        let memoryEngine = MemoryEngine(openAIService: openAIService)
        
        // Configure decision engine
        let decisionEngine = DecisionEngine(openAIService: openAIService, memoryEngine: memoryEngine)
        
        // Set up network connection
        try await connectAndProcessData(decisionEngine: decisionEngine)
    }
    
    // MARK: - Helper Methods
    
    /// Configure logging based on command arguments
    private func configureLogging() {
        setVerboseMode(verbose)
        
        if verbose {
            let logger = AgentLogger(category: "Agent")
            logger.info("Verbose logging enabled 📝")
        }
        
        log("🚀 Agent starting up!", verbose: true, forceShow: true)
    }
    
    /// Set up OpenAI service for LLM-based decisions
    private func setupOpenAIService() throws -> OpenAIService {
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
        let service = OpenAIService(apiKey: apiKey)
        log("🧠 LLM-based decision making enabled", verbose: true)
        let logger = AgentLogger(category: "Agent")
        logger.info("LLM-based decision making enabled 🧠")
        return service
    }
    
    /// Connect to the server and process data
    private func connectAndProcessData(decisionEngine: DecisionEngine) async throws {
        let logger = AgentLogger(category: "Agent")
        logger.info("Connecting to \(host):\(port)...")
        log("🔌 Connecting to \(host):\(port)", verbose: true)
        
        // Create network service and establish connection
        let networkService = NetworkService(host: host, port: port)
        
        do {
            // Connect to the server
            try await networkService.connect()
            logger.info("Connected to server! 🎉")
            
            // Keep receiving data in a loop
            try await receiveDataLoop(using: networkService, decisionEngine: decisionEngine)
        } catch {
            log("❌ Connection error: \(error.localizedDescription)", verbose: true)
            logger.error("Failed to connect: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Main message processing loop
    private func receiveDataLoop(using networkService: NetworkService, decisionEngine: DecisionEngine) async throws {
        let logger = AgentLogger(category: "Agent")
        logger.info("Listening for server messages... 👂")
        
        // Start an infinite loop to receive data
        while true {
            do {
                let data = try await networkService.receiveData()
                try await processReceivedData(data, using: networkService, decisionEngine: decisionEngine)
            } catch {
                log("📡 Data reception error: \(error.localizedDescription)", verbose: true)
                logger.error("❌ Connection error: \(error.localizedDescription)")
                throw error
            }
        }
    }
    
    /// Process incoming data from the server
    private func processReceivedData(_ data: Data, using networkService: NetworkService, decisionEngine: DecisionEngine) async throws {
        let decoder = JSONDecoder()
        
        do {
            // Try to parse the data as either a ServerResponse or ActionResponse
            if let actionResponse = try? decoder.decode(ActionResponse.self, from: data) {
                // Handle action response
                handleActionResponse(actionResponse)
            } else {
                // Try to parse as regular ServerResponse for observations
                let response = try decoder.decode(ServerResponse.self, from: data)
                try await handleServerResponse(response, using: networkService, decisionEngine: decisionEngine)
            }
        } catch {
            // If parsing fails, handle unparsed data
            handleUnparsedData(data)
            log("🔄 JSON parsing error: \(error.localizedDescription)", verbose: true)
        }
    }
    
    /// Handle parsed action response
    private func handleActionResponse(_ response: ActionResponse) {
        let logger = AgentLogger(category: "Agent")
        logger.info("📩 Received action response: \(response.message)")
        logger.info("🧭 Current position: (\(response.data.x), \(response.data.y)) - \(response.data.currentTileType)")
        log("📨 Received action response: \(response.responseType)", verbose: true)
    }
    
    /// Handle parsed server response
    private func handleServerResponse(_ response: ServerResponse, using networkService: NetworkService, decisionEngine: DecisionEngine) async throws {
        let logger = AgentLogger(category: "Agent")
        logger.info("📩 Received observation at time step \(response.timeStep)")
        logger.info("🧭 Current location: (\(response.currentLocation.x), \(response.currentLocation.y)) - \(response.currentLocation.type)")
        logger.info("👀 Surroundings: \(response.surroundings.tiles.count) tiles and \(response.surroundings.agents.count) agents visible")
        
        log("📨 Received response: \(response.responseType) for agent \(response.agent_id)", verbose: true)
        
        // Only send an action if this is an observation message
        if response.responseType == "observation" {
            try await decideAndSendAction(for: response, using: networkService, decisionEngine: decisionEngine)
        } else {
            logger.info("📝 Received \(response.responseType) message, not sending an action")
        }
    }
    
    /// Handle unparsed/unknown data format
    private func handleUnparsedData(_ data: Data) {
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
    }
    
    /// Decide on and send next action
    private func decideAndSendAction(for response: ServerResponse, using networkService: NetworkService, decisionEngine: DecisionEngine) async throws {
        let logger = AgentLogger(category: "Agent")
        
        // Decide on the next action
        let action: AgentAction
        do {
            // Use decision engine to determine next action
            action = try await decisionEngine.decideNextAction(basedOn: response)
        } catch {
            log("❌ Decision error: \(error.localizedDescription), cannot continue", verbose: true)
            logger.error("Decision making failed: \(error.localizedDescription)")
            throw error
        }
        
        // Send the action to the server
        try await networkService.sendAction(action)
        logger.info("🚀 Sent action: \(action.action.rawValue) to \(action.targetTile?.x ?? 0), \(action.targetTile?.y ?? 0)")
    }
}