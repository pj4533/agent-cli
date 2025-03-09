import Foundation
import OSLog

// Simple logging function that checks if we're in verbose mode
fileprivate func log(_ message: String, verbose: Bool = false) {
    // Only log if we've set AGENT_VERBOSE environment variable
    if verbose && ProcessInfo.processInfo.environment["AGENT_VERBOSE"] == "1" {
        let logger = AgentLogger(category: "Environment")
        logger.debug(message)
    }
}

struct EnvironmentService {
    
    // Process an .env file at the given path and load variables
    static func loadEnvironment(from path: String = ".env") {
        do {
            log("📁 Loading environment variables from \(path)", verbose: true)
            
            // Read the .env file
            let fileURL = URL(fileURLWithPath: path)
            let fileContents = try String(contentsOf: fileURL, encoding: .utf8)
            
            // Process each line
            fileContents.split(separator: "\n").forEach { line in
                // Skip comments and empty lines
                let trimmedLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                    return
                }
                
                // Parse KEY=VALUE pairs
                let parts = trimmedLine.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else {
                    log("⚠️ Invalid line in .env file: \(trimmedLine)", verbose: true)
                    return
                }
                
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                var value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Remove quotes if present
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                
                // Set the environment variable
                setenv(key, value, 1)
                log("🔑 Set environment variable: \(key)", verbose: true)
            }
            
            log("✅ Environment loaded successfully from \(path)", verbose: true)
        } catch {
            log("⚠️ Failed to load .env file: \(error.localizedDescription)", verbose: true)
            log("ℹ️ Will use existing environment variables instead", verbose: true)
        }
    }
    
    // Get a value from environment
    static func getEnvironmentVariable(_ name: String) -> String? {
        guard let rawValue = getenv(name) else {
            return nil
        }
        return String(cString: rawValue)
    }
}