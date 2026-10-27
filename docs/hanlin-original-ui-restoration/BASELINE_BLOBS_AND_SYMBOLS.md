# Baseline Blobs and Original Symbol Inventory

- **Repository**: `davidpovarsky/hanlin-ai`
- **Isolated Repair Worktree**: `C:\Users\DAVID\Code\hanlin-classic-source-first-20261027`
- **Branch**: `fix/classic-source-first-agent-acceptance-20261025`
- **Original Baseline Commit**: `478cdd2c23ae2b1a52044cff52ce720830128ea2`
- **Step 1 Literal Restore Checkpoint Commit**: `83ad2725d5d5eb600dc6613f4264461613eeb10e`

---

## 1. Exact Git Baseline Blobs (`478cdd2c23ae2b1a52044cff52ce720830128ea2`)

In Step 1 (`83ad2725d5d5eb600dc6613f4264461613eeb10e`), the five original files were restored byte-for-byte from `478cdd2c23ae2b1a52044cff52ce720830128ea2` and verified with `git rev-parse`:

| File Path | Baseline Blob SHA (`478cdd2c23...`) | Step 1 Restored Blob SHA (`83ad2725d...`) | Original Lines | Adapted Blob SHA | Adapted Lines |
|---|---|---|---:|---|---:|
| `AI_HLY/ChatView.swift` | `2040a1a97de5cdcc427a885c6b02bb585deba3dc` | `2040a1a97de5cdcc427a885c6b02bb585deba3dc` | 3,372 | `5fabfab0a1ec599609d7981c3b39457dfe8cc9f4` | 3,668 |
| `AI_HLY/Views/Components/ChatViewComponents.swift` | `7b6da5a889ca4c05288c4cb70468f2c271fc3fc0` | `7b6da5a889ca4c05288c4cb70468f2c271fc3fc0` | 5,514 | `d5de4f5b51f53c50bcd62a9d6331bb11b4c5dd67` | 5,804 |
| `AI_HLY/Views/Components/ChatViewBottom.swift` | `857d342b2389226681c7432a999a8a8e31ba4c60` | `857d342b2389226681c7432a999a8a8e31ba4c60` | 2,379 | `85ee7eff0c3f8d19fc325ae4025f00df1ccdacef` | 2,477 |
| `AI_HLY/Views/Components/ChatandFile.swift` | `2bb464042e235ab1b58821ba7c2c134851db7e83` | `2bb464042e235ab1b58821ba7c2c134851db7e83` | 645 | `4b0325aaca204e851508c369abfc85028d0a8213` | 646 |
| `AI_HLY/ListView.swift` | `ddbb0b89214fb81d7e23ef3dfbbdb63c65d623ac` | `ddbb0b89214fb81d7e23ef3dfbbdb63c65d623ac` | 485 | `6f5f756d6374ddd3434d87019fd10a22551e56a3` | 632 |

---

## 2. Original Symbol & View Inventory

### 2.1 `AI_HLY/ChatView.swift`
- `ChatView`: Root conversation screen owning `@State private var chatMessages: [ChatMessages]`, `@State private var isResponding: Bool`, `@State private var operationalState: String`, `@State private var operationalDescription: String`, `@State private var currentTask: Task<Void, Never>?`, and `@State private var activeAgentRunID: UUID?`.
- `ChatNavHeaderView`: Original top navigation bar header with conversation icon, title, subtitle (`共\(chatMessages.count)条对话`), and temporary chat badge.
- `ChatShareSheetView`: Original multi-select conversation share/export sheet.
- `buildMessageList()`: Original `ScrollViewReader` + `ScrollView` + `LazyVStack` rendering `ChatBubbleView` directly for every `ChatMessages` row without any parallel `ModernChatConversationScreen` or `ModernChatTranscriptList`.
- `sendUserMessage()` / `sendGroupChatRequests()` / `retrySingleMessage()`: Original message dispatch and streaming loop calling `APIManager.sendStreamRequest` and projecting events into `ChatMessages`.

### 2.2 `AI_HLY/Views/Components/ChatViewComponents.swift`
- `LoadingGradientText`: Animated `.hlBluefont` gradient shimmer text used for operational status headers (`正在思考...`, `正在使用工具...`, `正在检索网页...`).
- `ChatBubbleView`: Sole ordinary-chat row renderer for all roles (`user`, `assistant`, `search`, `information`, `error`):
  - `userMessageView()`: Right-aligned user bubble (`Color.hlBlue` background with white text in normal mode, `.primary` in temporary mode) with image grid, document pills, prompt cards, and context menu (`复制文本`, `选择文本`, `朗读文本`, `翻译内容`, `存为知识`, `重新请求`, `删除消息`).
  - `assistantMessageView()`: Left-aligned assistant turn with model header (`assistantHeader()`), foldable `reasoningView()`, `loadingSection()`, `imagesSection()`, `textSection()` (Markdown + LaTeX math mode), `codeBubble()`, `htmlBubble()`, `mapBubble()`, `canvasBubble()`, `eventBubble()`, `healthBubble()`, `knowledgeBubble()`, `nativeUIBlockSection()`, `toolContentView()`, `audioView()`, `translateView()`, `resourcesView()`, `actionButtons()`, and `assistantFooter()`.
  - `searchMessageView()`: Original `role == "search"` Information Content (`信息内容`) pill with `.hlBlue` capsule outline, `book` sheet button (`ResourcesSheetView`), search engine badge, and `xmark.circle` delete confirmation.
  - `informationMessageView()`: Original `role == "information"` greeting card with quick-action pills and random poem footer.
  - `errorMessageView()`: Original `role == "error"` red capsule with `arrow.clockwise.circle` retry and `xmark.circle` delete actions.
- `ToggleButton`: Original foldable header (`reasoning_chain`, `tooluse_content`, `voice_block`, `translated_content`, `reference_materials`) with `.hlBluefont` active icon/text.
- `CodeBlockRow` & `CodeDetailSheet` & `PistonRunner`: Original `源代码` card (`查看代码` / `运行代码`) and `运行结果` output section.
- `WebContentPreviewView` & `WebFullScreenSheet`: Original `网页信息` interactive HTML preview card.
- `MultiLocationMapView`, `CanvasCardView`, `EventCardView`, `HealthCardView`, `KnowledgeCardView`, `AudioMessageView`, `ResourcesSheetView`, `TextSelectionView`.

### 2.3 `AI_HLY/Views/Components/ChatViewBottom.swift`
- `ChatViewBottom`: Original bottom composer shell with:
  - Floating `画布` (Canvas) and `arrow.down` scroll-to-bottom capsule buttons with `BlurView(style: .systemUltraThinMaterial)`.
  - `buildMultiSelectAndInputControls()`: `GlassView(style: .systemUltraThinMaterial)` with `CustomCorners(tl: 20, tr: 20, bl: 30, br: 30)` and `.hlBlue` drop shadow (`color: TemporaryRecord ? .primary.opacity(0.25) : .hlBlue.opacity(0.25), radius: 6`).
  - `messageInput`: Expandable composer area (`imagePreviewSection`, `documentPreviewSection`, `linkPreviewSection`, `promptSection`, `imageSizeControlSection`, `voiceInputSection`, `inputFieldSection` with `NativeMultilineTextEditor`, `ActionButtonsView`).
  - `modelSelector` & `ModelMenuSheetView`: Horizontal capsule model selector strip (`modelSelectorMode == false`, default) and menu sheet mode (`modelSelectorMode == true`).
  - `sourceSelector`: Expandable attachment panel (`拍摄照片`, `相册选择`, `文件文本`, and prompt repo pills).
- `ActionButtonsView`: Original bottom action bar with `plus.circle` (`hanlin-composer-plus-menu`), `hammer.circle` (`ifToolUse`), `backpack.circle` (`ifKnowledge`), `network` (`ifSearch`), `location.circle` (`ifPlanning`), `lightbulb.circle` (`ifThink`), `waveform.circle` (`ifAudio`), `camera.aperture` (`supportsImageGen`), `lock.circle` (`LOCAL`), and right-side `stop.circle.fill` / `arrowtriangle.up.circle.fill` / `eye.circle.fill`.

### 2.4 `AI_HLY/Views/Components/ChatandFile.swift` & `AI_HLY/ListView.swift`
- `ChatRowView`: Original conversation list row with icon, title, pinned indicator (`pin.fill`), last message snippet, and timestamp.
- `ListView`: Original conversation list screen with search bar, pinned/unpinned sorting, swipe actions (`置顶`/`取消置顶`, `修改`, `删除`), top feature cards (`文本翻译`, `文本润色`, `摘要提取`), and iPad `NavigationSplitView` adaptation.

---

## 3. Deleted Competing Ordinary-Chat UI Files (9 Files Removed)

All nine parallel ordinary-chat replacement files introduced in earlier iterations were deleted via `git rm`:
1. `AI_HLY/Downstream/AgentActivity/AgentActivitySummaryView.swift`
2. `AI_HLY/Downstream/AgentActivity/Evidence/AgentEvidenceSummaryView.swift`
3. `AI_HLY/Downstream/AgentActivity/Transcript/AgentInlineProcessItemView.swift`
4. `AI_HLY/Downstream/AgentActivity/Transcript/AgentInlineProcessView.swift`
5. `AI_HLY/Downstream/AgentActivity/Transcript/AgentRunTranscriptView.swift`
6. `AI_HLY/Downstream/AgentActivity/Transcript/AgentTranscriptActivityRow.swift`
7. `AI_HLY/Downstream/ChatPresentation/ChatAssistantActionsView.swift`
8. `AI_HLY/Downstream/ChatPresentation/ChatExecutionTimelineItemView.swift`
9. `AI_HLY/Downstream/ChatPresentation/ChatUserMessageSurface.swift`
