import Foundation
import SQLite3

// MARK: - Memory Models

/// Structure representing a memory in the agent's memory database
struct Memory: Codable {
    let uniqueId: String
    let memoryType: String
    let timestamp: Int
    let textContent: String
    let links: String
    
    init(uniqueId: String = UUID().uuidString, 
         memoryType: String, 
         timestamp: Int = Int(Date().timeIntervalSince1970), 
         textContent: String, 
         links: String = "") {
        self.uniqueId = uniqueId
        self.memoryType = memoryType
        self.timestamp = timestamp
        self.textContent = textContent
        self.links = links
    }
}

/// Structure for OpenAI's memory generation response
struct MemoryGenerationResponse: Codable {
    let memories: [String]
}

// MARK: - Memory Engine

/// Engine responsible for generating and storing agent memories
actor MemoryEngine {
    // MARK: - Properties
    private let openAIService: OpenAIService
    private let logger = AgentLogger(category: "Memory")
    private var dbPath: String
    private var db: OpaquePointer?
    
    // MARK: - Initialization
    init(openAIService: OpenAIService) {
        self.openAIService = openAIService
        
        // Create unique database name with timestamp
        let timestamp = Int(Date().timeIntervalSince1970)
        self.dbPath = "AgentMemory_\(timestamp).db"
        
        // Initialize the database - this happens when first accessing the database
        log("🧠 Memory engine initialized with database: \(dbPath)", verbose: true)
    }
    
    /// Initialize the database - called on first access
    private func initializeDatabaseIfNeeded() {
        if db == nil {
            setupDatabase()
        }
    }
    
    // Remove deinit since we can't access actor-isolated state from it
    // The database will be closed when the process terminates
    
    // MARK: - Database Operations
    
    /// Sets up the SQLite database with the required schema
    private func setupDatabase() {
        // Open database connection
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            logger.error("Error opening database: \(String(describing: sqlite3_errmsg(db)))")
            return
        }
        
        // Create memories table
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS Memories (
            unique_id TEXT PRIMARY KEY,
            memory_type TEXT,
            timestamp INTEGER,
            text_content TEXT,
            links TEXT
        );
        """
        
        var createTableStatement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, createTableSQL, -1, &createTableStatement, nil) == SQLITE_OK {
            if sqlite3_step(createTableStatement) == SQLITE_DONE {
                log("Memories table created successfully", verbose: true)
            } else {
                logger.error("Memories table creation failed: \(String(describing: sqlite3_errmsg(db)))")
            }
        } else {
            logger.error("CREATE TABLE statement preparation failed: \(String(describing: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(createTableStatement)
    }
    
    /// Inserts a memory into the database
    private func saveMemory(_ memory: Memory) {
        // Initialize database if needed
        initializeDatabaseIfNeeded()
        
        let insertSQL = """
        INSERT INTO Memories (unique_id, memory_type, timestamp, text_content, links) 
        VALUES (?, ?, ?, ?, ?);
        """
        
        var insertStatement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, insertSQL, -1, &insertStatement, nil) == SQLITE_OK {
            // Bind parameters
            sqlite3_bind_text(insertStatement, 1, (memory.uniqueId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, (memory.memoryType as NSString).utf8String, -1, nil)
            sqlite3_bind_int(insertStatement, 3, Int32(memory.timestamp))
            sqlite3_bind_text(insertStatement, 4, (memory.textContent as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 5, (memory.links as NSString).utf8String, -1, nil)
            
            if sqlite3_step(insertStatement) == SQLITE_DONE {
                logger.info("Memory saved: \(memory.textContent)")
                log("Memory saved to database: \(memory.textContent)", verbose: true)
            } else {
                logger.error("Failed to save memory: \(String(describing: sqlite3_errmsg(db)))")
            }
        } else {
            logger.error("INSERT statement preparation failed: \(String(describing: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(insertStatement)
    }
    
    // MARK: - Memory Generation
    
    /// Generates a single memory based on the reasoning provided by the LLM
    func generateMemories(fromReasoning reasoning: String) async {
        log("🧠 Generating a memory based on LLM reasoning", verbose: true)
        
        // Create system prompt for memory generation
        let systemPrompt = "You take input from the user and generate a memory. Create a single short, one-sentence memory based on the reasoning provided."
        
        // Create user prompt with the reasoning
        let userPrompt = """
        Generate a single short, one sentence memory, based on this reasoning:
        
        \(reasoning)
        
        Respond as JSON in the following format:
        {"memories": ["I see water in the distance"]}
        
        Focus only on factual observations and genuine preferences/intentions.
        """
        
        do {
            // Get memories from the OpenAI API with JSON formatting
            let jsonResponse = try await openAIService.chatCompletion(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                jsonResponseFormat: true
            )
            
            // Parse the response and create memories
            let responseData = jsonResponse.data(using: .utf8)!
            let decoder = JSONDecoder()
            
            let memoryResponse = try decoder.decode(MemoryGenerationResponse.self, from: responseData)
            
            // Only save the first memory
            if let memoryText = memoryResponse.memories.first {
                let memory = Memory(
                    memoryType: "action",
                    textContent: memoryText
                )
                saveMemory(memory)
                log("✅ Successfully generated a memory: \(memoryText)", verbose: true)
            } else {
                log("⚠️ No memories were generated from the reasoning", verbose: true)
            }
        } catch {
            logger.error("Failed to generate memories: \(error.localizedDescription)")
            log("❌ Error generating memories: \(error.localizedDescription)", verbose: true)
        }
    }
    
    /// Retrieves relevant memories for a given context
    /// Currently stubbed out - will be enhanced with embedding-based similarity search later
    func getRelevantMemories(forContext context: String, limit: Int = 5) async -> [Memory] {
        // For now, just return an empty array
        // This will be enhanced with embedding similarity search in the future
        log("getRelevantMemories called but currently stubbed (future enhancement with embeddings)", verbose: true)
        return []
    }
}