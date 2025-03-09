---

## 4.2 Agent: `agent` Prompts

### **Prompt 1: SPM Project Setup**

```text
Create a new Swift Package Manager executable named "agent". Add it to a subdirectory of AgentWorld, but don't associate it with the xcode project for AgentWorld, it should be its own thing. It should have:

1. A `Package.swift` that uses Swift.
2. Dependencies on ArgumentParser (from apple/swift-argument-parser).
3. A `main.swift` or `AgentMain.swift` that prints "Hello from agent" for now.
4. Implement a simple command that expects `host` and `port` arguments.

Provide the complete `Package.swift` and main file. No other dependencies besides ArgumentParser. No Combine. Use OSLog for all logging, use plenty of emoji.
```

### **Prompt 2: Networking to Server**

```text
Extend the CLI to connect via TCP to the provided `host:port`. 

1. Parse the command line to get host and port. 
2. Use async/await with the Network framework or low-level sockets to connect. 
3. On success, print "Connected to server!". 
4. Keep the connection open and read any data from the server, printing it to console for now.

Show updated code. Include any new files or updates to main. 
```

### **Prompt 3: Personality & Memory Setup**

```text
Add personality and memory:

1. Read `.agentTraits` (assume it's in the same folder) and store lines in an array. 
2. Create a simple SQLite database "AgentMemory.db" with a table `Memories`:
   (unique_id TEXT, memoryType TEXT, timestamp INT, text_content TEXT, links TEXT).
3. Add placeholders for Pinecone operations, e.g. `func storeEmbedding(_ text: String) {}`. 
4. No real embedding logic yet. Just stubs. 

Provide code that sets up this DB (create table if not exists), and reads the traits. 
```

### **Prompt 4: Receiving Server Messages & Decision Loop**

Starts to get a little dicey here...prob will need to modify these prompts. For example, I want to use an LLM call to generate memories with a specific prompt. Short term memory is just the most recent X memories, long term memory uses embeddings to get relavant memories. I'll need code to do that. Both get added to the context window for decision making.

I could start decision making slowly:

1. include traits and server data
2. add short term memory
3. add long term memory
4. add reflection step

```text
Build the main loop:

1. When data arrives from the server, parse JSON to get:
   {
     "agent_id": "...",
     "currentLocation": {...},
     "surroundings": {...},
     "timeStep": ...
   }
2. Store relevant info in short-term memory (in the DB). 
3. For now, just construct a dummy response: `{"action": "move", "targetTile": [x+1, y]}`. 
4. Send that JSON back to the server. 
5. Keep looping until the connection closes.

Provide the updated code for main loop, focusing on reading server messages, storing them, sending actions.
```

### **Prompt 5: Integrate LLM (Prompting GPT-4)**

```text
Now let's integrate an LLM-based decision into the CLI agent:

1. Write code that communicates with the OpenAI API using the chat completions endpoint. Read the openAI api key from the environment. Process an .env file when launching the CLI. Try to avoid external dependencies.
2. Use the model `gpt-4o`
3. Separatly create a function called decideNextAction(), which will use the initial prompt: "You are an explorer in a new world. Try to see as much of the world as you can, without revisiting areas you have already visited. 

Decide where to move next. 

Output your next move using JSON formatted like this:
{"action": "move", "targetTile": {x,y}}

Current Observation:
<include most recent observation from server>
"
4. Send this prompt to OpenAI gpt-4o. Make sure to use "json_object" as the response_format, so that we get good JSON output.
5. Parse the output using Codable and send it to the server.
6. Make sure to use OSLog to log progress, debugging and errors.
```

### **Prompt 6: Reflection Mechanism**

```text
Implement reflection:

1. Every 20 steps, gather the last 20 memories plus current traits. 
2. Stub an LLM call that returns a "reflection result" describing how traits might change. 
3. Update the traits list in memory (and optionally in `.agentTraits` or the DB). 
4. Log a new memory of type "reflection".

Show the new or modified code, focusing on hooking it into the main loop. 
```

### **Prompt 7: Error Handling & Polishing**

```text
Finalize the agent:

1. If the server sends `{"action":"error","reason":"...","timeStep":...}`, store that error in memory and adjust future decisions. 
2. Tidy up the code: ensure the connection closes gracefully on exit. 
3. Possibly print a final summary of trait changes.

Provide the final code for the `agent` with all integrated pieces. 
```

---

## 5. Final Note on Iteration

With these prompts:
- You can start at **Prompt 1** in each project, feed the LLM the instructions, and paste the generated code into your local environment.
- Then test, confirm it builds and runs, and only then move on to **Prompt 2**, etc.
- Each step builds on the prior, ensuring no orphan code or big leaps in complexity.

By the time you complete all prompts in both **Server** (`AgentWorld`) and **Agent** (`agent`), you should have a working baseline project with:
- A 64×64 organically generated world.
- A macOS SpriteKit/SwiftUI interface controlling the simulation.
- A CLI agent that uses a memory system and LLM-based decision-making to move around the world.

No Combine or third-party dependencies (other than `ArgumentParser`) are used, and everything is incremental.

Good luck building your **AI-Driven Agent Simulation**!