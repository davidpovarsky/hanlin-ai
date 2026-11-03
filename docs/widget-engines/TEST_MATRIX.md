# Pass 3 acceptance ledger — updated 2026-11-01

The gate IDs below retain the mandate's exact original obligations. Earlier versions accidentally shifted G01–G07; inventory preservation is a prerequisite, not a replacement for Source/ABI. No Pass-2 CLOSED/AnyView/ZIP-existence assertion is accepted as native execution evidence.

Evidence keys: **P** = [41263527148](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41263527148), source 23ee9f15951864382762bcbba442a219f9424d8d, 28 extension/10 analyzer/7 JS tests, arm64 macOS. Its 28 extension/ten analyzer methods pass again at c6fcd063 in 41265958805, whose later build fails on test-only teardown isolation. **N** = [41261389588](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41261389588), source 6e3e7f54795fdbac507c0accc75a32a12d54b242, five native iOS renderer and eleven foreground UI methods passed; three Home Screen methods failed. Both use Xcode 27.1 (27A9275)/Swift 6.4; N targets iPad mini (A17 Pro), iPadOS 27 Simulator. Exact native executable hashes, raw artifacts and assertion identities are in CI_AND_DEVICE_RESULTS.md. N predates the later NSNumber/passive-legacy correction. **W** = [41267448297](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41267448297), source a1efb9ff0d778fd8d52e350b71632dab343e2ec9, exactly two new native semantic/wire and three Home Screen methods IN_PROGRESS; no result inferred. Separately, real loopback HTTP passes in 41266251371, measured installed-program durations in 41266957877, and same-target cross-package/variant isolation in 41267451217. Full source hashes and narrowly executed/reused scopes are in the CI ledger.

| Gate | Obligation | Status |
|---|---|---|
| G01 | Source/ABI | EXECUTED_PASS for N built appex: original AnyChild bridge/source-built ExpoUI/Core subset; audit-native-products follows three reachable images, no React/Hermes/missing/unsafe dependencies. W affected build pending |
| G02 | Original ScriptWidget | EXECUTED_PASS for original JSExport/runtime and 29 source builders compiled into N appex; P actual JSX/custom components and native rasters. Full notice/source SHA manifest retained |
| G03 | Resources | PARTIAL: deterministic Expo bundle hash cad96de7…; P real Babel/support/assets load through installAndVerifiedLoader/originalScriptWidgetImportedHelpersAndVerifiedFileStorage; N built resources, actual WidgetKit provider resource loading pending |
| G04 | Expo execution | PARTIAL: N testInstalledExternalSourceRendersThroughAnyChild renders actual Counter/Visuals source; real Home Screen placement failed before configuration, W pending |
| G05 | ScriptWidget execution | PARTIAL: P installAndVerifiedLoader and native installed Dashboard/Actions PNGs from original runtime; N host imported Actions/created Script A1; actual WidgetKit display pending |
| G06 | 29 ScriptWidget tags | PARTIAL: P originalTagRespondsToItsSemanticInput passes 29 changed input pairs; ten original chart variants pass. Significant dimensions enumerated in COMPONENT_PARITY_MATRIX; full per-prop/RTL/Dynamic Type/OS parity not inferred |
| G07 | Expo visual parity | PARTIAL: N all five renderer methods pass typed Text, slots, Label/Progress pixel references, Chart/Gauge children/data and installed Counter/Visuals native PNGs. Other native semantic rows remain individually untested |
| G08 | Three engines same extension | NOT_RUN_SIMULATOR_UI / BLOCKED_DEVICE: N imports all three engines into one frozen host but fails before configuring widgets; imports are not simultaneous Home Screen proof |
| G09 | Dynamic install after IPA | PARTIAL: N frozen simulator app/appex build followed by genuine previously absent source imports. Actual configure/display/action and physical frozen IPA proof remain open |
| G10 | Picker/families | PARTIAL: P unconfiguredAndWrongFamilyNeverSelectAnotherWidget and exact entity validation pass; actual picker/four-family UI pending |
| G11 | Independent instances | PARTIAL: P userCreatedInstancesAndHostRefreshPreserveState and concurrency pass; 41267451217 sameSourceActionTargetAcrossInstalledPackagesAndVariantsIsIsolated proves two real installations and A1/A2 keep 8/9/10 independently through republish/cold reload. N actual host UI creates A1/A2 with unique IDs; OS picker/action isolation pending |
| G12 | AppIntent actions | PARTIAL: P emittedExpoIntentCarriesVerifiedIdentityAndCallsSource/scriptWidgetNamedActionsAndBooleanSetValue pass; N fails before native OS press; W pending |
| G13 | WidgetKit lifecycle | NOT_RUN_SIMULATOR_UI / BLOCKED_DEVICE: provider restart/offline and signed lock/reboot/first-unlock observations absent |
| G14 | Storage & rollback | PARTIAL: P actualHistoricalV1EncoderAndDowngradeReader, interruptedShadowPublicationRestoresExactCommittedRevision, corruptCommittedV2NeverFallsBackToGoodV1 and checkedArtifactsRejectTamperTraversalOtherGenerationAndSymlink pass; signed binary downgrade pending |
| G15 | Malformed/negative cases | PARTIAL: P realArchiveImport rejects Invalid/Mixed; staleUndeclaredDisabledAndUninstalledActionsRejectBeforeMutation and artifact attacks pass; native visible error UI pending |
| G16 | Performance/resources | PARTIAL: N sampled simulator process RSS retained; 41266957877 installedProgramPreparationAndActionMeasurements records first/repeat fresh-VM execution and action/commit times for five isolated macOS installs. No 3–5 configured OS-widget stress or physical memory-peak/leak claim |
| G17 | No Hanlin grant gates | PARTIAL: P shared real install with empty approvals and N three native fixture imports work without Hanlin approval. Native widget action path not yet reached |
| G18 | Existing regressions | PARTIAL: N eleven existing foreground UI methods EXECUTED_PASS; concurrent package test preserves nonempty Live Activity/translation/intent collections. Full NativeScript/compiled Swift/Sefaria/Chat semantic scope not blanket tested; owner Chat edits preserved |
| G19 | Searchable/Probe | EXECUTED_PASS in N: testProductionExpoSearchableContentAndEvents, testProductionExpoSwiftUIProbeEndToEnd, DynamicPackageSwitching and LifecycleAndUninstall. Reuse after N only for documented unchanged dependency scope |
| G20 | Embedded Node HTTPS | MITIGATED / BLOCKED_DEVICE |
| G21 | RNHostView Fabric | MITIGATED: no proven Fabric root-cause fix |
| G22 | Mixed tree optional | DEFERRED_OPTIONAL: mixed ABI-0 rejected explicitly |
| G23 | Activity/WidgetKit native surfaces | PARTIAL: nonempty Live Activity/translation/intent arrays preserved by concurrent package tests; OS surfaces pending |
| G24 | Final integrity/release | PARTIAL: same-branch non-force commits/push and all raw failed/passed runs retained; W affected tests and final clean SHA pending; physical acceptance BLOCKED_DEVICE |

| Defect | Current evidence / status |
|---|---|
| B01 | PARTIAL: real shared install tests PASS; actual install/action UI pending. |
| B02 | EXECUTED_PASS for the Probe/Searchable assertions in N; full old import/publication suite not inferred beyond the eleven named methods. |
| B03 | MITIGATED / BLOCKED_DEVICE: ipv4first does not prove an IPv6 root cause or embedded TLS/fd reliability. |
| B04 | MITIGATED: explicit RN bounds do not prove the underlying Fabric crash is resolved. |
| B05 | PARTIAL: N native typed values and P actual source/install/cold-state tests pass; raw/tagged/date-specific publication/action roundtrip scope remains separately unverified. |
| B06 | PARTIAL: true source ports compile; shared state/action/selection tests PASS and original native rasters PARTIAL; OS presses pending. |
| B07 | PARTIAL: N actual .appex native closure EXECUTED_PASS; deterministic JS resources and original native modules compile/link. Actual provider resource execution pending. |
| B08 | SOURCE_INSPECTED: only workflow_dispatch is used; no automatic trigger added. |
| B09 | PARTIAL: zero widget-authored diff to all four Chat files relative to owner b5ce6f60. Two owner Chat changes deliberately imported; the other two remain unchanged from ce586667. N foreground regressions pass; full Chat/Runtime/Node/Sefaria scope not inferred. |

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
| P3-09 | PARTIAL | N original pinned AnyChild/ExpoUI source compiles/links; five exact native pixel/slot/data methods pass; further visual dimensions under focused verification |
| P3-10 | PARTIAL | Original 29 builders, 29 changed semantic-input pairs and ten native chart variants PASS in P; full per-prop/OS acceptance remains separate |
| P3-11 | EXECUTED_PASS | Real JSExport JSX lifecycle/custom component/helper/storage preparation and actions PASS |
| P3-12 | PARTIAL | Install-time compiler and cooperative guards/size/tree budgets compile and malformed JSX tests PASS; memory/hard preemption not proven |
| P3-13 | EXECUTED_PASS | checkedArtifactsRejectTamperTraversalOtherGenerationAndSymlink; same checked loader used by preparation/actions |
| P3-14 | PARTIAL | realArchiveImport/installAndVerifiedLoader preserve engine; N imports Counter/Actions/legacy through actual host UI and captures declared engine identities; native placement still open |
| P3-15 | EXECUTED_PASS | Dedicated widget compiler executes actual Expo/ScriptWidget JSX and all five positive installs |
| P3-16 | EXECUTED_PASS | Seven real archives plus strict analyzer version/engine/conflict negative assertions |
| P3-17 | PARTIAL | Real independent registry, durable source state, host publication package regression PASS; host relaunch UI pending |
| P3-18 | EXECUTED_PASS | actionAndPublicationPreserveUnrelatedCollections with nonempty arrays and concurrent publication |
| P3-19 | PARTIAL | actualHistoricalV1EncoderAndDowngradeReader, interruptedShadowPublicationRestoresExactCommittedRevision, corruptCommittedV2NeverFallsBackToGoodV1 PASS; signed old-binary downgrade pending |
| P3-20 | PARTIAL | concurrentSourceActionsReplayAndHostPublication PASS; explicit nonce dedup; OS automatic retry IDs unavailable/at-least-once |
| P3-21 | PARTIAL | Versioned exact entity IDs, public instance creation and wrong-family/unconfigured tests PASS; real picker pending |
| P3-22 | PARTIAL | Native engines have no covering root widgetURL; passive legacy URL retained only without nested buttons, P regression passes; actual Link/Button hit routing pending |
| P3-23 | PARTIAL | Only registered generic kind reload remains; OS source-action reload pending |
| P3-24 | PARTIAL | Typed storage/helper/file and timeline persistence PASS; 41266251371 actual loopback HTTP verbs/JSON/metadata/base64/limits/timeout/redirect tests PASS. Remote TLS and device network unverified |
| P3-25 | PARTIAL | AnyView type-name tests replaced by semantic/source/state/native raster suites; actual SpringBoard tests pending |
| P3-26 | PARTIAL | Authentic reproducible seven archives, real seven analyses/five installs PASS; actual new package Home Screen pending |
| P3-27 | PARTIAL | 133 source/blob hashes, full notices, reproducible JS and source-only native modules PASS; N actual three-image reachable appex closure PASS; provider resource execution pending |
| P3-28 | PARTIAL | Bad manifest/payload/artifact rejects without v1 fallback in tests; native visible error UI pending |
| P3-29 | PARTIAL | Historical overclaims reopened; per-path/gate evidence prepared; final result reconciliation pending |
| P3-30 | MITIGATED / BLOCKED_DEVICE | B03/B04 preserved; no new embedded TLS/fd/Fabric device proof |
| P3-31 | PARTIAL | Same branch scoped commits/non-force push; SDK/package PASS, actual full UI pending, signed device BLOCKED_DEVICE |

Current measured iOS failures and follow-up source are detailed in CI_AND_DEVICE_RESULTS.md (2026-11-01). The current merged source includes the owner OrganizerDock branch, so no pre-merge full app PASS is inferred. Native Home Screen interaction remains open; five original native renderer methods now cover the repaired Gauge, Label and Progress routes. The per-path audit separates 27 imported owner paths from widget-authored changes.

## Delivery override — 2026-11-01

Latest iOS run 41304461973: both added native renderer methods PASS (34 reference comparisons and wire/action roundtrip); three widget Home Screen methods FAILED at Add Widget. The final selector fix is not execution evidence. Retry 41308904140 and unsigned retry 41309874110 were cancelled at owner request. Owner now requests immediate TestFlight upload and will test on iPad: OWNER_DEVICE_QA_PENDING. No new optional tests are authorized by this handoff; earlier chronological pending statements are historical.

TestFlight delivery: [41310977352](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41310977352) SUCCESS; 0.7.3 (87401) VALID. This closes signed delivery, not the outstanding owner iPad/WidgetKit interaction rows.

## Pass 4 physical iPad blocker reproduction and corrective matrix — 2026-11-03

On 2026-11-01, owner physical iPad testing of TestFlight `0.7.3 (87401)` (`279f0ead777b961728ed91386c136e7e33659c36`) resulted in `OWNER_EXECUTED_FAIL` / `DEVICE_QA_FAILED`: `Hanlin-ScriptWidget-Actions.scripting` installed at generation 1, but Package Information showed empty `Widget instances` and red `invalidArtifactReference`, and tapping widget-only rows in Add Apps triggered foreground `Script App Error: invalidArtifactReference`.

Pass 4 corrective evidence keys:
- **P4-PKG** = [41559080533](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41559080533), source `3daf6e2b4d1c11880cb88c26074d48dbbcb98f2f` (identical `Packages/HanlinPlatform` source to `35fa7b06dcf6ae68e2ad13d0a27176e45de9767e`), 7 JS tests + 29 Swift Testing methods across `HanlinDualWidgetEnginesTests` and `HanlinOriginalScriptWidgetRenderingTests` + 10 `HanlinScriptAnalyzerTests` (`EXECUTED_PASS`).
- **P4-SIM-A** = [41561161396](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41561161396), source `35fa7b06dcf6ae68e2ad13d0a27176e45de9767e`, `build-for-testing` + `audit-native-products.mjs` + `testWidgetOnlyRowOpensPackageInformationNotApp` (`EXECUTED_PASS`, 157.814s); `testInstalledScriptWidgetPackageInformationShowsDefaultInstance` failed on initial simulator boot (`SBMainWorkspace Busy`).
- **P4-SIM-B** = [41564460036](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41564460036), source `35fa7b06dcf6ae68e2ad13d0a27176e45de9767e`, focused rerun of `testInstalledScriptWidgetPackageInformationShowsDefaultInstance` (`EXECUTED_PASS`, 169.717s).

| Finding / Scenario | Status | Executed / Reused Evidence |
|---|---|---|
| P4-01 (`/private/var` App Group canonicalization & `lstat` symlink checks) | EXECUTED_PASS (macOS + iPadOS 27 Simulator) / OPEN (physical iPad retest) | `pass4PrivateVarAliasedRootCleanLoadArtifactStoreAndSnapshotPublishSucceeds` and `pass4SymlinkAndTraversalSecurityRejectsManagedTreeLinksWithDiagnostics` in **P4-PKG** |
| P4-02 (Two-store non-destructive publication consistency & `republishWidgets(for:)`) | EXECUTED_PASS (macOS + iPadOS 27 Simulator) / OPEN (physical iPad retest) | `pass4TwoStorePublicationFailureRecoveryAndEntrypointRouting` in **P4-PKG**; `testInstalledScriptWidgetPackageInformationShowsDefaultInstance` in **P4-SIM-B** |
| P4-03 (Actionable Package Information error card, `Default` auto-selection, retry & copy diagnostic) | EXECUTED_PASS (iPadOS 27 Simulator) / OPEN (physical iPad retest) | `testInstalledScriptWidgetPackageInformationShowsDefaultInstance` in **P4-SIM-B** |
| P4-04 (Widget-only row tap opens Package Information, not foreground app launch) | EXECUTED_PASS (macOS + iPadOS 27 Simulator) / OPEN (physical iPad retest) | `pass4TwoStorePublicationFailureRecoveryAndEntrypointRouting` in **P4-PKG**; `testWidgetOnlyRowOpensPackageInformationNotApp` in **P4-SIM-A** |
| P4-05 (Cross-process store/instance lifecycle & `Default` + `Secondary` persistence) | EXECUTED_PASS (macOS + iPadOS 27 Simulator) / OPEN (physical iPad retest) | `pass4PrivateVarAliasedRootCleanLoadArtifactStoreAndSnapshotPublishSucceeds` in **P4-PKG**; `testInstalledScriptWidgetPackageInformationShowsDefaultInstance` in **P4-SIM-B** |
| P4-06 (Privacy-safe `HanlinWidgetStorageDiagnostic` with `HWG-<12hex>` correlation ID) | EXECUTED_PASS (macOS) | `pass4SymlinkAndTraversalSecurityRejectsManagedTreeLinksWithDiagnostics` and `pass4TwoStorePublicationFailureRecoveryAndEntrypointRouting` in **P4-PKG** |
| Physical iPad owner retest on new signed TestFlight build `0.7.3 (88001)` | OPEN / `OWNER_DEVICE_QA_PENDING` | Signed TestFlight build `0.7.3 (88001)` delivered in [41568291224](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41568291224) (`VALID` at `2026-11-03T03:31:19Z`, IPA SHA256 `0c02d6fb98918e6310546a99459eeee3928e6f029d586aec4cbf3da87e80769b`); physical iPad verification of checklist steps 1–10 pending owner execution |
