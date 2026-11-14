# A2UI test execution manifest

[איתן | ARCH] [MAIN_SESSION], 2026-11-15, Asia/Hebron. W1-001.

Repository: `davidpovarsky/hanlin-ai`. Worktree:
`C:/Users/DAVID/Code/hanlin-a2ui-wave1-20261115`.
Branch: `codex/hanlin-a2ui-wave1-20261115`.
Starting SHA: `ba7a5ba3ed9e8983cc47df532114079f64bff0b0`.
The handoff commit is supplied in the coordinator message; this file does not
self-reference its own commit hash.

Official upstream pin: `https://github.com/a2ui-project/a2ui`, revision
`3ed9601862ecc78027e20ac80ad8b1b98a5d9079`.
Read-only source verification is retained in
[upstream-verification.json](evidence/upstream-verification.json).
No upstream code or package dependency was installed into the app.

## Actual execution

| Check | Result | Scope |
| --- | --- | --- |
| Windows Swift6.3.3 local typecheck via apple-devtools | EXECUTED_PASS | HanlinA2UIIngress.swift only |
| Swift6 strict-concurrency standalone build and execution | EXECUTED_PASS, 7 scenarios | Actual ingress source plus portable cases in A2UITests.swift |
| Enabled-flag Swift frontend syntax parse | EXECUTED_PASS | All3 source files and test file; no import/type/API checking |
| Official exact-pin enabled SDK compilation | NOT_RUN | No dependencies wired; remote slot reserved for Runtime |
| Official SDK/SwiftUI cases | NOT_RUN, 13 cases | Flag-gated cases listed below |
| Inline app integration / hosted RTL / device acceptance | NOT_RUN | No host seam edits or UI automation authorized |

The7 local scenarios execute through the standalone runner, not XCTest or
Swift Testing discovery. Each uses the same check function as its project
Swift Testing wrapper. Output is in
[portable-results.txt](evidence/portable-results.txt). This does not assert
that7 Swift Testing case nodes exist in an xcresult. No Xcode run, CI run,
upstream conformance suite or simulator result is claimed.

The initial strict-concurrency compile caught a non-Sendable function-array
declaration in the portable harness. Its immutable scenario closures were
corrected to `@Sendable`; the rebuilt harness exited0 and executed all7 cases.

## Portable cases: 7 executed

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
swiftc -frontend -parse -D HANLIN_A2UI_POC `
  AI_HLY/Downstream/ChatPresentation/A2UI/HanlinA2UIIngress.swift `
  AI_HLY/Downstream/ChatPresentation/A2UI/HanlinA2UISession.swift `
  AI_HLY/Downstream/ChatPresentation/A2UI/HanlinA2UIResultView.swift `
  AI_HLYTests/A2UITests.swift
```

## Exact-pin SDK cases: 13 NOT_RUN

All case definitions are in `AI_HLYTests/A2UITests.swift`, suite
`A2UISDKTests`. They compile only with `HANLIN_A2UI_POC`, in the app and test
targets, and the real pinned upstream products linked. The standalone
`HANLIN_A2UI_PORTABLE_RUNNER` configuration never executes these cases.

| Case | Obligation | Actual result |
| --- | --- | --- |
| parsesAndRendersTextCardInputButton() | Official parser/model and renderer-builder availability | NOT_RUN |
| nativeInputBindingWritesAndReadsOfficialModel() | Native TextField writes; agent updates read back | NOT_RUN |
| stableIDsAndNodeIdentityAcrossUpdates() | Upstream node identity through model/component updates | NOT_RUN |
| malformedAndUnknownContentFallsBackAndRecovers() | Fallback routing and subsequent valid recovery | NOT_RUN |
| officialSchemasRejectInvalidTextInputButton() | Real catalog schema rejection of all3 malformed components | NOT_RUN |
| independentSurfacesKeepModelsSeparate() | Separate models and fallback per surface | NOT_RUN |
| independentOwnersCanReuseWireSurfaceID() | Separate processors for separate result owners | NOT_RUN |
| deleteDisposesAndRecreateStartsWithNewIdentity() | Surface deletion/recreation lifecycle | NOT_RUN |
| closeRejectsLateFramesAndDisposesSurfaces() | Owner disposal and late ingress | NOT_RUN |
| buttonEventUsesCurrentBoundValue() | Official action context after a user edit | NOT_RUN |
| hebrewFixtureRetainsBindingsInRTLComposition() | Hebrew model and RTL environment composition | NOT_RUN |
| surfaceLimitDoesNotRemoveExistingContent() | Four-surface capacity; preserve old model | NOT_RUN |
| rejectedSurfaceIDsCannotGrowFallbackStorageWithoutBound() | Bound rejected surface bookkeeping | NOT_RUN |

`Surface.render` constructs a native view builder result; it is not a hosted
screen assertion. The RTL case likewise constructs an RTL/accessibility-size
composition and checks Hebrew bindings. It does not measure layout, focus,
VoiceOver order, keyboard behavior or text clipping. Those hosted UI checks
are separate open acceptance gates.

## Enabled build/test command — proposed, NOT_RUN

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
  'OTHER_SWIFT_FLAGS=$(inherited) -D HANLIN_A2UI_POC' \
  CODE_SIGNING_ALLOWED=NO test
```

The project/scheme already exist. This is a future integrator command, not an
executed action or permission to edit shared files now. An isolated exact-pin
SDK harness may avoid the full app's Runtime dependency closure, but creating
that package/project is outside this lease. Prefer such a focused harness
after the lead assigns its owner; retain these same13 SDK cases and fixtures.

Retain resolved root/transitive revisions, compiler diagnostics and actual20
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
| invalid-components.jsonl | Invalid Text, TextField and Button schema payloads |
| malformed.txt | Truncated JSON envelope |

No fixtures are production network responses or claimed user sessions. No
secrets or private source artifacts are included.
