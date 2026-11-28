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
