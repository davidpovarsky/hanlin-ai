# Hanlin Composer Action & Capability Parity Matrix

This document records the 100% functional parity mapping from the legacy `ChatViewBottom` / `ActionButtonsView` / `modelSelector` / `sourceSelector` controls to the new **Two-Entry Native Composer** (`HanlinComposerGeneralActionsView`, `HanlinComposerToolsRootView`, `HanlinModelPickerPopover`, and the minimal bottom control bar).

## 1. Bottom Composer Surface & Direct Entrypoints

| Legacy Surface / Control | Legacy Location (`ChatViewBottom.swift`) | New Surface / Location | Accessibility Identifier | State / Binding / Action |
| :--- | :--- | :--- | :--- | :--- |
| Multiline text input (`NativeMultilineTextEditor`) | `textInputSection` (lines 1189–1236) | Composer text editor area | `hanlin-chat-input` | `@Binding var inputText: String`, `@FocusState`, `@` model trigger, Return / Shift+Return, pasteboard image/file handlers |
| General `+` Attachment & Mode Menu | `sourceSelector` (lines 1138–1185) | Bottom bar leading button #1 (mirrored in RTL) | `hanlin-composer-general-menu` (with alias `hanlin-composer-plus-menu` support) | Opens `HanlinComposerGeneralActionsView` via `HanlinComposerPopupCoordinator.activePopup = .general` |
| Direct Tools / Skills / MCP / Runtime Entry | Previously split across `ActionButtonsView` tool icon + `MCPChatServerButton` | Bottom bar leading button #2 (adjacent to `+`, mirrored in RTL) | `hanlin-composer-tools-direct` | Single-tap opens `HanlinComposerToolsRootView` directly via `HanlinComposerPopupCoordinator.activePopup = .tools` (shows active dot/count badge) |
| Model Selector Capsule | `modelSelector` horizontal scroll strip (lines 1656–1778) | Bottom bar compact capsule #3 | `hanlin-composer-model-picker` / `hanlin-model-selector-capsule` | Opens `HanlinModelPickerPopover` via `HanlinComposerPopupCoordinator.activePopup = .model` (V3.3 two-phase zoom to All Models) |
| Active Mode Summary Chips | Always-visible 6–10 icon scroll strip | Optional compact dismissible active-mode chips above editor (collapses to count badge on narrow widths) | `hanlin-composer-active-chips` | Reflects active `ifSearch`, `ifKnowledge`, `ifThink`, `ifPlanning`, `ifAudio`, `ifToolUse`, MCP server count; tap chip to toggle/inspect |
| Voice Input (Microphone) | `ActionButtonsView` right capsule `mic` button (lines 2409–2427) | Bottom bar trailing permanent button | `hanlin-chat-mic` | `showVoiceInput = true` -> presents `VoiceInputView` sheet |
| Send Message | `ActionButtonsView` right capsule `arrow.up` (lines 2345–2405) | Bottom bar trailing primary action button | `hanlin-chat-send` | `handleSendMessage()` when `hasSendableContent && !isOfflineModelInvalid` |
| Stop Streaming | `ActionButtonsView` right capsule `stop.fill` (lines 2331–2344) | Bottom bar trailing primary action button (when `isLoading`) | `hanlin-chat-stop` | `onStop()` |
| Observe / Continue Turn | `ActionButtonsView` right capsule `eye` (lines 2367–2384) | Bottom bar trailing primary action button (when input empty & `canObserve`) + General `+` menu item | `hanlin-chat-observe` | `onSendObserve()` |

---

## 2. Attachment & Context Strip Parity (Above Text Editor)

| Legacy Strip | Legacy Function | New Behaviour | Accessibility Identifiers | Bindings & Callbacks |
| :--- | :--- | :--- | :--- | :--- |
| Image Attachments Strip | `imagePreviewSection` (lines 1244–1331) | Shown above text editor only when `!selectedImages.isEmpty` | `hanlin-composer-image-attachment`, `hanlin-remove-image-attachment` | `@Binding var selectedImages: [UIImage]`, Clear All, Reverse Prompt toggle (`imageReversePrompt`) when model lacks multimodal |
| Document Attachments Strip | `documentPreviewSection` (lines 1334–1435) | Shown above text editor only when `!selectedDocumentURLs.isEmpty` | `hanlin-composer-document-attachment`, `hanlin-remove-document-attachment` | `@Binding var selectedDocumentURLs: [URL]`, Clear All |
| Detected Links Strip | `linkPreviewSection` (lines 1438–1501) | Shown above text editor when URLs detected in `inputText` | Preserved | `detectedLinks: [URL]`, tap to open via `openURL` |
| Selected Prompt Card | `promptSection` (lines 1504–1569) | Shown above text editor when `selectedPrompt != nil` | Preserved | `@Binding var selectedPrompt: PromptRepo?` |
| Image Size Selector | `imageSizeControlSection` (lines 1572–1654) | Shown when current model `supportsImageGen == true` (also accessible from General `+` menu) | `hanlin-composer-image-size` | `@Binding var selectedImageSize: String` (`1024x1024`, `864x1152`, `1152x864`, `768x1344`, `1344x768`, `832x1248`, `1248x832`) |
| `@` Model Suggestion Strip | `modelSuggestionSection` (lines 1781–1860) | Shown when `@` mention filter is active | Preserved | `filteredModels`, `temporaryModel`, `selectModel(_:)` |
| Floating Canvas & Scroll-to-Bottom Buttons | `buildMultiSelectAndInputControls` (lines 296–367) | Preserved above composer container | Preserved | `showCanvas`, `isBottomHidden`, `onScrollToBottom()` |
| Multi-Select Message Action Bar | `multiSelectActionToolbar` (lines 1082–1135) | Preserved when `isMultiSelectMode == true` | Preserved | `onDeleteSelected`, `onShareSelected`, `onArchiveSelected` |

---

## 3. General `+` Menu (`HanlinComposerGeneralActionsView`) Parity

| Feature / Action | Legacy Control | New Control in General `+` Popover | Availability / Enabled Rule | State / Callback |
| :--- | :--- | :--- | :--- | :--- |
| Camera Capture | `sourceSelector` -> Camera | Attachment tile / row: Camera (`camera`) | Always visible; alerts if model `!supportsMultimodal && !imageReversePrompt` | `showCameraPicker = true` |
| Photo Library | `sourceSelector` -> Select Photos | Attachment tile / row: Photos (`photo.on.rectangle`) | Always visible; supports multimodal or `imageReversePrompt` | `showImagePicker = true` |
| Select Files / Docs | `sourceSelector` -> Select Files | Attachment tile / row: Files (`doc`) | Always visible | `showDocumentPicker = true` |
| Simulator Sample Attachments | `sourceSelector` acceptance hooks | Sample Image & Sample Document buttons | `#if targetEnvironment(simulator)` && `AgentRuntimeUIAcceptanceProvider.isEnabled` | `hanlin-attach-sample-image`, `hanlin-attach-sample-document` |
| Saved Prompts (`PromptRepo`) | `sourceSelector` -> Prompt menu | Expandable / navigable Saved Prompts list | Enabled when `!prompts.isEmpty` | Sets `selectedPrompt` (`PromptRepo`) |
| Online Search | `ActionButtonsView` `globe` button | Toggle row: Online Search (`globe`) | Enabled when `currentModel?.supportsSearch == true`; runs `checkSearchAvailability()` before enabling `ifSearch` | `@Binding var ifSearch: Bool` |
| Knowledge Bag | `ActionButtonsView` `book.closed` button | Toggle row + long-press/button for Embedding Model (`book.closed`) | Enabled when `currentModel?.supportsTextGen == true`; runs `checkEmbeddingAvailability()` | `@Binding var ifKnowledge: Bool` + `showingEmbeddingModelSheet = true` (`SelectEmbeddingModelView`) |
| Deep Thinking & Length | `ActionButtonsView` `sparkles` button + menu | Toggle row + segmented/menu selector for Thinking Length (`sparkles`) | Visible when `currentModel?.supportsReasoning == true`; modifiable when `supportReasoningChange == true` | `@Binding var ifThink: Bool`, `@Binding var thinkingLength: Int` (`0: Auto`, `1: Short`, `2: Medium`, `3: Long`) |
| Planning Mode | `ActionButtonsView` `list.bullet.clipboard` | Toggle row: Planning (`list.bullet.clipboard`) | Enabled when `currentModel?.supportsTextGen == true` | `@Binding var ifPlanning: Bool` |
| Voice Synthesis | `ActionButtonsView` `waveform` | Toggle row: Voice Output (`waveform`) | Enabled when `currentModel?.supportsVoiceGen == true` | `@Binding var ifAudio: Bool` |
| Image Generation Status & Size | `ActionButtonsView` `paintbrush.pointed` (previously no-op haptic button!) | **Repaired**: Truthful capability row when `supportsImageGen == true` with direct Image Aspect/Size picker | Visible/active when `currentModel?.supportsImageGen == true` | `@Binding var selectedImageSize: String` (no fake toggle) |
| Local On-Device Model Status | `ActionButtonsView` `bolt.horizontal.icloud` (previously no-op haptic button!) | **Repaired**: Non-interactive informational status badge/row when `company?.uppercased() == "LOCAL"` | Visible when `currentModel?.company?.uppercased() == "LOCAL"` | Truthful read-only status indicator |
| Expand Long-Text Editor | `ActionButtonsView` `arrow.up.left.and.arrow.down.right` | Action row: Fullscreen / Long Editor | Always enabled | `inputExpanded = true` (`BottomSheetView`) |
| Observe / Continue | `ActionButtonsView` `eye` | Action row: Observe / Continue Conversation | Enabled when `!isLoading && canObserve` | `onSendObserve()` |
| Model Parameters (`Temperature`, `Top-P`, `Max Tokens`, `Max Messages`) | `ActionButtonsView` `slider.horizontal.3` (`showParameterPopover`) | Navigable / expandable **Parameters** sub-panel inside General `+` popover | Enabled when `currentModel?.supportsTextGen == true` | `@Binding var temperature: Double`, `@Binding var topP: Double`, `@Binding var maxTokens: Int`, `@Binding var maxMessagesNum: Double` |
| Quick Jump to Tools / Skills / MCP | N/A | Secondary convenience row in General `+` ("Tools, Skills & MCP") | Always enabled | Switches coordinator to `.tools` (in addition to the permanent 1-tap `hanlin-composer-tools-direct` button) |

---

## 4. Direct Tools / Skills / MCP / Runtime Popover (`HanlinComposerToolsRootView`) Parity

Opened in **one tap** via `hanlin-composer-tools-direct` (with V3.3 two-phase size expansion + `.navigationTransition(.zoom)` into detail pages):

| Domain | Source of Truth | Capabilities in Popover | State & Actions |
| :--- | :--- | :--- | :--- |
| **Tools** (`NativeToolCatalog`) | `NativeToolCatalog.shared`, `@Binding var ifToolUse: Bool`, `currentModel?.supportsToolUse` | Master `ifToolUse` toggle for current chat; informative model-capability banner when `supportsToolUse == false`; live list of `NativeToolCatalog.shared.settingsGroups()` and standalone tools with group/individual toggles and link to `NativeAssistantToolGroupSettingsView` | `ifToolUse`, `NativeToolCatalog.shared.setGroupEnabled(_:for:)`, `NativeToolCatalog.shared.setEnabled(_:for:)` |
| **Skills** (`HanlinSkillCatalog` & `SkillStore`) | `HanlinSkillCatalog.shared`, `SkillStore.shared` | Live count of enabled/installed skills; search & per-skill enable/disable toggles (`SkillStore.shared.setSkillEnabled`); zoom navigation to full `SkillCenterView`, `SkillDetailView`, and `SkillImportView` | `SkillStore.shared.isSkillEnabled(id:)`, `SkillStore.shared.setSkillEnabled(id:enabled:)` |
| **MCP Servers** (`MCPRuntimeProvider`) | `MCPRuntimeProvider.shared` | Live 5-state summary (`global_mcp_enabled`, `server_installed`, `server_enabled`, `selected_for_current_chat`, `worker_running`); per-chat server selection checkboxes (`provider.selection(chatID:temporary:)` / `setSelection`); start/stop/restart server; zoom navigation to `MCPServersSettingsView` / `MCPServerInstallView` | `MCPRuntimeProvider.shared.setEnabled`, `setSelection`, `start`, `stop` |
| **Runtimes** (`AppRuntimeCore`) | `AppRuntimeCore.shared` | Live runtime snapshots (`Node.js`, `TypeScript`, `Local Python`, `JavaScriptCore`, `Shell`); zoom navigation to `RuntimeCenterView` | `AppRuntimeCore.shared.snapshots()`, `RuntimeCenterView()` |
