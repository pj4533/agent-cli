import Foundation
import Network
import OSLog

// Simple logging function that checks if we're in verbose mode
fileprivate func log(_ message: String, verbose: Bool = false) {
    // Only log if we've set AGENT_VERBOSE environment variable
    if verbose && ProcessInfo.processInfo.environment["AGENT_VERBOSE"] == "1" {
        let logger = AgentLogger(category: "Network")
        logger.debug(message)
    }
}

actor NetworkService {
    // MARK: - Properties
    private let host: String
    private let port: UInt16
    private var connection: NWConnection?
    
    // MARK: - Initialization
    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
        log("🔧 Network service initialized for \(host):\(port)", verbose: true)
    }
    
    // MARK: - Connection Management
    func connect() async throws {
        log("🔌 Establishing connection to \(self.host):\(self.port)", verbose: true)
        
        // Create NWEndpoint for the connection
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(self.host),
            port: NWEndpoint.Port(rawValue: self.port)!
        )
        
        // Create connection with TCP parameters
        let connection = NWConnection(to: endpoint, using: .tcp)
        self.connection = connection
        
        // Return value for the connection result
        return try await withCheckedThrowingContinuation { continuation in
            // Set the state update handler
            connection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                
                switch state {
                case .ready:
                    log("✅ Connection established to \(self.host):\(self.port)", verbose: true)
                    continuation.resume(returning: ())
                    
                case .failed(let error):
                    log("❌ Connection failed: \(error.localizedDescription)", verbose: true)
                    continuation.resume(throwing: error)
                    
                case .cancelled:
                    log("🚫 Connection was cancelled", verbose: true)
                    continuation.resume(throwing: NSError(domain: "NetworkService", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Connection was cancelled"
                    ]))
                    
                default:
                    // For other states, we wait for the next update
                    log("🔄 Connection state: \(String(describing: state))", verbose: true)
                }
            }
            
            // Start the connection
            connection.start(queue: .main)
        }
    }
    
    func receiveData() async throws -> Data {
        guard let connection = self.connection else {
            throw NSError(domain: "NetworkService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "No active connection"
            ])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, context, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let data = content, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: NSError(domain: "NetworkService", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "Connection closed by remote peer"
                    ]))
                } else {
                    continuation.resume(throwing: NSError(domain: "NetworkService", code: 4, userInfo: [
                        NSLocalizedDescriptionKey: "Received empty data"
                    ]))
                }
            }
        }
    }
    
    func sendAction(_ action: AgentAction) async throws {
        guard let connection = self.connection else {
            throw NSError(domain: "NetworkService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "No active connection"
            ])
        }
        
        // Encode the action to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(action)
        
        // Log the action being sent
        if let jsonString = String(data: data, encoding: .utf8) {
            log("📤 Sending action: \(jsonString)", verbose: true)
        }
        
        // Send the data
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }
    
    func disconnect() {
        log("👋 Disconnecting from \(self.host):\(self.port)", verbose: true)
        connection?.cancel()
        connection = nil
    }
    
    // For clean deinitialization, we need a nonisolated method
    nonisolated func cleanup() {
        Task { await disconnect() }
    }
    
    deinit {
        cleanup()
    }
}