# Source Reference & Cryptographic Provenance (`InteriorOrganizerV3_3`)

## 1. Authoritative Reference Package & File Digests

| Artifact | Path / Origin | Size / Lines | SHA-256 Digest |
| :--- | :--- | :--- | :--- |
| Authoritative Local Reference Archive | `C:\Users\DAVID\Downloads\InteriorOrganizerV3_3.zip` (also uploaded as `media_1793486970294_0ef82922.zip`) | `102,422` bytes | `8611c6f7f537296f6ddc365b349f4bf773c2de70728183a94c75ea5731705723` |
| Extracted Swift Playground Source | `InteriorOrganizerV3_3.swiftpm/AppModule/ContentView.swift` | `73,974` bytes / **`1,810` lines** | `9d9ebe09a5f2ec6c590b7ad52cc15db6c967951acca6be42e9044623c642a716` |
| Excluded Alternative Archive (Do Not Use) | `C:\Users\DAVID\Downloads\InteriorOrganizerV3_3_2.zip` (`1,196` lines, SHA `33952ba155fd2fd4a8ebca52b74a2b71bd5792b281c2b7eb382deca3974775f4`) | Excluded | `38b3ebcb405f96bf0b8681f2ca8f19421c47cf07d79f8b2f88a902b8e213daff` |
| Clean Repair Base Branch (`origin/integration/hanlin-dual-widget-engines-20261029`) | Clean Worktree Base Commit SHA | — | `279f0ead777b961728ed91386c136e7e33659c36` |
| Historical Initial Dock Branch (`origin/fix/hanlin-organizerdock-source-parity-20261101`) | Historical Commit Tested in Run `41255137841` | — | `161640097a8aab3eebbfb2da08d721e56ef2bca9` |

### Verification Commands Executed

```powershell
Get-FileHash "C:\Users\DAVID\Downloads\InteriorOrganizerV3_3.zip" -Algorithm SHA256
# -> 8611C6F7F537296F6DDC365B349F4BF773C2DE70728183A94C75EA5731705723

# Extracted InteriorOrganizerV3_3.swiftpm/AppModule/ContentView.swift:
# SHA-256: 9d9ebe09a5f2ec6c590b7ad52cc15db6c967951acca6be42e9044623c642a716
# Byte length: 73,974 bytes | Line count: 1,810 lines
```

---

## 2. Exact Symbol & Line Map in `InteriorOrganizerV3_3.swiftpm/AppModule/ContentView.swift` (`1,810` lines)

- **Lines 270–273 (`private enum Destination: Hashable`)**:
  - `.allConversations`
  - `.conversation(UUID)`
- **Lines 295–385 (`struct ContentView: View`)**:
  - `@State private var navigationPath: [Destination] = []`
  - `@State private var activeConversationID: UUID?`
  - `@Namespace private var conversationZoomNamespace`
  - `@Namespace private var modelPopoverZoomNamespace`
  - Single outer `ZStack(alignment: .bottom)` hosting one `NavigationStack(path: $navigationPath)` and one persistent `organizerDock(availableHeight: proxy.size.height)` hidden only when `isShowingAllConversations` (`navigationPath.last == .allConversations`).
- **Lines 446–564 (`recentConversationsCard` & `recentConversationRow`)**:
  - Displays `Array(conversations.prefix(3))` above the persistent dock on Home.
  - `View All` button at lines `466–482` attaches `.matchedTransitionSource(id: "all-conversations", in: conversationZoomNamespace)` and appends `.allConversations` to `navigationPath`.
  - `recentConversationRow(_ item: ConversationThread)` at lines `501–564` renders a single-line fading preview with `LinearGradient` mask (`0`, `0.82`, `1.0`) and `0.6pt` divider.
- **Lines 599–629 (Dock Height & Viewport Formulas inside `ContentView`)**:
  - `autoComposerHeight(availableHeight:)`: base `92`, `+ (clampedLines - 1) * 20` (`clampedLines = min(max(draftLineCount, 1), 4)`), `+ (selectedFormat == nil ? 0 : 44)`, clamped against `maxComposerHeight(availableHeight:)`.
  - `maxComposerHeight(availableHeight:)`: `min(isExpanded ? 244 : 334, max(136, availableHeight - (isExpanded ? 280 : 120)))`.
  - `composerHeight(availableHeight:)`: `min(max(manualComposerHeight ?? auto, 92), maxH)`.
  - `panelHeight(availableHeight:)`: when collapsed `composer + 40`; when expanded `min(composer + 356, max(composer + 188, availableHeight - 16))`.
  - `editorMaxHeight(availableHeight:)`: `max(44, composerHeight(availableHeight: availableHeight) - (selectedFormat == nil ? 62 : 102))`.
- **Lines 637–648 (`organizerDock(availableHeight:)`)**:
  - Single bottom-aligned `ZStack(alignment: .bottom)` containing `drawerLayer(composerHeight:panelHeight:)` and `composerLayer(composerHeight:availableHeight:)` with `.frame(height: panel, alignment: .bottom)`.
- **Lines 650–748 (`drawerLayer(composerHeight:panelHeight:)`)**:
  - Rounded rectangle (`cornerRadius: 27, style: .continuous`), `36x4pt` top drag handle (`DragGesture(minimumDistance: 20)`, threshold `< -34` / `> 34`), `visibleContentHeight = max(0, panelHeight - composerHeight - 32)`, bottom `Spacer(minLength: composerHeight)`, and `.frame(height: panelHeight, alignment: .top)`.
- **Lines 750–904 (`composerLayer(composerHeight:availableHeight:)`)**:
  - Rounded rectangle (`cornerRadius: 25, style: .continuous`), top resize handle (`32x4pt` capsule inside `82x20pt` target), attachment/chip strip, multiline text input bounded by `editorMaxHeight`, bottom control row (`+`, model capsule, send), and `.frame(height: composerHeight, alignment: .top)`.
- **Lines 906–951 (`composerResizeGesture`, `adjustComposerHeight`, `toggleDrawerFromHandle`)**:
  - `DragGesture(minimumDistance: 7)` updating `manualComposerHeight = min(max(startHeight - value.translation.height, 92), maxHeight)`.
  - `toggleDrawerFromHandle()` toggling between `.collapsed` and `lastExpandedMode`.
- **Lines 1072–1139 (`allConversationsScreen`)**:
  - Full conversation library screen with `.navigationTransition(.zoom(sourceID: "all-conversations", in: conversationZoomNamespace))`.
- **Lines 1221–1503 (`ModelPopoverFlowView`)**:
  - Native `.popover` attached to the model capsule (`matchedTransitionSource(id: "model-popover", in: modelPopoverZoomNamespace)`), two-phase completion-driven expansion (`withAnimation(.easeInOut(duration: 0.24), completionCriteria: .removed)`), and `.matchedTransitionSource(id: "all-models", in: zoomNamespace)` into the provider-grouped `All Models` list.
