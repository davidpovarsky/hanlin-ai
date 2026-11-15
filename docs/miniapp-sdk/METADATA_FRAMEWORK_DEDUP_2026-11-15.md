# Framework ownership and duplicate metadata inputs

2026-11-15 — [נועם | Runtime/SDK] [MAIN_SESSION], lease W1-001.
SDK-03 `1220373608755846`; INT-03 `1220374076374903` remain open.
Baseline: `ba7a5ba3ed9e8983cc47df532114079f64bff0b0`.

App run [43650510166](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43650510166)
failed before all 15 selected tests. The public-header collector imported both
Products and PackageFrameworks copies of ExpoModulesCore. Sorting resolved paths
removed compiler search priority without removing physical duplicate inputs.

The collector now visits explicit framework search paths in order, then the SDK
standard framework root. A framework filename or top-level module identity has
one selected owner. Another physical copy is omitted from explicit imports only
when its complete Headers/PrivateHeaders and module-map file manifest matches
byte for byte. Each file's SHA-256, both framework paths and search priorities
are retained in the inventory. Differing content or missing files fails before
the generator runs; its conflict inventory survives temporary-directory cleanup.
Nested submodules and external module references do not claim global ownership.
Unique frameworks and existing public entry selection remain enabled. Clang
diagnostics, tool provenance and all eight required bridge symbols remain gates.

The two inherited dirty changes are included in this candidate: declaration
writer fixes for already-hidden properties and nullable blocks, and the actual
NativeScript SDK-shape characterization test. Neither is presented as a prior
native pass. The owner's untracked Expo MiniApp directory remains untouched.

## Impact and validation plan

Affected: public metadata discovery, the production wrapper, generated SDK
declarations and native metadata consumers. Runtime engine sources/archives,
HostServices ABI, package manifests, fixtures and workflows are unchanged.

- EXECUTED_PASS: four existing wrapper methods plus six new regression methods,
  `py -3 -B -m unittest Scripts.CI.Tests.test_nativescript_metadata_wrapper -v`;
  10 methods, 0.944s, Windows/Python. Synthetic framework fixtures verify file
  discovery and failure behavior; they do not prove Apple or VM behavior.
- Next: existing focused NativeScript SDK metadata workflow, compiling the actual
  metadata tool and Swift provider, checking declaration parity/negative cases.
- After focused proof: the exact 15 missing consumer selectors from the handoff,
  plus `actualNativeSDKGlobalAndPropertyShapesAreObservedWithoutInvokingUI()`.
  Each is affected or previously NOT_RUN; none is eligible for assumed reuse.
- Unrelated historical Core 305-second case: no rerun or fresh PASS claim.
- NOT_RUN: actual app/VM/UI, strict complete SDK typing and physical-device gates
  at this candidate checkpoint. Metadata proof alone cannot satisfy them.

Machine-readable results: `evidence/METADATA_FRAMEWORK_DEDUP_2026-11-15.json`.
Native execution results and exact source/run identities will be appended here.

## Actual native metadata result

Implementation `dd700c03e9fe9d22e95a031d4684275512ee6e6f` passed
[43654504526](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43654504526),
job 2m45s, Xcode 27.2/27B52, SDK 27.2, arm64. The actual rebuilt tool's source
and binary hashes match its provenance. System Python 3.9.6 ran the production
wrapper against the genuinely compiled Swift provider. All eight required
symbols are present, with zero Clang errors. SDK metadata remains byte-identical
(`dae58823…`), and the runtime-wrapper metadata remains `8c0809b1…`.
All 31 original/candidate UIKit/Host YAML files match; an invalid native SDK type
returns exit 1 with a genuine diagnostic. The actual provider declaration now
emits `onEvent: ((p1: NSDictionary<any, any>) => void) | null`, preserving its
callback and nullability. Complete strict SDK typing remains open.

Artifact `14137184091` is 28,346,655 bytes, GitHub SHA-256
`c3f0b902a56f1d07303f55a94b972ac055d97f6810d5ea56d7753a80d5551178`.
Raw downloaded evidence: `build/metadata-dedup-43654504526-artifacts/`.
The isolated probe inspected 285 SDK frameworks / 300 wrapper frameworks and
contains no physical duplicate ExpoModulesCore copies. Consequently it cannot
establish full-app deduplication or VM behavior by itself.

App follow-up [43654868788](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43654868788)
requests exactly 16 selectors (11 unit, 5 UI), preserving the previous 15 and
adding the SDK-shape test. The full baseline-to-candidate impact plan is retained
at `build/metadata-dedup-full-impact-plan.json`; the dispatch uses explicit
selectors and comparison base `dd700c03` without claiming baseline reuse.
The pinned Node/Python producer remains `42926628418`. No engine rebuild,
distribution or signing is requested.

## Actual app result and input-role blocker

Run 43654868788 FAILED during app build (simulator job 15m33s; baseline
compilation passed 2m40s). The simulator test step was skipped: **0/16 methods
executed**. Provider-summary success does not override this failure.

Its retained inventory contains 339 framework records: 327 selected owners and
12 byte-identical duplicate copies. All 12 complete input manifests were
compared after download. ExpoModulesCore's two 81-file manifests match SHA-256
`6cb6e803d96e5a8d5913230df4e85c17900ae84dc2ea5cc18868069ba0bbada9`.
The earlier-priority PackageFrameworks copy was selected; the Products copy was
omitted from root imports. There were no differing-copy conflicts. This proves
the duplicate-discovery correction on actual app inputs, not a successful build.

Artifact `14138215380`, 6,962,705 bytes, GitHub SHA-256
`cb3205f30dabb0d7666f19dcf14c50e28b2f023715f6f96161cd696d06d40661`,
retains the complete inventory, umbrella and actual diagnostics. Raw evidence:
`build/metadata-dedup-43654868788-artifacts/`. The next failure is 20 actual
Clang errors importing synthetic ReactCommon/jsi C++ headers as Objective-C
(`namespace`/`class` are unknown).

An ObjC++ attempt (`5ae5eb94`) preserved every root/header and used the project's
existing gnu++20 standard. Cheap probe
[43656411654](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43656411654)
FAILED in 2m21s: pinned Clang17 cannot parse SDK27.2 C++ builtins such as
`__builtin_clzg`, and the metadata generator cannot produce a jsName for a
CXXRecord. The wrapper rejected all eight absent bridge symbols and retained
28 Clang errors. No app retry was dispatched with that candidate.

Only that unsuccessful language change was undone. The wrapper and its test
file are restored byte-identical to dd700c03; all five code/test input hashes
again match the successful 43654504526 proof. That proof is consequently
**REUSED_VERIFIED_PASS** for the restored inputs, not a new execution. The
12-copy app discovery proof remains authentic; app/VM/UI/device gates remain
open. No diagnostics, SDK feature definitions, metadata serializers or API
declarations were suppressed to obtain a pass.

## Proposed contract, awaiting the lead

`Scripts/Expo/prepare-ios-dependencies.mjs` stages header-only modular shims
at lines 523–637. The actual ReactCommon/jsi shim headers and module maps
(5 + 8 files) match the local pinned copies byte for byte; neither shim has a
framework binary or any `@interface`/`@protocol` declarations. This provenance
supports a language-role distinction; absence of ObjC text alone is not a full
AST/API coverage proof.

Do **not** exclude the entire ModularFrameworks root: it also contains genuine
ObjC surfaces (RCTSwiftUIWrapper, React_RCTAppDelegate and react) and Yoga C
exports. Their existing search paths, owners and supported declarations must
survive. An explicit, narrowly scoped input-role contract should distinguish
the C++-only include dependencies from direct ObjC/C metadata roots, retaining
both shims in compiler framework search paths and recording their manifests
and role in the inventory. Unknown/changed inputs must not silently acquire an
exemption.

One candidate is an explicit language requirement on the two staged module
definitions, paired with a collector that honors that requirement for its ObjC
translation unit. Clang documents language requirements in its
[module-map requires declaration](https://clang.llvm.org/docs/Modules.html#requires-declaration).
This is a proposal, not an implemented exclusion or proof that the generated
module dependencies will compile unchanged.

The requested additional leases are the existing Expo staging script and
`Scripts/NativeScript/probe-sdk-metadata.py`, to construct a focused real combined
input proof before another full app run. No workflow/manifest/runtime ABI change
is proposed. The alternative is a separately scoped C++ metadata/compiler
migration; changing SDK macros, substituting SDK headers, or disabling errors is
not an acceptable repair.

The combined proof should use the existing pinned artifact/dependency staging,
the actual compiled Swift-provider header, and the real framework maps/headers.
Keep their paths/hash receipts and actual module/search order. It must prove
zero genuine diagnostics and retain the eight production bridge symbols plus
representative existing ObjC/C exports: EXExportedModule, EXModuleRegistry,
RCTBridge, RCTView, RCTAppDelegate, RCTSwiftUIContainerViewWrapper, YGNodeNew,
YGConfigNew and YGNodeStyleSetWidth. These names come from actual declarations;
their metadata presence is a **future obligation**, not an asserted pass.
Only after that proof should the unchanged 16 NOT_RUN selectors execute. The
Core 305-second case remains outside this tranche.
