# Native typed List input for the existing MiniApp action

## Source scope

This candidate adds four optional, homogeneous native List parameters to the existing `HanlinRunMiniAppShortcutIntent`: text, integer, number, and Boolean. It retains the five original parameter declarations and defaults, the three original input enum raw values, the action type/title, the existing `DefaultCase` summary content, and the original command, lease, execution-mode, progress, cancellation, presentation, output-file and snippet implementation.

The selected list maps directly to the existing `HanlinValue` contract. Text stays text; Boolean stays Boolean; `Int64(exactly:)` converts native `Int` without a Double intermediary. Number input uses the existing finite-Double validator. An absent selected optional list and an explicitly empty selected list both mean `[]`. Unselected input parameters do not participate in decoding. Invalid selected input still throws before creating any invocation command or lease.

The existing JSON and JSON-file routes remain available for dictionaries, nested or heterogeneous arrays, and null. This change does not establish direct arbitrary Dictionary/Any parameters, a heterogeneous native union parameter, an array of files, or a new output type. Existing text, JSON and binary output semantics are unchanged. Exact Int64 retention in this codec does not override an engine's existing JavaScript numeric-destination validation.

## Files and boundaries

The seven paths are listed with exact preimage and candidate hashes in `source-hashes.json`. Two production Swift files change: the existing standalone intent and its existing shared value codec. Two relevant existing test files gain additive controls. Canonical localization gains four entries in English, Hebrew and Simplified Chinese, and the existing AppIntents projection list selects those entries. The original producer generates the actual host catalog. All 1,294 old canonical records, all 60 old host records, their order, and catalog metadata remain unchanged.

R1 directly added the host entries. Source review then found that the existing SDK installer's original `--check` requires the canonical projection. That was a source finding; no failed execution was invented. R2 adds only the canonical entries and four projection keys. The generator's original render/main bodies are unchanged, and its actual output is byte-identical to R1's host catalog. All five R1 candidate files remain byte-identical.

The original input switch branches were moved verbatim into `decodedInputValue()`, which is invoked once at the original preflight point. Source qualification compares the entire remaining execution body and helper tail, rather than inferring lifecycle preservation from selected lines. No workflow, SDK runtime implementation, fixture, renderer, diagnostic source, test deadline, dependency or pin changes.

## Validation already completed

`source-preservation.json` retains the seven completed R1 mechanical source-check groups. It verifies the five whole-file inverses; each old parameter/default; the original summary inside `DefaultCase`; old enum values; the old input branches; the complete execution/output/helper suffix; original codec methods; all original test/helper bodies; and the existing host localization entries. R2 reuses these checks by exact equality of all five files. `canonical-localization-qualification.json` additionally verifies both new path inverses, all old canonical records/order, unchanged producer behavior, and records the original generator and `--check` command each executing once with exit 0. These are source/resource checks, not executed Swift behavior.

The exact seven paths have no intersection with the retained 396-file SDK producer input list (manifest SHA256 `7f2702e52587fe1d126cef37f068ab3a9e3a26adb275ffafb687cb38a2db9b87`, input fingerprint `9e397ad525cf254598f8b35256816d1519ae2adfb02f3e5692fc91c21a1a3ab1`). The full current collector qualification is retained separately; a path-set comparison alone is not a fresh archive qualification. The shared PlatformContracts package, canonical localization resources and host binaries/metadata have changed and require their corresponding native qualification.

At the R2 source-review boundary, actual shipping-source Swift compilation, Swift codec tests, app tests and saved Shortcuts execution were NOT_RUN. A separate public-SDK declaration probe has the narrower scope documented in `COMPILE_CONTRACT.md`; subsequent native outcomes belong to their separately retained source-bound receipts. No Python reimplementation of the codec was used as a substitute.

## Prepared meaningful controls

Six new codec methods cover exact UTF-8/order, signed Int extrema and an integer above binary64's exact range, Boolean identity, finite Double types/bit patterns including negative zero, nonfinite rejection, and all four empty list variants. Existing tagged-wire and plain-JSON routes are exercised where their existing contracts apply. All four original codec methods and their existing parameterized inputs remain unchanged.

Four new standalone intent test methods exercise selected-parameter isolation, nil/empty behavior and old defaults/raw identifiers, old text/JSON/file semantics including invalid UTF-8, and actual compiled host translations. All four original app-test methods and the original command helper are byte-preserved. These controls remain unexecuted until the native owner runs the real source.

## Public contract and remaining acceptance

Apple's [Adding parameters to an app intent](https://developer.apple.com/documentation/appintents/adding-parameters-to-an-app-intent) documents compatible primitive values, collections of compatible elements, optional parameters, and conditional summaries using `Switch`, `Case` and `DefaultCase`. The [IntentParameter](https://developer.apple.com/documentation/appintents/intentparameter) contract is the wrapper used here. The retained installed Xcode 27.0/iOS 27 public-interface packet confirms the relevant primitive, Array and Optional declarations; it is declaration evidence, not compiler or OS proof.

The actual emitted MiniApps metadata must retain the existing action and old five parameter identities/defaults and add only the four optional list fields/new enum values. Real Shortcuts must still demonstrate input acquisition/coercion, saving/reopening, action execution, output chaining, and continued operation of previously saved old routes. Native list values may be subject to Shortcuts' own supported-value/editor behavior; this source change does not claim that a physical device or a Simulator has exercised them.

## Retained source qualification

Source commit `42d690ba3879e70c5475d28c2e82faf54cc9e37a` is based on `445e2cb514012110cd865bdd33a3dbb8e6b8143d`. Both independent root reviews are included verbatim. Raw R1/R2 patches, the unchanged declaration probe and the original generator command logs are stored losslessly with gzip; `manifest.json` records both compressed and original byte hashes. Source-only checks are not app or OS acceptance.
