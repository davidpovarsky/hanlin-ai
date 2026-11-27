# Original Hanlin SDK obligations on a hosted Apple runner

This controller is a **source-only preparation until an actual run is separately
authorized and retained**. Local Python controls do not qualify Swift compilation,
native execution or an application. No workflow was dispatched while preparing it.

It extends the registered `build-ios26-unsigned-ipa.yml` dispatcher with one
closed selector, preserving all 27 old job conditions except excluding that new
selector from the two legacy SDK jobs. The existing 25 dispatch inputs remain.
The existing `composer_expected_sha` is also the explicit immutable SDK source
input for this selector; other Composer routes retain their old behavior.
The controller checkout SHA and the tested original source SHA are recorded
separately. No latest branch, current default source or unreviewed full SHA is
accepted. Every admitted source has its exact reviewed Git tree in
`obligations.json`, and 19 protected original test/manifest/lock/fixture/helper
blobs must still match the reviewed reference.

## Exact source and selection

The reference is `davidpovarsky/hanlin-ai` at
`20a1e6fa33ed261ba11e83a0b84a157029822e5e`, tree
`14e860ce3f7d2b8623085f16d99d34b8b347a48c`. A later source may be added to the
reviewed source table only by an explicit source review and immutable tree
entry. Its actual source archive, all selected file hashes and resolved package
revisions are then retained; a historical result is not relabeled.

| Original package / test module | Closed selector | Required actual result |
| --- | --- | --- |
| HanlinAgentSDK / HanlinAgentCoreTests | AgentSessionTests/stop | 5 named methods, 7 cases; both `false` and `true` arguments in each two-case method |
| HanlinPresentationSDK / HanlinChatUITests | ChatCodeFencePayloadRetentionTests | 6 named ownership/quota methods |
| HanlinPlatform / HanlinScriptExtensionsTests | HanlinDualWidgetEnginesTests/(installedProgramPreparationAndActionMeasurements\|v1ShadowProjectsHistoricalFieldsWithoutLosingCurrentMetadata) | 2 named original prepared-program/historical-reader methods |

Only those 13 methods / 15 cases execute. SwiftPM may compile the original
package's complete test target graph to produce its real test bundle. Original
modules, tests, package manifests, exact JSON vendor and fixture resources are
retained. No sliced proof module, target renaming, conditional test removal,
fake host receipt or copied implementation is introduced.

The original `HanlinChatUI` scheme is then built for the generic iOS Simulator
destination with signing disabled. This is an actual product compile, with its
original package graph, and no simulator launch. It is not UI runtime evidence.
The 48 MiB / 64 ownership tests concern retained UTF-8 payload bytes and leases;
they do not measure process or WebKit resident memory.

The Widget preparation case uses the five original archives under
`Fixtures/Widgets`. It emits its own actual original-program measurements and
the controller verifies each archive hash. Those temporary installations are
not five configured OS widgets. The original frozen LegacyWidgetStore fixture
remains part of the original package target. The earlier `16b79` historical
projection proof and the original `385289` cancellation proof retain their own
source scope; the new run, if performed, produces evidence only for the chosen
source and the listed cases. It does not rerun all 79 Widget tests.

The reviewed selective successor is also explicitly admitted:
`caa0dac32afa18e58bba55fb4f0fdd262f181835`, tree
`3c1f540131152aacc87a2249e0d938cb592a852c`, parent `20a1e6fa`.
Its Presentation tree is `ae9c38acacb2da5824d0c36e1f9d3923597dd515`;
the other five SDK/runtime package trees and locks remain identical to the
reference. It adds three reviewed shared scrolling changes and one locale row
while preserving all 1,294 old locale entries, plus six additive App/UIKit
regressions and source evidence. The controller records this successor's real
source identity; it does not call it the `20a` source. On macOS, UIKit-gated
`ChatScrollViewHandle` and `HanlinFollowLatestOverlay` are excluded. The separate
iOS `HanlinChatUI` product build includes those files, while Anytype application
integration and the six original App/UIKit tests remain separate requirements.

## Proposed dispatch inputs; no dispatch performed

Use the registered workflow on the reviewed **controller branch/ref**, and set:

```json
{
  "target_validation_group": "agent_sdk_session_only_proof",
  "exact_test_selector": "HanlinSDKCancellationQuotaWidgets",
  "composer_expected_sha": "caa0dac32afa18e58bba55fb4f0fdd262f181835",
  "runtime_publish_release": false,
  "testflight_upload": false,
  "runtime_bundle_only": false,
  "full_validation": false,
  "force_clean_build": false,
  "measure_warm_rebuild": false
}
```

All other boolean inputs must be false, and other selector/artifact/source fields
must be empty. The workflow's existing `runtime_publish_release` default is
true, so this route deliberately requires an explicit false value. The closed
group suppresses the ordinary planner, app, runtime bundle and upload jobs.
The controller also independently refuses contradictory event inputs. A manual
newer run does not cancel another accepted run's source/evidence work.

## Dependency and compiler closure

The controller materializes only three original packages, the Widget fixtures,
the published App lock and the two original vendor/Xcode helpers from the exact
source. The full selected source archive and Git blob/SHA-256 inventory are
retained before compilation. No source file or original package target is
edited. Actual package resolution and builds use private runner-temporary roots.

AgentSDK and Platform have original package locks. Presentation has **no
package-local lock at the reference source**. Its private resolver is seeded
with the unmodified published App lock, then the real resolver writes the
actual package lock. This seed is explicitly labeled and never called a
previously resolved Presentation graph. Before any compile, every actual pin
and Git checkout must match the selected source's published lock, including
its full revision and repository identity. The required direct dependencies
must be present. An unknown/new revision fails before compilation. Actual
locks and all checkout HEAD/cleanliness records are retained and rechecked.
Swift tests use `--force-resolved-versions --skip-update`; Xcode uses its locked
package-version options. Resolver failures remain failed evidence, not a reason
to change pins or remove an original dependency.

The original stable-Xcode selector must find Xcode 27 or later; beta fallback is
not introduced. The controller requires a genuine GitHub-hosted Darwin ARM64
runner and records actual Xcode, Swift, macOS and simulator SDK versions. The
source preparation performs none of these Apple actions locally or on the
owner's shared Scaleway Mac.

## Evidence and bounded execution

The hosted job admits at least 20 GiB of free space initially and checks a 2 GiB
floor before each new compile phase. These are declared admission bounds, not
an observed peak. Each native subprocess has a timeout and the controller has
a 70-minute command budget inside the 90-minute job, reserving time for
preservation. A timed-out process group is terminated and joined before the
failure is finalized. Every command retains its original PGID and positively
checks that group is absent after the leader exits. Remaining descendants get
bounded TERM/KILL only in that original group; abnormal cleanup remains a
failure even when it succeeds, preserving the leader's actual exit code. A
surviving group prevents copying potentially changing products. This proves
custody of the command's POSIX group, not absence of unrelated OS/XPC daemons.
No unrelated process/cache is touched.

All commands, raw stdout/stderr, source/pin identities, original result bundle,
actual named Swift Testing results and failures are retained under
`build/sdk-original-obligations/<run>-<attempt>`. Actual test bundles, resources,
compiled products and dSYMs are archived from both ordinary SwiftPM and the
original Apple SwiftBuild Products layouts. A successful result requires every
executed suite's original test product and the iOS product archive to be
preserved. Compiler intermediates are not substituted for these products.
The artifact is `hanlin-original-sdk-<run>-<attempt>`, retained for 30 days.

Named method/case parsing rejects zero tests, absent/duplicated parameter cases,
skips, issues, wrong suites and extra methods. Raw output is always the original
evidence; the JSON interpretation is explicitly derived. The `original-385`
terminal excerpt in `Fixtures` is a byte-exact historical **parser unit-test
fixture only**. It cannot make this new source pass or replace an actual run.
Local controller tests never invoke Swift, Xcode, a simulator or native APIs.

## Fixed continuation of original run45954793309

The separate closed selector `HanlinSDKQuotaWidgetsAfterAgent45954793309`
admits only source `caa0dac32afa18e58bba55fb4f0fdd262f181835`. It retrieves
the fixed original run45954793309/attempt1, controller35b504, job140358668934
and artifact15178855568 using the workflow's existing Actions read token.
The token is passed only to those bounded `gh api` commands, never to the
compiler/test child environment. The original ZIP is exactly119169729 bytes,
SHA-256 `266836f5a18a7977489cbd1e4624ff06b6ccc8d0bff872657ffc7885f0de4ca3`.
No arbitrary prior run, uploaded receipt, artifact ID or source is accepted.

That original workflow is still **failed**. Its actual Swift command exited0
and all five Stop methods/seven cases passed; the controller then miscounted
four individual case-success lines as additional methods. The corrected parser
separates method and case records, admits only the observed optional
`(Swift.Bool)` annotation, and rejects partial/duplicate/foreign case output.
The exact source-declared suite display names are bound to the two remaining
protected original test files. A display label cannot select another suite.

Before skipping any Agent execution, the continuation verifies the original
run/job outcomes, exact ZIP and14 fixed member hashes, the full1005-file
original Git/archive inventory against the newly admitted caa0 source,
34 actual command/log/process-group receipts, six actual clean dependency
checkouts before and after the test, the named5/7 terminal, and all203 retained
compiled product files. The original414MB product archive and failed result
remain available byte-for-byte. No archived binary or controller is executed.
The local fixture/admission replays are control verification, not new Swift
tests. The original controller stopped before its final all-suite source
recheck; that fact is stated in the reuse admission rather than invented.

Only after that admission does the new run skip the Agent build/test and
execute payload6, Widget2 and the iOS `HanlinChatUI` product build. These phases
retain their own actual source/dependency/compiler/process/output evidence.
The final product-preservation gate requires both the admitted original Agent
products and all newly compiled remaining products. The complete original ZIP
and the original failed result are not converted into a successful prior run.

Original Agent toolchain scope is **Xcode27.2 / Swift6.4.2 / Testing2403 /
macOS27.0.1**. The continuation records its own stable-helper-selected toolchain.
Neither result proves an Xcode27.0 binary compatibility claim or the separately
compiled Anytype App, original NativeScript handler, or six App/UIKit runtime
scrolling regressions.

## Separate original NativeScript and App/UIKit routes

The original explicit-handler test remains:

`AI_HLYTests/NativeScriptRuntimeWireTests/nativeScriptActionDeclarationsPreserveRegisteredJavaScriptState`

At the reference source its actual file blob is
`ab113355ec8b87b34bc07216806b08f005dc1c36`. It starts the real
`HanlinNativeScriptSession`, registers the actual JavaScript handler, checks
preserved state across requests and refuses a manufactured result for an
unhandled action. It cannot be selected by the three package filters above.

The existing registered main dispatcher supports that original app test with
`target_validation_group=exact_test_selector` and the exact selector above.
`simulator_e2e_only` must be **false**: the original planner rejects that mode
for an app unit test because it suppresses its execution. `nativescript_poc_only`
and `full_validation` must also be false. This separate route still requires the
complete original app/native graph and compatible verified RuntimeCore and
NativeScript resources, including an admitted runtime artifact when required.
It must retain the actual prepared source and all upstream/preparation changes;
an unrelated SDK result or absent artifact cannot satisfy that gate. No native
app dispatch is added or performed here.

The six App/UIKit scrolling regressions in `AI_HLYTests/ChatAutoFollowTests`
and `ChatScrollViewHandleTests` also import the original `AI_Hanlin` app module.
They are not counted by this macOS package route. A later reviewed scrolling
source is compiled as part of the original iOS `HanlinChatUI` product, but those
six original app runtime methods still need their separate real-host selection.
Anytype Save/Stop/account replacement, a full companion product, physical
devices, Release signing, IPA and TestFlight remain outside this controller.
