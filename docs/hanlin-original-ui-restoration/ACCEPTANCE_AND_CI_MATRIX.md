# Acceptance & CI Verification Matrix (`G8`, `G9`)

- **Repository**: `davidpovarsky/hanlin-ai`
- **Branch**: `fix/classic-source-first-agent-acceptance-20261025`
- **Original Baseline SHA**: `478cdd2c23ae2b1a52044cff52ce720830128ea2`
- **Literal Restore Checkpoint SHA**: `83ad2725d5d5eb600dc6613f4264461613eeb10e`
- **Verified Code Commit SHA**: `2c93655336eb79e5bd733d6a0c26811625e23678`
- **Signed Archive / Internal TestFlight CI Run**: [`40575471031`](https://github.com/davidpovarsky/hanlin-ai/actions/runs/40575471031) (`upload-chavrusachat-to-testflight / build-sign-and-upload` job `122440623977` — **SUCCEEDED** in `38m52s`; uploaded build **`84701`**, artifact `ChavrusaChat-signed-ipa-84701` / ID `12769961954`)
- **Full Validation & Simulator E2E CI Run**: [`40581474534`](https://github.com/davidpovarsky/hanlin-ai/actions/runs/40581474534) (`Plan affected validation and tests` `122461706670`, `Validate baseline, contracts, tests, and iOS compilation` `122461843419`, `Launch full app on iPad Simulator` `122461843325`, `Verify provider conformance test summary` `122485964269` — **ALL SUCCEEDED**)

---

## 1. Local Preflight & Regression Suites (Executed on Workstation)

| Suite / Command | Scope | Result | Status |
|---|---|---|---|
| `python -m unittest discover -s Scripts/CI/Tests -p "test_*.py" -v` | CI affected-validation router, cache keys, modular header staging, simulator fixture staging | `147/147` passed (`1` skipped) in `6.63s` | `EXECUTED_PASS` |
| `python -m unittest discover -s Scripts/Runtime/Tests -p "test_*.py" -v` | `ios_system` runner, runtime tooling acceptance parser, dyld closure, shell workflow | `43/43` passed in `0.90s` | `EXECUTED_PASS` |
| `node Scripts/Runtime/validate-runtime-lock.mjs` | `RuntimeDependencies.lock.json` integrity | Validated `RuntimeDependencies.lock.json` | `EXECUTED_PASS` |
| Node regex sanitizer verification (`server-worker.mjs`) | `sanitizeUnicodePropertyRegexes` + `installRegExpUnicodeShim()` on `/[\P{ASCII}]/u`, `/[^\P{ASCII}]/gu`, `/\p{ASCII}/u` | Transformed to valid ASCII hex ranges `[\u0080-\uFFFF]` & `[\x00-\x7F]`; `RegExp` test passed | `EXECUTED_PASS` |

---

## 2. Swift Package, App Unit/Integration, XCUI & TestFlight Suites (Executed in GitHub Actions)

| Target / Suite | Test Selectors | CI Run / Job ID | Result | Status |
|---|---|---|---|---|
| `HanlinChatCoreTests` (`Packages/HanlinPlatform/Tests/HanlinChatCoreTests/HanlinAISDKTests.swift`) | `HanlinAISDKTests` (`16/16` tests including `testNonPositiveMaxStepsClampedToAtLeastOne`, `testSourceAndFileStreamEventMapping`, `testMultimodalUserMessagePartsPreserved`) + full `HanlinChatCoreTests` (`95/95`) | Run `40581474534` / Job `122461843419` | `95/95` passed (`0` failures) | `EXECUTED_PASS` |
| `AI_HLYTests/ClassicChatRestorationTests.swift` | `ClassicChatRestorationTests` (`22/22` tests including `1..15` classic UI & `16..22` for multimodal SDK conversion, `ClassicChatAgentProjection`, Build 84001 defects `7A..7D`) | Run `40581474534` / Job `122461843325` | `22/22` passed (`0` failures) | `EXECUTED_PASS` |
| `AI_HLYTests` (Full App Unit & Integration Suite) | `AgentRuntimeConversationAcceptanceTests`, `RuntimeToolContractTests`, `ProductionProviderConformanceTests` (`77/77`), `MCPToolBridgeTests`, `MasterScenarioSemanticAcceptanceTests`, etc. | Run `40581474534` / Job `122461843325` & Job `122485964269` | `195/195` `AI_HLYTests` + `77/77` `ProductionProviderConformanceTests` passed (`0` failures) | `EXECUTED_PASS` |
| `AI_HLYUITests/AgentRuntimeConversationUITests.swift` | `testUI01`–`testUI08` + `testRealChatUISendsPromptShowsToolActivityAndFinalAnswer` + `testProductionCodeSkillLocalPythonNeedsNoUserNudge` + `testStopThenNewMessageHasNoGhostOldRun` (`11/11` XCUI tests) | Run `40581474534` / Job `122461843325` | `11/11` XCUI tests passed (`0` failures) on iPad Simulator | `EXECUTED_PASS` |
| Signed Archive / IPA & Internal TestFlight Upload | `upload-chavrusachat-to-testflight / build-sign-and-upload` (`testflight.yml`) | Run `40575471031` / Job `122440623977` | Signed IPA `ChavrusaChat-signed-ipa-84701` (`id: 12769961954`) built, signed, uploaded to App Store Connect, and verified in TestFlight | `EXECUTED_PASS` |
| `AI_HLYTests/LiveProviderMatrixConformanceTests.swift` | `LiveProviderMatrixConformanceTests` (`77` parameterized live external commercial provider tests) | Gated by `HANLIN_RUN_LIVE_PROVIDER_TESTS=1` | External commercial API keys are not configured in CI (`77 NOT_RUN`) | `LIVE_PROVIDER_BLOCKED` / `NOT_RUN` |
| Physical iPad Verification | Real iPad hardware check of TestFlight Build `84701` | Build `84701` available in Internal TestFlight | Pending manual check on physical iPad hardware | `DEVICE_PENDING` |
