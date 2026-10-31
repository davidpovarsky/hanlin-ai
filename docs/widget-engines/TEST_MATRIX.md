# Pass 3 acceptance ledger — 2026-10-30

No Pass-2 CLOSED/AnyView/ZIP-existence assertion is accepted as native execution evidence. Each row uses its own matching assertions. Package evidence: 41239674500 at 5bfcf03b; iOS source-only evidence: 41239669157 at the same SHA. Full iOS results: 41239679485 pending. These runs use Xcode 27.1 / Swift 6.4; package assertions execute on arm64 macOS, native SDK checks target arm64 iOS 27 Simulator. Current raw run links and platform scope are in CI_AND_DEVICE_RESULTS.md.

| Gate | Obligation | Status |
|---|---|---|
| G01 | Inventory/preservation | EXECUTED_PASS: preserved backup/inventory; four frozen paths unchanged from ce586667 |
| G02 | Original Expo AnyChild | PARTIAL: original AnyChild subset AND bridge SDK compile/link PASS (41239669157); native iOS semantics/OS pending |
| G03 | Original ScriptWidget native builders | PARTIAL: original JSExport/native builders compile and 29-tag/10-chart macOS raster assertions PASS (41239674500) |
| G04 | JSX compiler/resources | EXECUTED_PASS for install-time JSX/resources: 7 JS tests, real 7 archive analyses/5 installs; OS separate |
| G05 | Explicit import/engine metadata | EXECUTED_PASS for real analyzer/install/verified preparation; host UI acceptance pending |
| G06 | Complete native component parity | PARTIAL: original 29-tag distinct-output/10-chart data tests; full props/RTL/Dynamic Type/OS parity NOT_TESTED |
| G07 | Prepared presentation/JSC isolation | PARTIAL: frozen preparation/source actions/cold timeline storage PASS; actual provider UI pending |
| G08 | Three engines concurrently | NOT_RUN_SIMULATOR_UI / BLOCKED_DEVICE |
| G09 | New post-build package install | NOT_RUN_SIMULATOR_UI: actual post-build fixture import test pending; shared importer PASS |
| G10 | Picker/families | PARTIAL: exact identity/wrong-family/unconfigured tests PASS; actual picker/family UI pending |
| G11 | Configured independent variants | PARTIAL: real public create-instance registry/isolation/refresh tests PASS; A1/A2 picker UI pending |
| G12 | Actual native AppIntent press | NOT_RUN_SIMULATOR_UI: source callbacks/Bool SetValue integration PASS; actual native press pending |
| G13 | OS widget lifecycle | BLOCKED_DEVICE: signed lock/reboot/OS lifecycle absent |
| G14 | State, checksum, v1 rollback | PARTIAL: actual old encoder/reader, crash/journal/checksum/state tests PASS; signed binary downgrade pending |
| G15 | Malformed/negative cases | PARTIAL: invalid/mixed archives, artifact attacks, stale/disabled/uninstalled/family negatives PASS; native error UI pending |
| G16 | Measured performance/memory | NOT_RUN: no device memory/latency claim; sampled simulator RSS probe added, not yet run |
| G17 | No Hanlin grant gate | PARTIAL: source inspection and real shared installation PASS; app UI result pending |
| G18 | Existing regressions | NOT_RUN: latest dependency-affected foreground UI run pending |
| G19 | Searchable/Probe | HISTORICAL_PASS_ONLY (40994342575/e9226517); latest affected Searchable/Probe rerun pending |
| G20 | Embedded Node HTTPS | MITIGATED / BLOCKED_DEVICE |
| G21 | RNHostView Fabric | MITIGATED: no proven Fabric root-cause fix |
| G22 | Mixed tree optional | DEFERRED_OPTIONAL: mixed ABI-0 rejected explicitly |
| G23 | Activity/WidgetKit native surfaces | PARTIAL: nonempty Live Activity/translation/intent arrays preserved by concurrent package tests; OS surfaces pending |
| G24 | Final integrity/release | PARTIAL: scoped non-force commits/push; final full CI and signed acceptance open |

| Defect | Current evidence / status |
|---|---|
| B01 | PARTIAL: real shared install tests PASS; actual install/action UI pending. |
| B02 | Historical 11 selected foreground UI methods passed in run 40994342575 at e9226517; affected import/publication requires fresh testing. |
| B03 | MITIGATED / BLOCKED_DEVICE: ipv4first does not prove an IPv6 root cause or embedded TLS/fd reliability. |
| B04 | MITIGATED: explicit RN bounds do not prove the underlying Fabric crash is resolved. |
| B05 | SOURCE_CHANGED_NOT_EXECUTED: wire/timestamp regressions remain open until their own native tests. |
| B06 | PARTIAL: true source ports compile; shared state/action/selection tests PASS and original native rasters PARTIAL; OS presses pending. |
| B07 | PARTIAL: deterministic JS resources and both original source-built native modules compile/link PASS; final .appex audit pending. |
| B08 | SOURCE_INSPECTED: only workflow_dispatch is used; no automatic trigger added. |
| B09 | PARTIAL: four frozen Chat paths unchanged from ce586667; whole-series 37ba baseline differs historically. Runtime/Chat semantic execution not rerun yet. |

P3 source regression suite: HanlinDualWidgetEnginesTests.realArchiveImport, installAndVerifiedLoader, emittedExpoIntentCarriesVerifiedIdentityAndCallsSource, userCreatedInstancesAndHostRefreshPreserveState, scriptWidgetNamedActionsAndBooleanSetValue, staleUndeclaredDisabledAndUninstalledActionsRejectBeforeMutation, concurrentSourceActionsReplayAndHostPublication, actionAndPublicationPreserveUnrelatedCollections, checkedArtifactsRejectTamperTraversalOtherGenerationAndSymlink, actualHistoricalV1EncoderAndDowngradeReader, interruptedShadowPublicationRestoresExactCommittedRevision, corruptCommittedV2NeverFallsBackToGoodV1, unconfiguredAndWrongFamilyNeverSelectAnotherWidget.

These are semantic unit/integration tests, not claims of actual SpringBoard taps. They replace the previous AnyView type-name assertions. Failing-before Apple execution was not performed on the uncommitted starting worktree; do not label it as a measured red/green run.

## Individual Pass-3 corrective findings — observed 2026-10-31

Statuses below are acceptance scopes, not a blanket CLOSED label. Package PASS references run 41239674500 / 5bfcf03b; source-library PASS references 41239669157 / 5bfcf03b. Every initial dirty-state failing-before Apple run is NOT_RUN. Measured intermediate compiler/resource/test failures remain in CI_AND_DEVICE_RESULTS.md. Changed path hashes/targets/provenance/coverage are in PASS3_CHANGED_PATH_AUDIT.json.

| Finding | Status | Actual assertion / remaining condition |
|---|---|---|
| P3-01 | PARTIAL | Typed injected Expo intent; emittedExpoIntentCarriesVerifiedIdentityAndCallsSource PASS; actual native tap pending |
| P3-02 | PARTIAL | Genuine source callback including arbitrary props PASS; OS press pending |
| P3-03 | PARTIAL | scriptWidgetNamedActionsAndBooleanSetValue PASS (true/true/false/false); native Toggle pending |
| P3-04 | PARTIAL | Stale/corrupt/missing authority throws before success; package negatives PASS; App Group/OS failure UI pending |
| P3-05 | EXECUTED_PASS | staleUndeclaredDisabledAndUninstalledActionsRejectBeforeMutation; exact generation/engine/variant validation |
| P3-06 | PARTIAL | userCreatedInstancesAndHostRefreshPreserveState PASS; actual A1/A2 picker pending |
| P3-07 | PARTIAL | No JSC fallback in bodies; timelinePreparationCommitsOriginalTypedStorageAcrossColdReads PASS; provider OS pending |
| P3-08 | PARTIAL | One-shot context; alternating JS globals and concurrent native action tests PASS; no device stress claim |
| P3-09 | PARTIAL | Original pinned AnyChild/ExpoUI source compiles/links; native pixel/slot iOS results pending |
| P3-10 | PARTIAL | Original 29 builders and ten chart native rasters PASS; broad raster is not full semantic parity |
| P3-11 | EXECUTED_PASS | Real JSExport JSX lifecycle/custom component/helper/storage preparation and actions PASS |
| P3-12 | PARTIAL | Install-time compiler and cooperative guards/size/tree budgets compile and malformed JSX tests PASS; memory/hard preemption not proven |
| P3-13 | EXECUTED_PASS | checkedArtifactsRejectTamperTraversalOtherGenerationAndSymlink; same checked loader used by preparation/actions |
| P3-14 | PARTIAL | realArchiveImport/installAndVerifiedLoader preserve engine; host install UI pending |
| P3-15 | EXECUTED_PASS | Dedicated widget compiler executes actual Expo/ScriptWidget JSX and all five positive installs |
| P3-16 | EXECUTED_PASS | Seven real archives plus strict analyzer version/engine/conflict negative assertions |
| P3-17 | PARTIAL | Real independent registry, durable source state, host publication package regression PASS; host relaunch UI pending |
| P3-18 | EXECUTED_PASS | actionAndPublicationPreserveUnrelatedCollections with nonempty arrays and concurrent publication |
| P3-19 | PARTIAL | actualHistoricalV1EncoderAndDowngradeReader, interruptedShadowPublicationRestoresExactCommittedRevision, corruptCommittedV2NeverFallsBackToGoodV1 PASS; signed old-binary downgrade pending |
| P3-20 | PARTIAL | concurrentSourceActionsReplayAndHostPublication PASS; explicit nonce dedup; OS automatic retry IDs unavailable/at-least-once |
| P3-21 | PARTIAL | Versioned exact entity IDs, public instance creation and wrong-family/unconfigured tests PASS; real picker pending |
| P3-22 | PARTIAL | Root widgetURL removed; actual native Link/Button hit routing pending |
| P3-23 | PARTIAL | Only registered generic kind reload remains; OS source-action reload pending |
| P3-24 | PARTIAL | Typed storage/helper/file and timeline persistence PASS; bounded HTTP transport semantics NOT_TESTED |
| P3-25 | PARTIAL | AnyView type-name tests replaced by semantic/source/state/native raster suites; actual SpringBoard tests pending |
| P3-26 | PARTIAL | Authentic reproducible seven archives, real seven analyses/five installs PASS; actual new package Home Screen pending |
| P3-27 | PARTIAL | 133 source/blob hashes, full notices, reproducible JS and source-only native modules PASS; final appex closure pending |
| P3-28 | PARTIAL | Bad manifest/payload/artifact rejects without v1 fallback in tests; native visible error UI pending |
| P3-29 | PARTIAL | Historical overclaims reopened; per-path/gate evidence prepared; final result reconciliation pending |
| P3-30 | MITIGATED / BLOCKED_DEVICE | B03/B04 preserved; no new embedded TLS/fd/Fabric device proof |
| P3-31 | PARTIAL | Same branch scoped commits/non-force push; SDK/package PASS, actual full UI pending, signed device BLOCKED_DEVICE |
