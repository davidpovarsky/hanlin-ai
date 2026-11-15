# A2UI test execution manifest

**Current source candidate:** optional actual-chat-host projection plus the
per-result retired-ID policy for the delayed-action/reincarnation P2. The frozen
961 benchmark's34 method identities/assertions are retained; one SDK race method
brings the isolated contract to8 portable +27 SDK =35. All current SDK-backed
compilation/execution is NOT_RUN. Six iOS-only actual-host methods below are
separate and NOT_RUN. Local8 framing scenarios and Windows syntax parsing pass;
7 synthetic verifier checks pass; prior25/benchmark34 case sets cannot satisfy35.
No native job/CI, project wiring or production transport was added/dispatched.

**Latest actual native attempt:** source961 failed compilation in
[run43674291306](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43674291306),
workflow `b34ea9d90104a4787665aa2c3ae1869edcf76ecf`, xcodebuild exit65.
Raw tests.json has0 actual Test Case nodes: all34 cases are NOT_RUN, not3 failed
tests. The compiler reports recursive Testing.require expansion at A2UITests.swift
line507. That nested expression also remained in e1d3d242. The current correction
uses sequential requires inside a returning helper, so no unwrapped strong sink
survives into the caller's intentional sink=nil. Weak/cancel/privacy assertions
and all35/6 current method identities remain. See
[retained failed-build evidence](evidence/native-run-43674291306.json).
Native compilation of the correction remains NOT_RUN. A local macro typecheck
could not proceed because the active Windows Swift invocation cannot import Testing; syntax
parsing and portable scenarios cannot substitute for actual macro expansion.

**Latest passing native source:** [run43668852483](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43668852483)
compiled source `f654ac113447177df3838908c53ce9aa24dc47ff` with the actual
`AI_Hanlin` consumer module, `AI_HLYTests` test module and POC+DEBUG enabled.
All25 actual cases passed, including the privacy canaries. Workflow SHA:
`e1dba14f78e543316dd2f6c9b901cdb558bdb844`. The owner independently verified
all25 raw Test Case nodes,13 source and15 workflow Git byte hashes, the actual
harness manifest and raw lock bytes/hash/full JSON. See the
[consumer-module correction](CONSUMER_MODULE_FIX_2026-11-15.md) and
[retained f654 evidence](evidence/native-run-43668852483.json).
The earlier [c40 failure](evidence/native-run-43662884686.json),
[2bae identifier pass](evidence/native-run-43664698104.json) and
[a43 privacy pass](evidence/native-run-43667371439.json) remain separate.
Earlier NOT_RUN statements below describe source-preparation history; actual
native results supersede them only for the isolated macOS package scope.
Actual iOS app/test-bundle integration, hosted UI and physical iPad remain open.

[איתן | ARCH] [MAIN_SESSION], 2026-11-15, Asia/Hebron. W1-001.

Repository: `davidpovarsky/hanlin-ai`. Worktree:
`C:/Users/DAVID/Code/hanlin-a2ui-wave1-20261115`.
Branch: `codex/hanlin-a2ui-wave1-20261115`.
Starting SHA: `ba7a5ba3ed9e8983cc47df532114079f64bff0b0`.
The handoff commit is supplied in the coordinator message; this file does not
self-reference its own commit hash.

Revision after independent QA of `e7141d55`: both P2 fixes and3 additional
SDK regressions are included. The7 portable scenarios were rebuilt and rerun
after the ingress/policy change (all passed); the shared bounded async-wait
helper also compiled under Swift6 strict concurrency. Enabled syntax parsing
included both `HANLIN_A2UI_POC` and `DEBUG`. SDK execution is still pending,
so this revision does not supersede the independent acceptance decision.

After targeted QA of `6aae92b7`, rejection correlation was tightened: ingress
rejections expose no target ID; only a validated update/delete frame and current
SDK ownership permit a targeted fallback. Rejected creates, unsupported operations
and foreign IDs cannot add presentation entries. Malformed input may replace only
an empty result placeholder. One portable case and one SDK case were added:
**8 portable EXECUTED_PASS, 17 SDK NOT_RUN, 25 authored cases total**. The two
earlier disposal/RPC fixes remain in place. This is a new source handoff, not
independent QA acceptance or enabled SDK verification.

Budget clarification after source review of `3a24003e`: ingress rejection and
the session resource gate are distinct. `sessionBudget` is checked after a
validated Frame; a valid update/delete for a current SDK-owned surface remains
correlated and shows fallback for that same surface. No mutation/deletion is
applied and other surfaces remain untouched. The existing
`surfaceLimitDoesNotRemoveExistingContent()` now fills the real session's exact
byte budget and asserts both update/delete rejection, correlated ID, unchanged
models/data and unaffected second surface. The25 case identities are unchanged;
these added SDK assertions remain NOT_RUN. No policy logic was changed.

Official upstream pin: `https://github.com/a2ui-project/a2ui`, revision
`3ed9601862ecc78027e20ac80ad8b1b98a5d9079`.
Read-only source verification is retained in
[upstream-verification.json](evidence/upstream-verification.json).
No upstream code or package dependency was installed into the app.

## Actual execution

| Check | Result | Scope |
| --- | --- | --- |
| Windows Swift6.3.3 local typecheck via apple-devtools | EXECUTED_PASS | HanlinA2UIIngress.swift only |
| Swift6 strict-concurrency standalone build and execution | EXECUTED_PASS, 8 scenarios | Actual ingress source plus portable cases in A2UITests.swift |
| Windows Swift frontend syntax parse, enabled and feature-off | EXECUTED_PASS | iOS-target parse; Windows sysroot warnings; no Apple import/type/API checking |
| Isolated proof plan and verifier self-checks | EXECUTED_PASS | Current source/fixture hashes,35 selectors;7 synthetic XML/lock checks and prior25/benchmark34 set rejection, no SDK execution |
| Generated SwiftPM manifest API typecheck | EXECUTED_PASS | Windows Swift6.3.3, PackageDescription6.1,24 template lines via stdin; no manifest file or dependency resolution |
| Exact-pin enabled SDK compilation at c40e617b | EXECUTED_PASS | Actual native run43662884686; isolated consumer, no app wiring |
| Exact-pin SDK cases at c40e617b | FAILED, 17 cases | All executed; common valid-fixture load rejection |
| Exact-pin enabled compilation/cases at2bae5a3e | EXECUTED_PASS, 25 cases | Run43664698104; identifier correction only, privacy P2 not accepted |
| Exact-pin enabled compilation/cases at a43f1563 | EXECUTED_PASS, 25 cases | Run43667371439; privacy canaries executed, old consumer module |
| Actual AI_Hanlin consumer-name proof at f654ac11 | EXECUTED_PASS, 25 cases | Run43668852483; actual AI_Hanlin consumer and AI_HLYTests module |
| Result-owner benchmark961 native build | FAILED, exit65 | Run43674291306; recursive require macro,0 actual case nodes, all34 NOT_RUN |
| Local Swift Testing macro typecheck | UNAVAILABLE | Windows import Testing fails; no macro or SDK typecheck result |
| Current SDK compilation/cases | NOT_RUN, 35 authored cases | Changed source; f65425-case and96134-case outcomes do not cover this correction |
| Current iOS host compilation/cases | NOT_RUN, 6 authored cases | AI_HLYTests/A2UIHostedResultTests.swift; excluded from macOS harness |
| Inline app integration / hosted RTL / device acceptance | NOT_RUN | No host seam edits or UI automation authorized |

The8 local scenarios execute through the standalone runner, not XCTest or
Swift Testing discovery. Each uses the same check function as its project
Swift Testing wrapper. Output is in
[portable-results.txt](evidence/portable-results.txt). This does not assert
a native result by itself. Run43668852483 independently contains all8 portable
and17 SDK Swift Testing case nodes. Actual c40,2bae,a43 and f654 results are
recorded separately above. No upstream conformance suite or iOS simulator result
is claimed.

The initial strict-concurrency compile caught a non-Sendable function-array
declaration in the portable harness. Its immutable scenario closures were
corrected to `@Sendable`; the rebuilt harness exited0 and executed all7 cases.

## Portable cases: 8 executed

All case definitions are in `AI_HLYTests/A2UITests.swift`, suite
`A2UIIngressTests`. Source under test:
`AI_HLY/Downstream/ChatPresentation/A2UI/HanlinA2UIIngress.swift`.

| Case | Actual result |
| --- | --- |
| acceptsOfficialV1FixtureFrames() | EXECUTED_PASS |
| rejectsMalformedAndAmbiguousFrames() | EXECUTED_PASS |
| rejectsOtherProtocolVersions() | EXECUTED_PASS |
| preservesUnicodeSurfaceIdentity() | EXECUTED_PASS |
| boundsUTF8MessageAndComponentBatch() | EXECUTED_PASS |
| rejectsRPCAndUnnegotiatedCatalogs() | EXECUTED_PASS |
| rejectedEnvelopesNeverExportSurfaceCorrelation() | EXECUTED_PASS |
| componentValidationRemainsWithSDK() | EXECUTED_PASS |

These checks deliberately accept the framing of malformed *components* so
their actual schema validation remains the upstream SDK's responsibility.
They do not simulate two-way binding, Node identity or native rendering.

Reproduce on Windows from the allocated worktree (PowerShell):

```powershell
py -3 C:/Users/DAVID/Code/apple-devtools/src/apple_devtools.py apple-typecheck --path AI_HLY/Downstream/ChatPresentation/A2UI/HanlinA2UIIngress.swift --local --json

swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library `
  -D HANLIN_A2UI_PORTABLE_RUNNER `
  AI_HLY/Downstream/ChatPresentation/A2UI/HanlinA2UIIngress.swift `
  AI_HLYTests/A2UITests.swift `
  -o docs/a2ui/evidence/a2ui-portable.exe
if ($LASTEXITCODE -ne 0) { throw 'Portable compile failed' }
& ./docs/a2ui/evidence/a2ui-portable.exe
if ($LASTEXITCODE -ne 0) { throw 'Portable execution failed' }
```

The Python entry point above is the installed apple-devtools implementation;
the local `python` alias did not select the configured interpreter, so `py -3`
was used explicitly. No replacement Apple tooling was written. Remove the
three generated `.exe`, `.exp`, `.lib` files after reproducing; no binaries
are committed. Missing fixtures cause an error, not skipped success.

Actual enabled-flag syntax-only check:

```powershell
swiftc -frontend -parse -D HANLIN_A2UI_POC -D DEBUG `
  AI_HLY/Downstream/ChatPresentation/A2UI/HanlinA2UIIngress.swift `
  AI_HLY/Downstream/ChatPresentation/A2UI/HanlinA2UISession.swift `
  AI_HLY/Downstream/ChatPresentation/A2UI/HanlinA2UIResultView.swift `
  AI_HLYTests/A2UITests.swift
```

## Exact-pin SDK cases: 27 authored, current candidate NOT_RUN

All case definitions are in `AI_HLYTests/A2UITests.swift`, suite
`A2UISDKTests`. They compile only with `HANLIN_A2UI_POC`, in the app and test
targets, and the real pinned upstream products linked. The standalone
`HANLIN_A2UI_PORTABLE_RUNNER` configuration never executes these cases.
The pending-call disposal regression also requires `DEBUG` in both consumers;
the actual package proof and proposed app command explicitly define it. Require its case node,
rather than accepting a smaller discovered count.

| Case | Obligation | Actual result |
| --- | --- | --- |
| parsesAndRendersTextCardInputButton() | Official parser/model and renderer-builder availability | PASS at f654; current NOT_RUN |
| nativeInputBindingWritesAndReadsOfficialModel() | Native TextField writes; agent updates read back | PASS at f654; current NOT_RUN |
| stableIDsAndNodeIdentityAcrossUpdates() | Upstream node identity through model/component updates | PASS at f654; current NOT_RUN |
| malformedAndUnknownContentFallsBackAndRecovers() | Fallback routing and subsequent valid recovery | PASS at f654; current NOT_RUN |
| officialSchemasRejectInvalidTextInputButton() | Keep4 negatives and invalid_identifier; canary component ID absent from local/callback diagnostic renderings | PASS at f654; current NOT_RUN |
| independentSurfacesKeepModelsSeparate() | Separate models and fallback per surface | PASS at f654; current NOT_RUN |
| independentOwnersCanReuseWireSurfaceID() | Separate processors for separate result owners | PASS at f654; current NOT_RUN |
| deleteDisposesAndRecreateStartsWithNewIdentity() | Surface deletion/recreation lifecycle | PASS at f654; current NOT_RUN |
| closeRejectsLateFramesAndDisposesSurfaces() | Owner disposal and late ingress | PASS at f654; current NOT_RUN |
| buttonEventUsesCurrentBoundValue() | Official action context after a user edit | PASS at f654; current NOT_RUN |
| hebrewFixtureRetainsBindingsInRTLComposition() | Hebrew model and RTL environment composition | PASS at f654; current NOT_RUN |
| surfaceLimitDoesNotRemoveExistingContent() | Four-surface and exact byte-budget limits; update/delete correlated only to the owned target; preserve models/data | PASS at f654; current NOT_RUN |
| rejectedSurfaceIDsCannotGrowFallbackStorageWithoutBound() | Bound rejected surface bookkeeping | PASS at f654; current NOT_RUN |
| unknownFunctionsAndUnsolicitedResponsesCannotEnableRPC() | Keep no-RPC checks; canary function/argument identifiers absent from local and roundtrip callback diagnostics | PASS at f654; current NOT_RUN |
| closeRevokesQueuedAndRetainedActionCallbacks() | Revoke queued delivery and retained SDK actions; repeat close | PASS at f654; current NOT_RUN |
| closeCancelsSeededInFlightSDKCallPromptlyAndOnlyOnce() | Real pending SDK RPC cancels before2s rather than30s timeout; later calls DISPOSED | PASS at f654; current NOT_RUN |
| unsupportedOperationsCannotCreateOrRerouteOwnedSurfaceFallbacks() | Missing, blank, whitespace, overlong/UTF-8/60KB IDs, other-owner and current IDs cannot route fallback or change live models | PASS at f654; current NOT_RUN |
| transientOwnerLookupKeepsWireIDsIndependent() | Exact identity, side-effect-free lookup, real SDK binding/node isolation and no replay | NOT_RUN |
| transientReceiveRejectsWrongIdentityAndSequence() | Run/result/call/generation mismatch, duplicate/out-of-order/partial-frame rejection | NOT_RUN |
| sealedResultRetainsModelsAndRevokesActions() | Queued/retained real SDK actions revoked; model/node identity retained; input sealed | NOT_RUN |
| sealingRunDoesNotRevokeOtherRun() | Weak typed sink gets only the other live owner's real Button event | NOT_RUN |
| replacementRevokesOldGenerationBeforeNewDelivery() | Old owner closed; stale key cannot lookup/receive/replace/discard successor | NOT_RUN |
| endingResultCancelsOwnedReceiveTask() | Both seal and discard cancel a real receiver before30s and reject its late SDK frame | NOT_RUN |
| presentationCopiesDoNotOwnDiscard() | Inline/expanded projection copies share models; releasing one copy does not close; explicit discard does | NOT_RUN |
| eventSinkIsWeakAndCannotKeepAuthorityAlive() | Weak sink released before queued/retained SDK action delivery | NOT_RUN |
| deletedSurfaceDropsQueuedOwnedEvents() | Real SDK delete removes membership and queued/retained callbacks cannot escape | NOT_RUN |
| retiredSurfaceCannotReanimateQueuedEventsInSameResult() | Queue SDK action, delete/recreate before delivery; reject host reuse, permit unowned-ID/other-owner/fresh-generation actions | NOT_RUN |

The three lifecycle/RPC cases address the2 P2 findings in the independent review of
`e7141d55`; they exercise official SDK objects, not source-string matching.
The disposal test temporarily installs a listener through a Debug-only test
hook to seed a real in-flight call, observes its request, closes the session,
and requires `CANCELLED` before2s. A late call must return `DISPOSED`. Both
close regressions check repeated-close safety and a bounded100ms window with
no callbacks after revocation. These assertions executed in the retained native
package proofs. No normal session installs an outbound RPC listener.
The Button regression now waits for the actual callback with a2s deadline;
it no longer assumes `Task.yield()` completes asynchronous delivery.

The correlation regression sends27 unsupported/RPC envelopes over two live
surfaces and a separate result owner. It checks unchanged model/node identity,
data, surface IDs and fallback state, including an existing correctly targeted
SDK-validation fallback. The portable case executes the same generated inputs
against real ingress and checks rejection classification and absent target IDs;
it does not simulate SDK ownership. Existing missing-target and capacity tests
now require no phantom fallback entries. Malformed-content coverage retains an
empty-result fallback and verifies malformed input cannot hide live content.

`Surface.render` constructs a native view builder result; it is not a hosted
screen assertion. The RTL case likewise constructs an RTL/accessibility-size
composition and checks Hebrew bindings. It does not measure layout, focus,
VoiceOver order, keyboard behavior or text clipping. Those hosted UI checks
are separate open acceptance gates.

## Actual iOS host cases: 6 authored, NOT_RUN

AI_HLYTests/A2UIHostedResultTests.swift imports AI_Hanlin and is explicitly gated by
HANLIN_A2UI_POC and os(iOS). The suite is A2UIHostedResultTests. It uses owned
UIWindow/UIHostingController instances, actual ChatBubbleView and result host,
real SDK fixtures/models/native input, with bounded waits and explicit cleanup.
It is not copied into the isolated macOS harness. No iOS API typecheck, app/test
bundle execution or physical-device result is claimed.

| Case | Obligation | Actual result |
| --- | --- | --- |
| projectionSourceRequiresExactRegisteredIdentityAndGeneration() | Full identity, pure lookup, duplicate/stale source rejection; no automatic replacement following | NOT_RUN |
| chatBubblePreservesDisplayGateAndDoesNotInferProjectionFromPayload() | Actual caller shows registered result without persisted payload; summary-off/nil-source/foreign-run/wrong-kind stay hidden | NOT_RUN |
| actualHostInputBindsWithoutReplayAcrossBodyUpdates() | Hosted native text input updates real SDK model; redraw preserves identity and ordered update still works | NOT_RUN |
| sealedHostRetainsVisibleModelAndDisablesNativeInput() | Completed model remains visible, native input disabled and old SDK actions revoked | NOT_RUN |
| presentedProjectionDismissalAndHostRemovalDoNotDiscardOwner() | Actual UIKit presentation/dismissal and removal preserve shared owner until explicit discard | NOT_RUN |
| nilAndMismatchedProjectionKeepExistingNativeFallbacks() | Existing modern/legacy native content remains nonempty and does not mount unrelated SDK controls | NOT_RUN |

The presentation test does not activate ChatEmbeddedResultHost's expansion button;
its actual sheet/full-screen controls, RTL, Dynamic Type and accessibility/device
acceptance remain open. The mount's default environment source is nil and no
production frame/event transport or run-continuation policy is supplied.

## App build/test command — proposed, NOT_RUN

For a consumer without app wiring, use [EXACT_PIN_PROOF_ROUTE.md](EXACT_PIN_PROOF_ROUTE.md)
and `prepare_exact_pin_proof.py`. The planner copies actual source/fixtures
without rewriting them, enables both SDK/Debug gates, verifies the resolved pin
and requires25 executed cases. Local planning and seven synthetic verifier
self-checks do not run SDK code. Tomer's actual c40 proof failed17 cases and
its2bae,a43 and f654 follow-ups passed25. The f654 run also verifies the actual
AI_Hanlin consumer name.
The app command below remains a separate future integration route.

Prerequisites: explicit serialized Apple-slot approval, stable Xcode with the
project's iOS27 SDK, approved isolated dependency wiring at the exact revision,
and the four products in README linked to the actual consumers. Stage the
fixtures in the test bundle (folder or flat resources supported); source-path
fallback is only for host-based execution with the checkout present. Keep
`HANLIN_A2UI_PORTABLE_RUNNER` undefined. Do not lower the deployment target.

After those prerequisites, on macOS with an existing bootable simulator ID:

```bash
# Record Xcode/SDK identity and the post-resolution Package.resolved first.
xcodebuild -project AI_HLY.xcodeproj -scheme AI_HLY \
  -resolvePackageDependencies

python3 - <<'PY'
import json
from pathlib import Path
lock = json.loads(Path('AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())
pins = [p for p in lock['pins'] if p.get('identity') == 'a2ui']
assert len(pins) == 1, 'Missing or ambiguous official a2ui resolution'
assert pins[0]['location'] == 'https://github.com/a2ui-project/a2ui'
assert pins[0]['state']['revision'] == '3ed9601862ecc78027e20ac80ad8b1b98a5d9079'
PY
# Stop if resolution or the pin assertion fails; retain the complete lock hash.
xcodebuild -project AI_HLY.xcodeproj -scheme AI_HLY \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -resultBundlePath "$A2UI_RESULT_BUNDLE" \
  '-only-testing:AI_HLYTests/A2UIIngressTests' \
  '-only-testing:AI_HLYTests/A2UISDKTests' \
  'OTHER_SWIFT_FLAGS=$(inherited) -D HANLIN_A2UI_POC -D DEBUG' \
  CODE_SIGNING_ALLOWED=NO test
```

The project/scheme already exist. This is a future integrator command, not an
executed action or permission to edit shared files now. An isolated exact-pin
SDK harness may avoid the full app's Runtime dependency closure, but creating
or wiring a shared product package/project is outside this lease. The prepared
temporary-consumer recipe above creates no manifest in the product checkout
and runs only later on an approved Apple host; retain these same17 SDK cases
and fixtures.

Retain resolved root/transitive revisions, compiler diagnostics and actual25
executed case identities. A green process with zero/omitted tests or the flag
off is **not** a pass. Select the suites as above, or exact Swift Testing method
signatures including `()`, and inspect xcresult case nodes. Never promote this
portable run to SDK/app/physical-device verification.

## Fixture identities

All fixtures live under `AI_HLYTests/A2UIFixtures/`. Exact byte counts and SHA256
values are retained in [fixture-identities.json](evidence/fixture-identities.json).

| Fixture | Purpose |
| --- | --- |
| form.jsonl | 3 ordered messages, 6 components, Card/Column/Text/TextField/Button, @path |
| update.jsonl | Model edit and same-ID component update |
| rtl.jsonl | Same native composition with Hebrew strings, separate surface ID |
| unknown.jsonl | Unknown component fallback |
| unknown-function.jsonl | Unknown function binding/action-context requests; no RPC authorization |
| invalid-components.jsonl | Invalid Text, TextField and Button schema payloads |
| malformed.txt | Truncated JSON envelope |

No fixtures are production network responses or claimed user sessions. No
secrets or private source artifacts are included.
