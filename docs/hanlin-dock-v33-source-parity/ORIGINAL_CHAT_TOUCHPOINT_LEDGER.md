# Original Chat Touchpoint Ledger (§5 Minimal Hook Policy)

## 1. Zero-Touch Cryptographic Guarantee on Protected Original Chat Files

Base Commit SHA (`origin/integration/hanlin-dual-widget-engines-20261029`): `279f0ead777b961728ed91386c136e7e33659c36`

| Protected File | Git Blob Hash (`git rev-parse HEAD:<path>`) | LF-Normalized Byte Length | LF-Normalized SHA-256 Digest | Diff Lines Against Base |
| :--- | :--- | :--- | :--- | :--- |
| `AI_HLY/Views/Components/ChatViewComponents.swift` | `bc2ff417d810301cfaef5e89d578aba66427df8f` | `245,684` bytes | `cbcbdffd5a05abe6889b9eafe83a5266661f61c6440c6e12ac74be4565ba1901` | **0 lines (byte-identical)** |
| `AI_HLY/Views/Components/ChatandFile.swift` | `4b0325aaca204e851508c369abfc85028d0a8213` | `1,966` bytes | `3260125c5dece237c8775806b21c470275c9cb5a88328fa6fba2f283c8f3e26d` | **0 lines (byte-identical)** |
| `AI_HLY/Services/ChatServices/APIManager.swift` | `60fe0b151f4391a1e1fd7ebe84337c6d2cd272a5` | `197,303` bytes | `ec09f12217985b6f37e9f88ea6653eff2823a31f96a9eb0ad6fe1062ea204df4` | **0 lines (byte-identical)** |

### Verification Commands & Automated Test

- Automated Unit Test: `OriginalSourceNonRegressionTests.protectedFilesAndReferenceMetadataRemainIntact` (`AI_HLYTests/HanlinOrganizerDockParityTests.swift` lines `959–998`).
- Git Verification:
  ```bash
  git diff --exit-code 279f0ead777b961728ed91386c136e7e33659c36 HEAD -- \
    AI_HLY/Views/Components/ChatViewComponents.swift \
    AI_HLY/Views/Components/ChatandFile.swift \
    AI_HLY/Services/ChatServices/APIManager.swift
  ```

---

## 2. Minimal Scoped Hooks in Original Chat Files & Why Downstream-Only Was Insufficient

| Original File | Exact Symbols & Line Ranges Modified | Why a Downstream-Only Change Was Insufficient |
| :--- | :--- | :--- |
| `AI_HLY/Views/Components/ChatViewBottom.swift` | `struct ChatViewBottom` (`lines 25–155`, `248–460`, `620–785`, `965–1070`):<br>• `dockContextKey`, `availableWorkspaceSize`, `@State measuredAttachmentPreviewHeight`, `@State baselineWorkspaceHeight`<br>• `composerCard` wrapped in `HanlinOrganizerDock`<br>• `NativeMultilineTextEditor` `.frame(height: popupCoordinator.dockState.effectiveEditorFrameHeight(...))`<br>• Synchronous `chatRecord.input = message` update in `.onChange(of: message)` and `.onDisappear`<br>• Keyboard notification observers (`keyboardWillChangeFrameNotification`, `keyboardWillHideNotification`) feeding `dockState.updateKeyboardOverlap`<br>• Classic `plus.circle`, `hammer.circle`/`hammer.circle.fill`, `.hlBluefont`, `.hlBrown`, `.hlRed` styling & model capsule `.popover` zoom source | `ChatViewBottom` owns the live `NativeMultilineTextEditor`, attachment preview strips, and bottom toolbar buttons. Without binding `NativeMultilineTextEditor`'s frame to `effectiveEditorFrameHeight`, measuring the attachment preview strip height, and syncing `chatRecord.input` before the 0.5s debounce, manual composer resize could not grow the `UITextView`, multi-attachment previews clipped the bottom toolbar, and switching chats within `< 0.5s` dropped typed drafts. |
| `AI_HLY/ChatView.swift` | `struct ChatView` (`lines 120–145`, `155–185`, `535–580`, `630–795`, `2320–2335`):<br>• Environment reads (`hanlinExternalCompactComposerHost`, `hanlinExternalDockHeight`, `hanlinComposerSessionBridge`)<br>• `@State measuredWorkspaceSize` via `.onGeometryChange` passed to `ChatViewBottom`<br>• `calculateDynamicBottomPadding` cap raised from `420` to `680`<br>• Per-chat draft/attachment snapshot & restore via `sessionBridge` on `onAppear`/`onDisappear` in both wide and compact modes<br>• `validateSendAcceptance` callback on `Endpoint`<br>• Layout-transition and `sessionBridge.isTemporaryChat` guard in `cleanupTemporaryChatIfNeeded()`<br>• `openHistory()` clearing `chatRecord.input = ""` when `message` is empty | `ChatView` owns `@State selectedImages`, `@State selectedDocumentURLs`, `@State selectedURLs`, `@State selectedPrompts`, `@State TemporaryRecord`, and the transcript `ScrollView` bottom clearance. Without snapshotting/restoring attachments in `ChatView` and guarding `cleanupTemporaryChatIfNeeded()` across width transitions, wide-mode chat switching lost image/document attachments and Stage Manager width changes deleted active temporary chats. |
| `AI_HLY/ListView.swift` | `struct ListView` (`lines 38–90`, `112–210`, `505–545`):<br>• Shared `@State private var sessionBridge = HanlinActiveComposerSessionBridge()` injected into both wide and compact branches<br>• `sessionBridge.beginLayoutModeTransition()` / `endLayoutModeTransition()` across the `640pt` threshold<br>• `HANLIN_SIMULATE_CONTAINER_WIDTH` support in `effectiveContainerWidth(for:)`<br>• `defaultInitialChatRecord` selecting the most recently edited `"chat"` record rather than an older pinned thread<br>• `chatRecordRow(for:)` using a deterministic selection `Button` + `.tag(record)` instead of a conflicting `NavigationLink(destination:)` inside `NavigationSplitView(sidebar:detail:)` | `ListView` is the root container switching between `NavigationSplitView` (`>= 640pt`) and `HanlinCompactChatWorkspace` (`< 640pt`). Holding `sessionBridge` in `ListView` preserves per-chat draft snapshots and temporary-chat protection across width transitions, while fixing `chatRecordRow` and `defaultInitialChatRecord` eliminated the `NavigationSplitView` detail selection race in wide mode. |
