# Original Chat Touchpoint Ledger (§5 Minimal Hook Policy)

## 1. Zero-Touch Guarantee on Protected Original Chat Files

| Protected File | Status Against Base `9281bd2f6e2c11706b1ae47962cc9a312d17d412` | Verification Command |
| :--- | :--- | :--- |
| `AI_HLY/Views/Components/ChatViewComponents.swift` | **0 lines changed (byte-identical)** | `git diff --exit-code 9281bd2f6e2c11706b1ae47962cc9a312d17d412 HEAD -- AI_HLY/Views/Components/ChatViewComponents.swift` |
| `AI_HLY/Views/Components/ChatandFile.swift` | **0 lines changed (byte-identical)** | `git diff --exit-code 9281bd2f6e2c11706b1ae47962cc9a312d17d412 HEAD -- AI_HLY/Views/Components/ChatandFile.swift` |
| `AI_HLY/Services/ChatServices/APIManager.swift` | **0 lines changed (byte-identical)** | `git diff --exit-code 9281bd2f6e2c11706b1ae47962cc9a312d17d412 HEAD -- AI_HLY/Services/ChatServices/APIManager.swift` |

## 2. Minimal Scoped Hooks in Original Chat Files

| File | Scoped Hook Summary | Purpose |
| :--- | :--- | :--- |
| `AI_HLY/Views/Components/ChatViewBottom.swift` | Replaced floating `.popover` attachments on `+` and `Tools` with `HanlinOrganizerDock`; restored classic `plus.circle` and `hammer.circle` / `hammer.circle.fill` icons; wired `popupCoordinator.dockState.editorMaxHeight` into `NativeMultilineTextEditor`; added `.matchedTransitionSource(id: "model-popover")` + `.navigationTransition(.zoom)` on the model capsule popover; used stable `effectiveMCPChatID`. | R2, R3, R4, R6 |
| `AI_HLY/ChatView.swift` | Read `hanlinExternalCompactComposerHost`, `hanlinExternalDockHeight`, and `hanlinComposerSessionBridge` from environment; hid inline `ChatViewBottom` when externally hosted by `HanlinCompactChatWorkspace`; registered/updated/unregistered live `Endpoint` on `sessionBridge`; adjusted `dynamicBottomPadding()` to `max(225, externalDockHeight + 24)`; guarded temporary chat cleanup on layout transitions. | R5, R6 |
| `AI_HLY/ListView.swift` | Measured container width via `onGeometryChange` and routed compact widths (`< 640pt` or iPhone) to `HanlinCompactChatWorkspace` while keeping wide iPad `NavigationSplitView` untouched; extracted `createAuthorizedNewChatRecord()` helper. | R1, R5 |
