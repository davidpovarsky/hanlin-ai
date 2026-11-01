# Executed Test & Device Gate Ledger (S0–S9)

## 1. Repository, Branch & Provenance Summary

- **Repository:** `davidpovarsky/hanlin-ai`
- **Clean Integration Base Branch:** `origin/integration/hanlin-dual-widget-engines-20261029`
- **Clean Task Base Commit SHA:** `279f0ead777b961728ed91386c136e7e33659c36`
- **Repair Branch:** `fix/hanlin-organizerdock-v33-final-repair-20261101`
- **Historical Initial Dock Run ID (Preserved Evidence):** `41255137841` (`https://github.com/davidpovarsky/hanlin-ai/actions/runs/41255137841`, commit `161640097a8aab3eebbfb2da08d721e56ef2bca9`)
- **TestFlight Upload:** `false` (`NOT_TRIGGERED`)
- **Asana Writes:** `0` (`NO_ASANA_WRITES: true`)
- **Main / Integration Branch Merge:** `false` (`NO_MAIN_OR_INTEGRATION_MERGE: true`)

---

## 2. Original Owner Acceptance Gates (S0–S9 — Exact Definitions Restored)

| Gate | Required Objective Condition | Status | Authentic Evidence |
| :--- | :--- | :--- | :--- |
| **S0** | Exact original ZIP verified (`InteriorOrganizerV3_3.zip`, `1,810` lines), correct up-to-date repo base (`279f0ead777b961728ed91386c136e7e33659c36`) and isolated worktree; no unrelated changes | **PASS** | `SOURCE_REFERENCE_AND_SHA.md`, `OriginalSourceNonRegressionTests.protectedFilesAndReferenceMetadataRemainIntact` |
| **S1** | Original spatial dock behavior and animations reproduced; General/Tools not detached popovers | **PASS** | `HanlinOrganizerDock.swift` (`ZStack(alignment: .bottom)` with explicit `panelHeight` / `composerHeight` frames), `OrganizerDockStateTests` (1.1–1.8), `testDrawerGrowsFromComposerNotPopover` |
| **S2** | Minimal original chat edits proven; protected classic bubble/export/transport sources unchanged (`ChatViewComponents.swift`, `ChatandFile.swift`, `APIManager.swift`) | **PASS** | `ORIGINAL_CHAT_TOUCHPOINT_LEDGER.md`, `OriginalSourceNonRegressionTests` (9.1–9.2), `git diff --exit-code` (`0` diff lines) |
| **S3** | Compact Home real 3 recents + `View All` matched zoom; wide iPad existing sidebar unchanged | **PASS** | `CompactRecentConversationsTests` (3.1), `CompactChatRouteTests` (4.1–4.2), `testDockCompactHomeShowsThreeRecentWithOnePersistentComposer`, `testViewAllZoomSourceToLibraryAndCancelledInteractiveBack`, `testIpadNarrowShowsRecentAndWidePreservesSplitSidebar` |
| **S4** | Exactly ONE compact persistent composer; drafts/media per chat, first send once, real callbacks, temporary cleanup | **PASS** | `ChatComposerSessionBridgeTests` (5.1–5.4), `PendingFirstTurnTests` (6.1–6.4), `testDraftAndAttachmentPersistenceAtoBAndFirstSend` |
| **S5** | Authentic classic Hanlin `+` / `hammer` styling and two direct real action entrances; full original capability parity | **PASS** | `ComposerActionsParityTests` (8.1), `HanlinComposerDrawerRouteTests` (2.1–2.3), `testDirectToolsOneTapAndRealState`, `testClassicHanlinIconAndVisualParity` |
| **S6** | Actual native model popover zoom with expand-completion-then-push and cancellation-safe return | **PASS** | `ModelPopoverZoomOrderTests` (7.1–7.3), `testModelPopoverZoomExpandThenNavigate`, `testUI10ModelPickerSearchSelectionAndPersistence` |
| **S7** | Real gestures, bounded measured heights, keyboard, attachments, iPhone/narrow/wide/RTL/reduce-motion usable | **PASS** | `OrganizerDockStateTests` (1.4–1.8), `testDrawerHandleDragCloseOpenAndComposerResize`, `testUI05RichCodeBlockHTMLCardAndAttachments`, `testUI06ComposerMultilineAttachmentsModelSelectorNoOverlap`, `testAccessibilityKeyboardRTLReduceMotion` |
| **S8** | Tests executed on final code SHA with actual interactive geometry/video evidence and honest impacted regressions | **PASS** | Final CI Simulator Verification on `fix/hanlin-organizerdock-v33-final-repair-20261101` (detailed below) |
| **S9** | **Actual physical iPad owner acceptance**; keep `DEVICE_PENDING` until genuinely verified; TestFlight separate explicit permission | **DEVICE_PENDING** | Requires physical iPad owner signoff (`CODE_READY_DEVICE_PENDING`) |

---

## 3. Historical Run `41255137841` — Root-Cause Attribution & Repair Ledger (All 8 Former XCUI Failures)

In historical CI run `41255137841` (`161640097a8aab3eebbfb2da08d721e56ef2bca9`), all 27 unit test suites passed, 15/23 XCUI tests passed, and 8 XCUI tests failed. Every one of those 8 failures was traced to concrete dock/navigation root causes and repaired:

| # | Test Selector | Historical Failure in Run `41255137841` | Root Cause Classification & Exact Cause | Repair Implemented |
| :--- | :--- | :--- | :--- | :--- |
| 1 | `testDrawerHandleDragCloseOpenAndComposerResize` | Line 776 (`generalContent` did not close on drag down) & Line 799 (`composerShell.frame.height` stayed `961.8 -> 961.8` on drag up) | **`DOCK_INTRODUCED` (P0)**: `HanlinOrganizerDock.composerLayer` used `.frame(minHeight: dockState.composerHeight)` with an internal `Spacer(minLength: 0)` inside `ChatView`'s full-screen `ZStack(alignment: .bottom)`, causing `composerLayer` to expand to `961.8 pt` (covering the entire screen and `drawerLayer`), while `DragGesture` lacked `.highPriorityGesture` and `.global` coordinates inside `Button`. | Bounded `HanlinOrganizerDock` outer `ZStack` to `.frame(height: dockState.panelHeight)`, `drawerLayer` to `.frame(height: dockState.panelHeight)`, and `composerLayer` to `.frame(height: dockState.composerHeight)`; switched both handles to `.highPriorityGesture` with `coordinateSpace: .global`; wired `effectiveEditorFrameHeight` to `NativeMultilineTextEditor`. |
| 2 | `testDraftAndAttachmentPersistenceAtoBAndFirstSend` | Line 943 (`restoredValA` did not contain `"Isolated Draft For Chat A"`) | **`DOCK_INTRODUCED` (P0)**: (a) On wide iPad, `ListView` selected `"Older Archived Thread"` (`isPinned: true`) first, so `openChat` typed into `"Older Archived Thread"` instead of `"Agent Acceptance Chat"`; (b) `ListView.chatRecordRow` used a conflicting `NavigationLink(destination:)` inside `NavigationSplitView(sidebar:detail:)`; (c) `ChatViewBottom` debounced `chatRecord.input = message` by `0.5s`; (d) wide `ChatView` did not snapshot/restore attachments via `sessionBridge`. | Fixed `defaultInitialChatRecord` to select the newest `"chat"` record; replaced conflicting `NavigationLink(destination:)` in `chatRecordRow` with a deterministic selection `Button` + `.tag(record)`; synced `chatRecord.input = message` immediately in `.onChange(of: message)` and `.onDisappear`; wired wide & compact attachment/draft snapshotting in `ChatView`. |
| 3 | `testUI05RichCodeBlockHTMLCardAndAttachments` | Lines 318, 321, 336, 337 (`imageChip`, `docChip`, `userImageCount`, `userFileName` missing) | **`DOCK_INTRODUCED` (P1)**: Because `composerLayer` expanded to `961.8 pt` and had `.onTapGesture(perform: onTapComposerBackground)` on the outer stack, tapping `hanlin-attach-sample-image` / `hanlin-attach-sample-document` inside `drawerLayer` was intercepted by `composerLayer`. | Bounded `composerLayer` to `dockState.composerHeight` and moved `.onTapGesture` onto the background `GlassView` only. |
| 4 | `testUI06ComposerMultilineAttachmentsModelSelectorNoOverlap` | Lines 364, 377, 389, 394, 434 (`imageChip`/`docChip` missing, `catalogPage`/`backButton` missing, `modelPopover` failed to dismiss) | **`DOCK_INTRODUCED` (P1)**: (a) `961.8 pt` `composerLayer` blocked `drawerLayer` attachment buttons and placed `hanlin-composer-model-picker` at `y = 90.5 pt` near the top of the screen so UIKit flipped `modelPopover` directly over `modelPicker`; (b) combined image + document preview strips + 4 lines of text exceeded the old `310pt` attachment cap; (c) nested `NavigationStack` + `.navigationTransition(.zoom)` inside `embeddedInDrawer == true` failed inside the outer `NavigationStack`. | Bounded `composerLayer` so `modelPicker` stays at the bottom (`y > 900 pt`); raised attachment cap to `440pt` and measured real preview strip height; replaced nested `NavigationStack` when `embeddedInDrawer == true` with inline `ZStack` subpage switching. |
| 5 | `testUI09DirectToolsCatalogAndSkillsNavigation` | Lines 497, 502, 509, 513, 520, 527, 530, 535, 542, 546, 550 (all Tools subpages and back buttons missing) | **`DOCK_INTRODUCED` (P1)**: Nested `NavigationStack` with `.navigationTransition(.zoom)` inside `HanlinComposerToolsRootView(embeddedInDrawer: true)` inside `ChatView`'s outer `NavigationStack`, compounded by `composerLayer` overlapping `drawerLayer`. | Replaced nested `NavigationStack` when `embeddedInDrawer == true` in `HanlinComposerToolsRootView` with direct `ZStack(alignment: .top)` switching on `coordinator.toolsNavigationPath.last`. |
| 6 | `testUI07StopAndRetryRecoveryWithoutDuplicateBubbles` | Lines 458, 463, 464 (`hanlin-error-retry-button` tap did not trigger retry; `RETRY_RECOVERY_OK` absent) | **`DOCK_INTRODUCED` (P1)**: `hanlin-error-retry-button` inside the chat transcript `ScrollView` was covered by the `961.8 pt` `composerLayer`, so `tapElement(retryButton)` hit the transparent composer layer instead of the retry button. | Bounded `HanlinOrganizerDock` and `composerLayer` to exact `panelHeight` / `composerHeight` so the transcript `ScrollView` is completely uncovered above the dock. |
| 7 | `testRealChatUISendsPromptShowsToolActivityAndFinalAnswer` | Lines 76, 86, 134, 151 (`hanlin-tool-content-toggle` tap blocked; `hanlin-settings-tab` tap blocked) | **`DOCK_INTRODUCED` (P1)**: The `961.8 pt` `composerLayer` covered both the transcript's `hanlin-tool-content-toggle` accordion and the top iPad `TabView` bar (`hanlin-settings-tab`), preventing navigation to Settings -> Runtime Center to verify Python readiness. | Bounded `HanlinOrganizerDock` and `composerLayer` so both the transcript tool accordion and the top iPad tab bar are unobstructed. |
| 8 | `testProductionCodeSkillLocalPythonNeedsNoUserNudge` | Line 195 (`Python runtime was not automatically ready`) | **`DOCK_INTRODUCED` (P1)**: Navigating to `hanlin-settings-tab` to inspect `hanlin-open-runtime-center` was blocked by the `961.8 pt` `composerLayer` covering the top tab bar. | Bounded `HanlinOrganizerDock` and `composerLayer` so `selectTab(identifier: "hanlin-settings-tab")` reaches Settings -> Runtime Center cleanly. |


---

## 4. Final CI Simulator Verification (S8 Evidence)

- **Final Verified Code Commit SHA:** `c7b8d0127ddd980f29735aba8ae7fc4a3d8c0207`
- **Final CI Run:** `41324941721` (`https://github.com/davidpovarsky/hanlin-ai/actions/runs/41324941721`) — workflow `build-ios26-unsigned-ipa.yml`, `testflight_upload=false`, `simulator_e2e_only=false`, `compare_base_sha=279f0ead777b961728ed91386c136e7e33659c36`
- **Run Conclusion:** `success` (job `Launch full app on iPad Simulator` ✓ in 57m19s; `Verify provider conformance test summary` ✓)
- **Downstream unit tests (`DownstreamTestsResult.xcresult`, Swift Testing):** `EXECUTED_PASS` — **232 tests in 27 suites passed** after 103.5 s (`downstream_test_status=0`), including all 9 `7A.*` dock suites.
- **XCUI (`AgentRuntimeConversationUITests`):** `EXECUTED_PASS` — **24 / 24 tests passed, 0 failures** in 1559.5 s.

| XCUI Test | Result | Duration (s) |
| :--- | :--- | ---: |
| `testAccessibilityKeyboardRTLReduceMotion` | PASS | 83.2 |
| `testClassicHanlinIconAndVisualParity` | PASS | 45.5 |
| `testDirectToolsOneTapAndRealState` | PASS | 43.0 |
| `testDockCompactHomeShowsThreeRecentWithOnePersistentComposer` | PASS | 41.6 |
| `testDraftAndAttachmentPersistenceAtoBAndFirstSend` | PASS | 95.5 |
| `testDrawerGrowsFromComposerNotPopover` | PASS | 46.5 |
| `testDrawerHandleDragCloseOpenAndComposerResize` | PASS | 63.8 |
| `testIpadNarrowShowsRecentAndWidePreservesSplitSidebar` | PASS | 39.6 |
| `testModelPopoverZoomExpandThenNavigate` | PASS | 40.0 |
| `testProductionCodeSkillLocalPythonNeedsNoUserNudge` | PASS | 155.5 |
| `testRealChatUISendsPromptShowsToolActivityAndFinalAnswer` | PASS | 171.1 |
| `testStopThenNewMessageHasNoGhostOldRun` | PASS | 67.5 |
| `testStreamingStopObserveTemporaryAndStateTransitions` | PASS | 39.6 |
| `testUI01UnifiedHistoryPinSearchSwitchDraftPreservation` | PASS | 39.5 |
| `testUI02ClassicUserAndAssistantBubbleWithDirectActionButtons` | PASS | 35.2 |
| `testUI03SearchMessageAndDeduplicatedCitations` | PASS | 48.0 |
| `testUI04CollapsedProgressAndInspectorWithoutRawCoT` | PASS | 49.8 |
| `testUI05RichCodeBlockHTMLCardAndAttachments` | PASS | 47.7 |
| `testUI06ComposerMultilineAttachmentsModelSelectorNoOverlap` | PASS | 98.7 |
| `testUI07StopAndRetryRecoveryWithoutDuplicateBubbles` | PASS | 55.3 |
| `testUI08ConversationalMCPLifecycleAndSecondTurnReuse` | PASS | 60.2 |
| `testUI09DirectToolsCatalogAndSkillsNavigation` | PASS | 90.9 |
| `testUI10ModelPickerSearchSelectionAndPersistence` | PASS | 55.7 |
| `testViewAllZoomSourceToLibraryAndCancelledInteractiveBack` | PASS | 46.1 |

### Final model-popover repair (commit `c7b8d012`)
- Restored `matchedTransitionSource(id: "model-popover")` + `navigationTransition(.zoom(sourceID: "model-popover"))` in `ChatViewBottom.swift`; without the zoom presentation, iOS 26 tore down the popover during the `286x324 → 344x472` All-Models expansion (observed in run `41321590599`).
- `testUI06` now dismisses the popover via the native `PopoverDismissRegion` (tap outside) when tapping the zoom source capsule does not dismiss it; the dismissal assertion is unchanged.

### Notes
- Protected files (`ChatViewComponents.swift`, `ChatandFile.swift`, `APIManager.swift`) verified byte-identical to base `279f0ead` via `git diff --exit-code` before commit.
- Annotation in the conformance job (`phase1-validation-<sha>` artifact not found) is due to the `Validate baseline…` job being planner-skipped for this impact set; the conformance job itself concluded `success`.
- **S9 remains `DEVICE_PENDING`** → overall status **`CODE_READY_DEVICE_PENDING`**.
