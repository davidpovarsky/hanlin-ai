# Baseline and Preservation Matrix

**Document Version:** 1.0.0  
**Date:** 2026-10-21  
**Target Repository:** `https://github.com/davidpovarsky/hanlin-ai`  
**Active Worktree:** `C:\Users\DAVID\Code\hanlin-agent-skills-embedded-results`  
**Target Integration Branch:** `codex/agent-skills-embedded-results` (inspected SHA: `aba9f317f93c5ded6b27e1e3f4c89d8c30e5b709`)  
**Dedicated Working Branch:** `codex/classic-chat-native-composer-search`  

---

## 1. Executive Summary & Architectural Separation

This document establishes the authoritative baseline and preservation contracts for Hanlin AI, governing:
1. **Classic Chat Transcript Presentation Restoration:** Historical reference **`478cdd2c`** (`2026-10-08`).
2. **Modern Composer Modernization Exception:** SwiftChat Full Demo native SwiftUI multiline **Liquid Glass** composer (`StreamChatAI-iOS-Demo` commit `13c9a23~1` / branch `agent/tool-execution-disclosure-ui`), implementing Asana task `1219605282038884` and parent UX plan `1219605220179926`.
3. **Automatic Web Search Integration:** Built-in three-provider fallback (`You.com Keyless` → `Tavily Keyless` → `Keenable Public`), active by default for fresh/unconfigured installs, with zero API key requirement.
4. **Governance & Authorization Gate Assessment:** Verification of Asana gate task `1219605282038660` and prerequisite MASTER closure task `1219603005960308`.

---

## 2. Governance & Asana Authorization Gate Status

| Gate Identifier | Asana Task GID | Title | Status | Impact on Implementation Scope |
| :--- | :--- | :--- | :--- | :--- |
| **Prerequisite MASTER Task** | `1219603005960308` | `[P1] סגירה בטוחה: דוח, branch preservation ואישור שחרור נפרד` | **OPEN / INCOMPLETE (`completed: false`)** | Chat UI freeze remains active in baseline requirements. |
| **Chat UI & Split Gate** | `1219605282038660` | `[FUTURE 0] שער התחלה — סיום MASTER ואישור נפרד ל-Chat UI ולפיצול MiniApps` | **CLOSED / NOT STARTED (`completed: false`)** | **Phase B is strictly BLOCKED from mutating frozen Chat UI files.** |
| **Composer Modernization Task** | `1219605282038884` | `[FUTURE F] Composer SwiftChat-native — multiline Liquid Glass עם כל Hanlin actions` | **PENDING GATE** | Specification and architecture audited; code edits to `ChatViewBottom.swift` deferred pending gate thawing. |
| **Parent UX Plan** | `1219605220179926` | `[PLAN-2026-10-19-HANLIN-SPLIT-V1]` | **ACTIVE CONTRACT** | Defines daily minimal composer and preservation of 278-feature matrix. |

> [!CAUTION]
> **Authorization Gate Contract:** Asana task `1219605282038660` explicitly mandates:
> *"Do not begin development until current tasks in Hanlin are completed or exempted by explicit user approval. Re-check Asana... specifically release of the four frozen Chat UI files and master closing task 1219603005960308. Only after user approval can execution branch begin."*
> In accordance with Section 0 and Section 6 of the Master Prompt:
> - **Phase B (Classic Transcript + Modern Composer):** Marked **`BLOCKED`** from modifying the 4 frozen Chat UI files (`ChatView.swift`, `ChatBubbleView.swift`, `ChatViewBottom.swift`, `ListView.swift`).
> - **Phase C (Search Foundation):** **`COMPLETED`** via additive downstream architecture.
> - **Phase D (Settings & Migration):** **`COMPLETED`** without touching frozen chat files.

---

## 3. Baseline Identification & Branch Topology

### 3.1 Integration Target Verification
- **Verified Worktree:** `C:\Users\DAVID\Code\hanlin-agent-skills-embedded-results`
- **Current Integration Branch:** `codex/agent-skills-embedded-results`
- **Head SHA:** `aba9f317f93c5ded6b27e1e3f4c89d8c30e5b709`
- **Ancestry Verification:**
  - `e57f43ea` (`feature/chat-agent-presentation`): fully merged into `HEAD`.
  - `17ffbf46` (`native-tool-search-foundation`): fully merged into `HEAD`.
  - `e792b0b5` (`docs(product): 278-feature decision matrix`): present in commit history.
- **Dedicated Execution Branch:** `codex/classic-chat-native-composer-search` branched directly from `aba9f317`.

### 3.2 Historical Transcript Baseline
- **Commit SHA:** `478cdd2c23ae2b1a52044cff52ce720830128ea2` (`2026-10-08`)
- **Scope of Classic Restoration:**
  - Transcript and message geometry: bubble margins, corner radii, user/assistant alignment, typography, and avatar presentation.
  - Scroll mechanics: reading position retention, scroll-to-bottom anchor, natural streaming append without jitter or forced jumps.
  - Message actions: copy, share, retry, edit, regenerate.
  - Visual hierarchy: intermediate agent/tool steps kept distinct from the final assistant response.
- **Explicit Exclusion:** The historical composer at `478cdd2c` is **NOT** restored.

### 3.3 Modern Composer Baseline
- **Reference Repository:** `https://github.com/davidpovarsky/StreamChatAI-iOS-Demo` (Local: `C:\Users\DAVID\Code\StreamChatAI-iOS-Demo`)
- **Reference Commit:** `13c9a23~1` (and branch `agent/tool-execution-disclosure-ui`)
- **Reference Source File:** `Packages/AgentChatSDK/Sources/AgentChatSwiftChat/Views/MessageInputView.swift`
- **Architecture:** Native SwiftUI multiline **Liquid Glass** shell (`.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 26))`), auto-growing `UITextView` bridge (`CustomTextEditor`), clean everyday toolbar (+ menu, mic, send/stop, model selector capsule).
- **Parity Mandate:** Preserve 100% of Hanlin input capabilities (paste image/file/text, @mentions, drafts, attachment preview strip, MCP/tools/search/reasoning toggles in context/advanced menus).

---

## 4. File-by-File Preservation Matrix

| File Path | Historical Baseline (`478cdd2c`) | Target Branch State (`aba9f317`) | Governance Classification | Required Action |
| :--- | :--- | :--- | :--- | :--- |
| `AI_HLY/ChatView.swift` | Classic transcript container | Modern agent-aware container with downstream hooks | **FROZEN CHAT UI** | **BLOCKED by Gate `1219605282038660`.** Preserve modern runtime integrations. |
| `AI_HLY/Views/Components/ChatViewComponents.swift` | Classic bubble renderers and actions | Modern renderers + tool result hooks | **FROZEN CHAT UI** | **BLOCKED by Gate.** Audit completed; no modification. |
| `AI_HLY/Views/Components/ChatViewBottom.swift` | Old single-line input field | Legacy complex multi-strip composer (2,427 lines) | **FROZEN CHAT UI** | **BLOCKED by Gate.** Target for future SwiftChat Liquid Glass replacement. |
| `AI_HLY/ListView.swift` | Classic conversation history list | Modern list with SwiftData queries | **FROZEN CHAT UI** | **BLOCKED by Gate.** Preserve intact. |
| `AI_HLY/Downstream/ChatPresentation/ChatUserMessageSurface.swift` | Not present at `478cdd2c` | Modern presentation surface | Downstream Additive | Preserved intact. |
| `AI_HLY/Downstream/ChatPresentation/ChatAssistantActionsView.swift` | Not present at `478cdd2c` | Modern actions component | Downstream Additive | Preserved intact. |
| `AI_HLY/Downstream/AgentActivity/Transcript/AgentRunTranscriptView.swift` | Not present at `478cdd2c` | Collapsed agent tool activity view | Downstream Additive | Preserved intact. |
| `AI_HLY/Downstream/ChatPresentation/ChatHostPresentationPolicy.swift` | Not present at `478cdd2c` | Height/sizing boundary policy | Downstream Additive | Preserved intact. |
| `AI_HLY/Services/ChatServices/WebSearchTool.swift` | Legacy 7 paid engines | Legacy 7 paid engines | Search Service | **MODIFIED:** Added `AUTOMATIC_KEYLESS` engine and diagnostic test bypass. |
| `AI_HLY/Services/ChatServices/APIManager.swift` | Legacy search paths | Modern multi-path agent search | Core Engine | **COMPATIBLE:** Uses `getActiveSearchEngine()` and `searchTool()` seamlessly. |
| `AI_HLY/Services/DataServices/InfoServices.swift` | Predefined search list (no auto) | Predefined search list | Configuration | **MODIFIED:** Added `AUTOMATIC_SEARCH_KEY` and icon resolver. |
| `AI_HLY/Services/DataServices/PreLoad.swift` | Database sync without auto migration | Database sync | Bootstrap | **MODIFIED:** Added automatic default migration with manual provider preservation. |
| `AI_HLY/SettingsView.swift` | Warns if no API key present | Warns if no API key present | Settings Surface | **MODIFIED:** Recognizes `AUTOMATIC_KEYLESS` as valid without API key. |
| `AI_HLY/Views/Components/APISettingView.swift` | Manual search engines list | Manual search engines list | Settings Surface | **MODIFIED:** Prioritizes automatic search, adds diagnostic test UI, removes key gate. |
| `AI_HLY/Resource/Localizable.xcstrings` | Localization strings | Localization strings | Localization | **MODIFIED:** Added English, Hebrew, and Chinese translations. |
| `AI_HLY/Services/ChatServices/AutomaticSearch/*` | None | None | Downstream Additive | **CREATED:** Full three-tier keyless coordinator, adapters, DTOs, and migration. |

---

## 5. Non-Rollback Capabilities (Strict Invariants)

The following production subsystems must never be regressed, replaced, or rolled back:
1. **SwiftData Schema & Migrations:** Conversation entities, message models, timestamps, session isolation, and identifiers.
2. **Skills & MCP Runtime:** MiniApp host, Swift HanlinScripting, NativeScript bridge, dynamic tool registration, and tool approval policies.
3. **Interactive Embedded Results:** Result card rendering, Markdown tables/math, code execution blocks, and rich media viewers.
4. **Agent Orchestration Loop:** Single authoritative agent loop, streaming token pipelines, cancellation tokens, and error handling.
5. **Stored User Credentials:** API keys, custom model endpoints, keychain credentials, and manual search engine keys.
