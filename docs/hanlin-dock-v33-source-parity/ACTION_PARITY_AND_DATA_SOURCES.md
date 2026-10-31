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

## 2. Authentic Data Sources (No Demo/Fake Strings)

| Surface | Authentic Hanlin Data Source | Verification |
| :--- | :--- | :--- |
| Compact Home Recent Conversations (R1) | `@Query var chatRecords: [ChatRecords]` filtered by `type == "chat"` and `!temporaryChatIDs.contains(id)`, sorted by `lastEdited` descending (`prefix(3)`). | `CompactRecentConversationsTests`, `testDockCompactHomeShowsThreeRecentWithOnePersistentComposer` |
| Compact Conversation Library (R1) | `ListView.filterAndSortChatRecords` + `ChatRowView` with search, pin/unpin, rename/icon edit, and delete. | `testViewAllZoomSourceToLibraryAndCancelledInteractiveBack` |
| General Drawer Saved Prompts Horizontal Slot (R7) | `@Query var savedPrompts: [PromptRepo]` rendered in the horizontal scroll gallery (`hanlin-drawer-saved-prompts-slot`); tapping a card populates the composer draft; empty state links to Prompts manager (`hanlin-drawer-open-prompts-empty`). | `testDrawerGrowsFromComposerNotPopover` |
| Direct Tools Drawer (`.tools`) (R3, R6) | `NativeToolCatalog.shared`, `ToolPermissionStore.shared`, `HanlinSkillCatalog.shared`, `SkillStore.shared`, `MCPRuntimeProvider.shared` (keyed on stable `effectiveMCPChatID`), and `AppRuntimeCore.shared`. | `testDirectToolsOneTapAndRealState`, `testUI09DirectToolsCatalogAndSkillsNavigation` |
| Model Picker Popover & All Models (R2, R6) | `@Query var allModels: [AllModels]` filtered by visible models, grouped by provider (`company`) in the expanded `All Models` view with live search. | `ModelPopoverZoomOrderTests`, `testModelPopoverZoomExpandThenNavigate`, `testUI10ModelPickerSearchSelectionAndPersistence` |
