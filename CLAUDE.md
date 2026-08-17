# CLAUDE.md
## Cost and token budget — mandatory

API usage is paid per token. Minimize model calls aggressively.

### Agent behavior

- Do not poll background jobs repeatedly.
- When a long-running build, CI run, download, or acceptance test has started:
  - start it once;
  - record its process/run ID;
  - do not repeatedly inspect logs while it is healthy;
  - wait for completion or inspect only after failure/completion.
- Never use repeated "sleep -> check -> reason -> check again" agent loops.

### Context discipline

- Never reread the whole repository.
- Never reread files already inspected unless they changed.
- Prefer `rg`, `git diff`, `git show`, targeted `sed` ranges, and failed-log excerpts.
- Do not ingest entire GitHub Actions logs.
- Do not summarize files merely to keep yourself oriented.
- Keep working notes concise.

### Build/test discipline

- Do not run expensive validation speculatively.
- Identify the root cause before rerunning CI.
- Run the narrowest relevant test first.
- Do not rerun passing expensive tests unless affected code changed.
- Never rerun full corpus acceptance unless indexing semantics changed.
- Never start heavy acceptance while fast CI is red.

### Background jobs

For long-running operations:
1. Start the operation.
2. Tell the user exactly what command/run was started and its ID.
3. Stop active agent work while it runs.
4. Do not monitor it continuously.
5. Resume investigation only when the user asks or when completion/failure is available without repeated polling.

### Scope

- Implement only the requested task.
- Do not proactively investigate unrelated improvements.
- Do not perform optional refactors.
- Do not continue with "while I'm here" work.
- Once the requested Definition of Done is satisfied, stop.

### Reporting

- Do not provide a live diary.
- Do not repeatedly restate prior context.
- Report only:
  - a newly discovered blocker,
  - a decision requiring the user,
  - a failed validation and its root cause,
  - final results.

### Model usage

- Use Sonnet by default.
- Do not switch to Opus unless explicitly authorized by the user.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AI翰林院 (AI Hanlin Academy) is a comprehensive iOS AI workstation app integrating 20+ AI providers (OpenAI, Claude, Qwen, DeepSeek, GLM, etc.) with chat, vision analysis, knowledge management, and extensive tool integration capabilities.

## Build Commands

```bash
# Open project
open AI_HLY.xcodeproj

# Build: ⌘+B in Xcode
# Run: ⌘+R in Xcode
# Clean: ⌘+Shift+K in Xcode
```

## Architecture

### Core Structure

**Entry Point**: `AI_HLY/AI_HLY.swift`
- Initializes SwiftData ModelContainer with CloudKit sync
- Configures all data models and preloads defaults
- Handles `AI-Hanlin://` deep links

**Main Navigation**: `AI_HLY/MainTabView.swift`
- 5-tab interface: Chat List, Vision, Knowledge, Models, Settings

### Data Layer (SwiftData + CloudKit)

**Chat Models** (`AI_HLY/Model/`):
- `ChatRecords.swift` - Conversation metadata
- `ChatMessages.swift` - Messages with rich content
- `MemoryArchive.swift` - Long-term memory

**Configuration Models**:
- `AllModels.swift` - AI model definitions with capabilities (multimodal, reasoning, tools)
- `APIKeys.swift` - Encrypted API key storage
- `SearchKeys.swift`, `ToolKeys.swift` - Service configurations

**Knowledge Management**:
- `KnowledgeRecords.swift` - Knowledge base metadata
- `KnowledgeChunk.swift` - RAG-optimized content chunks

### Service Architecture

**API Services** (`AI_HLY/Services/APIServices/`):
- `APIManager.swift` - Unified streaming API abstraction for all providers
- `APIBalance.swift` - Usage tracking
- `APITest.swift` - Endpoint validation

**Tool System** (`AI_HLY/Services/ChatServices/`):
- `ChatTools.swift` - Tool registration/orchestration
- `ToolsAPI.swift` - Execution framework
- Individual tools: WebSearchTool, MapServices, WeatherServices, CalendarService, HealthServices, CodeServices, CanvasServices, TextToSpeech

**Specialized Services**:
- `VisionServices/` - Camera integration, OCR, image analysis
- `KnowledgeServices/` - RAG implementation, vector search
- `ModelServices/` - Local model inference via LLM.swift

### Key Patterns

**Streaming Responses**:
- `StreamData` struct defines content types (text, tools, images, etc.)
- Real-time updates via `@Published` properties
- Tool orchestration during streaming

**Model Capabilities**:
- Each model defines: multimodal, reasoning, tool_use flags
- UI adapts based on selected model capabilities
- Supports both cloud and local models

## Adding Features

### New AI Provider
1. Add model definition in `AllModels.swift` with capabilities
2. Implement API integration in `APIManager.swift`
3. Add provider icon to `Assets.xcassets`
4. Update UI in `ModelsView.swift`

### New Tool
1. Implement in `Services/ChatServices/`
2. Register in `ChatTools.swift`
3. Add API keys if needed in model definitions
4. Update settings UI

## Dependencies (Swift Package Manager)

- **LLM.swift** (1.8.0) - Local LLM support
- **CoreXLSX** (0.14.2) - Excel parsing
- **LaTeXSwiftUI** (1.5.0) - LaTeX rendering
- **MarkdownUI** (2.0.0) - Markdown display
- **SwiftSoup** (2.6.0) - HTML parsing
- **RichTextKit** (0.9.0) - Rich text editing
- **ZIPFoundation** (0.9.0) - Archive handling

## Development Notes

- **Requirements**: iOS 18.0+, Xcode 15.0+, Swift 5.9+
- **Data**: All models use SwiftData with automatic CloudKit sync
- **Localization**: Multi-language via `Localizable.xcstrings`
- **Deep Linking**: `AI-Hanlin://` URL scheme configured in Info.plist
- **Performance**: Heavy async/await usage, streaming for real-time UX