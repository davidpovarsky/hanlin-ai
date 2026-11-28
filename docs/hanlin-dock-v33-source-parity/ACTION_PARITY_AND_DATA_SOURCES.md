# Action Parity, Classic Hanlin Visual Vocabulary & Real Data Sources

## 1. Restored Classic Hanlin Button & Color Vocabulary (R4)

| Control | Accessibility ID | Inactive Icon | Active / Open Icon | Active / Accent Color |
| :--- | :--- | :--- | :--- | :--- |
| General `+` Drawer Button | `hanlin-composer-general-menu` | `plus.circle` (outlined) | `xmark.circle.fill` (when `.general` open) | `.hlBluefont` (`.hlRed` when close icon shown; `.primary` in temporary chat) |
| Direct 1-Tap Tools Drawer Button | `hanlin-composer-tools-direct` | `hammer.circle` (when tools off) / `hammer.circle.fill` (when `ifToolUse` or MCP active) | `xmark.circle.fill` (when `.tools` open) | `.hlBrown` when tools/MCP active, `.hlBluefont` default, `.hlRed` when close icon shown |
| Model Selector Capsule | `hanlin-composer-model-picker` | Provider asset icon / `sparkles` + `chevron.up.chevron.down` | Popover presented | `.hlBluefont` |
| Voice Input (Microphone) | `hanlin-chat-mic` | `mic.fill` | Sheet presented | `.hlBluefont` |
| Send Message | `hanlin-chat-send` | `arrow.up.circle.fill` | N/A | `.hlBluefont` (`.gray.opacity(0.4)` when model invalid) |
| Stop Active Run | `hanlin-chat-stop` | `stop.circle.fill` | N/A | `.hlRed` |
| Observe / Continue | `hanlin-chat-observe` | `eye.circle.fill` | N/A | `.hlBluefont` |

---

## 2. Authentic Data Sources & Complete Action Parity Matrix

| Capability / Surface | Authentic Hanlin Data Source & Binding | Executed Test Verification |
| :--- | :--- | :--- |
| Compact Home Recent Conversations (R1) | `@Query var chatRecords: [ChatRecords]` filtered by `type == "chat"` and `!temporaryChatIDs.contains(id)`, sorted by `lastEdited` descending (`prefix(3)`). | `CompactRecentConversationsTests`, `testDockCompactHomeShowsThreeRecentWithOnePersistentComposer` |
| Compact Conversation Library (R1) | `ListView.filterAndSortChatRecords` + `ChatRowView` with search, pin/unpin, rename/icon edit, and delete. | `testViewAllZoomSourceToLibraryAndCancelledInteractiveBack` |
| Camera, Photos, Document Attachments & Preview Strips | Real `selectedImages: [UIImage]`, `selectedDocumentURLs: [URL]`, `selectedURLs: [String]` bindings in `ChatView` & `ChatViewBottom`; removable on-screen preview strips (`hanlin-composer-image-attachment`, `hanlin-composer-document-attachment`); simulator-only fixture buttons (`hanlin-attach-sample-image`, `hanlin-attach-sample-document`) gated strictly behind `HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE == "1"`. | `testUI05RichCodeBlockHTMLCardAndAttachments`, `testUI06ComposerMultilineAttachmentsModelSelectorNoOverlap`, `testDraftAndAttachmentPersistenceAtoBAndFirstSend` |
| General Drawer Saved Prompts Horizontal Slot (R7) | `@Query var savedPrompts: [PromptRepo]` rendered in the horizontal scroll gallery (`hanlin-drawer-saved-prompts-slot`); tapping a card populates the composer draft; empty state links to Prompts manager (`hanlin-drawer-open-prompts-empty`). | `testDrawerGrowsFromComposerNotPopover` |
| General Drawer Mode Toggles & Image Size Subpage | Real bindings for `ifSearch`, `ifKnowledge`, `ifThink`, `thinkingLength`, `ifPlanning`, `ifAudio`, `temporaryRecord`, `selectedImageSize` (`hanlin-general-imagesize-row` -> inline `hanlin-general-imagesize-page`), and `onClearContext`. | `ComposerActionsParityTests`, `testUI06ComposerMultilineAttachmentsModelSelectorNoOverlap` |
| Direct Tools Drawer (`.tools`) & Inline Subpages (R3, R6) | `NativeToolCatalog.shared`, `ToolPermissionStore.shared`, `HanlinSkillCatalog.shared`, `SkillStore.shared`, `MCPRuntimeProvider.shared` (keyed on stable `effectiveMCPChatID`), and `AppRuntimeCore.shared` across `.root`, `.toolsCatalog` (`hanlin-tools-catalog-page`), `.skills` (`hanlin-skills-page` + `hanlin-skills-search-field`), `.mcp` (`hanlin-mcp-page` + server toggles), and `.runtime` (`hanlin-runtime-page`). | `HanlinComposerDrawerRouteTests`, `testDirectToolsOneTapAndRealState`, `testUI09DirectToolsCatalogAndSkillsNavigation` |
| Model Picker Popover & All Models (R2, R6) | `@Query var allModels: [AllModels]` filtered by visible models, grouped by provider (`company`) in the expanded `All Models` view with live search (`hanlin-model-picker-search-field`). | `ModelPopoverZoomOrderTests`, `testModelPopoverZoomExpandThenNavigate`, `testUI10ModelPickerSearchSelectionAndPersistence` |
| Send / Stop / Observe / Retry & Tool Activity | Real `ChatView.sendMessage()`, `cancelCurrentRun()`, `sendObserveMessage()`, `retryLastTurn()` (`hanlin-error-retry-button`), and collapsible tool activity bubbles (`hanlin-tool-content-toggle`). | `testStreamingStopObserveTemporaryAndStateTransitions`, `testUI07StopAndRetryRecoveryWithoutDuplicateBubbles`, `testRealChatUISendsPromptShowsToolActivityAndFinalAnswer` |
