# W1-006 consolidated integration

Owner: Tomer, independent primary `01a1dc9e-91cb-7d12-9102-acd3500aee90`.
Worktree `C:/Users/DAVID/Code/hanlin-wave1-integration-20261115`, branch
`codex/hanlin-wave1-integration-20261115`. Source integration task
K `1219656771637321`; HQ `1220539630159023`. Date: 2026-11-15, Asia/Hebron.

## Current continuation: W1-007 provider candidate

The bootstrap P2 is corrected in the current candidate: a single observable
preparation boundary keeps the live provider unconstructed until real
`AppRuntimeCore.prepareStorage()` succeeds. Failure shows a native unavailable
view with Retry and actual allowlisted system domain/code; no raw error message,
path or payload is shown. Retry reruns the real preparation; concurrent attempts
coalesce and successful preparation is not repeated. Initial view tasks run only
from idle, so an error does not trigger an automatic retry loop.

Three actual bootstrap Swift Testing cases PASS on Windows Swift 6.3.3 against
byte-identical production coordinator/test source: failure/retry plus private-path
canary, concurrent preparation, and no repeated preparation after success. Tests
inject only that boundary and never instantiate a provider/Expo/AppGroup/store.
The first Windows SwiftPM attempt failed on a generated long-path I/O error before
test execution; using a short separate build directory executed all three cases.
Both logs and the source-hashed test harness remain under ignored evidence paths.
This is not Apple/UI acceptance.

The registered native plan now has **three UI + three bootstrap + six leaf**
cases. The third UI case imports the unchanged ordinary default-JSC production
compiler corpus `ValidScriptUI` through the existing preview/compiler/installer,
finds its real canonical catalog row, launches it and requires the real Increment
callback to change `Count 0` to `Count 1`. No installed registry, provider, script
output or nil runtime profile is synthesized. Only the actual package archive is
staged into this integration bundle's isolated simulator Documents after install;
no live user store or cleanup is used. The library refreshes through its actual
provider after management dismissal. The separate bootstrap unit target compiles
the same production coordinator directly and has no app/runtime dependency.

Noam's source-accepted Host/SDK JSC correction `6c4d30c8` was consumed as one
isolated delta, preserving the composition test route. His seven Apple discovery
cases remain NOT_RUN until his actual proof. Current source registration has
**57 Swift + three native sources**; the helper manifest is the exact membership
record. Nine source graph guards pass. The full provider proof remains blocked
on the corrected metadata handoff: the old six-file candidate was withdrawn for
non-fail-closed role audit errors, effective deployment-target mismatch, and stale
React headers after staging. It was not applied here, no guard was waived, and
the actual target stays iOS 27.0 rather than being raised to match a receipt.

The W1-006 results below remain attached to their original tested source, not
the expanded provider target. The earlier provider candidate registered 56 existing/shared
Swift sources, three existing native bridge sources, 21 package products, two
existing native frameworks and 16 resources by explicit paths in
`Scripts/CI/IntegrationValidation/miniapps_provider_sources.json`. No AI source
root is included in MiniApps. Metadata/Python preparation and framework embedding
reuse the existing build phase bodies, with separate phase/build-file identities.
Original AI target/project settings are preserved.

`HanlinMiniAppsProvider` composes the existing Host/catalog/restore, canonical
launch functions and existing package detail/import UI. It refreshes before
launching retained rows, checks actual active package and engine presentation
after the existing non-throwing platform launch, and throws on failure instead
of returning an unavailable container as success. Compiled Swift roots and the
existing script container keep their own navigation. The new app entry point
uses production defaults; no Assistant service, AI ModelContext, credential
adapter, test factory or second authority is configured in MiniApps.

Noam's application-services cut was consumed as exact deltas `21a7394d` and
`6837d0ae`, cherry-picked to this branch without their metadata ancestors. Its
corrected publication is synchronous on MainActor, with generation/captured
configuration checks for queued work; Assistant loading remains asynchronous.
The new AI integration file is deliberately absent from MiniApps source membership.
Roni's scoped source review accepts both prior P2 corrections; Noam owns the
separate original 16 + eight composition Apple cases. Those results are not
assumed or rerun here.

The initial provider candidate added a genuine MiniApps-only UI test target with two authored
cases: real canonical Swift Parity launch, and the existing package import screen.
Both capture screenshots and require actual controls. They are **NOT_RUN**.
The old shell-only extraction route now rejects this expanded graph. The next
provider proof uses the real project/target and existing pinned Runtime/SDK
preparation routes, then those two UI cases and the six registered leaf cases.
No full AI build is selected. Actual corrected metadata inputs must be delivered
before running a known-blocked dependency closure; no metadata ancestor was
silently promoted with the application-services cut.

Fixture correction `6567a187` was integrated once, after the lead's scoped QA
acceptance. It also changes **production** `DurableMigration.swift` (persisted
recovery choice) and `DurableReceiver.swift` (new error case), so it is not
classified as fixture-only. The focused Windows package rebuilt those sources
and executed **six** actual Swift Testing cases successfully, including new
serialization/irreversible-recovery-choice coverage. Raw output and actual lock
are in ignored `build/integration-validation-evidence/windows-correction-*`.
The old five-case iOS proof is historical evidence, not proof of these changed
production bytes. Nine graph/evidence guards pass for the registered candidate;
syntax parses do not establish Apple compilation or UI behavior. All three
fixture adapters and all producer portable executable tests remain excluded.

## Enabled A2UI proof and consumer-module correction

The separate existing workflow mode `a2ui_exact_pin_proof` tests exact A2UI source
in scratch without product wiring or source edits by this integrator. Exact
source-only verification refs publish immutable tested inputs so the runner can
fetch them; no producer branch was synchronized. The owner's recipe copies
byte-identical source/tests/fixtures, enables POC + DEBUG, and uses four official
products at root revision `3ed9601862ecc78027e20ac80ad8b1b98a5d9079`.

Actual environment: Xcode 27.2 (27B52), Apple Swift 6.4.2, macOS SDK 27.2, host
macOS 27.0.1. Per-command plugin/macro flags match existing repository CI; the
official schema generator and macros execute. Initial setup run `43662580025`
stopped at the plugin consent step before compilation. Then:

- [43662884686](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43662884686),
  workflow `127092d9`, tested source `c40e617b`: enabled compilation succeeded;
  25 actual cases executed, eight ingress PASS and all 17 SDK cases FAIL with
  `sdkValidation` loading positive fixtures. Artifact `a2ui-exact-pin-43662884686`,
  id `14141275174`, API-advertised digest
  `sha256:ac5719290dd51265b2c333311ba17cbfe8c1c46f108fec5a833c9fced89c4d92`.
  The failure and actionable logs were delivered to Eitan; this integrator did
  not weaken validation, alter tests or replay the unchanged failing source.
- [43664698104](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43664698104),
  workflow `04c8837a1863303dd0a20304062481802a1fd437`, tested source
  `2bae5a3e08138b5d346d9c7e8b609e0827407231`: **25 actual cases PASS** after
  Eitan's coherent identifier correction. Exact-pin UAX31 validation rejected
  `submit-label`; positive references became `submitLabel` while the invalid
  spelling remains a negative case. Artifact `a2ui-exact-pin-43664698104`, id
  `14142305401`, API-advertised digest
  `sha256:90b9ad4e8f76ac93d417fc9734ff9ecbbb991be26a8fe8ea926f2a5516e7e0b7`.

Both artifacts were downloaded and their exported actual test trees inspected.
The passing artifact's 13 archived source/recipe/fixture hashes match exact tested
Git blobs; nine workflow input hashes match its workflow SHA. The unchanged owner
verifier reports `RESULT_CONTENTS_VALID`, 25 cases, with process exit 0. Both runs
retain raw xcresults, exported JSON, logs, source archive and **raw** resolved
locks. Raw lock hash is `8930d6c472f0e98f01831d0af3abdc573c3f85fa255091e45d45e2564c73f6ac`
in both: official a2ui root above; swift-json-schema 0.13.2
(`c0a9375ea9cd3fd47d875c98ed7f027ea61c03cb`); swift-collections 1.7.6
(`88754449ab766a739610b660e117762115fabc9c`); swift-syntax 604.0.0
(`050f1a346fbbac0ca2cfb15a95274f7bd1cf0ccf`). Raw bytes/hash/parsed JSON agree.

This is enabled **macOS SDK** proof for `2bae5a3e`, not iOS app/inline host/UI
acceptance or A2UI02. A newer diagnostic privacy P2 remains assigned to Eitan:
SDK paths may contain caller-derived identifiers despite length bounds. His
coherent privacy correction will need one changed-source proof. No final source
acceptance is inferred from the intermediate 25-case PASS.

Privacy correction `a43f15639cdfb5c2edded52742bc62f1f7876b4e` subsequently passed
the same 25 actual enabled cases in
[43667371439](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43667371439),
workflow `eb58144679df5bb3f95692686bbeae33e7c47000`, on the same exact SDK pin,
compiler/host and raw resolved graph. Artifact `a2ui-exact-pin-43667371439`, id
`14142832088`, API digest
`sha256:584046a55ec1f57bcfc0f06b33df99f486d6154c9c62f83cd2cc305f06036efe`.
Downloaded export has 25 Passed nodes, no omissions/skips; 13 tested source input
hashes and 12 workflow input hashes match the respective exact Git blobs, and raw
lock bytes/hash/parsed JSON agree. This covers the actual added privacy canary
assertions. Raw xcresult is retained; no independent Windows binary decode is
claimed. Result was delivered to lead/root/Eitan/Roni.

A separate concrete app-consumer mismatch was found during integration:
`A2UITests.swift` imports `AI_HLY`, while the actual app target/product and the
Composer tests use `AI_Hanlin`, with no project/CI module override or alias. The
isolated recipe mirrors `AI_HLY`, masking that app test-bundle compile boundary.
Eitan was asked to correct the real test import and the exact-byte recipe module
and paths coherently. No app module identity or source was changed by this
integrator. Owner correction `f654ac113447177df3838908c53ce9aa24dc47ff`
changes the actual test import and generated consumer module to `AI_Hanlin`,
preserving physical repository paths, the `AI_HLYTests` test module and all 25
case bodies/assertions. Roni accepted this source correction.

Its changed-source native proof
[43668852483](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43668852483)
is **SUCCESS**, workflow `e1dba14f78e543316dd2f6c9b901cdb558bdb844`.
The downloaded export contains exactly 25 actual passing Test Case nodes; all
13 source and 15 workflow hashes match their respective Git commits. The compiler
log records `-module-name AI_Hanlin`. Raw lock bytes/hash/full JSON agree, with
SHA256 `af74be77f91276268a10e0b32f13e04d538f4a01110ad93d8c9e484177dd9fae`;
the manifest origin hash changed with the module name, while the exact upstream
revision and four resolved package pins are unchanged. Artifact
`a2ui-exact-pin-43668852483`, id `14143507639`, API digest
`sha256:4c8473c1acc6930b25c6d6f448276637146f4f33b20a4f8321502ad69b5b49cd`.
Evidence remains under ignored `build/integration-validation-evidence/a2ui-43668852483`.
This is the native macOS consumer proof using Xcode 27.2, Swift 6.4.2, macOS SDK
27.2 and macOS 27.0.1. Actual iOS app/test-bundle compilation, inline connection,
A2UI02 and physical iPad acceptance remain open. The producer source has not yet
been merged into this integration branch; its verification ref only supplies the
exact immutable source object. No unchanged proof rerun is needed.

## W1-008 Composer verification preparation

Lead released clean source checkpoint `ee534fae3b87fc087cb80828bca15236c8a752dd`
for preparation while the service-observation hook follow-up remains pending.
`Scripts/CI/ComposerValidation/prepare_capability_proof.py` stages seven complete
production files from exact Git blobs: the Morph shell, popup coordinator, dock
state, detached chips, ActionBridge, real SwiftData `AllModels`, and its real
`ProviderModelCatalogMetadata` dependency. It also copies the entire Morph test
file unchanged and checks the six actual case declarations, including
`capabilityRoutesReturnToOpenHome`. The prepared package uses the existing
`AI_Hanlin` component manifest; there is no model stub or source slicing.
Preparation succeeded locally and recorded hashes; compilation/tests are
**NOT_RUN**. No workflow was dispatched on an intermediate producer packet.

The complete `HanlinOrganizerDockParityTests.swift` file also compiles tests for
`HanlinCompactChatWorkspace`, which constructs real `ChatViewWrapper` and
`ChatViewBottom`. Its session suite compiles `HanlinComposerSessionBridge`, whose
send gating calls `ChatViewBottom.shouldEnableSend`. Therefore the requested
`ComposerActionsParityTests/detachedCapabilitiesProjectRealModeState` and
`ChatComposerSessionBridgeTests/toolUseBindingRemainsScopedToItsChat` require
the actual application closure. Compiling only selected suites by slicing that
file would hide this dependency and is not a valid isolated proof.
`HanlinMorphComposerUITests/testEnabledToolsChipOpensSettingsAndContextMenuDisables`
also requires the actual app UI. All three are recorded as NOT_RUN app selectors
in the preparation manifest. The earlier five-case SDK 26.5 component result
does not cover these new sources, the app at iOS 27, UI or a physical iPad.

## Assembled sources

Frozen Runtime baseline `dd700c03e9fe9d22e95a031d4684275512ee6e6f` plus one
octopus assembly of Split `fb90d670e05f282405327466d07b1ff81a95addb`, A2UI
`3a24003ea45636feae76f684234119a0ddeccd6b`, and Composer
`d2126940850b48c9c448fff606dfb79607e5e045`. The separate released verification
tranche through Composer `54b5d90a7c137fe895d3d8cc0c37d31b1d8d62a3` joined this
same window once. The later authorized Split delta `053d1535d008c044caaebbd241f9fe29ce85aab3`
joined once after its handoff; its receiver/migration sources are included without
fixture persistence. No Runtime failed trial or unaccepted W1-004 candidate joined.
No producer branch was rebased, merged back or synchronized.

## Registered implementation

- `HanlinProductSplit/Package.swift` exports the actual leaf product with the
  existing `HanlinPlatformContracts` and `HanlinMiniAppCore` products. Production
  explicitly excludes `SplitFixtureStore.swift`, `SplitReceiverFixturePersistence.swift`
  and `SplitMigrationFixturePersistence.swift`. Five real Swift Testing cases
  are registered under `Tests/RegisteredIntegrationTests`; the producer's custom
  portable `@main` remains outside every production/test target.
- `HanlinMiniApps` is a separate application target and scheme with only
  `HanlinMiniAppsApp` synchronized source membership. It links the three canonical
  products, has no AI app/extension dependency or Runtime build phase, and uses
  Swift 6 / iOS 27. Its unsigned simulator-only identity is
  `com.itorah.hanlinminiapps.integration`, not a registered production App ID.
- The existing AI target, build configurations, bundle identity, stores, Host
  source and authority remain unchanged. The graph validator compares every
  existing project object against the frozen baseline, allowing only additive
  project/package/product/source-group parent lists.
- `MiniAppsServices.unconfigured` remains the honest composition state. A failed
  catalog load now leaves a persistent unavailable view and Retry action, so
  dismissing an action alert cannot turn missing services into an empty catalog.
  No fabricated catalog, action handler, permission grant or successful dispatch
  is introduced.
- The existing manual workflow selects this proof through
  `target_validation_group=product_split_integration`. Other execution/release
  modes are excluded for that selection. No automatic trigger was added.

## Verification boundaries and executed evidence

| Check | Actual result | Scope |
| --- | --- | --- |
| Six pairwise read-only merge previews of initial source pins | PASS, no overlapping changed paths/conflict markers | Textual source readiness only |
| Graph validator + real SwiftPM manifest evaluation | PASS on Windows | Product linkage, source/test/fixture separation, unchanged original target objects and identity |
| Nine Python graph/extraction/evidence guards | PASS | Includes rejecting AI membership/dependency, Runtime build phase, signing/lowered deployment, missing linked product, duplicate/zero/skipped result nodes |
| `swift test --package-path Packages/HanlinProductSplit --filter RegisteredSplitIntegrationTests` | **5 actual Swift Testing cases PASS** after durable-source integration, Swift 6.3.3, Windows x86_64 | Complete real canonical contract/core products and new exported leaf product; no source substitution or resource helper omission |
| Swift frontend parse of three MiniApps files + registered tests | PASS | Syntax only, no Apple SDK acceptance |
| Bash syntax, YAML parsing, 25-input dispatch limit, `git diff --check` | PASS | Verification route/configuration only |
| iOS 27 extracted target build / simulator install + launch / registered package tests | **PASS, 5 actual cases**, run 43660671583 at `58fa4e45` | Xcode 27.2 (27B52), SDK 27.2, Apple Swift 6.4.2, iPhone 18 Pro runtime iOS 27.0; extracted target scope only |
| Full AI app/host, live MiniApps provider, authenticated OS bridge, two-app installation, physical iPad, visual parity, 278 feature behaviors | **NOT_RUN / unresolved** | No feature acceptance is inferred |

The five executed registered cases are
`canonicalBrokerRoundTripPreservesOriginAndConsumesReturn`,
`canonicalAuthorityDenialIsNotBypassedByAdapter`,
`absentTransportCannotAdvanceToDispatched`, and
`registeredMigrationIsPureAndPreservesIdentityBytes`, and
`unconfiguredDurableReceiverRejectsBeforePersistence`. They exercise real
canonical broker authorization, exact-origin return/duplicate consumption,
unavailable-transport non-dispatch, pure synthetic byte-preserving dry-run, and
rejection of an unconfigured durable receiver before persistence is attempted.
The final successful test output explicitly reports five Swift Testing cases in one
suite; XCTest's separate zero-case heading is not the executed-test denominator.
The earlier initial-product run executed four cases; after the leaf source graph
changed, the focused registered suite rebuilt the affected product and executed
all five cases successfully. Neither run redoes or relabels the producer's 55
portable cases.

Windows resolution evidence is retained locally under ignored
`build/integration-validation-evidence/windows-Package.resolved`. The actual
resolved graph includes swift-ai-sdk `43ebcfaae67ca2c47ea1ce940d66b581e60ca7f6`,
swift-argument-parser 1.8.2, SwiftyJSON 5.0.1 and ZIPFoundation 0.9.19. That
generated lock is evidence, not a manually invented app lock or a new committed
file outside the lease. The Windows transcript is the tool execution evidence;
no separate full raw Windows log file was retained.

### Native checkpoint

The full Xcode project references Runtime binary packages whose artifacts are
outside this tranche. The validation script therefore extracts the **same**
registered MiniApps target into a disposable project: identical target object,
compiler settings, package products and actual checkout source paths; unrelated
target/package references are pruned. No source/SDK/engine is copied or replaced.
The generated graph and source hashes are retained. Its result is extracted
target proof, never full-project or live-provider acceptance.

The runner requires actual stable Xcode 27, iOS Simulator SDK 27+, and an
available iOS 27 phone simulator before building. It retains exact SHA, SDK,
source hashes, resolved graphs, build/test logs, xcresults and actual test case
nodes. It does not lower deployment to reuse the SDK 26 Composer proof. The inherited
`Config.xcconfig` is generated in the disposable directory from the existing
full-app simulator workflow template, including its original compiler flags and
intentionally empty CI credential fields; it is hashed and retained. No private
configuration or runtime implementation is substituted. Missing
or duplicate/skipped/zero cases fail verification. Signing and release jobs stay
excluded. The simulator launch, when reached, launches the unavailable shell.

An initial dispatch at `e79082c1` was rejected before any job because adding a
26th workflow input exceeded GitHub's limit. The final route reuses the existing
input instead. Run [43660248871](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43660248871)
at `e71c0dac` failed before native compilation because Actions' shallow checkout
did not contain the frozen graph baseline. The runner now fetches only that
exact baseline object, preserving the dispatched checkout. Corrected run
[43660351669](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43660351669)
at `4cfe4c49` reached real Xcode 27.2 / SDK 27.2 and an eight-target dependency
graph without Runtime targets, then failed because the inherited ignored
`Config.xcconfig` was missing from the disposable graph directory. This was a
verification setup failure, not a compiler/test pass. The existing deterministic
CI template is now retained there. Run
[43660671583](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43660671583)
at full SHA `58fa4e45d72c3c767853ab0300f85ad4575eb951` includes the durable
Split delta and fifth registered case
`unconfiguredDurableReceiverRejectsBeforePersistence`: **SUCCESS**.

Artifact `product-split-integration-43660671583`, id `14139693176`, GitHub digest
`sha256:81355b1eef171eef1b42152cf209baab03e977c8fe8113a808d3dd8bb1431635`,
was downloaded and inspected locally. Build log reports an eight-target graph
and `BUILD SUCCEEDED`. The built app Info records minimum iOS 27.0 and the
expected simulator-only bundle identity. Successful install is followed by
`simctl launch` reporting PID 20060. This is process launch evidence, not hosted
UI/interaction acceptance. The exported xcresult test tree contains exactly the
five expected passing Swift Testing cases; its local result verifier also passed,
and the original job retained both build/test xcresults. Binary xcresult contents
were not independently decoded on Windows; the runner export and logs are the
reviewed evidence. `process-status.json` records exit 0.

Both real resolved graphs are retained in `resolution.json` with complete pins:
extracted-project lock SHA256
`ccb829ac517d970ef57434d0b71408e2e746d19bea0b43c24522aca6ec6db9c6`;
registered-package lock SHA256
`37e1bea92fa11a36225b4aa28e9039b6b3c107cbdc1b6bb60f20194779bcdeed`.
They resolve the same four root/transitive package revisions listed above.
Native evidence is under ignored
`build/integration-validation-evidence/native-43660671583`. Every retained input
SHA256 matched both the current committed Git blob and working-tree bytes at
review time. This verification of returned evidence is not an additional SDK run.

Composer's separate independently reviewed run
[43658910005](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43658910005)
executed five actual component cases at `3417dc6e` with Xcode 26.6 / SDK 26.5 /
iPhone 17 Pro runtime 26.4.1, targeting iOS 26. Source bytes match `d2126940`.
Artifact digest `sha256:58a836796b0b192a4e286752707e6062a767ecd8ef5dba606e03b0d0ecd92bd9`.
That evidence remains geometry/coordinator scope only, not ChatViewBottom/live
consumers, iOS 27 application, UI, physical device or visual parity acceptance.
It was carried unchanged and not rerun merely for this handoff.

## Open composition and security decisions

The existing concrete `HanlinMiniAppHost`, `HanlinScriptingPlatform` and
`ScriptingPackageCenterViews` are app-only; the Host has a private initializer
and the platform depends on app SwiftData/services. No exported shared provider
exists for `MiniAppsServices(discovery:launch:packageManagement:)`. The necessary
next contract is an existing-implementation provider exposing current canonical
discovery, package refresh/lifecycle, launch destinations for Swift / ScriptUI /
NativeScript / Expo, and existing package-management UI with explicit owned
storage/model context. Noam must agree on any actual Host ABI extraction;
copying these implementations or making the AI app a library is not an option.

URL ingress is not wired to execution. The assembled durable receiver requires
a trusted request source and atomic/integrity-protected persistence, and records
ambiguous interrupted execution as `outcomeUnknown`; production implementations
of those bindings are absent. Its fixture persistence is excluded. The producer
reports 30/30 durable checks (29 Swift cases plus real competing/restarted Windows
processes); those results are writer evidence, not repeated integrator execution
or authenticated OS transport proof. Subsequent independent QA requested two
fixture corrections: interrupted `restoreBefore` recovery must not leave an intent
that later finishes the after-state, and oversized JSON must be rejected before
replacing a readable slot. The Split owner is correcting these; fixture acceptance
and independent cache provenance remain open. These excluded fixture issues do
not establish a production-target compile failure. A URL cannot establish
authority, and the sender ledger is not cross-process exactly-once execution.
No ChatEmbeddedResultHost/schema/A2UI-02 migration or Composer-owned source was
edited by this integrator. A2UI remains the gated prototype with SDK/inline
acceptance unproven. Live migration, credentials, AppGroups/Keychain/CloudKit,
production App ID/signing, main merge and TestFlight remain separately gated.
All 278 historical behavior rows retain their producer NOT_RUN/BLOCKED status.
