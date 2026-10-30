# Pass 3 acceptance ledger — 2026-10-30

No Pass-2 CLOSED/AnyView/ZIP-existence assertion is accepted as native execution evidence. All rows await their own matching assertions. Current raw run links and platform scope are in CI_AND_DEVICE_RESULTS.md.

| Gate | Obligation | Status |
|---|---|---|
| G01 | Inventory/preservation | SOURCE_CHANGED_NOT_EXECUTED |
| G02 | Original Expo AnyChild | SOURCE_CHANGED_NOT_EXECUTED |
| G03 | Original ScriptWidget native builders | SOURCE_CHANGED_NOT_EXECUTED |
| G04 | JSX compiler/resources | PARTIAL (JS EXECUTED_PASS; Apple NOT_RUN) |
| G05 | Explicit import/engine metadata | SOURCE_CHANGED_NOT_EXECUTED |
| G06 | Complete native component parity | NOT_RUN |
| G07 | Prepared presentation/JSC isolation | SOURCE_CHANGED_NOT_EXECUTED |
| G08 | Three engines concurrently | BLOCKED_DEVICE |
| G09 | New post-build package install | NOT_RUN_SIMULATOR_UI |
| G10 | Picker/families | SOURCE_CHANGED_NOT_EXECUTED |
| G11 | Configured independent variants | SOURCE_CHANGED_NOT_EXECUTED |
| G12 | Actual native AppIntent press | NOT_RUN_SIMULATOR_UI |
| G13 | OS widget lifecycle | BLOCKED_DEVICE |
| G14 | State, checksum, v1 rollback | SOURCE_CHANGED_NOT_EXECUTED |
| G15 | Malformed/negative cases | PARTIAL (JS checks only) |
| G16 | Measured performance/memory | NOT_RUN |
| G17 | No Hanlin grant gate | SOURCE_CHANGED_NOT_EXECUTED |
| G18 | Existing regressions | NOT_RUN |
| G19 | Searchable/Probe | HISTORICAL_PASS_ONLY; impact rerun pending |
| G20 | Embedded Node HTTPS | MITIGATED / BLOCKED_DEVICE |
| G21 | RNHostView Fabric | MITIGATED |
| G22 | Mixed tree optional | DEFERRED_OPTIONAL |
| G23 | Activity/WidgetKit native surfaces | SOURCE_CHANGED_NOT_EXECUTED |
| G24 | Final integrity/release | NOT_RUN |

| Defect | Current evidence / status |
|---|---|
| B01 | SOURCE_CHANGED_NOT_EXECUTED: existing automatic ordinary capability grants preserved; native install/action tests pending. |
| B02 | Historical 11 selected foreground UI methods passed in run 40994342575 at e9226517; affected import/publication requires fresh testing. |
| B03 | MITIGATED / BLOCKED_DEVICE: ipv4first does not prove an IPv6 root cause or embedded TLS/fd reliability. |
| B04 | MITIGATED: explicit RN bounds do not prove the underlying Fabric crash is resolved. |
| B05 | SOURCE_CHANGED_NOT_EXECUTED: wire/timestamp regressions remain open until their own native tests. |
| B06 | SOURCE_CHANGED_NOT_EXECUTED: true source ports, state/action/selection repairs added; original native rendering and OS presses pending. |
| B07 | PARTIAL: deterministic JS resources and pinned native sources exist; .appex binary/resource/ABI audit pending. |
| B08 | SOURCE_INSPECTED: only workflow_dispatch is used; no automatic trigger added. |
| B09 | PARTIAL: four frozen Chat paths unchanged from ce586667; whole-series 37ba baseline differs historically. Runtime/Chat semantic execution not rerun yet. |

P3 source regression suite: HanlinDualWidgetEnginesTests.realArchiveImport, installAndVerifiedLoader, emittedExpoIntentCarriesVerifiedIdentityAndCallsSource, userCreatedInstancesAndHostRefreshPreserveState, scriptWidgetNamedActionsAndBooleanSetValue, staleUndeclaredDisabledAndUninstalledActionsRejectBeforeMutation, concurrentSourceActionsReplayAndHostPublication, actionAndPublicationPreserveUnrelatedCollections, checkedArtifactsRejectTamperTraversalOtherGenerationAndSymlink, actualHistoricalV1EncoderAndDowngradeReader, interruptedShadowPublicationRestoresExactCommittedRevision, corruptCommittedV2NeverFallsBackToGoodV1, unconfiguredAndWrongFamilyNeverSelectAnotherWidget.

These are semantic unit/integration tests, not claims of actual SpringBoard taps. They replace the previous AnyView type-name assertions. Failing-before Apple execution was not performed on the uncommitted starting worktree; do not label it as a measured red/green run.
