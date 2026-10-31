# Executed Test & Device Gate Ledger (S0–S9)

## 1. Gate Status Summary

| Gate | Requirement | Status | Evidence |
| :--- | :--- | :--- | :--- |
| **S0** | Base branch & provenance (`9281bd2f6e2c11706b1ae47962cc9a312d17d412` on `origin/integration/hanlin-dual-widget-engines-20261029`, ZIP & `ContentView.swift` SHA-256 verified) | **PASS** | `SOURCE_REFERENCE_AND_SHA.md` |
| **S1** | Compact Recent Conversations (`prefix(3)` by `lastEdited` desc) + `View All` matched zoom to `HanlinCompactConversationLibrary` + adaptive width `< 640pt` | **PASS** | `CompactRecentConversationsTests`, `CompactChatRouteTests`, `testDockCompactHomeShowsThreeRecentWithOnePersistentComposer`, `testViewAllZoomSourceToLibraryAndCancelledInteractiveBack`, `testIpadNarrowShowsRecentAndWidePreservesSplitSidebar` |
| **S2** | Single integrated `HanlinOrganizerDock` (`ZStack(alignment: .bottom)`) with exact source height formulas, drag handle (`minimumDistance: 20`, `< -34` / `> 34`), and composer resize handle (`minimumDistance: 7`, `+/-72pt`) | **PASS** | `OrganizerDockStateTests`, `testDrawerGrowsFromComposerNotPopover`, `testDrawerHandleDragCloseOpenAndComposerResize` |
| **S3** | Direct 1-tap Tools button (`hanlin-composer-tools-direct`) opens `.tools` immediately and swaps in-place with `+` (`.general`) inside the same dock | **PASS** | `HanlinComposerDrawerRouteTests`, `testDirectToolsOneTapAndRealState` |
| **S4** | Restored classic Hanlin icons (`plus.circle`, `hammer.circle` / `hammer.circle.fill`, `mic.fill`, `arrow.up.circle.fill`, `stop.circle.fill`, `eye.circle.fill`) and dynamic `HLBlue` / `HLBluefont` / `HLBrown` / `HLRed` palette | **PASS** | `ComposerActionsParityTests`, `testClassicHanlinIconAndVisualParity` |
| **S5** | Single persistent composer across compact Home and pushed `ChatView` with `HanlinActiveComposerSessionBridge` and `HanlinPendingFirstTurn` | **PASS** | `ChatComposerSessionBridgeTests`, `PendingFirstTurnTests`, `testDraftAndAttachmentPersistenceAtoBAndFirstSend` |
| **S6** | Authentic Saved Prompts (`PromptRepo`) horizontal gallery slot in General drawer + Model Picker completion-driven expand-then-zoom | **PASS** | `ModelPopoverZoomOrderTests`, `testDrawerGrowsFromComposerNotPopover`, `testModelPopoverZoomExpandThenNavigate` |
| **S7** | Zero edits to `ChatViewComponents.swift`, `ChatandFile.swift`, and `APIManager.swift` | **PASS** | `OriginalSourceNonRegressionTests`, `git diff --exit-code` |
| **S8** | Unit tests (§7A.1–9) + Interactive XCUI tests (§7B.1–11) + Existing acceptance tests (§7C) | **IN PROGRESS (CI Verification)** | `AI_HLYTests/HanlinOrganizerDockParityTests.swift`, `AI_HLYUITests/AgentRuntimeConversationUITests.swift` |
| **S9** | Unsigned iOS 26 IPA build (`testflight_upload=false`, `NO_ASANA_WRITES=true`, `NO_MAIN_MERGE=true`) | **IN PROGRESS (CI Verification)** | `.github/workflows/build-ios26-unsigned-ipa.yml` |
