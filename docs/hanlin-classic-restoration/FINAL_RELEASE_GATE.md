# HANLIN P0 — Final Release Gate & Evidence Summary

**Date:** 2026-10-26  
**Repository:** `https://github.com/davidpovarsky/hanlin-ai`  
**Branch:** `fix/classic-source-first-agent-acceptance-20261025`  
**Final Code SHA:** `f62290e0c54a81b94166594ea204f6484856cd40`  
**Historical Classic Baseline SHA:** `478cdd2c23ae2b1a52044cff52ce720830128ea2` (2026-10-08)

---

## 1. Execution Environment & CI Provenance

- **Host OS (GitHub Actions Runner):** `macOS 27.0.1 (Build 26A434)`
- **Xcode / Compiler:** `Xcode 27.2 (Build 27B48)` at `/Applications/Xcode_27.2_Release_Candidate.app/Contents/Developer`
- **Target SDK:** `Simulator - iOS 27.2 (-sdk iphonesimulator27.2)`
- **Target Scheme & Bundle ID:** Scheme `AI_HLY`, App Target `AI_Hanlin` (`com.cherri.hanlin`), Unit Test Target `AI_HLYTests`, UI Test Target `AI_HLYUITests`
- **Simulator Device:** `iPad mini (A17 Pro)` (`UDID: D964FD22-3755-4972-8B2A-EE51929C1018`, `iOS 27.0 / Build 24A434`, `arm64`)
- **Authenticated GitHub Actions Runs:**
  1. **[Run `40322217987`](https://github.com/davidpovarsky/hanlin-ai/actions/runs/40322217987)** (Commit `f62290e0c54a81b94166594ea204f6484856cd40`, Job ID `121569859852`):
     - Command: `xcodebuild test-without-building -project AI_HLY.xcodeproj -scheme AI_HLY -destination "platform=iOS Simulator,id=D964FD22-3755-4972-8B2A-EE51929C1018" -only-testing:AI_HLYUITests/AgentRuntimeConversationUITests`
     - Result: **`11/11` `AgentRuntimeConversationUITests` PASSED (`0` failures)** in `1018.25s`.
     - Artifact: `AI_Hanlin-iOS26-simulator-smoke-logs` (`NativeScriptProductionE2EResult.xcresult` with 8 PNG screenshots for `UI-01..UI-08`).
  2. **[Run `40316311859`](https://github.com/davidpovarsky/hanlin-ai/actions/runs/40316311859)** (Commit `b323eec082b4cfe794b3aeb7641d96502d4924b6`, Job ID `121549767110`):
     - Command: `xcodebuild test-without-building -project AI_HLY.xcodeproj -scheme AI_HLY -destination "platform=iOS Simulator,id=..." -only-testing:AI_HLYTests`
     - Result: **`176/176` unit tests in `AI_HLYTests` PASSED (`0` failures)** in `38.83s` (including **`15/15` `ClassicChatRestorationTests`**, **`14/14` `ProductionProviderConformanceTests`**, and **`62/62` Swift Testing tests**).
  3. **[Run `40307800961`](https://github.com/davidpovarsky/hanlin-ai/actions/runs/40307800961)** (Commit `2620d01814e74e6602562a3c6b10af9c04f2bc00`, Job ID `121520102022`):
     - Result: **`176/176` unit tests in `AI_HLYTests` PASSED (`0` failures)** in `34.4s` + **`1/1` `HanlinRuntimeInstallationUITests/testRuntimeCenterEmbeddedRuntimesSmokeAndReadiness` PASSED** in `177.6s`.
  4. **Local Preflight Validation (`f62290e0c54a81b94166594ea204f6484856cd40`):**
     - `python -m unittest discover -s Scripts/CI/Tests -p "test_*.py" -q`: **`147/147` PASSED**.
     - `node Scripts/Runtime/validate-runtime-localization.mjs`: **`190/190` RuntimeL10n keys** validated for `en`, `he`, `zh-Hans`.
     - `node Scripts/Runtime/validate-runtime-lock.mjs` & `node Scripts/Runtime/validate-ios-system-package.mjs`: **PASSED**.

---

## 2. Exit Gate Evaluation (`G0` .. `G8`)

| Gate | Requirement | Status | Evidence & Notes |
|---|---|---|---|
| **G0 — Git Integrity** | Known HEAD, no destructive reset, latest changes preserved, reviewable pushed commits on `fix/classic-source-first-agent-acceptance-20261025`. | **`PASS`** | Branch `fix/classic-source-first-agent-acceptance-20261025` at `f62290e0c54a81b94166594ea204f6484856cd40`, cleanly fast-forwarded from `6fc8743efac37cc324460cfe0ddb40dd900fb57a`. |
| **G1 — Source Authority** | All relevant historic chat symbols compared against `478cdd2c23ae2b1a52044cff52ce720830128ea2`, classic behavior primary, modern additions subordinate, deviations recorded. | **`PASS`** | Documented symbol-by-symbol in `docs/hanlin-classic-restoration/SOURCE_FIRST_DECISION_LEDGER.md`; verified by `ClassicChatRestorationTests` (`15/15 PASS`). |
| **G2 — UI Acceptance** | Classic actions, history, user+assistant bubbles, RTL/localization, and composer pass real XCUI and visual inspection with screenshots. | **`PASS` (Simulator) / `DEVICE_PENDING` (Physical iPad)** | `11/11` `AgentRuntimeConversationUITests` (`UI-01..UI-08` + 3 runtime/lifecycle E2E tests) passed in Run `40322217987` with 8 verified PNG screenshots in `NativeScriptProductionE2EResult.xcresult`. |
| **G3 — Search / Results** | Original `role == "search"` rows, citations, rich results (`CodeBlockRow`, `htmlWebBubble`), persistence, and canonical URL deduplication pass actual execution. | **`PASS`** | `ClassicChatRestorationTests/webSearchCitationsAndSourcesDeduplicated`, `toolResultVisibilityAndHistory` (`UNIT_PASS` in Run `40316311859`) + `testUI03SearchMessageAndDeduplicatedCitations`, `testUI05RichCodeBlockHTMLCardAndAttachments` (`SIMULATOR_XCUI_PASS` in Run `40322217987`). |
| **G4 — MCP / Skills / Runtime** | Same-chat MCP lifecycle (`status`, `preview`, `install`, `select_for_chat`, `start`, `list_tools`, `mcp__hanlin_echo_mcp__echo_ping`, `stop`, `uninstall`), 2-turn reuse, `code` skill Python execution, and embedded runtimes pass. | **`PASS`** | `ClassicChatRestorationTests/mcpInstallSelectInvokeUninstallE2E` (`UNIT_PASS` in Run `40316311859`), `testUI08ConversationalMCPLifecycleAndSecondTurnReuse` & `testProductionCodeSkillLocalPythonNeedsNoUserNudge` (`SIMULATOR_XCUI_PASS` in Run `40322217987`), `HanlinRuntimeInstallationUITests` (`SIMULATOR_XCUI_PASS` in Run `40307800961`). |
| **G5 — Providers & Images** | Correct routing (`resolveModelExecutionRoute`), capability preservation across probe failures (`mergeRefreshedModelCapabilities`), deterministic provider contract tests (`14/14 PASS`), and explicit status for live external provider matrix (`77 NOT_RUN`). | **`BLOCKED` (Live External Provider API Keys Not Configured in CI)** | Deterministic `ProductionProviderConformanceTests` (`14/14 PASS`) and `modelRoutingAcrossPersistentProbeRefresh` (`1/1 PASS`) passed in Run `40316311859`. The `77` live external network tests in `LiveProviderMatrixConformanceTests` are `NOT_RUN` because external commercial API keys are not configured in CI. |
| **G6 — Lifecycle** | Stop/cancel/retry and late-event concurrency stable under repeatable unit and XCUI tests; zero `LateMutationAttemptedAfterTerminal` or duplicate bubbles. | **`PASS`** | `ClassicChatRestorationTests/retryReplacesFailedAssistantGroupWithoutDuplicateBubbles` & `lifecycleCancelRetryLateEventsAcrossRuns` (`UNIT_PASS` in Run `40316311859`) + `testStopThenNewMessageHasNoGhostOldRun` & `testUI07StopAndRetryRecoveryWithoutDuplicateBubbles` (`SIMULATOR_XCUI_PASS` in Run `40322217987`). |
| **G7 — Real CI Gates** | Executed relevant unit and XCUI suites in GitHub Actions with exact Xcode/SDK/artifact/SHA provenance and zero fabricated pass claims. | **`PASS`** | Runs `40307800961`, `40316311859`, and `40322217987` executed and verified with downloaded `.xcresult` and `.log` artifacts. |
| **G8 — Device / Ship Decision** | Physical iPad screenshots and hardware acceptance when available, otherwise `DEVICE_PENDING`; unsigned/signed release IPA built only when gates/authorization permit. | **`DEVICE_PENDING`** | No physical iPad connected during this session (`DEVICE_PENDING`), and `simulator_e2e_only=true` was used for test iteration so no release IPA artifact was published for `f62290e0c54a81b94166594ea204f6484856cd40` (`ARTIFACT: NONE`). |

---

## 3. Explicit Gate Conclusion

- **All deterministic code repairs, unit tests (`176/176 PASS`), local CI/runtime preflight checks (`147/147 PASS`, `190/190` l10n keys), and iPad Simulator XCUI tests (`11/11` `AgentRuntimeConversationUITests` + `1/1` `HanlinRuntimeInstallationUITests` `PASS`) are complete and verified.**
- Per Section 9 & Section 10 of the P0 order, because physical iPad hardware verification (`G8: DEVICE_PENDING`) and live external commercial API provider conformance (`G5: 77 NOT_RUN` without external API keys) remain external environment blockers, the overall release gate remains **`BLOCKED` (`NOT_ACCEPTED` for final physical-device/release sign-off)** until physical iPad verification and authorized live provider runs are executed.
