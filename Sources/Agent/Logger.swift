import Foundation
import OSLog

// MARK: - Logging Utilities

/// Check if verbose mode is enabled via environment variable
func isVerboseMode() -> Bool {
    return ProcessInfo.processInfo.environment["AGENT_VERBOSE"] == "1"
}

/// Set verbose mode via environment variable
func setVerboseMode(_ verbose: Bool) {
    if verbose {
        setenv("AGENT_VERBOSE", "1", 1)
    } else {
        unsetenv("AGENT_VERBOSE")
    }
}

/// Central logging function that respects verbose flag
func log(_ message: String, verbose: Bool = false, forceShow: Bool = false) {
    // Only log if we're in verbose mode OR this is a message that should always be shown
    if forceShow || (verbose && isVerboseMode()) {
        let logger = AgentLogger(category: "Agent")
        logger.debug(message)
    }
}

/// Agent logger struct that uses OSLog but also prints to terminal for CLI usage
struct AgentLogger {
    private let logger: Logger
    private let category: String
    private let dateFormatter = DateFormatter()
    
    init(category: String) {
        self.logger = Logger(subsystem: "com.agentworld.Agent", category: category)
        self.category = category
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }
    
    private func formatMessage(_ level: String, _ message: String) -> String {
        let timestamp = dateFormatter.string(from: Date())
        return "[\(timestamp)] [\(category)] \(level): \(message)"
    }
    
    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        print(formatMessage("DEBUG", message))
    }
    
    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        print(formatMessage("INFO", message))
    }
    
    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        print(formatMessage("ERROR", message))
    }
}