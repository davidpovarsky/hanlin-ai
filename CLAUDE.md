# CLAUDE.md

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

## Living Project Board

`PROJECT_BOARD.md` is this repository's shared living project board. Before starting substantial work, scan it for relevant context. During normal work, agents should proactively add concise, actionable entries when they discover something with genuine future value, including useful technical discoveries, optimization opportunities, implementation tricks, architectural ideas, possible future improvements, experiments worth running, unresolved issues or questions, and follow-up work that should not be lost—even when the discovery is incidental to the current task.

Do not add trivial observations, temporary debugging chatter, information already documented elsewhere, generic suggestions with no project relevance, or every step performed during a task. The board supports memory but is not a source of truth when repository code, documentation, or current state contradicts it. When an item is implemented, mark it complete and optionally record the date and commit/PR, moving it to `Done` when useful; delete or archive obsolete entries when appropriate.

Updating `PROJECT_BOARD.md` as a side effect of another task is allowed and encouraged when a worthwhile discovery is made. Recording an idea is allowed; implementing unrelated ideas is not.

Preserve all existing repository-specific instructions.
