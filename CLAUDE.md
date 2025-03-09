# CLAUDE.md - Agent CLI Project Guidelines

## Build & Run Commands
```bash
# Standard build and run
swift build
swift run agent

# Run with options
swift run agent --host localhost --port 8000 --envFile .env --verbose

# Build for release
swift build -c release
```

## Code Style Guidelines
- **Imports**: Foundation first, group related imports
- **Formatting**: 4-space indentation, trailing commas in multi-line collections
- **Types**: Structs for models, actors for concurrent code, descriptive enums
- **Naming**: camelCase for variables/functions, PascalCase for types
- **Error Handling**: Use Swift's throwing mechanism, propagate errors appropriately
- **Concurrency**: Use Swift's concurrency model with actors and async/await
- **Logging**: Use OSLog with categories and verbosity levels
- **Organization**: Group related functionality with MARK: comments
- **Architecture**: Create dedicated services for specific functionality
- **Arguments**: Use SwiftArgumentParser for command-line arguments

Always follow existing patterns in the codebase when making modifications.