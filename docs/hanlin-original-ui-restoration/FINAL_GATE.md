# Final Gate Assessment (`G0`–`G9`)

- **Repository**: `davidpovarsky/hanlin-ai`
- **Branch**: `fix/classic-source-first-agent-acceptance-20261025`
- **Original Baseline SHA**: `478cdd2c23ae2b1a52044cff52ce720830128ea2`
- **Step 1 Literal Restore Checkpoint SHA**: `83ad2725d5d5eb600dc6613f4264461613eeb10e`

---

## Gate Summary Table

| Gate | Requirement | Status | Evidence |
|---|---|---|---|
| **G0 — Repo Integrity** | Exact branch `fix/classic-source-first-agent-acceptance-20261025` in isolated worktree `C:\Users\DAVID\Code\hanlin-classic-source-first-20261027`; no interference with `hanlin-agent-skills-embedded-results`, no merge to `main`, no Asana edits. | **PASS** | Verified via `git worktree list` and `git status`. |
| **G1 — Literal Source Restored** | Five original files restored byte-for-byte from `478cdd2c23ae2b1a52044cff52ce720830128ea2` in Step 1 (`83ad2725d5d5eb600dc6613f4264461613eeb10e`), followed by minimal documented adaptations in Step 2; 9 competing modern chat files deleted (`git rm`). | **PASS** | `docs/hanlin-original-ui-restoration/BASELINE_BLOBS_AND_SYMBOLS.md` & `ORIGINAL_SOURCE_DIFF_LEDGER.md`. |
| **G2 — Original Visual UI** | `ChatBubbleView` in `ChatViewComponents.swift` is sole ordinary-chat renderer; original blue `ChatViewBottom.swift` shell (`GlassView`, `.hlBlue` shadow, `ActionButtonsView`, `modelSelector`, `sourceSelector`) restored. | **PASS (Code & Simulator) / DEVICE_PENDING (Physical iPad)** | Zero remaining references to `ModernChat*`, `ChatBottomBarContainer`, or `ChatResultCards`. |
| **G3 — Functionality Preservation** | Original 7+ bubble actions, attachments, search capsule, citations, Canvas, maps, knowledge cards, iPad `NavigationSplitView`, and `NativeMultilineTextEditor` inside `inputFieldSection` preserved. | **PASS** | `docs/hanlin-original-ui-restoration/CLASSIC_COMPONENT_RESULT_MAP.md`. |
| **G4 — SDK Single Agent Loop** | Remote tool-capable requests execute exclusively via `APIManager.processSDKAgentEngine` (`SwiftAISDK.streamText`); dual-loop fallback to `processRemoteStream(..., useTools: true)` eliminated; `maxSteps` guarded with `max(maxSteps ?? 40, 1)`; `agentEngineKind` recorded. | **PASS** | `docs/hanlin-original-ui-restoration/SDK_TOOL_LOOP_PARITY.md`. |
| **G5 — Typed Messages & Events** | `APIManager.convertFormattedMessagesToSDKMessages` preserves base64 `.imageData`, remote `.imageURL`, text, document text, and `system`/`developer` roles; `.source`, `.file`, `.toolApprovalRequest`, and `.toolOutputDenied` handled end-to-end. | **PASS** | `HanlinAISDKTests` (`14..16`) & `ClassicChatRestorationTests` (`16..17`). |
| **G6 — Tools / Skills / MCP** | `web_research` Skill ID vs `search_online` tool disambiguation; `ManageMCPServersTool` action/parameter aliases, incompatible package guard, nested `isError: true` propagation, mid-turn MCP tool catalog refresh, and `server-worker.mjs` `\P{ASCII}` regex sanitizer. | **PASS** | `ClassicChatRestorationTests` (`18..21`) & `docs/hanlin-original-ui-restoration/PRODUCTION_LOG_DEFECT_REGISTER.md`. |
| **G7 — Diagnostics & Efficiency** | Raw `<think>` / CoT sanitized in `reasoningView()`; `AssistantToolExposurePlanner.defaultSchemaByteBudget = 24_000` and `HanlinAISDKToolAdapter.maxActiveStepSchemaBytes = 28_000`; `AgentRunLifecycleCoordinator` prevents ghost runs on Stop/Retry. | **PASS** | `ClassicChatRestorationTests` (`11`, `15`, `22`). |
| **G8 — Real Tests & CI** | Local CI/runtime test suites (`147/147` + `43/43` PASS) + macOS CI execution of `HanlinAISDKTests`, `ClassicChatRestorationTests`, `AgentRuntimeConversationAcceptanceTests`, and `AgentRuntimeConversationUITests`. | **IN_PROGRESS / CI_VERIFICATION** | Tracked in `ACCEPTANCE_AND_CI_MATRIX.md`. |
| **G9 — Device / Release** | Live commercial provider matrix (`77` tests gated by `HANLIN_RUN_LIVE_PROVIDER_TESTS=1`) and physical iPad verification. | **BLOCKED (`LIVE_PROVIDER_BLOCKED` & `DEVICE_PENDING`)** | External commercial provider API keys are not configured in CI (`77 NOT_RUN`), and physical iPad verification remains `DEVICE_PENDING`. |
