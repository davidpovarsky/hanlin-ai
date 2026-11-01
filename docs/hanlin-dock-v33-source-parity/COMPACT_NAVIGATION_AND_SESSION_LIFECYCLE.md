# Compact Navigation, Persistent Composer & Session Lifecycle

## 1. Adaptive Width Routing & Shared Session Bridge (`ListView` <-> `HanlinCompactChatWorkspace`)

- **Shared `HanlinActiveComposerSessionBridge` Owned by `ListView`**:
  - `ListView` owns `@State private var sessionBridge = HanlinActiveComposerSessionBridge()` and injects `.environment(\.hanlinComposerSessionBridge, sessionBridge)` into both the compact (`HanlinCompactChatWorkspace`) and wide (`NavigationSplitView`) hierarchies.
  - Because `sessionBridge` lives above the compact/wide branch in `ListView`, per-chat `draftSnapshots: [UUID: HanlinChatDraftSnapshot]` and `temporaryChatIDs: Set<UUID>` survive dynamic container width changes (`700pt -> 500pt -> 700pt`) without data loss.
- **Compact Mode (`HanlinCompactChatWorkspace.shouldUseCompactWorkspace(availableWidth:isPad:) == true`)**:
  - Active on all iPhone configurations (`!isPad`) and on narrow iPad windows (`availableWidth < 640pt`, or when `HANLIN_SIMULATE_CONTAINER_WIDTH < 640` in UI acceptance tests).
  - Renders a single outer `ZStack(alignment: .bottom)` containing:
    1. One `NavigationStack(path: $path)` with destinations for `.allConversations` (`HanlinCompactConversationLibrary`) and `.chat(UUID)` (`ChatView`).
    2. One persistent `ChatViewBottom` (`anchoredComposer`) anchored at the bottom across Home and `.chat(UUID)`, hidden only when `path.last == .allConversations`.
- **Wide Mode (`isPad && availableWidth >= 640pt`)**:
  - Preserves the classic `NavigationSplitView` sidebar and detail `ChatView` with inline `ChatViewBottom` (which uses `HanlinOrganizerDock` for the integrated drawer).
  - Sidebar rows use a deterministic selection `Button { selectedChatRecord = record }` with `.tag(record)` before `.id(...)`, and initial selection defaults to the most recently edited conversation (`defaultInitialChatRecord`).

---

## 2. Per-Chat Draft & Attachment Isolation (Wide & Compact)

- **Text Drafts**:
  - `ChatViewBottom` synchronously updates `chatRecord.input = message` inside `.onChange(of: message)` and `.onDisappear`, eliminating the 0.5-second debounce race when switching chats quickly.
  - `ChatView.openHistory()` explicitly clears `chatRecord.input = ""` when `message` is empty so sent messages never resurrect as stale drafts.
- **Attachments, URLs, Prompts, Model & Mode Toggles (`HanlinChatDraftSnapshot`)**:
  - `HanlinChatDraftSnapshot` stores `message`, `selectedImages`, `selectedDocumentURLs`, `selectedURLs`, `selectedPrompts`, `selectedModelIndex`, `ifKnowledge`, `ifSearch`, `ifToolUse`, `ifThink`, `ifAudio`, `ifPlanning`, `thinkingLength`, `selectedImageSize`, `imageReversePrompt`, and `isTemporaryChat` keyed by `chatID: UUID`.
  - Both compact and wide `ChatView` instances call `sessionBridge.snapshotEndpointState()` before unmount and `sessionBridge.restoreCachedDraftIfNeeded(into: endpoint)` on mount (`ChatView.restoreDraftSnapshotFromSessionBridgeIfNeeded()`), guaranteeing complete per-chat isolation for text, images, documents, URLs, prompts, and modes across `Chat A -> Chat B -> Chat A`.

---

## 3. Out-of-Order Registration Guard & Width-Transition Temporary Chat Protection

- **Expected Active Session Guard (`expectedActiveSessionID`)**:
  - `HanlinCompactChatWorkspace` sets `sessionBridge.expectedActiveSessionID = activeChatID` whenever `path` changes.
  - `sessionBridge.register(endpoint:)` verifies `expectedActiveSessionID == nil || endpoint.sessionID == expectedActiveSessionID`, rejecting stale `register` calls from an outgoing `ChatView` during rapid navigation.
  - `sessionBridge.unregister(sessionID:token:)` verifies both `activeEndpoint?.sessionID == sessionID` and `activeEndpoint?.registrationToken == token`.
- **Width-Transition Temporary Chat Lifecycle Guard**:
  - Before `measuredContainerWidth` crosses `640pt`, `ListView` calls `sessionBridge.beginLayoutModeTransition()`, setting `isTransitioningLayoutMode = true`.
  - When a temporary chat (`TemporaryRecord == true`) is active, `ChatView` registers `sessionBridge.setTemporaryChat(true, for: chatID)`.
  - In `ChatView.cleanupTemporaryChatIfNeeded()`, deletion is suppressed when `sessionBridge.isTransitioningLayoutMode` is true, and when the user explicitly turns off `TemporaryRecord` or sends a non-temporary message, `sessionBridge.setTemporaryChat(false, for: chatID)` clears the temporary flag so `HanlinCompactRecentChats` immediately includes the conversation.

---

## 4. Idempotent & Recoverable Home First-Turn State Machine (`HanlinPendingFirstTurn`)

- **Strict Model Validation (No Silent Fallback)**:
  - `beginHomeFirstTurn` validates `availableModels.indices.contains(homeSelectedModelIndex) && !availableModels[homeSelectedModelIndex].isHidden`. If invalid, it returns `nil` immediately without creating a phantom chat or silently falling back to an unintended model.
- **Two-Stage Dispatch & Acceptance (`awaitingChatMount -> dispatching -> dispatched`)**:
  1. `beginHomeFirstTurn` snapshots all Home draft fields (`message`, `selectedImages`, `selectedDocumentURLs`, `selectedURLs`, `selectedPrompts`, `selectedModelIndex`, and all mode toggles) into `pendingFirstTurn` in state `.awaitingChatMount(targetChatID:)` and clears the Home composer.
  2. When the target `ChatView` mounts and calls `register(endpoint:)`, `deliverPendingFirstTurnIfNeeded` transitions `pendingFirstTurn` to `.dispatching(targetChatID:registrationToken:)`, applies the payload to `endpoint`, and schedules execution on the next main-actor turn.
  3. Before invoking `endpoint.onSendUser()` / `endpoint.onSendObserve()`, `sessionBridge` checks `endpoint.validateSendAcceptance?()`.
  4. Only when `validateSendAcceptance` succeeds does `pendingFirstTurn` transition to `.dispatched(targetChatID:)` with a non-nil `acceptedUserMessageID` (`isAccepted == true`).
- **Full Rollback on Pre-Acceptance Cancellation, Unmount, or Rejection**:
  - If `cancelPendingFirstTurn()`, `failPendingFirstTurn(reason:)`, or `unregister(sessionID:token:)` occurs before `isAccepted == true`, `restoreHomeState(from: turn)` restores the user's complete message, images, documents, URLs, prompts, selected model index, and mode toggles back to the Home composer.
