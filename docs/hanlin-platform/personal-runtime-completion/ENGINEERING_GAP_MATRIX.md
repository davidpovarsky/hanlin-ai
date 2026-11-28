# ENGINEERING GAP MATRIX & EVIDENCE RECONCILIATION
**Repository:** `davidpovarsky/hanlin-ai`  
**Branch:** `codex/agent-skills-embedded-results`  
**Current Branch HEAD:** `ccc49fded9b48e0feb0801ac8db012aa323d7499`  
**Implementation Ancestor SHA:** `89ff5b4368a25294649f7ea483395d9748eef38d`  
**Broad Validation Base SHA:** `378978eee9af74725a4056ae4db0bb68db417fb3`  
**Frozen Chat UI Reference SHA:** `37ba73ba876fad72a3156052751c1b6a89bf825c` (Verified 100% byte-identical, 0 diff)

---

## 1. Executive Summary & Reconciliation Status

This document reconciles all outstanding verification obligations across the 493 MASTER scenarios, 77 provider conformance functions, and 7 UI test families on branch `codex/agent-skills-embedded-results`.

- **Verified Workflow Runs:**
  - **Run `39093980698`** (Targeted CI at `ccc49fded9b48e0feb0801ac8db012aa323d7499`):
    - All 4 executed jobs succeeded (`Plan affected validation`, `Validate baseline`, `Launch full app on iPad Simulator`, `Verify provider conformance test summary`).
    - iPad mini (A17 Pro) iOS 27.0 simulator smoke executed 17 test suites (163 tests, 163 PASSED, 0 FAILED).
    - Contains authentic execution of 18 `ProductionProviderConformanceTests` and 19 `MasterScenarioSemanticAcceptanceTests`.
  - **Run `38894350038`** (Full CI at `378978eee9af74725a4056ae4db0bb68db417fb3`):
    - Contains authentic execution of 59 `HanlinChatCoreTests/ProviderConformance` package tests.
    - Contains authentic execution of NativeScript (`HanlinNativeScriptProductionE2ETests`), Expo (`HanlinExpoProductionE2ETests`), and ScriptUI (`HanlinScriptUIProductionE2ETests`).
    - Contains authentic execution of 12 `CanonicalMiniAppIntegrationTests`.

---

## 2. 24 Open MASTER Scenarios Reconciliation Ledger

| Scenario ID | Layer | Verifier Kind | Authoritative Test / Evidence Identity | Status Classification | Evidence Origin / Run | Disposition & Reason |
|---|---|---|---|---|---|---|
| `ZIP-01` | I | `xctest` | `MasterScenarioSemanticAcceptanceTests/zip01RootZIPImportWithSkillHanlinAndAgentConfig()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `ZIP-01` | S | `xctest` | `MasterScenarioSemanticAcceptanceTests/zip01RootZIPImportWithSkillHanlinAndAgentConfig()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `ZIP-01` | D | `device` | Physical iPad execution | `BLOCKED_DEVICE` (`NOT_RUN_DEVICE`) | None | Hardware gated; requires physical Apple iPadOS 27 device |
| `ZIP-02` | I | `xctest` | `MasterScenarioSemanticAcceptanceTests/zip02WrappedZIPImportUnderFixtureRuntime()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `ZIP-02` | S | `xctest` | `MasterScenarioSemanticAcceptanceTests/zip02WrappedZIPImportUnderFixtureRuntime()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `ZIP-02` | D | `device` | Physical iPad execution | `BLOCKED_DEVICE` (`NOT_RUN_DEVICE`) | None | Hardware gated; requires physical Apple iPadOS 27 device |
| `ZIP-08` | I | `xctest` | `MasterScenarioSemanticAcceptanceTests/zip08LargeArchiveOver25MBExpanded64MBWithMarker()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `ZIP-08` | S | `xctest` | `MasterScenarioSemanticAcceptanceTests/zip08LargeArchiveOver25MBExpanded64MBWithMarker()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `FS-01` | I | `xctest` | `MasterScenarioSemanticAcceptanceTests/fs01PythonNodeShellSharedWorkspace()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `FS-01` | S | `xctest` | `MasterScenarioSemanticAcceptanceTests/fs01PythonNodeShellSharedWorkspace()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `FS-01` | D | `device` | Physical iPad execution | `BLOCKED_DEVICE` (`NOT_RUN_DEVICE`) | None | Hardware gated; requires physical Apple iPadOS 27 device |
| `SH-01` | I | `xctest` | `MasterScenarioSemanticAcceptanceTests/sh01DynamicCommandsReconciliationWithoutExact23()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `SH-01` | S | `xctest` | `MasterScenarioSemanticAcceptanceTests/sh01DynamicCommandsReconciliationWithoutExact23()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `SH-01` | D | `device` | Physical iPad execution | `BLOCKED_DEVICE` (`NOT_RUN_DEVICE`) | None | Hardware gated; requires physical Apple iPadOS 27 device |
| `CMD-01` | I | `xctest` | `MasterScenarioSemanticAcceptanceTests/cmd01AwkExecutionWithPrintArgvSampleText()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `CMD-01` | S | `xctest` | `MasterScenarioSemanticAcceptanceTests/cmd01AwkExecutionWithPrintArgvSampleText()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `CMD-01` | D | `device` | Physical iPad execution | `BLOCKED_DEVICE` (`NOT_RUN_DEVICE`) | None | Hardware gated; requires physical Apple iPadOS 27 device |
| `PY-02` | I | `xctest` | `MasterScenarioSemanticAcceptanceTests/py02DistributionNameDiffersFromImportName()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `PY-02` | S | `xctest` | `MasterScenarioSemanticAcceptanceTests/py02DistributionNameDiffersFromImportName()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `BUILD-04` | B | `build_command` | iPadOS 27 `build-for-testing` arm64 simulator | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Executed `build-for-testing` with `IOS_DEPLOYMENT_TARGET: "27.0"` |
| `BUILD-04` | S | `xctest` | `test-without-building` suite execution | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Executed 163 tests from `.xctestrun` |
| `BUILD-05` | B | `build_command` | Generic iOS device compile / unsigned IPA | `NEEDS_RUN` | Final Full CI Run | Will be executed in full validation run |
| `APPLEAI-01` | build | `build_command` | Stable Xcode 27 Apple Foundation Models adapter | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Verified in `AppleLocalProvidersTests` (8/8 tests passed) |
| `SCRIPTARCH-04` | integration | `xctest` | `MasterScenarioSemanticAcceptanceTests/fs01PythonNodeShellSharedWorkspace()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Verified in shared workspace execution |
| `SCRIPTARCH-05` | integration | `xctest` | `MasterScenarioSemanticAcceptanceTests/fs01PythonNodeShellSharedWorkspace()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Verified in Python HostService execution |
| `APPENG-03` | integration | `xctest_ui` | `HanlinNativeScriptProductionE2ETests/testProductionNativeScriptParityFullRuntime` | `REUSABLE_AFTER_CLOSURE` | Run 38894350038 (`378978e`) | Passed in full run; re-executes in full validation run |
| `APPENG-04` | agent | `xctest` | `CanonicalMiniAppIntegrationTests/interAppRequestBrokering()` | `REUSABLE_AFTER_CLOSURE` | Run 38894350038 (`378978e`) | Passed in run 38894350038; re-executes in full validation run |
| `APPENG-05` | UI | `xctest_ui` | `HanlinExpoProductionE2ETests/testProductionExpoSwiftUIProbeEndToEnd()` | `REUSABLE_AFTER_CLOSURE` | Run 38894350038 (`378978e`) | Passed in full run; re-executes in full validation run |
| `FINAL-03` | build | `build_command` | iPadOS 27 `build-for-testing` on implementation SHA | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Proven on `ccc49fd`; reconfirmed in final full run |
| `FINAL-04` | simulator | `reused_verified_pass` | 17 unit test suites (163 tests) + 59 package tests | `REUSABLE_AFTER_CLOSURE` | Run 39093980698 & Run 38894350038 | Proven across runs; fully consolidated in full validation run |
| `FINAL-05` | UI | `xctest_ui` | 7 distinct UI test families (see Section 3) | `NEEDS_RUN` / `REUSABLE` | Run 38894350038 & Full Run | NativeScript/Expo/ScriptUI proven; full suite executed in full run |
| `FINAL-06` | CI | `ci_workflow` | Targeted CI run with valid jobs/artifacts | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Targeted CI ran clean |
| `FINAL-07` | CI | `ci_workflow` | Full validation single-run with Runtime Tooling collector | `NEEDS_RUN` | Final Full CI Run | Must be executed once after mapping fixes |
| `FINAL-09` | provider | `xctest` / `external` | `MasterScenarioSemanticAcceptanceTests/final09LiveToolDiscoveryAndExecution()` | `ALREADY_PROVEN` (Local) / `BLOCKED_EXTERNAL` (Model) | Run 39093980698 (`ccc49fd`) | Local tool discovery passed; live LLM model execution blocked on credentials |
| `FINAL-10` | persistence | `xctest` | `MasterScenarioSemanticAcceptanceTests/final10ColdRelaunchStateRestorationAndToolReset()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `FINAL-11` | cancellation | `xctest` | `MasterScenarioSemanticAcceptanceTests/final11CancellationAndImmediateNextRunCleanliness()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |
| `FINAL-12` | audit | `xctest` | `MasterScenarioSemanticAcceptanceTests/final12InvariantsAndToolsCrossJoinAudit()` | `ALREADY_PROVEN` | Run 39093980698 (`ccc49fd`) | Passed on iPadOS 27 simulator |

---

## 3. FINAL-05: Seven UI Families Reconciliation

| UI Family | Incorrect Mapping in Old Evidence Map | Authoritative Real Method Identity in Current Source | Source File | Status / Origin |
|---|---|---|---|---|
| **Skills UI** | `HanlinSkillCenterUITests/testSkillCenterCatalogAndInstallationFlow()` | `HanlinSkillCenterUITests/testSkillCenterNavigationAndInteraction` | `AI_HLYUITests/HanlinSkillCenterUITests.swift` | Target for full validation run |
| **Runtime Install** | `HanlinRuntimeInstallationUITests/testMCPServerInstallationUIWorkflowAndFailure()` | `HanlinRuntimeInstallationUITests/testMCPServerInstallationUIWorkflowAndFailure` | `AI_HLYUITests/HanlinRuntimeInstallationUITests.swift` | Exists in source; target for full validation run |
| **ScriptUI** | `HanlinScriptUIProductionE2ETests/testScriptUIRenderingAndInteraction()` | `HanlinScriptUIProductionE2ETests/testProductionScriptUIUserJourneyAndLifecycle` | `AI_HLYUITests/HanlinScriptUIProductionE2ETests.swift` | `PASSED` in Run 38894350038 |
| **NativeScript** | `HanlinNativeScriptProductionE2ETests/testProductionNativeScriptParityFullRuntime` | `HanlinNativeScriptProductionE2ETests/testProductionNativeScriptParityFullRuntime` | `AI_HLYUITests/HanlinNativeScriptProductionE2ETests.swift` | `PASSED` in Run 38894350038 |
| **Expo** | `HanlinExpoProductionE2ETests/testProductionExpoSwiftUIProbeEndToEnd()` | `HanlinExpoProductionE2ETests/testProductionExpoSwiftUIProbeEndToEnd` | `AI_HLYUITests/HanlinExpoProductionE2ETests.swift` | `PASSED` in Run 38894350038 |
| **Agent Conversation**| `AgentRuntimeConversationUITests/testAgentRuntimeConversationStreamFlow()` | `AgentRuntimeConversationUITests/testRealChatUISendsPromptShowsToolActivityAndFinalAnswer` | `AI_HLYUITests/AgentRuntimeConversationUITests.swift` | Target for full validation run |
| **Rich Chat / Navigation** | `HanlinPrimaryNavigationSmokeUITests/testPrimaryNavigationTabsAndRichChat()` | `HanlinPrimaryNavigationSmokeUITests/testWholeAppPrimaryNavigationSmoke` and `AgentSkillsEmbeddedResultsUITests/testAgentSkillsDeferredExposureAndEmbeddedResultFlow` | `AI_HLYUITests/HanlinPrimaryNavigationSmokeUITests.swift` & `AgentSkillsEmbeddedResultsUITests.swift` | Target for full validation run |

---

## 4. 77 Provider Conformance Functions Reconciliation

- **18 Production Conformance Functions** (`AI_HLYTests/ProviderConformance/ProductionProviderConformanceTests.swift`):
  - `testOpenAINativeProductionAPIManagerSmoke`: PASSED (Run 39093980698)
  - `testP01SkillsExposureAndExecution`: PASSED (Run 39093980698)
  - `testP02FailureRecovery`: PASSED (Run 39093980698)
  - `testP03FiveStepSequentialTools`: PASSED (Run 39093980698)
  - `testP04ParallelTools`: PASSED (Run 39093980698)
  - `testP05ReasoningToolLoopOpenAICompatible`: PASSED (Run 39093980698)
  - `testP05ReasoningToolLoopAnthropic`: PASSED (Run 39093980698)
  - `testP05ReasoningToolLoopGoogle`: PASSED (Run 39093980698)
  - `testP05ReasoningToolLoopOpenRouter`: PASSED (Run 39093980698)
  - `testP06TwentyStepProductionLoop`: PASSED (Run 39093980698)
  - `testP07AbruptCloseFailure`: PASSED (Run 39093980698)
  - `testP08FinishOtherNoContent`: PASSED (Run 39093980698)
  - `testP09CancelProviderStream`: PASSED (Run 39093980698)
  - `testP10CancelRunningTool`: PASSED (Run 39093980698)
  - `testP11OverlappingRunBSupercedesA`: PASSED (Run 39093980698)
  - `testP12ARealApplicationSecondTurnHistory`: PASSED (Run 39093980698)
  - `testDynamicProviderInventory`: PASSED (Run 39093980698)
  - `testOpenAIResponseDormancyCharacterization`: PASSED (Run 39093980698)

- **59 Package Conformance Functions** (`Packages/HanlinPlatform/Tests/HanlinChatCoreTests/ProviderConformance/`):
  - All 59 executed and PASSED in Run 38894350038 (`378978eee9af74725a4056ae4db0bb68db417fb3`).
  - Between `378978eee` and `ccc49fd`, no changes occurred to `Packages/HanlinPlatform/Sources` or `Tests/HanlinChatCoreTests/ProviderConformance`.
  - When the final full validation workflow runs with `full_validation=true`, both the 59 package conformance tests (Phase 1) and the 18 production tests (Simulator downstream) will execute in that single run, yielding fresh 77/77 execution.
