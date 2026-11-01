# Compact Navigation, Persistent Composer & Session Lifecycle

## 1. Adaptive Width Routing (`ListView` <-> `HanlinCompactChatWorkspace`)

- **Compact Mode (`HanlinCompactChatWorkspace.shouldUseCompactWorkspace(availableWidth:isPad:) == true`)**:
  - Active on all iPhone configurations (`!isPad`) and on narrow iPad windows (`availableWidth < 640pt`, such as Slide Over, 1/3 Split View, or narrow Stage Manager windows).
  - Renders a single outer `ZStack(alignment: .bottom)` containing:
    1. A single `NavigationStack(path: $path)` with destinations for `.allConversations` (`HanlinCompactConversationLibrary`) and `.chat(UUID)` (`ChatView`).
    2. A single persistent `ChatViewBottom` (`anchoredComposer`) anchored at the bottom across Home (`"new"`) and `.chat(UUID)`, hidden only when `path.last == .allConversations`.
- **Wide Mode (`isPad && availableWidth >= 640pt`)**:
  - Preserves the classic `NavigationSplitView` sidebar and detail `ChatView` with inline `ChatViewBottom` (which still uses `HanlinOrganizerDock` for the integrated drawer).

## 2. Live Session Bridge (`HanlinActiveComposerSessionBridge`)

- When a `ChatView` is pushed inside `HanlinCompactChatWorkspace`, `.environment(\.hanlinExternalCompactComposerHost, true)` hides `ChatView`'s internal `ChatViewBottom` and registers an `Endpoint` binding the external persistent `ChatViewBottom` directly to `ChatView`'s `@State` properties (`inputText`, `selectedImages`, `selectedDocumentURLs`, `ifSearch`, `ifKnowledge`, `ifThink`, `thinkingLength`, `ifPlanning`, `ifAudio`, `ifToolUse`, `temporaryRecord`, `isResponding`, `currentModel`, and send/observe/cancel callbacks).
- **Per-Chat Draft & Attachment Isolation**:
  - `HanlinChatDraftSnapshot` stores per-conversation drafts, image/document attachments, mode toggles, and selected model ID keyed by `chatID: UUID`.
  - Switching between Chat A, Home, and Chat B saves and restores each conversation's independent draft state.
- **Race-Safe Unregistration**:
  - `unregister(chatID:)` checks `activeEndpoint?.chatID == chatID` before clearing `activeEndpoint`, preventing an outgoing `ChatView`'s `onDisappear` from clobbering a newly mounted `ChatView`.

## 3. Deterministic Home First-Turn State Machine (`HanlinPendingFirstTurn`)

- When the user types a message (or attaches files) on compact Home (`activeEndpoint == nil`) and taps Send or Observe:
  1. `sessionBridge.beginHomeFirstTurn(mode:createChat:)` snapshots the Home draft, attachments, mode toggles, and selected model into a `HanlinPendingFirstTurn` in state `.created`, clears the Home composer, invokes `createChat()` to insert the new `ChatRecords` and append `.chat(newID)` to `path`, and transitions the pending turn to `.awaitingEndpoint`.
  2. When the newly pushed `ChatView` mounts and calls `sessionBridge.register(endpoint)` with matching `endpoint.chatID == pending.chatID`, `deliverPendingFirstTurnIfNeeded(to: endpoint)` transfers the draft/attachments/toggles to the live `ChatView`, transitions `pendingFirstTurn` to `.dispatched`, and invokes `endpoint.sendUser()` (or `endpoint.sendObserve()`) on the next main-actor turn.
  3. If the user taps Stop (`cancelPendingFirstTurn()`) before `ChatView` finishes mounting, `pendingFirstTurn` transitions to `.cancelled` and is cleared, preventing any late execution.
