# Project Board

This is a living working-memory document for this repository.
It is intentionally lightweight. Humans and coding agents should update it when useful discoveries, ideas, plans, optimizations, problems, or follow-up work arise during normal development.
Do not turn this into a duplicate issue tracker or a dump of temporary thoughts.

## Inbox

Quick captures that still need classification.

## Ideas & Opportunities

Potential improvements, features, optimizations, or architectural ideas.

## Discoveries & Tips

- **CloudKit Container in CI:** On iOS Simulator running in CI without active iCloud entitlements/credentials, `cloudKitDatabase` must be initialized to `.none` to avoid blocking/deadlock during app/agent startup.
- **Node Worker ESM Resolution:** Node 22 exhibited a known worker loader internal assertion failure (`ERR_INTERNAL_ASSERTION: Unexpected module status 3`) on concurrent ESM worker resolution. Resolved cleanly in Node 24.5 (`@cablate/mcp-google-map` passes capability probing with exit code 0).
- **Simulator Concurrency Gates:** In XCTest suites driving async agent loops, unbounded polling loops can cause test runner timeouts. Use bounded timeouts with exponential backoff.
- **Authoritative Defect Identification:** The 6 test failures discovered in Pass 3 were previously mislabeled against scenario IDs SH-03, SH-05, CMD-04, ZIP-04, ZIP-07, ZIP-11. Their root causes were in `loadDescriptor` title propagation (`SkillStore.swift`), atomic rollback metadata preservation (`SkillStore.swift`), internal symlink policy acceptance (`HanlinArchivePolicy.swift`), dual-mode shell tool schema advertisement (`ExecuteShellCommandTool.swift`), obsolete path policy removal from smoke suite (`ShellRuntimeSmokeSuite.swift`), and raw command pipe execution / symlink reading (`HanlinUnifiedHostServicesAgentAcceptanceTests.swift`). All 6 have been fully fixed and verified.
- **Expo multi-exposure integration gap**: Hanlin's canonical MiniApp architecture already separates runtime family from exposure/entrypoint kind. `HanlinScriptAnalyzer.discoverEntrypoints(...)` already discovers `widget.tsx`, `app_intents.tsx`, `live_activity.tsx`, translation entrypoints, assistant tools, and embedded results and assigns `.hanlinExpo` when the package declares `"hanlinRuntime": "hanlin-expo"`. Two confirmed blockers currently prevent Expo packages from using the generic extension path: (1) `validatePreparedExpoApplication(...)` incorrectly requires `entrypoints.count == 1` and only a foreground `.app`; (2) `HanlinScriptingPlatform.refreshExtensionSnapshot()` filters Widget/App Intent extension entrypoints to `.scriptingJSC` and `.hanlinNativeScript`, excluding `.hanlinExpo`. Fix these seams and reuse the canonical exposure architecture rather than creating an Expo-specific extension system.
- **Modular React Cxx Header Compilation in Swift Frameworks**: When compiling modular frameworks imported into Swift (such as `ExpoModulesCore`), Clang builds underlying C++ modular headers under Objective-C++/C++17 by default unless `-std=c++20` is explicitly enforced across all targets. Any C++20 `concept` declarations (e.g., `RawPropsFilterable` in `RawProps.h`, `DeclaresOwnSetProp`/`HasSetProp`/`HasIteratorSetterCtor` in `Props.h`) must be guarded with `#if defined(__cpp_concepts)`. In addition, `folly::dynamic` stubs used in isolated module contexts must supply range iterators (`begin()`, `end()`), item key checks (`isString()`, `getString()`), and value-casting operators to satisfy `RawValue.h`.

## Experiments / Investigations

Things worth testing or researching before deciding whether to implement them.

## Open Questions

Important unresolved questions or uncertainties.

## Planned / Todo

Concrete work that is worth doing but is not part of the current task.

Use Markdown checkboxes where useful:

- [ ] (Future) Physical Apple hardware device test execution (Layer D) when hardware test bench is provisioned.
- [ ] (Future) Live external cloud model provider end-to-end integration when production credentials are configured.
- [ ] **Complete Expo MiniApp integration with Hanlin's canonical exposure/entrypoint system**
  - **Goal:** A `.hanlinExpo` package must be able to expose the same supported Hanlin surfaces as the other MiniApp runtime families instead of being limited to a single foreground app entrypoint.
  - **Architectural rule:** Do **not** build a separate Expo-specific Widget/App Intent/Live Activity system. Expo must plug into the existing canonical MiniApp entrypoint/exposure architecture and the existing generic extension hosts.

  ### Existing architecture to preserve

  Hanlin already separates runtime family from entrypoint/exposure kind.

  Runtime families include:
  - `scriptingJSC`
  - `hanlinNativeScript`
  - `hanlinExpo`
  - other supported runtime profiles

  Canonical entrypoint/exposure kinds include:
  - `app`
  - `assistantTool`
  - `embeddedResult`
  - `widget`
  - `appIntent`
  - `liveActivity`
  - `translationUI`
  - `spotlight`
  - other reserved/system surfaces

  Relevant existing types/infrastructure include:
  - `HanlinPackageEntrypointKind`
  - `HanlinExposureKind`
  - `HanlinPackageEntrypointDescriptor`
  - `HanlinEntryPointDescriptor`
  - `HanlinStoredPackageSnapshot`
  - `HanlinAppDescriptor`
  - `HanlinScriptExtensionSnapshot`
  - `HanlinScriptWidgetSnapshot`
  - `HanlinScriptIntentEntityRecord`
  - `HanlinScriptTranslationUISnapshot`
  - `HanlinScriptingWidgets.appex`
  - `HanlinScriptExtensionStore`
  - generic Widget/App Intent/Live Activity snapshot contracts
  - generic WidgetKit rendering through `HanlinExtensionNodeView`
  - App Group-backed extension snapshot publication
  - Widget reload through `WidgetCenter`

  Runtime family and exposure kind must remain orthogonal.

  ### Confirmed current behavior

  `HanlinScriptAnalyzer.discoverEntrypoints(...)` already recognizes conventional package entrypoints including:

  ```text
  index.tsx                     -> app
  assistant_tool.tsx            -> assistantTool
  embedded_result.tsx           -> embeddedResult
  widget.tsx                    -> widget
  widget.ts                     -> widget
  widget.json                   -> widget
  app_intents.tsx               -> appIntent
  intent.tsx                    -> appIntent
  intent.json                   -> appIntent
  live_activity.tsx             -> liveActivity
  translation_ui_provider.tsx   -> translationUI
  translation_ui_provider.ts    -> translationUI
  translation.json              -> translationUI
  translation_ui.json           -> translationUI
  ```

  When the package declares `"hanlinRuntime": "hanlin-expo"`, these discovered entrypoints already receive `runtimeProfile = .hanlinExpo`. The generic discovery/model layer therefore already understands an Expo package with multiple exposure entrypoints.

  ### Confirmed blocker 1 — Expo validation incorrectly requires exactly one entrypoint

  File:
  `Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinScriptAnalyzer.swift`

  `validatePreparedExpoApplication(...)` currently requires `entrypoints.count == 1` and the only entrypoint to be `.app`. This contradicts both the canonical MiniApp architecture and the entrypoint discovery logic.

  A package such as:

  ```text
  MyMiniApp.hanlinExpo
  ├── index.tsx
  ├── widget.tsx
  ├── app_intents.tsx
  └── live_activity.tsx
  ```

  is discovered correctly and then rejected because more than one entrypoint exists.

  **Required correction:**
  - require exactly one foreground `.app` entrypoint;
  - allow additional supported entrypoints;
  - preserve their canonical kinds and runtime profiles;
  - validate the prepared Expo `package.json` against the foreground app entrypoint;
  - do **not** require total `entrypoints.count == 1`.

  Conceptually:

  ```swift
  let appEntrypoints = entrypoints.filter { $0.kind == .app }

  guard appEntrypoints.count == 1,
        let appEntrypoint = appEntrypoints.first
  else {
      // invalid Expo package
  }
  ```

  Add analyzer coverage proving:
  - Expo app only -> accepted
  - Expo app + widget -> accepted
  - Expo app + widget + appIntent -> accepted
  - Expo app + multiple supported exposures -> accepted
  - Expo without foreground app -> rejected
  - Expo with more than one foreground app -> rejected if representable

  ### Confirmed blocker 2 — extension snapshot publication filters Expo out

  File:
  `AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift`

  `refreshExtensionSnapshot()` currently filters Widget/App Intent extension entrypoints to:

  ```swift
  ($0.runtimeProfile == .scriptingJSC ||
   $0.runtimeProfile == .hanlinNativeScript)
  ```

  so `.hanlinExpo` entrypoints are ignored even if installed correctly.

  **Required correction:**
  - allow Expo extension entrypoints to participate in the canonical extension path;
  - do not merely add `.hanlinExpo` to the filter and then fall through the JSC implementation;
  - provide an explicit runtime/exposure adapter that produces the existing canonical result types.

  Prefer a structure conceptually equivalent to:

  ```swift
  switch entrypoint.runtimeProfile {
  case .scriptingJSC:
      ...
  case .hanlinNativeScript:
      ...
  case .hanlinExpo:
      ...
  default:
      ...
  }
  ```

  The output must still be canonical:
  - Widget -> `HanlinScriptWidgetSnapshot`
  - App Intent -> `HanlinScriptIntentEntityRecord`
  - Live Activity -> existing canonical Live Activity contract

  Do not introduce parallel Expo-only snapshot contracts unless a genuine platform constraint makes that unavoidable.

  ### Required Expo Widget execution path

  For an Expo package containing `widget.tsx`, Hanlin must evaluate/render the widget entrypoint in a widget-specific Expo context and convert the result into the existing extension-safe declarative representation:

  ```text
  widget.tsx
      ↓
  Expo runtime/exposure adapter
      ↓
  canonical extension-safe UI
      ↓
  HanlinScriptUINode
      ↓
  HanlinScriptWidgetSnapshot
      ↓
  HanlinScriptExtensionStore
      ↓
  HanlinScriptingWidgets.appex
  ```

  The existing generic Widget host remains the renderer.

  Do not:
  - create a WidgetKit target per Expo package;
  - require rebuilding Hanlin whenever a new `.hanlinExpo` package is installed;
  - build an independent Expo Widget registry or persistence layer.

  ### Package format acceptance target

  A single dynamically imported package should be able to contain, for example:

  ```text
  DemoExpoMiniApp.hanlinExpo
  ├── script.json
  ├── package.json
  ├── bundle.js
  ├── index.tsx
  ├── widget.tsx
  ├── app_intents.tsx
  └── live_activity.tsx
  ```

  Verify that all discovered entrypoints survive:

  ```text
  HanlinImportPreview.entrypoints
      ↓
  HanlinInstallPlan.entrypoints
      ↓
  HanlinAtomicScriptStore
      ↓
  HanlinStoredPackageSnapshot.entrypoints
      ↓
  HanlinAppDescriptor.entryPoints
      ↓
  HanlinAppDescriptor.supportedExposures
  ```

  No Expo-specific install path may discard sibling exposure entrypoints.

  ### Widget proof of concept

  Add a real Expo Widget fixture, e.g. `Fixtures/ExpoWidgetProbe/` or equivalent.

  The foreground Expo MiniApp should expose a small demo state, for example:
  - Today's Progress
  - 72%
  - 6 completed
  - 3 remaining
  - Complete Task
  - Refresh Widget

  Its `widget.tsx` should represent the same state in at least:
  - `systemSmall`
  - `systemMedium`

  Prefer exercising all generic families already supported by Hanlin:
  - `systemSmall`
  - `systemMedium`
  - `systemLarge`
  - `systemExtraLarge`

  Exact styling is secondary; the acceptance point is that one imported Expo MiniApp owns both its foreground UI and its Widget exposure.

  ### State sharing and refresh

  Reuse the existing Hanlin MiniApp/platform storage/state abstractions wherever possible.

  The proof must demonstrate:
  1. launch Expo MiniApp;
  2. change demo state;
  3. persist/update state;
  4. regenerate/publish the Widget snapshot;
  5. reload the Widget timeline;
  6. observe the updated state in the Widget.

  Reuse the canonical refresh path around `refreshExtensionSnapshot()` and `WidgetCenter.shared.reloadTimelines(ofKind: "com.hanlin.scripting.widget")`, or factor equivalent generic logic if needed.

  If Expo needs a Host Services operation to request a refresh, that operation must call the canonical platform refresh path rather than publishing an unrelated Expo Widget format.

  ### App Intent / Live Activity / other exposure follow-up

  `app_intents.tsx` and `live_activity.tsx` are already discovered canonically.

  For App Intents:
  - either implement Expo App Intent execution fully in this task;
  - or explicitly record the remaining work instead of claiming full Expo multi-exposure completion;
  - do not silently ignore `.hanlinExpo` App Intent entrypoints.

  For Live Activities:
  - inspect the current implementation state before modifying behavior;
  - preserve the catalog's implemented/generic-hosted/reserved truth;
  - if Expo Live Activity execution remains incomplete, preserve canonical metadata and record a concrete follow-up.

  Also audit Expo `translationUI`, `assistantTool`, and `embeddedResult` entrypoints for discovery, installation, surfacing, and execution. Do not broaden the patch blindly; record remaining runtime-specific gaps accurately.

  ### Runtime adapter design

  Avoid spreading more logic shaped as runtime-specific `if/else` chains through the platform.

  Prefer a reusable seam:

  ```text
  runtimeProfile + entrypointKind
          ↓
  entrypoint executor/renderer
          ↓
  canonical result
  ```

  For Widget-like surfaces, the canonical result should be `HanlinScriptUINode` or the closest existing canonical equivalent. For App Intents, return canonical action/entity registration data.

  This work should reduce runtime-family coupling in extension publication, not increase it.

  ### Required tests

  **Analyzer/import**
  - Expo app-only package succeeds.
  - Expo app + `widget.tsx` succeeds.
  - Expo app + `app_intents.tsx` succeeds if App Intent execution is implemented.
  - multiple Expo exposures survive in `HanlinImportPreview.entrypoints`.
  - all discovered Expo entrypoints retain `.hanlinExpo`.
  - Expo without foreground app fails.
  - duplicate foreground app fails if representable.

  **Install/store**
  - all Expo entrypoints survive preview, install plan, atomic store, restore, stored snapshot, and app descriptor;
  - `supportedExposures` contains `.widget` when `widget.tsx` exists.

  **Extension snapshot**
  - an installed Expo Widget entrypoint creates a real `HanlinScriptWidgetSnapshot`;
  - snapshot identity includes installed package ID, package ID, active generation, and widget entrypoint ID;
  - snapshot survives `HanlinScriptExtensionStore` save/load;
  - widget family selection works.

  **Integration**
  Exercise:
  ```text
  Import
  → Preview
  → Install
  → Launch Expo foreground UI
  → Generate Widget snapshot
  → Generic Widget host visibility
  → Update state
  → Refresh Widget
  ```

  Prefer a real simulator/UI test where supported by current CI.

  ### Regression requirements

  Do not regress:
  - Scripting Widgets
  - NativeScript Widgets
  - generic Widget host
  - App Intent resume queue
  - Translation UI
  - foreground Expo runtime
  - foreground NativeScript runtime
  - ordinary Scripting MiniApps

  Existing `.hanlinExpo` foreground fixtures must continue to pass.

  ### Documentation

  Review/update as appropriate:
  - `docs/hanlin-platform/SCRIPTING_EXTENSIONS.md`
  - `docs/hanlin-platform/SCRIPTING_AUTHORING_GUIDE.md`
  - `docs/hanlin-platform/IMPLEMENTATION_STATUS.md`
  - `PROJECT_BOARD.md`

  Document explicitly that runtime family and exposure surface are orthogonal.

  Do not claim full Expo multi-exposure completion unless each claimed surface has verified end-to-end support.

  ### Definition of Done

  This item may be marked complete only when a real imported `.hanlinExpo` package containing at least **foreground app + widget** successfully:
  1. passes Import Preview;
  2. installs;
  3. retains both canonical entrypoints;
  4. launches the Expo foreground UI;
  5. produces a real `HanlinScriptWidgetSnapshot`;
  6. is visible through the existing generic `HanlinScriptingWidgets` Widget;
  7. reflects updated MiniApp state after refresh;
  8. survives app restart/restore;
  9. passes relevant unit/integration/UI tests;
  10. passes the repository's normal Xcode/CI build gates when verification is explicitly run.

  **Key implementation discovery:** this is not a request to add Widgets to Expo from scratch. The repository is already architected for runtime-independent exposures. The two confirmed breakpoints are the Expo validator's single-entrypoint assumption and the extension publisher's exclusion of `.hanlinExpo`. Fix the integration at those seams and reuse the existing canonical MiniApp exposure architecture.

## Done

- [x] Hanlin Final Closure & Authoritative Evidence Pipeline
  - Implemented: 2026-10-07
  - Commit: Current HEAD
  - Notes: Ingested authoritative 493 MASTER specification (`BF76406CEE...`). Archived Pass 3 results safely. Diagnosed and fixed all 6 real product/test defects in Swift. Truthful Apple local providers (Foundation Models & Core AI) availability and test seams implemented. Complete rewrite of `Scripts/generate_acceptance_results.mjs` with zero synthetic fallback pass, full evidence artifact checksum verification, negative self-tests, and derived requirements matrix (R01–R47). All 44 Node host tests, Cablate MCP installation, and unit tests passing. Chat UI strictly frozen.
- [x] Pass 3 Apple Verification & Final Evidence Completion
  - Implemented: 2026-10-07
  - Commit/Run: `0c0025b` / GitHub Actions run `37587829849`
  - Notes: Executed full downstream app and simulator suites on real macOS 27 / Xcode 27 / iOS Simulator 27 infrastructure. Eliminated all 368 `NOT_RUN_PLATFORM` scenarios (417 PASSED, 6 FAILED, 60 NOT_RUN_DEVICE, 10 BLOCKED_EXTERNAL, 0 NOT_RUN_PLATFORM). Built 116MB unsigned Release IPA (`f6fe11fbaae74702b3c8e63907d58fea6d851481a6f97a9a08e1a489755b3347`). Resolved CabLate MCP-04 with exit code 0. Generated verified acceptance matrix and requirement results (R01–R47).

## Archive

Older completed/superseded items that still have historical value.
