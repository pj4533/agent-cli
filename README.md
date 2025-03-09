# AgentWorld Agent 🌎

A CLI agent for exploring the AgentWorld simulation. This agent connects to the AgentWorld server via TCP and uses either random movement or OpenAI's GPT-4o for intelligent decision-making.

## Features

- 🤖 LLM-powered decision making using OpenAI's GPT-4o
- 🎲 Fallback to random movement when needed
- 🌐 TCP communication with AgentWorld server
- 📊 Rich logging and output

## Setup

### Prerequisites

- Swift 5.8+
- An OpenAI API key (for LLM-based decisions)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/agentworld.git
   cd agentworld/agent
   ```

2. Create an `.env` file with your OpenAI API key:
   ```bash
   cp .env.example .env
   ```
   
3. Edit the `.env` file and add your OpenAI API key:
   ```
   OPENAI_API_KEY=your-api-key-here
   ```

### Building

Build the agent using Swift Package Manager:

```bash
swift build
```

For a release build:

```bash
swift build -c release
```

## Usage

Run the agent, connecting to the local AgentWorld server:

```bash
swift run agent --host localhost --port 8000
```

### Command-line Options

- `--host`: The hostname of the AgentWorld server (default: localhost)
- `--port`: The port of the AgentWorld server (default: 8000)
- `--envFile`: Path to a custom .env file (default: .env)
- `--randomMovement`: Use random movement instead of LLM-based decisions

### Examples

Connect to a remote server:

```bash
swift run agent --host remote-server.example.com --port 9000
```

Use random movement instead of LLM:

```bash
swift run agent --randomMovement
```

Use a custom .env file:

```bash
swift run agent --envFile /path/to/custom.env
```

## How It Works

1. The agent connects to the AgentWorld server via TCP
2. It receives observation data from the server containing:
   - Current location and tile type
   - Surrounding tiles and agents
   - Current time step
3. For decision making:
   - If using LLM: The observation is sent to OpenAI's GPT-4o which decides where to move next
   - If using random movement: A random adjacent non-water tile is selected
4. The agent sends its action back to the server as a JSON message
5. This cycle repeats until the connection is closed

## License

[MIT License](LICENSE)