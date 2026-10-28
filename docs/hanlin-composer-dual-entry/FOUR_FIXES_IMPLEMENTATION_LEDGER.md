# Hanlin P0/P1 Four Focused Composer & Tool Presentation Fixes — Implementation Ledger

**Date**: 2026-10-28  
**Repository**: `davidpovarsky/hanlin-ai`  
**Branch**: `fix/classic-source-first-agent-acceptance-20261025`  
**Base Code SHA**: `6318093d7dc2bb0936766d27608c350def307f13`  
**Worktree**: `C:\Users\DAVID\Code\hanlin-classic-source-first-20261027` (Isolated worktree)  
**Untouched Workspace**: `C:\Users\DAVID\Code\hanlin-agent-skills-embedded-results` (Verified 100% clean)

---

## 1. Track 1: Tool Results — True Structured Per-Call Display

### Defects in Base
1. `AI_HLY/Downstream/ChatPresentation/ClassicChatAgentProjection.swift:301-360`: `syncStructuredToolEntries` merged distinct calls if `existing.callID == rawCallID || (existing.toolName == canonicalToolName && existing.output == effectiveOutput)` and deduplicated on `toolName::output`, collapsing multiple calls with identical output into one.
2. `AI_HLY/Downstream/ChatPresentation/ClassicChatAgentProjection.swift:62-74`: `sanitizeUserFacingToolOutput` globally stripped anything following `### Instructions`, corrupting legitimate user-facing Markdown headings in domain tools.
3. `AI_HLY/Downstream/ChatPresentation/ClassicChatAgentProjection.swift:371-410`: `applyFormattedToolProjection` set an aggregate `assistantMessage.toolName` like `"manage_mcp_servers (+1)"` and flattened all tool rows into one string.
4. `AI_HLY/Views/Components/ChatViewComponents.swift:2160-2186`: `toolContentView()` rendered the flattened string into a single text block rather than individual rows.

### Fixes Implemented
- **Typed Display Items**: Defined `typealias ClassicToolDisplayItem = ClassicProjectedToolCallEntry` with `id`, `runID`, `callID`, `toolName`, `sequence`, `status`, `summary`, `output`, `errorDescription`, `embeddedResultPayload`, and `isMetaSkillOrDiscoveryTool`.
- **Call-ID Deduplication Authority**: Lookup and upsert strictly by `callKey = "\(runID.uuidString):call:\(rawCallID)"`. Never match on `output` or `toolName` alone. Calls with identical output retain their distinct entries and order.
- **Selective Heading Sanitization**: `sanitizeUserFacingToolOutput(_ raw:isMetaSkillOrDiscoveryTool:)` removes `### Instructions` ONLY when `isMetaSkillOrDiscoveryTool == true`. Legitimate domain Markdown headings are preserved.
- **Truthful Header Badge**: Set `assistantMessage.toolName = String(format: String(localized: "Tool activity (%lld)"), count)` when multiple calls occurred, never attributing earlier calls to the last tool.
- **Structured Rows inside Classic Accordion**: Replaced content area of `toolContentView()` in `ChatViewComponents.swift` with a `ForEach(structuredToolEntries)` rendering per-call rows (`toolCallRowView`) with blue badges, status icons, and monospaced output blocks. Preserved legacy fallback for stored chats lacking `agentRunJSON`.

---

## 2. Track 2: Popovers — Responsive Native Geometry & Coordinator Race Guards

### Defects in Base
1. `HanlinComposerPopupView.swift` and `HanlinModelPickerPopover.swift` enforced rigid fixed frames (`compactSize` / `expandedSize`), which could clip on narrow Split View, portrait keyboards, or high Dynamic Type.
2. `HanlinComposerPopupCoordinator.swift`: Navigation completion handlers lacked state guards, risking race conditions on rapid switching or early dismissal.

### Fixes Implemented
- **Dynamic Sizing**: Added `responsiveSize(target:horizontalMargin:verticalMargin:)` to `HanlinComposerPopupCoordinator`, calculating bounds dynamically from `UIWindow`/`UIScreen` minus safe area insets.
- **Dynamic Clamping**: Clamped `currentSize` in `HanlinComposerGeneralActionsView`, `HanlinComposerToolsRootView`, and `HanlinModelPickerPopover` using responsive available geometry.
- **Coordinator Race Guards**: Added `guard self.activePopup == popup, self.frameExpanded else { return }` in `pushGeneralSubroute`, `pushToolsSubroute`, and `pushModelSubroute` completion closures to prevent appending to inactive navigation paths.
- **Preserved Design Language**: Preserved 2-phase matched transitions, original blue glass aesthetic, and reduce motion fallbacks.

---

## 3. Track 3: Acceptance & E2E Flows

### Defects in Base
1. `AI_HLYUITests/AgentRuntimeConversationUITests.swift:383-401` in `testUI06`: Interacted with `hanlin-tools-open-catalog` and `hanlin-tools-subpage-back` inside optional `if waitForExistence` checks, allowing failures to silently pass.
2. `AI_HLYUITests/AgentRuntimeConversationUITests.swift:433-436`: Model picker test accepted static label existence without navigating, searching, or returning.
3. `HanlinComposerPopupView.swift:1185-1195`: Optimistic MCP server toggle updated state before confirmation and lacked failure rollback.

### Fixes Implemented
- **Unconditional XCUI Assertions**: Converted `testUI06` subpage navigation, back button, and model picker exploration to unconditional `XCTAssertTrue`/`XCTUnwrap`.
- **E2E Tool Navigation Test (`testUI09`)**: Added test covering fresh chat -> direct tools popover -> native tools catalog -> skills center -> MCP manager -> runtime center, verifying subpages, search fields, toggles, and back navigation.
- **E2E Model Search & Selection Test (`testUI10`)**: Added test opening model picker, expanding All Models, searching via `hanlin-model-picker-search`, selecting, and asserting dismissal/persistence.
- **MCP Provider Confirmation & Rollback**: In `HanlinComposerPopupView.swift`, MCP toggling awaits `mcpProvider.setSelection(...)`, verifies confirmed state from `mcpProvider.selection(...)`, and rolls back on failure.

---

## 4. Track 4: Localization — Full Coverage for New Composer Surfaces

### Defects in Base
1. `Localizable.xcstrings` lacked keys for newly added composer controls, badges, and titles.
2. `HanlinComposerPopupView.swift` and `HanlinModelPickerPopover.swift` contained hardcoded Chinese string literals.
3. `LoadSkillTool`, `ReadSkillResourceTool`, `ToolSearchTool`, and `ReadToolResultTool` lacked Hebrew localization, defaulting to English when Hebrew was active.

### Fixes Implemented
- **Catalog Population**: Added 67 new keys to `Localizable.xcstrings` (total keys: 858), providing complete `en`, `he`, and `zh-Hans` localizations.
- **Localized UI**: Replaced all hardcoded string literals in `HanlinComposerPopupView.swift` and `HanlinModelPickerPopover.swift` with `String(localized: ...)` keys. Zero hardcoded Chinese strings remain on touched surfaces.
- **Four Meta-Tool Summaries**: Updated `userFacingSummary` in `LoadSkillTool`, `ReadSkillResourceTool`, `ToolSearchTool`, and `ReadToolResultTool` to support `he` (Hebrew) alongside `en` and `zh`.
- **Unit Verification**: Added Test 30 in `ClassicChatRestorationTests.swift` validating all 4 meta-tools in Hebrew, English, and Chinese.

---

## 5. Summary of Touched Files

| File | Nature of Change |
|---|---|
| `AI_HLY/Downstream/ChatPresentation/ClassicChatAgentProjection.swift` | Per-call deduplication by callID, selective heading sanitization, truthful badge |
| `AI_HLY/Views/Components/ChatViewComponents.swift` | Structured per-call rows in tool accordion, localized header, legacy fallback |
| `AI_HLY/Downstream/ChatInput/HanlinComposerPopupCoordinator.swift` | Dynamic responsive sizing, navigation race guards |
| `AI_HLY/Downstream/ChatInput/HanlinComposerPopupView.swift` | Responsive sizing, localized strings, MCP confirmed selection & rollback |
| `AI_HLY/Downstream/ChatInput/HanlinModelPickerPopover.swift` | Responsive sizing, localized badges and search placeholders |
| `AI_HLY/Downstream/AgentSkills/LoadSkillTool.swift` | Hebrew localization in userFacingSummary |
| `AI_HLY/Downstream/AgentSkills/ReadSkillResourceTool.swift` | Hebrew localization in userFacingSummary |
| `AI_HLY/Downstream/AgentSkills/ToolSearchTool.swift` | Hebrew localization in userFacingSummary |
| `AI_HLY/Downstream/AgentSkills/ReadToolResultTool.swift` | Hebrew localization in userFacingSummary |
| `AI_HLY/Resource/Localizable.xcstrings` | 67 new keys with complete `en`, `he`, `zh-Hans` localizations (858 keys total) |
| `AI_HLYTests/ClassicChatRestorationTests.swift` | Updated Test 25, added Tests 27–31 |
| `AI_HLYUITests/AgentRuntimeConversationUITests.swift` | Unconditional assertions in `testUI06`, added `testUI09` and `testUI10` |

### Explicit Out-of-Scope Confirmation
- No changes to main chat message database or SwiftData schemas.
- No modifications to SDK tool-loop mechanics or backend APIs.
- Primary workspace `C:\Users\DAVID\Code\hanlin-agent-skills-embedded-results` remained 100% clean and untouched.
- No changes to Asana or remote provisioning profiles.
