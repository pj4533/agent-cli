# Specification: AI-Driven Agent Simulation

## Agent Application Specification

### Overview
A standalone CLI application built using Swift Package Manager (SPM) and Argument Parser, communicating with the server via TCP, leveraging OpenAI's LLM for decision-making.

### Initialization
- Reads personality traits from `.agentTraits` file (plain text, one trait per line)
- Connects via TCP to the server:
```bash
agent localhost:8000
```
- Server assigns unique `agent_id`

### Decision-Making (via LLM)
- Uses OpenAI `gpt-4o` for actions and reflections
- Prompt includes:
  - Current location
  - Immediate surroundings
  - Qualitative personality traits
  - Short-term (last 5 steps) and relevant long-term memories retrieved via RAG

### Memory System
- Stored in SQLite database:
  - `unique_id`
  - `memoryType`: regular, conversation, spatial, reflection
  - `timestamp`: time step
  - `text_content`
  - `links`: array of linked memory IDs
- Short-term memory includes all memory types from recent 5 steps
- Long-term memory retrieval via RAG with embeddings stored externally in Pinecone, linked by unique ID

### Reflection
- Triggered every 20 steps or explicitly via events determined by LLM:
  - Meeting new agent
  - Completing conversation
- Reflection includes:
  - Recent memories
  - Personality traits
  - Current context (location, surroundings, situation)
- Personality traits evolve incrementally during reflections (adjust, add, remove)

### Communication Protocol
- JSON-based TCP communication
- Example server → agent message:
```json
{
  "agent_id": "agent-123",
  "currentLocation": {"x": 10, "y": 20},
  "surroundings": {"tiles": [], "agents": []},
  "timeStep": 0
}
```
- Example agent response:
```json
{
  "action": "move",
  "targetTile": [21, 21]
}
```

