# HANLIN P0 — Agent Tool, Runtime, Skills & Conversational MCP End-to-End Verification

**Date:** 2026-10-26  
**Target Branch:** `fix/classic-source-first-agent-acceptance-20261025`  
**Verified Code SHAs:** `f62290e0c54a81b94166594ea204f6484856cd40` (XCUI Run `40322217987`), `b323eec082b4cfe794b3aeb7641d96502d4924b6` (Unit Run `40316311859`), `2620d01814e74e6602562a3c6b10af9c04f2bc00` (Unit + Runtime Installation UI Run `40307800961`).

---

## 1. Canonical Tool & Skill Map

| Domain | Canonical Tool / Skill Identifiers | Backing Implementation | Session & Permission Scope |
|---|---|---|---|
| **Conversational MCP Lifecycle** | Skill: `mcp_servers`<br>Tool: `manage_mcp_servers` (`status`, `list`, `preview`, `install`, `enable`, `disable`, `select_for_chat`, `deselect_for_chat`, `start`, `stop`, `restart`, `list_tools`, `uninstall`)<br>Dynamic tools: `mcp__<sanitized_server>__<sanitized_tool>` | `ManageMCPServersTool.swift`, `MCPPackageInstaller.swift`, `MCPRuntimeProvider.swift`, `MCPChatConfigManager.swift`, `MCPManager.swift`, `HanlinAISDKToolAdapter.swift` | Session-scoped via `effectiveChatSessionID` (`chatRecord.id ?? sessionScopeID`). Temporary chats clean up via `MCPChatConfigManager.shared.removeSession(chatID:)`. |
| **Embedded Code & Runtimes** | Skill: `code`<br>Tools: `execute_local_python_code`, `execute_javascript_code`, `execute_typescript_code`, `execute_shell_command`, `manage_runtime_packages`, `get_runtime_capabilities`, `create_web_view` | `PythonRuntime`, `NodeRuntime`, `ShellRuntime` (`ios_system`), `NativeScriptRuntime`, `APIManager+LegacyTools.swift` | Sandboxed per-session execution; outputs mapped to `NativeToolResult` + `StreamData(codeBlock:htmlContent:)` for `ChatBubbleView`. |
| **Skill Discovery & Progressive Loading** | Tools: `load_skill`, `list_tools`, `tool_search`, `read_skill_resource`, `execute_skill_resource` | `SystemSkillsProvider.swift`, `ListToolsTool.swift`, `ToolSearchTool.swift`, `HanlinAISDKToolAdapter.swift` | Mid-turn discovery calls (`load_skill`, `list_tools`, `tool_search`, `manage_mcp_servers`) dynamically refresh the active `tools` dictionary in `HanlinAISDKToolAdapter` so newly discovered/installed tools are immediately callable in the next step of the same turn. |
| **Web Search & Page Reading** | Tools: `search_online`, `read_web_page` | `APIManager+LegacyTools.swift`, `AutomaticWebSearch/*`, `CanonicalCitationDeduplicator`, `ChatTurnStateOperations.upsertSearchMessageRow` | Updates classic `role == "search"` `ChatMessages` row in place and deduplicates canonical URLs across `resources` and `AgentEvidenceAccumulator`. |

---

## 2. End-to-End Conversational MCP Lifecycle Verification

### 2.1 Unit & Integration E2E (`AI_HLYTests/ClassicChatRestorationTests/mcpInstallSelectInvokeUninstallE2E`)
- **Executed in:** CI Run `40307800961` & CI Run `40316311859` (`08-downstream-unit-tests.log` — **PASSED**).
- **Verified Steps:**
  1. `status`: Reports all 5 MCP state dimensions (`global_mcp_enabled`, `server_installed`, `server_enabled`, `selected_for_current_chat`, `worker_running`).
  2. `preview`: Inspects deterministic local `.tgz` MCP archive (`makeDeterministicMCPArchive()` containing `package/package.json` and `package/index.mjs` without a pre-existing `mcp-manifest.json`), verifying `MCPPackageInstaller.synthesizeLocalArchiveManifestIfNeeded` synthesizes a valid manifest from `package.json`.
  3. `install`: Installs `hanlin-echo-mcp` from the local `.tgz` archive, auto-enables global MCP (`MCPPreferencesStore.shared.isMCPEnabled = true`), enables the server (`server_enabled = true`), selects it for the active `chatID` (`selected_for_current_chat = true`), starts the embedded Node worker (`worker_running = true`), and refreshes the session MCP catalog (`refreshSessionMCPCatalog`).
  4. `list_tools`: Discovers `echo_ping` (`mcp__hanlin_echo_mcp__echo_ping`) on the running worker.
  5. **Direct Tool Execution:** Invokes `mcp__hanlin_echo_mcp__echo_ping` through `AssistantToolBridge` / `MCPRuntimeProvider.executeTool` with `{"message":"hello-mcp"}` and verifies `"ECHO_PONG_OK:hello-mcp"`.
  6. **Session Isolation:** Verifies a second `otherChatID` does **not** inherit `hanlin-echo-mcp` unless explicitly selected (`MCPChatConfigManager.shared.selectedServerIDs(for: otherChatID)` excludes `hanlin-echo-mcp`), and temporary chat discard (`removeSession(chatID:)`) cleans up session state without affecting persistent chats.
  7. `stop` & `uninstall`: Stops the worker (`worker_running = false`) and uninstalls the package (`server_installed = false`).

### 2.2 Simulator XCUI Two-Turn Conversational MCP E2E (`AI_HLYUITests/AgentRuntimeConversationUITests/testUI08ConversationalMCPLifecycleAndSecondTurnReuse`)
- **Executed in:** CI Run `40322217987` (`08-nativescript-production-ui-tests.log` — **PASSED in 69.32s**).
- **Turn 1 (`PROMPT_UI08_MCP_TURN_1`):**
  - User sends `PROMPT_UI08_MCP_TURN_1` in `ChatView`.
  - Step 1: Model calls `manage_mcp_servers(action: "install", source: "<staged hanlin-echo-mcp.tgz>", select_for_chat: true, auto_start: true)`.
  - `HanlinAISDKToolAdapter` detects `manage_mcp_servers` completion and dynamically refreshes its mid-turn `tools` dictionary from `AssistantToolBridge.prepare`, exposing `mcp__hanlin_echo_mcp__echo_ping` immediately for Step 2.
  - Step 2 (same turn): Model calls `mcp__hanlin_echo_mcp__echo_ping(message: "turn1")`, which executes on the embedded Node MCP worker and returns `ECHO_PONG_OK:turn1`.
  - Step 3: Model outputs `UI08_MCP_TURN_1_COMPLETE: ECHO_PONG_OK:turn1` in `ChatBubbleView`.
- **Turn 2 (`PROMPT_UI08_MCP_TURN_2`):**
  - User sends `PROMPT_UI08_MCP_TURN_2` in the same conversation.
  - Because `effectiveChatSessionID` is stable across turns and `hanlin-echo-mcp` remains selected and running for that chat session, `mcp__hanlin_echo_mcp__echo_ping` is already present in the initial `tools` dictionary for Turn 2.
  - Model directly calls `mcp__hanlin_echo_mcp__echo_ping(message: "turn2")` without calling `manage_mcp_servers` again and renders `UI08_MCP_TURN_2_COMPLETE: ECHO_PONG_OK:turn2` (`Worked for 1s >`).

---

## 3. Embedded Runtimes, Skills, Search, and Lifecycle E2E Results

| Capability | Executed Test Selectors | Result & Evidence |
|---|---|---|
| **Embedded Runtimes Readiness (`Python`, `Node`, `Shell`, `NativeScript`, `MCP`)** | `AI_HLYUITests/HanlinRuntimeInstallationUITests/testRuntimeCenterEmbeddedRuntimesSmokeAndReadiness` | **PASSED (`177.6s`)** in Run `40307800961` |
| **Autonomous `code` Skill + Local Python Execution** | `AI_HLYUITests/AgentRuntimeConversationUITests/testProductionCodeSkillLocalPythonNeedsNoUserNudge`, `AI_HLYTests/SkillStoreAndImportTests` | **PASSED (`272.6s` XCUI in Run `40322217987`; Unit in Run `40316311859`)** — `HANLIN_SKILL_PYTHON_UI_OK:8076113` |
| **Code Block (`CodeBlockRow`) & Interactive HTML (`create_web_view`) Persistence** | `AI_HLYUITests/AgentRuntimeConversationUITests/testUI05RichCodeBlockHTMLCardAndAttachments`, `AI_HLYTests/ClassicChatRestorationTests/toolResultVisibilityAndHistory` | **PASSED (`73.1s` XCUI in Run `40322217987`; Unit in Run `40316311859`)** |
| **Web Search Classic Row (`role == "search"`) & Citation Deduplication** | `AI_HLYUITests/AgentRuntimeConversationUITests/testUI03SearchMessageAndDeduplicatedCitations`, `AI_HLYTests/ClassicChatRestorationTests/webSearchCitationsAndSourcesDeduplicated` | **PASSED (`42.7s` XCUI in Run `40322217987`; Unit in Run `40316311859`)** |
| **Stop/Cancel Concurrency & Error Retry Recovery** | `AI_HLYUITests/AgentRuntimeConversationUITests/testStopThenNewMessageHasNoGhostOldRun`, `testUI07StopAndRetryRecoveryWithoutDuplicateBubbles`, `AI_HLYTests/ClassicChatRestorationTests/lifecycleCancelRetryLateEventsAcrossRuns` | **PASSED (`137.7s` & `39.9s` XCUI in Run `40322217987`; Unit in Run `40316311859`)** |
| **Live External Commercial Provider Matrix (`77` tests)** | `AI_HLYTests/LiveProviderMatrixConformanceTests` | **`NOT_RUN` (`0/77` live, `14/14` deterministic `ProductionProviderConformanceTests` `UNIT_PASS`)** — External paid provider API keys are not configured in CI. |
