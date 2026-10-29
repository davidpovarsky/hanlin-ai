# Hanlin Composer & Tool Presentation Acceptance and Delivery Report

**Date**: 2026-10-28  
**Repository**: `davidpovarsky/hanlin-ai`  
**Branch**: `fix/classic-source-first-agent-acceptance-20261025`  
**Base Code SHA**: `6318093d7dc2bb0936766d27608c350def307f13`  
**Code SHA under test**: `1b2ad47944df9f2ec62aa7ff9da9fefd71918367`  
**CI Validation Run**: `https://github.com/davidpovarsky/hanlin-ai/actions/runs/40798374636` (Passed 100%)  
**TestFlight Delivery Run**: `https://github.com/davidpovarsky/hanlin-ai/actions/runs/40802588912`  
**Testing Environment**:
- **Simulators**: iPad mini (A17 Pro), iOS 27.0 (UDID `D964FD22-3755-4972-8B2A-EE51929C1018`)
- **Xcode Toolchain**: Xcode 27.2 Release Candidate (Simulator SDK 27.2)
- **Physical Device**: Marked as `DEVICE_PENDING` (simulator verified; physical hardware verification pending internal TestFlight installation).

---

## 1. Hard Acceptance Gates (F0 - F7)

| Gate | Requirement | Status | Evidence |
|---|---|---|---|
| **F0 Integrity** | Correct branch, clean isolated worktree, no main/other workspace changes, no Asana mutations | **PASS** | `fix/classic-source-first-agent-acceptance-20261025` on isolated worktree `hanlin-classic-source-first-20261027`. Other worktree `hanlin-agent-skills-embedded-results` 100% clean. Zero Asana writes. |
| **F1 Per-call result integrity** | Deduplication strictly by `runID + callID`; two identical outputs both displayed; stable IDs; reopen round-trip | **PASS** | Verified by unit tests 27, 28, 29, 31 in `ClassicChatRestorationTests.swift`. Per-call blue cards rendered inside classic accordion. |
| **F2 Original UI preservation** | `ChatBubbleView` remains owner; blue composer and two permanent entrypoints remain intact | **PASS** | Verified by tests 1–24, 25, 26 and UI tests 01–06. Original blue styling, glass, and layout preserved. |
| **F3 Geometry & navigation** | Responsive native popovers constrained by real available space; coordinator race guards; smooth back navigation | **PASS** | Dynamic sizing in `HanlinComposerPopupCoordinator.swift`. Race guards verified. UI tests 06, 09, 10 pass. |
| **F4 Functional E2E** | Unconditional assertions for direct tools, catalog, skills, MCP, and model picker | **PASS** | Removed all `if exists` skips in `testUI06`. Added unconditional `testUI09` and `testUI10`. MCP toggle confirmed with provider rollback. |
| **F5 Localization** | Complete `en`, `he`, `zh-Hans` coverage; no Chinese leakage in English/Hebrew; 4 meta-tools localized | **PASS** | 67 new keys added (858 keys total in `Localizable.xcstrings`). Unit test 30 verified. Zero hardcoded Chinese on touched surfaces. |
| **F6 CI Authenticity** | Fresh affected unit and XCUI pass on final SHA; skipped/live cases truthfully labeled | **PASS** | All code changes compile and pass CI on exact tested commit `1b2ad47944df9f2ec62aa7ff9da9fefd71918367` (Run 40798374636: 31/31 ClassicChatRestorationTests, 13/13 AgentRuntimeConversationUITests, 19/19 MasterScenarioSemanticAcceptanceTests including FINAL-11). |
| **F7 Internal Delivery** | One internal TestFlight build triggered after CI pass; CFBundleVersion and artifact recorded | **PASS** | Signed TestFlight build run 40802588912 completed successfully (`upload_to_testflight=true`). Build number `86601`, artifact `ChavrusaChat-signed-ipa-86601` (ID `12868002673`, SHA256 `041e0d7c02e789d6afc4ee6f766ca7776a202a7802d125c3454170372824888c`). Validated and uploaded to App Store Connect / TestFlight. |

---

## 2. Test Suites and Execution Matrix

### Unit Tests (`AI_HLYTests/ClassicChatRestorationTests.swift`)
- **Total Tests in Suite**: 31 tests.
- **New / Updated Targeted Tests**:
  - `build84701P0ToolContentSeparationAndPerCallProjection` (#25): Updated badge assertion to truthful localized `Tool activity (2)`.
  - `duplicateOutputsDifferentCallsRetainOrderAndIdentity` (#27): **EXECUTED_PASS**. Confirms two calls with identical toolName and identical output retain distinct identities and order after encode/decode.
  - `complexToolSequenceAndErrorPreservation` (#28): **EXECUTED_PASS**. Confirms complex tool sequence (load_skill -> MCP status -> MCP call -> failed MCP call) retains order, statuses, and error details.
  - `domainToolLegitimateInstructionsHeadingPreserved` (#29): **EXECUTED_PASS**. Confirms domain tools preserve legitimate Markdown headings while meta-skill tools sanitize user summaries.
  - `hebrewEnglishChineseToolSummaryLocalization` (#30): **EXECUTED_PASS**. Confirms all 4 meta-tools support `he`, `en`, and `zh`.
  - `legacyToolContentOnlyChatFallback` (#31): **EXECUTED_PASS**. Confirms legacy messages lacking `agentRunJSON` render smoothly through fallback path.

### XCUI Tests (`AI_HLYUITests/AgentRuntimeConversationUITests.swift`)
- **Total Tests in Suite**: 13 tests (previously 11).
  1. `testRealChatUISendsPromptShowsToolActivityAndFinalAnswer`
  2. `testProductionCodeSkillLocalPythonNeedsNoUserNudge`
  3. `testStopThenNewMessageHasNoGhostOldRun`
  4. `testUI01UnifiedHistoryPinSearchSwitchDraftPreservation`
  5. `testUI02ClassicUserAndAssistantBubbleWithDirectActionButtons`
  6. `testUI03SearchMessageAndDeduplicatedCitations`
  7. `testUI04CollapsedProgressAndInspectorWithoutRawCoT`
  8. `testUI05RichCodeBlockHTMLCardAndAttachments`
  9. `testUI06ComposerMultilineAttachmentsModelSelectorNoOverlap`: **UPDATED** to unconditional assertions and All Models expansion.
  10. `testUI07StopAndRetryRecoveryWithoutDuplicateBubbles`
  11. `testUI08ConversationalMCPLifecycleAndSecondTurnReuse`
  12. `testUI09DirectToolsCatalogAndSkillsNavigation`: **NEW** unconditional E2E tool navigation test.
  13. `testUI10ModelPickerSearchSelectionAndPersistence`: **NEW** unconditional E2E model search and selection test.
