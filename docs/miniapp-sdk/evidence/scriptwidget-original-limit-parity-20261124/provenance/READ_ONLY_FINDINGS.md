# ScriptWidget quota provenance: read-only findings

## Result

All seven numeric limits are genuine declarations from `everettjf/scriptwidget` commit `4da256d58247bbafb9a5cd443a285250b97b3c4b`. They are identical in the installed original runtime. The phrase “unchanged original values” is accurate; complete enforcement equivalence is not: two Hanlin adapter paths apply those values more narrowly than upstream.

## Exact original authority

The manifest names Git blob `1504079272e64447a0cba422492ab6a8313c80c9`. One anonymous GitHub API GET retrieved its 70,509 bytes. Independent Git blob hashing and SHA-256 matched the recorded identities; SHA-256 is `7040cab9a460f5845ee96114c396b7e27e46caf8c9e62614a717e25adb1af574`. An earlier root-user `gh api` invocation stopped before HTTP with exit 4 (not authenticated); its exact command and stderr are retained. No second successful retrieval was made. An earlier `git cat-file` object lookup invoked the partial clone's lazy-fetch mechanism and failed to obtain the blob; subsequent verification used the exact API object only.

The installed original runtime SHA-256 is `15a60ffc1a6171dde86fa442a7a51764fd073eee4f615e329b6593dc5cf9b34a`. The whole file is adapted, as the manifest accurately states. The exact upstream/local diff is retained; do not label the whole runtime or whole contract body byte-identical.

| Contract | Value | Upstream and local declaration line |
|---|---:|---:|
| maximumSourceBytes | 512 KiB | 72 |
| maximumTranspiledBytes | 2 MiB | 73 |
| executionTimeout | 5 seconds | 74 |
| compileTimeout | 10 seconds | 77 |
| maximumElementNodes | 1,000 | 78 |
| maximumElementDepth | 64 | 80 |
| maximumPropsPerElement | 128 | 81 |

`HanlinOriginalScriptWidgetSession.swift` lines 23–47 exposes those original values/validators. Its unknown-future-enum fallback currently returns 5, but no current contract path uses that fallback.

## Hanlin enforcement differences and minimal proposals

### 1. Compile timeout aggregates independent inputs

The original `ScriptWidgetCompiler.compile` starts a fresh deadline inside each call (upstream lines 342–350, 407–416). Original `$import` calls `transform` separately for the imported source (922–945). The Hanlin compiler starts one deadline at `HanlinWidgetCompiler.swift` 80–81, then uses it for the entry and every independently prepared import through lines 108. The modular adapter at `prepare-widget.js` 48–74 shares that same callback across source transformations. This is an added aggregate application of the original number.

Minimal proposal: retain the original timeout authority and cooperative checks, but create a deadline for each original compiler/source operation. Do not add a package-wide deadline. No timing test was run, so the finding is source-derived and does not claim an observed timeout.

### 2. Root Fragment adds an extra counted node and level

The authoritative original runtime unwraps a single-element root `Fragment`, after flattening child arrays, at the same depth (776–810). It counts the normalized tree afterward. Hanlin's `freeze` charges one element at 291 and always recurses into children at `depth + 1` (322), with no corresponding root normalization. A root Fragment around an otherwise valid 1,000-element tree or depth-64 tree becomes 1,001 elements or depth 65 only in the host adapter. This is a source-reasoned boundary case, not an executed fixture.

Minimal proposal: mirror upstream normalization for the rendered root and each Dynamic Island region root before charging node/depth allowance. Keep non-root Fragment handling and cycle/invalid-value rejection. Do not remove or increase the seven upstream constants.

## Active callers

These are current paths, separate from frozen legacy Scripting/ScriptUI:

- Authoring analysis: `HanlinScriptAnalyzer.swift` 183 and 196 calls `HanlinWidgetCompiler.prepare` / `preparePresentation`.
- Package preparation: `HanlinWidgetPackagePreparation.swift` 39–49 calls the same compiler for widgets and native presentation artifacts.
- Widget timeline: `HanlinPreparedWidget.swift` 140–142 calls `HanlinScriptWidgetRuntime.shared.run`.
- Widget / Control actions: `HanlinWidgetActionExecutor.swift` 144–153 calls `performAction` or `run`.
- Native presentations: `HanlinNativePresentation.swift` 197–203 calls `run`.
- ScriptWidget Live Activity: `HanlinScriptWidgetLiveActivity.swift` 72–75 calls `run`.

The runtime validates prepared JavaScript at line 72 (and imports at 156), delegates the five-second duration at line 92, and uses the original node/depth/property values in `freeze` at 274, 288, 295 and 309. Scalar values and nested child arrays do not themselves consume element counts. Each Dynamic Island region receives a separate node budget. Those parts agree with the original limits' relevant counting scope.

## Boundaries and retained proof

No source edits, builds, tests, native execution, CI queries or dispatch occurred. The original fresh SDK-only proof was not changed. This is a bounded check of the seven identified limits, not a claim that all other runtime policies were audited. Legacy Scripting/ScriptUI paths remain excluded. `source-comparison.json` records exact local source snapshots/hashes and the two findings; `receipt.json` preserves the original blob retrieval and all seven declaration comparisons.
