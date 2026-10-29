# Original Source Diff Ledger

- **Baseline Commit**: `478cdd2c23ae2b1a52044cff52ce720830128ea2`
- **Literal Restore Checkpoint Commit**: `83ad2725d5d5eb600dc6613f4264461613eeb10e`
- **Aggregate Diff Across All 5 Restored Files**: `5 files changed, 1099 insertions(+), 435 deletions(-)` out of `12,395` original lines.

---

## 1. Per-File Diff Summary Against `478cdd2c23ae2b1a52044cff52ce720830128ea2`

| File | Baseline Lines | Final Lines | Diff Stat vs `478cdd2c23...` | Purpose of Minimal Adaptations |
|---|---:|---:|---|---|
| `AI_HLY/Views/Components/ChatandFile.swift` | 645 | 646 | `+2 / -1` | Set `@AppStorage("modelSelectorMode") private var isMenuMode: Bool = false` so the classic horizontal model strip is the default; add `.accessibilityIdentifier("hanlin-new-chat-button")` on `AddChatButtonView`. |
| `AI_HLY/ListView.swift` | 485 | 632 | `+198 / -51` | Add `static func filterAndSortChatRecords(_:searchText:)`, iPad `NavigationSplitView` adaptation (`horizontalSizeClass == .regular`), `ChatViewWrapper` for detail pane, and `AgentRuntimeUIAcceptanceProvider.seedIfNeeded(context:)` hook for deterministic simulator XCUI runs. |
| `AI_HLY/Views/Components/ChatViewBottom.swift` | 2,379 | 2,477 | `+106 / -8` | Preserve 100% of the original BLUE `ChatViewBottom` visual shell (`GlassView`, `.hlBlue` shadow, `messageInput`, `ActionButtonsView`, `modelSelector`, `sourceSelector`); embed `NativeMultilineTextEditor` inside `inputFieldSection` for native multiline/IME/paste/Return-key handling; add `static func shouldEnableSend(...)` and XCUI accessibility identifiers. |
| `AI_HLY/Views/Components/ChatViewComponents.swift` | 5,514 | 5,804 | `+446 / -156` | Preserve `ChatBubbleView` as sole ordinary-chat renderer; add `sanitizedReasoningDisplay` (`ProgressSummarySanitizer.sanitizeProviderReasoningSummary`), `resolvedToolContentForDisplay`, `resolvedResourcesForDisplay` (filtering `search.local`), `nativeUIBlockSection()` hosting `ChatEmbeddedResultHost` in `.hlBlue` card styling only for interactive `NativeUIBlock` payloads, and XCUI accessibility identifiers. |
| `AI_HLY/ChatView.swift` | 3,372 | 3,668 | `+347 / -219` | Preserve original `ChatView` structure, `ChatNavHeaderView`, `buildMessageList()`, and `ChatViewBottom`; wire `ClassicChatAgentProjection` in `sendGroupChatRequests` and `retrySingleMessage` to project `StreamData` (`agentEvent`, `sourceId`/`sourceUrl`, `fileData`/`fileMimeType`, `nativeUIBlock`) into `ChatMessages`; wire `AgentRunLifecycleCoordinator` in `cancelStreamingResponse()` and `retrySingleMessage(_:)` to isolate cancelled runs and prevent ghost output. |

---

## 2. Symbol-by-Symbol Exception Ledger

### 2.1 `AI_HLY/Views/Components/ChatandFile.swift`
1. `ChatListHeaderView.isMenuMode`:
   - **Original**: `@AppStorage("modelSelectorMode") private var isMenuMode: Bool = true`
   - **Adapted**: `@AppStorage("modelSelectorMode") private var isMenuMode: Bool = false`
   - **Justification**: Matches `ChatViewBottom.swift` default (`false`) so the original horizontal model capsule strip renders by default unless the user toggles menu mode.
2. `AddChatButtonView`:
   - **Adapted**: Added `.accessibilityIdentifier("hanlin-new-chat-button")` for XCUI navigation.

### 2.2 `AI_HLY/ListView.swift`
1. `ListView.filterAndSortChatRecords(_:searchText:)`:
   - **Original**: Inline `filteredChatRecords` computed property.
   - **Adapted**: Extracted `static func filterAndSortChatRecords(_ records: [ChatRecords], searchText: String) -> [ChatRecords]` called by `filteredChatRecords`.
   - **Justification**: Allows unit testing pinned/unpinned sorting and search matching directly without changing UI behavior.
2. `ListView.body`:
   - **Original**: Single `NavigationStack(path: $navigationPath)` for all size classes.
   - **Adapted**: Uses `NavigationSplitView` when `horizontalSizeClass == .regular` (iPad) and the original `NavigationStack(path: $navigationPath)` in compact width.
   - **Justification**: Required iPad adaptation (`G3`) while keeping the exact original list rows (`ChatRowView`), swipe actions, and top feature buttons (`文本翻译`, `文本润色`, `摘要提取`).

### 2.3 `AI_HLY/Views/Components/ChatViewBottom.swift`
1. `ChatViewBottom.inputFieldSection`:
   - **Original**: Used single-line `PassThroughTextField` (`UITextField`) when collapsed and `TextEditor` when expanded.
   - **Adapted**: Uses `NativeMultilineTextEditor` (`UITextView` wrapper) inside the exact original `inputFieldSection` container alongside the original expand (`arrow.down.right.and.arrow.up.left`) and voice (`waveform`/`xmark`) buttons.
   - **Justification**: Fixes multiline auto-growth (1–6 lines), hardware keyboard `Return` vs `Shift+Return`, Hebrew/Arabic RTL & CJK `markedTextRange` IME composition, and clipboard image/file paste (`G3`) inside the untouched original blue `GlassView` composer shell.
2. `ChatViewBottom.shouldEnableSend(...)`:
   - **Adapted**: Pure static helper verifying that send is enabled when text or attachments (`selectedImages`, `selectedDocumentURLs`, `selectedPrompts`) are present and `!isResponding`.

### 2.4 `AI_HLY/Views/Components/ChatViewComponents.swift`
1. `ChatBubbleView.reasoningView()`:
   - **Original**: Rendered raw `reasoning` string directly.
   - **Adapted**: Uses `sanitizedReasoningDisplay` and `sanitizedReasoningLines` via `ProgressSummarySanitizer.sanitizeProviderReasoningSummary` so raw `<think>` tags and private chain-of-thought monologues are never exposed in UI (`G7`).
2. `ChatBubbleView.toolContentView()` & `resourcesView()`:
   - **Original**: Read `toolContent`/`toolName` and `resources` directly.
   - **Adapted**: `resolvedToolContentForDisplay` and `resolvedResourcesForDisplay` read `toolContent`/`resources` and also project any persisted `agentRun.steps` / `agentRun.evidenceItems` while filtering out invalid or `search.local` links.
3. `ChatBubbleView.nativeUIBlockSection()`:
   - **Adapted**: Renders `ChatEmbeddedResultHost` (styled with `.hlBlue` border/tint) inside `assistantMessageView()` only when `nativeUIBlocks` is non-empty (interactive `NativeScript` / `Svelte` / `WebView` mini-apps).

### 2.5 `AI_HLY/ChatView.swift`
1. `ChatView.sendGroupChatRequests(...)` & `retrySingleMessage(...)`:
   - **Adapted**: Connects `APIManager.sendStreamRequest` stream chunks (`data.agentEvent`, `data.sourceId`, `data.fileData`, `data.nativeUIBlock`) to `ClassicChatAgentProjection.applyAgentEvent`, `appendProviderSource`, `appendProviderFile`, and `finalizeTurn`, and registers/cancels runs via `AgentRunLifecycleCoordinator.shared`.
