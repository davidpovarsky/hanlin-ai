# Hanlin Personal Runtime Completion — Requirements Matrix

**Repository:** `davidpovarsky/hanlin-ai`  
**Working branch:** `codex/agent-skills-embedded-results`  
**Master Document:** `Hanlin_FINAL_SDK_First_Full_Implementation_and_Test_Master_Prompt.md`  
**Execution Date:** 2026-10-05  

---

## 1. Master Architectural Directives (MASTER-0 through MASTER-8)

| Directive ID | Scope | Core Requirement | Status |
|---|---|---|---|
| `MASTER-0` | Mission & Strategy | Full execution without stopping after audit. Independent fork policy. SDK-first, one implementation path, thin Hanlin adapters. Preserve chat UI unchanged. | IN PROGRESS |
| `MASTER-1` | Capability Invariants | 35 mandatory capability invariants preserved without regression. Documented in `capability-invariants.json` and `.md`. | ACTIVE |
| `MASTER-2` | Current Architecture Facts | Swift AI SDK agent engine (`HanlinAISDKAgentEngine.swift`) is authoritative; official MCP Swift SDK (0.12.1); NodeMobile 24.5.0; NativeScript 9.1.0; Expo brownfield. | VERIFIED |
| `MASTER-3` | Dependency Research & Baseline | Binding dependency adoption rules. No beta/RC packages; stable compatible closures only. | VERIFIED |
| `MASTER-4` | Chat UI Freeze | Zero chat-UI replacement or migration. Preserve existing `ChatView`, `ChatBubbleView`, `ChatViewBottom`, and all composer/result controls as-is. | FROZEN / ACTIVE |
| `MASTER-5` | Platform Modernization | Migrate to stable Xcode 27 / iOS 27 deployment target. Swift 6.4 / Swift 6 mode. | PLANNED STEP 4 |
| `MASTER-6` | Independent Fork Repository Policy | Update `AGENTS.md` and `PROJECT_AGENT_GUIDANCE.md` to establish independent-fork rules. | COMPLETED |
| `MASTER-7` | 14-Step Execution Sequence & Deletion Discipline | Strict execution sequence (1..14) with before/after parity proofs. | IN EXECUTION |
| `MASTER-8` | Requirements R27-R47 | Additional modern architecture requirements (Swift AI SDK consolidation, MCP, UI freeze, Yams, GRDB eval, LLM.swift eval, Foundation Models, Core AI). | ACTIVE |

---

## 2. Requirements Inventory (R01 through R47)

| Requirement ID | Domain | Key Mandate | Implementation Files | Acceptance Tests |
|---|---|---|---|---|
| `R01` | Full Code & Call Graph Mapping | Map all production sources, candidate gates, tools, schemas, and executors across repo. | `restriction-inventory.json`, `tool-inventory.json` | `AUD-01` .. `AUD-06` |
| `R02` | Skill Import & Package Policy Removal | Fix ZIP import root/wrapper handling, eliminate artificial limits (size/file count/depth/ratio/extensions). Single destination resolution. | `SkillImporter.swift`, `HanlinArchivePolicy.swift` | `ZIP-01` .. `ZIP-22`, `E2E-A` |
| `R03` | Skill Metadata, Markdown & Codec | Unified ISO-8601 & legacy Foundation Date codec. YAML frontmatter parser for multiline/quoted/Unicode without losing data. | `SkillModels.swift`, `SkillStore.swift`, `SkillMarkdownParser.swift` | `META-01` .. `META-16`, `YAML-01` .. `YAML-09` |
| `R04` | Skill Catalog, Resources & Overrides | Fix built-in override precedence; fix `read_skill_resource` path resolution (support `..` in filenames, binary assets). | `HanlinSkillCatalog.swift`, `ReadSkillResourceTool.swift` | `META-11` .. `META-15`, `DISC-06`, `DISC-14` |
| `R05` | Skill-Driven Progressive Discovery | No hardcoded Swift intent classifier. Progressive tool disclosure via `load_skill` / `tool_search`. Remove 4KB schema clamp. | `HanlinAISDKToolAdapter.swift`, `HanlinSkillIndex.swift`, `ToolSearchTool.swift` | `DISC-01` .. `DISC-22`, `E2E-C`, `E2E-G` |
| `R06` | Complete Built-in Skills Pack | Full built-in skills covering all production tools. Self-contained ZIP packages and bulk installer. | `SystemSkillsProvider.swift`, built-in skill bundles | `ZIP-16`, `ZIP-17`, `BUILD-08`, `E2E-A` |
| `R07` | Real Capabilities Enumeration | Expose `list_tools` and `get_runtime_capabilities` to model. Distinguish native/legacy/MCP/Script/MiniApp. | `NativeToolCatalog.swift`, `GetRuntimeCapabilitiesTool.swift`, `ListToolsTool.swift` | `TOOLS-01` .. `TOOLS-04` |
| `R08` | Agent Package Management Tools | Canonical typed package management tool (`manage_runtime_packages`) for Node and Python. | `NodePackageManager.swift`, `PythonPackageManager.swift`, `ManageRuntimePackagesTool.swift` | `PKGT-01` .. `PKGT-12`, `E2E-B`, `E2E-H` |
| `R09` | Accessible Filesystem & Shared cwd | Remove artificial MiniRoot restrictions in personal dev profile. Ensure shared cwd across Python, Node, and shell. | `RuntimeFileLayout.swift`, `HanlinFileService.swift`, `RuntimeBroker.swift` | `FS-01` .. `FS-12`, `E2E-B`, `E2E-H` |
| `R10` | Environment Variables & Overrides | Allow environment variable overrides (`PATH`, `HOME`, `PYTHONPATH`, `NODE_PATH`) with proper scoping and locking. | `RuntimeEnvironment.swift`, `host.mjs`, Python bridge | `ENV-01` .. `ENV-08` |
| `R11` | Real Shell Command Execution | Broaden ios_system command execution to real backend capabilities. Support structured argv and raw command syntax. Remove arbitrary 23-command clamp. | `IOSSystemRunner.swift`, `ExecuteShellCommandTool.swift` | `SH-01` .. `SH-22`, `CMD-01` .. `CMD-23`, `DEP-08` |
| `R12` | JS/TS Source Scanner Removal | Remove `rejectUnsafeSource` word blacklists. Support Node/JSC selection based on capability. Support ESM/CJS and TypeScript compilation. | `host.mjs`, `ExecuteJavaScriptTool.swift`, `ExecuteTypeScriptTool.swift` | `JS-01` .. `JS-11`, `FINAL-02` |
| `R13` | MCP Node Platform Adaptation | Disentangle anti-bypass policy from real platform limits. Support imports of standard Node modules without false bans. | `server-worker.mjs`, `host.mjs`, `NodeRuntimeService+MCP.swift` | `MCP-01` .. `MCP-08` |
| `R14` | npm/MCP Installation Without Veto | Eliminate `rejectUnsupported` guesswork and lifecycle approval ledger for personal profile. Execute lifecycle scripts when supported. | `package-installer.mjs`, `package-compatibility.mjs`, `NodePackageManager.swift` | `PKGT-03`, `PKGT-05`, `E2E-I` |
| `R15` | Real Python Package Installation | Proper wheel and pure-Python sdist extraction. Match ABI/platform tags. Isolate probe from install. | `PythonPackageManager.swift`, `PythonRuntimeService.swift` | `PKGT-04`, `E2E-B`, `E2E-H` |
| `R16` | Network & HTTP Restrictions Removal | Allow HTTP for local/LAN resources. Remove hardcoded hostname allowlists and replace hard size/redirect cutoffs with streaming. | `URLSession+Policy.swift`, `HanlinHostServicesBroker.swift` | `SH-16`, `F03` |
| `R17` | Capabilities & Trust Simplification | Remove Hanlin artificial permission approvals for personal developer mode. Retain real Apple system privacy gates. | `HanlinHostCapabilityAuthority.swift`, `ScriptPermissionAuthority.swift` | `AUD-06`, `DISC-15`, `E2E-D` |
| `R18` | Limits, Streaming & Cancellation | Replace hard maxima (300s, 8MB, 32 steps) with configurable parameters. Support cancellation across all engines. | `RuntimeModels.swift`, `ToolResultStore.swift`, `HanlinAISDKAgentEngine.swift` | `DISC-19`, `DISC-20`, `E2E-F`, `E2E-N` |
| `R19` | Scripting Analyzer & Bundler | Remove regex-based source bans and arbitrary bare-import rejection. Treat analyzer findings as diagnostics. | `HanlinScriptAnalyzer.swift`, `HanlinScriptingBundler.swift` | `SCRIPTARCH-08`, `E2E-E` |
| `R20` | NativeScript & Expo Policy Removal | Remove arbitrary plugin and version whitelists. Support pure-JS plugins and verified native providers. | `HanlinNativeScriptProductionBootstrap.swift`, `HanlinExpoRuntime` | `APPENG-01` .. `APPENG-06`, `E2E-J` |
| `R21` | Personal Data & System Services | Remove arbitrary clamps on Health date ranges, workout queries, reminders, and notification size. | `HanlinScriptingRuntimeServices.swift`, `AppleServiceAdapters.swift` | `E2E-D` |
| `R22` | Data Integrity, Locks & Transactions | Preserve atomic transactions, rollback, mutex locks around cwd/streams, Python GIL, and double-resume prevention. | `AtomicTransaction.swift`, `RuntimeLocks.swift` | `AUD-07`, `ZIP-19`, `PKGT-09` |
| `R23` | Canonical Tool Contracts | Verify complete contract: registration -> catalog -> schema -> validated invocation -> executor -> model/UI payload. | `NativeToolCatalog.swift`, `HanlinAISDKToolAdapter.swift` | Contract tests 1..10 for each tool |
| `R24` | Diagnostic Feedback to Model | Provide specific typed error reasons (unavailable, arg error, OS denial) rather than vague "isolated environment". | `AgentDiagnosticsRecorder.swift`, `ToolError.swift` | `DISC-12`, `TOOLS-04`, `FINAL-09` |
| `R25` | Test & CI Suite Adaptation | Update obsolete tests asserting "must block". Retain real correctness and safety assertions. | `AI_HLYTests`, `Tests/*.test.mjs` | `AUD-04`, `AUD-07`, `FINAL-01` .. `FINAL-05` |
| `R26` | Final Deliverables & Gate Verification | Complete code, schemas, Skills, tests, results, and limitations inventory. Final commit and verification evidence. | Final artifacts and reports | `AUD-08`, `FINAL-01` .. `FINAL-12` |
| `R27` | Remote AI/Provider Loop Consolidation | Consolidate text/tool provider execution on `HanlinAISDKAgentEngine.swift`. Retire legacy APIManager manual tool recursion. | `HanlinAISDKAgentEngine.swift`, `APIManager.swift` | `SDKAI-01` .. `SDKAI-18`, `E2E-G` |
| `R28` | Swift AI SDK Fork Maintenance | Maintain fork patch queue in `docs/dependencies/swift-ai-sdk-patches.md`. Pinned immutable revision. | `Package.swift`, `swift-ai-sdk-patches.md` | `SDKFORK-01` .. `SDKFORK-05` |
| `R29` | Single MCP Protocol Stack | Sole authority is `modelcontextprotocol/swift-sdk`. Remove duplicate JSON-RPC layers while preserving Hanlin embedded Node transport. | `MCPClientSession.swift`, `EmbeddedNodeMCPTransport.swift` | `MCPSDK-01` .. `MCPSDK-08`, `E2E-I` |
| `R30` | Chat UI Freeze | Keep existing Hanlin chat interface completely frozen. No third-party chat UI packages or redesign. | `ChatView.swift`, `ChatBubbleView.swift`, `ChatViewBottom.swift` | `CHAT-01` .. `CHAT-32`, `E2E-K`, `E2E-O` |
| `R31` | Chat State & Callback Contract Preservation | Route consolidated backend events through existing UI state/callbacks without changing presentation semantics. | `ChatView.swift`, `AgentRun.swift`, `NativeUIBlock.swift` | `CHAT-02`, `CHAT-04`, `CHAT-05`, `CHAT-50` .. `CHAT-54` |
| `R32` | Composer & All Controls Preserved | Preserve every composer button, toggle, chip, attachment picker, and input mode in `ChatViewBottom.swift`. | `ChatViewBottom.swift`, `InputTextField.swift` | `CHAT-33` .. `CHAT-49` |
| `R33` | Skill Frontmatter Simplification with Yams | Adopt Yams for standard YAML frontmatter parsing and deterministic serialization. | `SkillMarkdownParser.swift`, `Package.swift` | `YAML-01` .. `YAML-09` |
| `R34` | SQLite / GRDB Evaluation | Evaluate GRDB with a dedicated prototype against `HanlinSQLiteService`. Adopt only if bridge code shrinks without capability loss. | `HanlinSQLiteService.swift`, `grdb-evaluation.md` | `DB-01` .. `DB-07` |
| `R35` | Code Editor Evaluation (Runestone) | Evaluate Runestone for editable code/Skill surfaces outside chat. Chat code rendering stays unchanged. | `CanvasCodeEditor.swift`, evaluation report | `CHAT-07`, `RunestoneEval` |
| `R36` | Runtime Dependency Refresh | Refresh Python Apple support, ios_system, QuickJS-NG, and NodeMobile using reproducible bundle pipeline. | `build-runtime-bundle.yml`, runtime bundles | `DEP-07` .. `DEP-10` |
| `R37` | NativeScript Matched Closure | Keep matched `ios-spm 9.1.0` and `@nativescript/core@9.1.0` closure unless an official matching 9.1.2 closure exists. | `HanlinNativeScriptRuntime` | `APPENG-01` .. `APPENG-04`, `DEP-11` |
| `R38` | Expo Stable Channel Migration | Query Expo stable channel. Use stable SDK (SDK 57 stable patch with scene lifecycle or stable SDK 58 if released; no RC/beta). | `HanlinExpoRuntime` | `APPENG-05`, `APPENG-06`, `DEP-12`, `DEP-13` |
| `R39` | Utility Dependency Updates | Update compatible stable dependencies (ZIPFoundation, SWCompression, SwiftSoup, swift-log). | `Package.swift`, `Packages/*/Package.swift` | `DEP-01` .. `DEP-05` |
| `R40` | Local Model Modernization (LLM.swift) | Evaluate LLM.swift 3.x for GGUF models without creating a second tool loop. Bridge any tool calls to canonical authority. | `LocalLLMProvider.swift`, `LLMManager.swift` | `DEP-06`, `SDKAI-16`, `E2E-P` |
| `R41` | Scripting / HostServices De-customization | Remove unnecessary broker hops and trust layers while preserving multi-engine service sharing. | `HanlinHostServicesBroker.swift`, `HanlinScriptServices` | `SCRIPTARCH-01` .. `SCRIPTARCH-10` |
| `R42` | Dependency Update Automation | Extend automated reporting for SwiftPM and runtime dependencies (report-only). | `check-runtime-dependency-updates.yml` | `DEP-14`, `DEP-15`, `ARCH-10` |
| `R43` | Dead Code & Duplicate Path Removal | Remove obsolete manual request builders/parsers and legacy tool recursion once parity tests are green. Exclude chat UI. | Project codebase | `SDKAI-12`, `SDKAI-13`, `ARCH-03` .. `ARCH-06` |
| `R44` | Final Architecture Documentation | Update documentation to reflect reality: dependency map, runtime map, agent/tool flow, and frozen chat rendering. | `docs/hanlin-platform/` | `ARCH-07` .. `ARCH-10` |
| `R45` | Apple Foundation Models Local Provider | Add iOS 27 `SystemLanguageModel` / `LanguageModel` local provider adapter feeding the same Hanlin conversation and canonical tools. | `AppleFoundationModelsProvider.swift` | `APPLEAI-01` .. `APPLEAI-08`, `E2E-P` |
| `R46` | Apple Core AI (.aimodel) Local Runtime | Add iOS 27 Core AI engine for `.aimodel` on-device models, integrated with Foundation Models session. | `CoreAILanguageModelProvider.swift` | `COREAI-01` .. `COREAI-06`, `E2E-Q` |
| `R47` | Chat/Agent/Runtime Compatibility Contract | Final proof that frozen chat UI renders identically, zero third-party chat UI packages added, and single agent loop is active. | Full system validation | `CHAT-55`, `FINAL-12`, `E2E-O` |

---
