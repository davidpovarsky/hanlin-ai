# A2UI test execution manifest

**Latest real native result:** [run43667371439](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43667371439)
compiled `a43f1563` against official pin3ed9601 with POC+DEBUG enabled and
passed all25 actual cases, including the privacy canaries. The current
[consumer-module correction](CONSUMER_MODULE_FIX_2026-11-15.md) matches the
real AI_Hanlin target without changing those25 identities; its native proof
is pending. The earlier c40 failure and2bae identifier pass remain retained.
Read [identifier evidence](NATIVE_VALIDATION_FIX_2026-11-15.md),
[failed c40 outcomes](evidence/native-run-43662884686.json) and
[passing2bae outcomes](evidence/native-run-43664698104.json) and
[passing a43 outcomes](evidence/native-run-43667371439.json).
Earlier NOT_RUN statements below describe source-preparation history; they do
not override actual native results or imply the consumer-name correction passed.

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
| Enabled-flag Swift frontend syntax parse | EXECUTED_PASS | All3 source files and test file; no import/type/API checking |
| Isolated proof plan and verifier self-checks | EXECUTED_PASS | Current source/fixture hashes,25 selectors;7 synthetic XML/lock checks, no SDK execution |
| Generated SwiftPM manifest API typecheck | EXECUTED_PASS | Windows Swift6.3.3, PackageDescription6.1,24 template lines via stdin; no manifest file or dependency resolution |
| Exact-pin enabled SDK compilation at c40e617b | EXECUTED_PASS | Actual native run43662884686; isolated consumer, no app wiring |
| Exact-pin SDK cases at c40e617b | FAILED, 17 cases | All executed; common valid-fixture load rejection |
| Exact-pin enabled compilation/cases at2bae5a3e | EXECUTED_PASS, 25 cases | Run43664698104; identifier correction only, privacy P2 not accepted |
| Exact-pin enabled compilation/cases at a43f1563 | EXECUTED_PASS, 25 cases | Run43667371439; privacy canaries executed, old consumer module |
| Actual AI_Hanlin consumer-name proof | NOT_RUN | Same25-case verifier with matching test import/recipe module |
| Inline app integration / hosted RTL / device acceptance | NOT_RUN | No host seam edits or UI automation authorized |

The8 local scenarios execute through the standalone runner, not XCTest or
Swift Testing discovery. Each uses the same check function as its project
Swift Testing wrapper. Output is in
[portable-results.txt](evidence/portable-results.txt). This does not assert
that8 Swift Testing case nodes exist in a new corrected-source xcresult.
Actual c40,2bae and a43 results are recorded separately above. No consumer-name
SDK pass, upstream conformance suite or iOS simulator result is claimed.

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

## Exact-pin SDK cases: 17 PASS at a43; consumer-name correction pending

All case definitions are in `AI_HLYTests/A2UITests.swift`, suite
`A2UISDKTests`. They compile only with `HANLIN_A2UI_POC`, in the app and test
targets, and the real pinned upstream products linked. The standalone
`HANLIN_A2UI_PORTABLE_RUNNER` configuration never executes these cases.
The pending-call disposal regression also requires `DEBUG` in both consumers;
the proposed enabled command explicitly defines it. Require its case node,
rather than accepting a smaller discovered count.

| Case | Obligation | Actual result |
| --- | --- | --- |
| parsesAndRendersTextCardInputButton() | Official parser/model and renderer-builder availability | PASS at a43; naming NOT_RUN |
| nativeInputBindingWritesAndReadsOfficialModel() | Native TextField writes; agent updates read back | PASS at a43; naming NOT_RUN |
| stableIDsAndNodeIdentityAcrossUpdates() | Upstream node identity through model/component updates | PASS at a43; naming NOT_RUN |
| malformedAndUnknownContentFallsBackAndRecovers() | Fallback routing and subsequent valid recovery | PASS at a43; naming NOT_RUN |
| officialSchemasRejectInvalidTextInputButton() | Keep4 negatives and invalid_identifier; canary component ID absent from local/callback diagnostic renderings | PASS at a43; naming NOT_RUN |
| independentSurfacesKeepModelsSeparate() | Separate models and fallback per surface | PASS at a43; naming NOT_RUN |
| independentOwnersCanReuseWireSurfaceID() | Separate processors for separate result owners | PASS at a43; naming NOT_RUN |
| deleteDisposesAndRecreateStartsWithNewIdentity() | Surface deletion/recreation lifecycle | PASS at a43; naming NOT_RUN |
| closeRejectsLateFramesAndDisposesSurfaces() | Owner disposal and late ingress | PASS at a43; naming NOT_RUN |
| buttonEventUsesCurrentBoundValue() | Official action context after a user edit | PASS at a43; naming NOT_RUN |
| hebrewFixtureRetainsBindingsInRTLComposition() | Hebrew model and RTL environment composition | PASS at a43; naming NOT_RUN |
| surfaceLimitDoesNotRemoveExistingContent() | Four-surface and exact byte-budget limits; update/delete correlated only to the owned target; preserve models/data | PASS at a43; naming NOT_RUN |
| rejectedSurfaceIDsCannotGrowFallbackStorageWithoutBound() | Bound rejected surface bookkeeping | PASS at a43; naming NOT_RUN |
| unknownFunctionsAndUnsolicitedResponsesCannotEnableRPC() | Keep no-RPC checks; canary function/argument identifiers absent from local and roundtrip callback diagnostics | PASS at a43; naming NOT_RUN |
| closeRevokesQueuedAndRetainedActionCallbacks() | Revoke queued delivery and retained SDK actions; repeat close | PASS at a43; naming NOT_RUN |
| closeCancelsSeededInFlightSDKCallPromptlyAndOnlyOnce() | Real pending SDK RPC cancels before2s rather than30s timeout; later calls DISPOSED | PASS at a43; naming NOT_RUN |
| unsupportedOperationsCannotCreateOrRerouteOwnedSurfaceFallbacks() | Missing, blank, whitespace, overlong/UTF-8/60KB IDs, other-owner and current IDs cannot route fallback or change live models | PASS at a43; naming NOT_RUN |

The three lifecycle/RPC cases address the2 P2 findings in the independent review of
`e7141d55`; they exercise official SDK objects, not source-string matching.
The disposal test temporarily installs a listener through a Debug-only test
hook to seed a real in-flight call, observes its request, closes the session,
and requires `CANCELLED` before2s. A late call must return `DISPOSED`. Both
close regressions check repeated-close safety and a bounded100ms window with
no callbacks after revocation. This is authored regression coverage, **not
executed SDK proof**. No normal session installs an outbound RPC listener.
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

## Enabled build/test command — proposed, NOT_RUN

For a consumer without app wiring, use [EXACT_PIN_PROOF_ROUTE.md](EXACT_PIN_PROOF_ROUTE.md)
and `prepare_exact_pin_proof.py`. The planner copies actual source/fixtures
without rewriting them, enables both SDK/Debug gates, verifies the resolved pin
and requires25 executed cases. Local planning and seven synthetic verifier
self-checks do not run SDK code. Tomer's actual c40 proof failed17 cases and
its2bae and a43 follow-ups passed25. Only consumer-name verification is NOT_RUN.
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
