# Source Reference & Cryptographic Provenance (`InteriorOrganizerV3_3`)

## 1. Uploaded Reference Package & File Digests

| Artifact | Path / Origin | SHA-256 Digest |
| :--- | :--- | :--- |
| Uploaded Reference Archive | `InteriorOrganizerV3_3_2.zip` (`media_1793486970294_0ef82922.zip`) | `8611C6F7F537296F6DDC365B349F4BF773C2DE70728183A94C75EA5731705723` |
| Extracted Source File | `InteriorOrganizerV3_3.swiftpm/AppModule/ContentView.swift` (`1,196` lines) | `9D9EBE09A5F2EC6C590B7AD52CC15DB6C967951ACCA6BE42E9044623C642A716` |
| Base Branch (`origin/integration/hanlin-dual-widget-engines-20261029`) | Base Commit SHA | `9281bd2f6e2c11706b1ae47962cc9a312d17d412` |
| Superseded Historical Branch (`origin/fix/hanlin-composer-dual-entry-v33-build84701`) | Superseded Commit SHA (108 commits behind base) | `9bf36a0b97f41687853fc0e3e37e9507c7fa7d0b` |

## 2. Authoritative Line Ranges in `InteriorOrganizerV3_3.swiftpm/AppModule/ContentView.swift`

- **Lines 178–252 (`WorkspaceRoute` & `InteriorOrganizerRootView`)**: Single outer `ZStack(alignment: .bottom)` hosting one `NavigationStack(path: $path)` and one persistent `anchoredComposer` hidden only on `.allConversations`.
- **Lines 469–578 (`recentConversationsSection` & `ConversationLineRow`)**: 3 most recent conversations above the persistent composer on compact Home, single-line fading mask (`LinearGradient` `0 -> 0.82 -> 1.0`), 0.6pt hairline dividers, and `View All` `.matchedTransitionSource(id: "all-conversations", in: libraryZoom)` -> `.navigationTransition(.zoom(sourceID: "all-conversations", in: libraryZoom))`.
- **Lines 586–935 (`OrganizerDock`)**: Single bottom-aligned `ZStack(alignment: .bottom)` combining the back `drawer` (top handle bar with `DragGesture(minimumDistance: 20)` and `< -34` / `> 34` threshold) and front `composer` (top resize handle with `DragGesture(minimumDistance: 7)` and `+/-72pt` accessibility adjust action).
- **Lines 937–1154 (`ModelPopoverFlowView`)**: Compact model capsule `.popover` with `.matchedTransitionSource(id: "model-popover", in: modelPopoverZoom)`, two-phase completion-driven expansion (`withAnimation(.easeInOut(duration: 0.24), completionCriteria: .removed)`), and `.matchedTransitionSource(id: "all-models", in: zoomNamespace)` into the provider-grouped `All Models` list.
