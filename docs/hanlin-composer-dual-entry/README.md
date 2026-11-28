# Hanlin Two-Entry Native Composer, Popovers, Real Tools/Skills/MCP & Clean Original-Blue UI

## 1. Overview & Architectural Goals

This document specifies the design, state coordination, V3.3 two-phase zoom/expansion adaptation, P0 tool-output separation fix (Build 84701), and test coverage for the Hanlin two-entry native composer in `ChatViewBottom`.

### Key Architectural Principles
1. **Preserve Original Hanlin Blue Visual Identity**:
   - Retains the original `GlassView(style: .systemUltraThinMaterial)` container, subtle `hlBluefont.opacity(0.22)` border (`0.8pt`), `hlBlue` shadow, rounded corners (`cornerRadius: 26`), system Dynamic Type, Dark/Light adaptation, and RTL/LTR layout support.
   - Replaces the legacy 6–10 icon horizontal scroll strip (`ActionButtonsView`) and full-width bottom model strip (`modelSelector`) with a clean, single-row minimal control bar.
2. **Two Explicit Entrypoints in One Integrated `HanlinOrganizerDock` + Compact Model Capsule**:
   - **Entrypoint 1 — General `+` (`hanlin-composer-general-menu`, classic `plus.circle`)**: Expands `HanlinComposerGeneralActionsView` (`.general` drawer mode inside `HanlinOrganizerDock`) behind/above the composer for attachments (Camera, Photos, Files), Saved Prompts horizontal gallery slot (`PromptRepo`), conversation modes (Online Search, Knowledge Bag, Deep Thinking + effort level, Planning, Voice Generation, Image Generation aspect ratio + negative prompt, Local Model status), Model Parameters, Long Text Editor, and Multi-model Observe.
   - **Entrypoint 2 — Direct 1-Tap Tools / Skills / MCP (`hanlin-composer-tools-direct`, classic `hammer.circle` / `hammer.circle.fill`)**: Permanently adjacent to `+` in the composer bottom bar. Tapping it expands `HanlinComposerToolsRootView` (`.tools` drawer mode inside the same `HanlinOrganizerDock`) directly in **1 tap** without navigating through the General `+` menu. Switching between `+` and `Tools` swaps drawer modes in-place without dismissing the dock.
   - **Compact Model Selector Capsule (`hanlin-composer-model-picker`)**: The **only** `.popover` exception. Uses `.matchedTransitionSource(id: "model-popover", in: modelPopoverZoom)` + `.navigationTransition(.zoom(sourceID: "model-popover", in: modelPopoverZoom))` and expands first (`completionCriteria: .removed`) before pushing `.allModels`.
   - See `docs/hanlin-dock-v33-source-parity/` for the complete `InteriorOrganizerV3_3` source-parity architecture and verification ledger.

---

## 2. Shared Popup Coordinator & V3.3 Integrated Dock vs. Model Popover Transition

> **Supersession Note (2026-11-01 — `InteriorOrganizerV3_3` Source Parity)**: The earlier floating `.popover` presentation for General (`+`) and Direct Tools (`hammer.circle`) described in the initial Build 84701 audit is **superseded** by the single bottom-integrated `HanlinOrganizerDock` (`ZStack(alignment: .bottom)`). Only the Model Picker (`hanlin-composer-model-picker`) remains a floating `.popover` with matched-geometry zoom (`model-popover` -> `all-models`). Embedded General and Tools subpages (`imageSize`, `toolsCatalog`, `skills`, `mcp`, `runtime`) switch inline inside the expanded dock drawer without nested `NavigationStack` or popover frame resizing.

`HanlinComposerPopupCoordinator` (`AI_HLY/Downstream/ChatInput/HanlinComposerPopupCoordinator.swift`) is the single `@MainActor @Observable` coordinator governing the integrated dock drawer modes (`.general`, `.tools`) and the model picker popover (`.model`):

```swift
public enum ComposerPopup: String, Identifiable, Equatable, Sendable {
    case general // `+` button: attachments, modes, parameters, prompts
    case tools   // Direct 1-tap button: Tools, Skills, MCP, Runtimes
    case model   // Compact model capsule: featured models -> All Models
}
```

### Mutual Exclusion
- Opening `.general`, `.tools`, or `.model` atomically closes any other open popover and resets its subpage navigation path.
- `presentDirectTools(isInputCurrentlyFocused:)` transitions directly to `.tools` at its root page in 1 tap.

### Adaptation of `InteriorOrganizerV3_3` Two-Phase Sizing
To prevent SwiftUI popover layout clipping during drill-down navigation and to protect against cancelled interactive back-swipes:
- **Stage 1 (Expand Before Push)**:
  - `navigateToGeneralSubpage(_:)`, `navigateToToolsSubpage(_:)`, and `navigateToModelSubpage(_:)` first set `isExpanded = true` with `.spring(response: 0.34, dampingFraction: 0.86)` and clear `destinationDisappeared = false`, then push the destination onto `navigationPath`.
- **Stage 2 (Shrink Only After Pop + Disappear)**:
  - `syncGeneralShrinkState()`, `syncToolsShrinkState()`, and `syncModelShrinkState()` shrink `isExpanded = false` **only when both** `navigationPath.isEmpty` **and** `destinationDisappeared == true` hold simultaneously.
  - If a user starts an interactive swipe-back gesture and cancels it mid-gesture (`destinationDisappeared == false`), the popover remains at its expanded dimensions without visual jumping.

---

## 3. Real Runtime Wiring for Tools, Skills, MCP & Runtimes

`HanlinComposerToolsRootView` (`AI_HLY/Downstream/ChatInput/HanlinComposerPopupView.swift`) connects directly to Hanlin's production runtime singletons:
1. **Master Tool Use Toggle**: Bound directly to `$ifToolUse` (`ChatRecords.ifToolUse`). When the active model does not support tool calling (`!capability.supportsToolUse`), displays an informative banner while still allowing inspection of tools, skills, MCP servers, and runtimes.
2. **Native Tools Subpage (`hanlin-tools-native-tools-page`)**: Reads `NativeToolCatalog.groups` and `NativeToolCatalog.definitions` grouped by category (`search`, `files`, `code`, `device`, `ui`, `skills`, `mcp`), bound to `ToolPermissionStore.shared`.
3. **Agent Skills Subpage (`hanlin-tools-agent-skills-page`)**: Reads `HanlinSkillCatalog.shared.loadAllSkills()` and binds per-skill enablement to `SkillStore.shared`, plus provides direct sheet access to `SkillCenterView`.
4. **MCP Servers Subpage (`hanlin-tools-mcp-servers-page`)**: Reads `MCPRuntimeProvider.shared` for truthful 5-state status (`globalMCPEnabled`, `installedCount`, `enabledCount`, `selectedForChatCount`, `runningCount`), supports per-chat server selection (`MCPRuntimeProvider.shared.setServerSelected(_:serverID:chatID:temporary:)`), and opens `MCPServersSettingsView`.
5. **Runtime Center Subpage (`hanlin-tools-runtimes-page`)**: Reads `AppRuntimeCore.shared.allRuntimeSnapshots()` for Python, Node.js, and Shell runtimes and opens `RuntimeCenterView`.

---

## 4. P0 Fix: Build 84701 Tool Content Separation & Per-Call Attribution

### Root Cause in Build 84701
1. `LoadSkillTool` (and `ReadSkillResourceTool`, `ToolSearchTool`, `ReadToolResultTool`) returned full `### Instructions` / internal payloads in `result`, which `HanlinAISDKToolAdapter` passed to **both** `resultForModel` (`modelText`) and `resultForUser` (`userText` / `StreamData.toolContent`).
2. `ClassicChatAgentProjection` concatenated all tool outputs into a single `assistantMessage.toolContent` string while overwriting `assistantMessage.toolName` with the latest tool's name (`manage_mcp_servers`). Consequently, the UI displayed `manage_mcp_servers` as the header while the body showed `Skill 'mcp_integrations' loaded... ### Instructions`.

### Fix Implemented
1. **Model-Only Full Instructions vs Concise User Summary**:
   - Added `userFacingSummary(...)` to `LoadSkillTool`, `ReadSkillResourceTool`, `ToolSearchTool`, and `ReadToolResultTool`.
   - Updated `HanlinAISDKToolAdapter` (`makeLoadSkillDefinition`, `makeReadSkillResourceDefinition`, `makeToolSearchDefinition`, `makeReadToolResultDefinition`) so `resultForModel` receives the full `result` (preserving `### Instructions` for the LLM), while `resultForUser` and `StreamData.toolContent` receive only the concise localized summary.
2. **Per-Call Tool Attribution in `ClassicChatAgentProjection` & `ChatBubbleView`**:
   - `ClassicChatAgentProjection` now tracks `ClassicProjectedToolCallEntry` per `(runID, callID, toolName)`.
   - When multiple tools execute in a single turn, `assistantMessage.toolName` shows `"<latestTool> (+N)"` (e.g., `manage_mcp_servers (+1)`) and each tool's output section is clearly prefixed with `[<toolName>]`.
   - `ClassicChatAgentProjection.sanitizeUserFacingToolOutput(_:)` and `ChatBubbleView.resolvedToolContentForDisplay()` strip any `### Instructions` blocks from user-facing display.
