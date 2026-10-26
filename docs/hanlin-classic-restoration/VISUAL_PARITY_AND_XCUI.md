# HANLIN P0 — Visual Parity & Simulator XCUI Evidence

**Date:** 2026-10-26  
**Historical Classic Baseline Commit:** `478cdd2c23ae2b1a52044cff52ce720830128ea2` (2026-10-08)  
**Verified XCUI Commit SHA:** `f62290e0c54a81b94166594ea204f6484856cd40`  
**GitHub Actions Run:** [Run `40322217987`](https://github.com/davidpovarsky/hanlin-ai/actions/runs/40322217987) (`Launch full app on iPad Simulator`, Job ID `121569859852`)  
**Execution Environment:** `macOS 27.0.1 (26A434)`, `Xcode 27.2 (Build 27B48)`, `Simulator - iOS 27.2 (-sdk iphonesimulator27.2)`, Device: `iPad mini (A17 Pro)` (`D964FD22-3755-4972-8B2A-EE51929C1018`, `iOS 27.0 / 24A434`).  
**Artifact Bundle:** `AI_Hanlin-iOS26-simulator-smoke-logs` -> `simulator-logs/NativeScriptProductionE2EResult.xcresult`

---

## 1. Executed XCUI Suite Summary (`11/11 Passed` in `AgentRuntimeConversationUITests` + `1/1 Passed` in `HanlinRuntimeInstallationUITests`)

| Selector | Duration | Result | Attached Screenshot ID in `NativeScriptProductionE2EResult.xcresult/Data` | Screenshot Size (Bytes) | Screenshot SHA-256 |
|---|---:|---|---|---:|---|
| `AgentRuntimeConversationUITests/testProductionCodeSkillLocalPythonNeedsNoUserNudge` | `272.61s` | `SIMULATOR_XCUI_PASS` | Automatic XCTest failure-only policy (0 failures) | — | — |
| `AgentRuntimeConversationUITests/testRealChatUISendsPromptShowsToolActivityAndFinalAnswer` | `178.40s` | `SIMULATOR_XCUI_PASS` | Automatic XCTest failure-only policy (0 failures) | — | — |
| `AgentRuntimeConversationUITests/testStopThenNewMessageHasNoGhostOldRun` | `137.70s` | `SIMULATOR_XCUI_PASS` | Automatic XCTest failure-only policy (0 failures) | — | — |
| `AgentRuntimeConversationUITests/testUI01UnifiedHistoryPinSearchSwitchDraftPreservation` | `47.76s` | `SIMULATOR_XCUI_PASS` | `data.0~8H3goEBVO1QFosJ3aqGSkr-QzfCP4dJCMSJtkQJs6yckdZXO1-zo83K1un-3BjPP40HPWQPCvERh38-5dpvcQQ==` | `267,670` | `DFAD79D805D112368DFF116749A7F23008B655A893FE2C77597C4D778EE6BC42` |
| `AgentRuntimeConversationUITests/testUI02ClassicUserAndAssistantBubbleWithDirectActionButtons` | `45.69s` | `SIMULATOR_XCUI_PASS` | `data.0~0U_90-kF0wevMliRxWBVb3Wmu-OE3U2BTcVJFCD4rqkpm9r5I28w1x1ZmUxZzz5HiaPH6eF-yu27hax6w68jKg==` | `285,236` | `824DF9DF676C8F79EB6CFDD676618FAC7E3088858EE50871DDD80EFC31AB1127` |
| `AgentRuntimeConversationUITests/testUI03SearchMessageAndDeduplicatedCitations` | `42.66s` | `SIMULATOR_XCUI_PASS` | `data.0~6gTOwvqvpPOvjCkfsUmaWVHVFlfGII6n7K2v_mVSjNnlicfs3SrTK2b_D4Y-e6i0f0PhvZweNdwmU57dA3cQrw==` | `315,623` | `674E058DC0EA027684CFD839FED53040AA552B4C4969275DC25ED378C4B4874A` |
| `AgentRuntimeConversationUITests/testUI04CollapsedProgressAndInspectorWithoutRawCoT` | `51.60s` | `SIMULATOR_XCUI_PASS` | `data.0~vryOCg2OuVdvl04_9ztXhixyea_erqLsEHXmUCxdCk6Kil0O-LraLksBhjnsnNkDnakhiG9ma-hRwCMIDQ5Zmw==` | `375,050` | `6FFA053073E9985CD52F4758B8381CECDC2B8E574E11BB015955B6F51A2107B2` |
| `AgentRuntimeConversationUITests/testUI05RichCodeBlockHTMLCardAndAttachments` | `73.10s` | `SIMULATOR_XCUI_PASS` | `data.0~Vrqd2eZJ2jfMWF4CzvDuA7nznulydUBumduEJTHnbuQwgMq731wep0T2M3F-tx8lZ1XcaHZkGH5FZIp1W9npAQ==` | `437,764` | `DF7387510AB7C87056F0601648C798E7E02D8C55DC03D7D307AA1A51011F2635` |
| `AgentRuntimeConversationUITests/testUI06ComposerMultilineAttachmentsModelSelectorNoOverlap` | `59.54s` | `SIMULATOR_XCUI_PASS` | `data.0~hiRS0cxCI_u8XnBLCzbkD9ClDf-rQW2QJTQpvJ0ekcH-lhrcoLaL3_AzWtS87oFKimnPN8rzqj8K2gDLeBoguw==` | `319,058` | `A6306B1614D203F8BF50458B0D76A6A55D7E961397227DD39BD1F16F12A87FC5` |
| `AgentRuntimeConversationUITests/testUI07StopAndRetryRecoveryWithoutDuplicateBubbles` | `39.87s` | `SIMULATOR_XCUI_PASS` | `data.0~hCN9hX_hlKGA2omNI8m4REbc3Y_zsw3N6dgU1Gy3i7Hi-sG-2BM8EieGrmjYPQevUiFeEniXoLTAlY1dnKZSoA==` | `262,161` | `5DBB86DAAD8464F695D5CD7E5354EEE933DF3C9872F500905BE90FDFD34836A1` |
| `AgentRuntimeConversationUITests/testUI08ConversationalMCPLifecycleAndSecondTurnReuse` | `69.32s` | `SIMULATOR_XCUI_PASS` | `data.0~VSjAXgi_aKxpaBeSQqZt3wyVn58ObhvYskK1Z7qea9yRi8NzxBFbkNURviaE4voKW2ExDOg8TtmqZu_3DUHoGg==` | `330,822` | `D80B0C72E9BA1CB5780FC92B4F80E5AC2AB3E29ACA9EC79633954679570ECFC3` |
| `HanlinRuntimeInstallationUITests/testRuntimeCenterEmbeddedRuntimesSmokeAndReadiness` (Run `40307800961`) | `177.59s` | `SIMULATOR_XCUI_PASS` | Verified in Run `40307800961` (`2620d01814e74e6602562a3c6b10af9c04f2bc00`) | — | — |

---

## 2. Visual Inspection Findings Across Captured Simulator Screenshots (`UI-01` .. `UI-08`)

1. **`UI-01` (`UI-01_UnifiedHistoryPinSearchSwitchDraftPreservation`):**
   - Left Split-View column displays the unified `对话` section with `New Group Chat` (`Welcome to the new group chat! 👏`) and `Agent Acceptance Chat` (`[草稿] Draft preserved across switch` with `[草稿]` highlighted in `Color.hlRed`).
   - Right detail pane shows `Draft preserved across switch` restored inside the multiline composer, with external accessory pills (`Agent Acceptance`, `Tools`, `继续生成`) positioned cleanly above the glass input capsule.
2. **`UI-02` (`UI-02_ClassicUserAndAssistantBubbleWithDirectActionButtons`):**
   - User prompt (`PROMPT_UI02_CLASSIC_BUBBLES`) renders inside the classic `Color.hlBlue` bubble with `CustomCorners(topLeft: 20, topRight: 20, bottomLeft: 20, bottomRight: 5)`.
   - Assistant response renders markdown heading (`Classic Bubble Heading`), bold text, and inline math (`$E=mc^2$`), followed by all 7 directly visible classic action buttons (`Copy`, `Select Text`, `TTS`, `Translate`, `Math`, `Knowledge Bag`, `Retry`) in a single horizontal bar without hiding actions inside an overflow menu.
3. **`UI-03` (`UI-03_SearchMessageAndDeduplicatedCitations`):**
   - Classic `role == "search"` card (`Information Content` with book icon) renders directly above the assistant turn (`Agent Acceptance`), followed by `Worked for 5s >`, assistant answer, `Tool Message (read_web_page)`, and `Reference 1` (confirming 3 duplicate URL variants collapsed into 1 canonical source).
4. **`UI-04` (`UI-04_CollapsedProgressAndInspectorWithoutRawCoT`):**
   - Both the inline expanded activity block (`Worked for 6s v` -> `Using a tool` -> `Running local Python`) and the modal `Thinking` inspector sheet display structured tool execution (`source: print(6 * 7)` -> `42`, `Completed`) with **zero raw chain-of-thought (`Thinking Process:`)** exposed.
5. **`UI-05` (`UI-05_RichCodeBlockHTMLCardAndAttachments`):**
   - User turn displays image attachment (`hanlin-user-image-attachment`), document attachment card (`AcceptanceSample TXT`), and user bubble (`PROMPT_UI05_RICH_CONTENT`).
   - Assistant turn displays classic `BlurView` `CodeBlockRow` (`Program Results`, `Source Code` pill button, `Code output: 42`) and interactive `WebView` HTML preview card (`hanlin-html-web-bubble`) with `</>` and fullscreen buttons.
6. **`UI-06` (`UI-06_ComposerMultilineAttachmentsModelSelectorNoOverlap`):**
   - Composer expands cleanly for 3 lines of text (`Line 1..3 of multiline composer test`) above the on-screen keyboard, with `+`, `mic`, and `send` button aligned at the bottom of the capsule, external accessory pills (`Tools`, `继续生成`) above the capsule, and the open model selector popover (`选择与添加模型...`, `✓ Agent Acceptance`) floating cleanly without clipping or overlapping text input.
7. **`UI-07` (`UI-07_StopAndRetryRecoveryWithoutDuplicateBubbles`):**
   - Shows `PROMPT_UI07_FAIL_ONCE` user bubble and a single recovered assistant bubble (`UI07_RETRY_RECOVERY_COMPLETE`) after tapping `hanlin-error-retry-button`. The failed error bubble is completely removed and neither the user bubble nor the assistant bubble is duplicated.
8. **`UI-08` (`UI-08_ConversationalMCPLifecycleAndSecondTurnReuse`):**
   - Shows both Turn 1 (`PROMPT_UI08_MCP_TURN_1` -> `Worked for 22s >` -> `UI08_MCP_TURN_1_COMPLETE: ECHO_PONG_OK:turn1` + `Tool Message mcp__hanlin_echo_mcp__echo_ping`) and Turn 2 (`PROMPT_UI08_MCP_TURN_2` -> `Worked for 1s >` -> `UI08_MCP_TURN_2_COMPLETE: ECHO_PONG_OK:turn2` + `Tool Message mcp__hanlin_echo_mcp__echo_ping`) in the same conversation.

---

## 3. Documented Exceptions & Visual Limits

- **Approved Composer Exception (Section 2.4):** The bottom input area uses the approved native multiline Liquid Glass capsule (`ChatViewBottom.swift`) with an external accessory bar (`hanlin-model-selector` + `hanlin-active-capabilities-pill`) instead of the legacy 2-row `478cdd2c` composer.
- **Subordinate Agent Activity Summary:** When an agent turn executes tools or reasoning, a compact single-line `Worked for Xs >` summary (`AgentActivitySummaryView`) appears above the assistant markdown body inside `ChatBubbleView`.
- **Physical Device Visual & Hardware Limits (`DEVICE_PENDING`):** All 8 screenshots were captured on `iPad mini (A17 Pro)` Simulator (`iOS 27.0`). Physical iPad Pro/Air/mini optical display inspection, live camera feed, and hardware keyboard attachment remain `DEVICE_PENDING`.
