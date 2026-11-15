# Isolated exact-pin proof route

The frozen961 source remains the34-case benchmark. The current mount/retired-ID
packet retains those identities and adds one SDK regression:35 cases (8 portable
+27 SDK) and all5 owned SDK-source files, with unchanged official products/pin.
Its compilation/execution is NOT_RUN. Six separate iOS hosted cases and the two
shared UI files are not part of this macOS harness. No961 result can accept the
new lifetime-policy correction or host mounting. This owner dispatched no CI.

Initially prepared after source review of `3a24003e`; the preparation utility
itself dispatched no native job. Tomer's actual run43662884686 later compiled
c40e617b and executed all25 cases:8 PASS/17 SDK FAIL during fixture load. The
fixture/diagnostic correction is documented in
[NATIVE_VALIDATION_FIX_2026-11-15.md](NATIVE_VALIDATION_FIX_2026-11-15.md).
The2bae5a3e follow-up passed25 in run43664698104, and a43 passed25 including
privacy canaries in run43667371439. The actual AI_Hanlin consumer-name
correction at f654ac11 then passed all25 in
[run43668852483](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43668852483).
See [retained native evidence](evidence/native-run-43668852483.json).

`prepare_exact_pin_proof.py` prepares the current5 source files, the exact35
Swift Testing selectors and all7 fixtures in an isolated SwiftPM consumer.
It does not dispatch jobs or invoke a compiler. Its default `--plan` and
`--self-test` modes are portable, read-only checks. No product manifests,
locks, project files, workflows, build flags or upstream source are edited.

The generated temporary consumer uses the official exact root revision and
four real products. Its source module is the actual app module `AI_Hanlin`,
copied under `Sources/AI_Hanlin`; the unchanged tests import that module.
`AI_HLY` is the repository/source directory, not the app module. The test
target remains `AI_HLYTests`; the original25 case identities are retained and10
owner lifecycle cases are added. No
PRODUCT_MODULE_NAME override, stub or module alias is used. Both targets enable
`HANLIN_A2UI_POC` and `DEBUG` for the Debug build; the standalone portable
runner flag is absent. Source/fixture bytes and the harness manifest are
hashed. The corrected f654ac11 consumer compiled and all25 tests passed,
including the byte-budget assertions. The earlier c40e617b cases actually ran
and failed; the successful follow-ups do not erase that result.

This proves a macOS27 SDK consumer when executed successfully. It does not
prove iOS27 app integration, an inline host, hosted layout or physical iPad
acceptance. No NativeScript/Expo Runtime rebuild is part of this route.

## Local preparation — executed

```powershell
py -3 docs/a2ui/prepare_exact_pin_proof.py --plan
py -3 docs/a2ui/prepare_exact_pin_proof.py --self-test
```

The plan lists actual case names/input hashes and `PREPARED_NOT_EXECUTED`.
Seven verifier self-checks use synthetic XML/locks (valid25, zero, omitted,
duplicate, skipped cases, valid pin and wrong pin). They test evidence guards;
they are not additional SDK tests or evidence that the25 cases executed.
The retained plan is `evidence/exact-pin-proof-plan.json`; local verifier
output is `evidence/proof-validator-results.json`.

The24-line generated manifest template was also typechecked against the local
Swift6.3.3 PackageDescription API with `-package-description-version 6.1`,
using stdin and the installed ManifestAPI module. No Package.swift file was
created and no dependency was resolved. This checks the preparation template,
not Apple SDK imports or the upstream package build.

## Native recipe — executed at f654ac11; current35-case candidate NOT_RUN

Only after the authorized stable-Xcode host and serialized resource are
available, run from an authenticated checkout of the handoff commit. Keep the
current Apple toolchain selection per invocation (`DEVELOPER_DIR`) supplied by
the coordinator; never change global xcode-select. The setup command requires
macOS and a fresh temporary output directory outside the product checkout.

```bash
set -euo pipefail
A2UI_PROOF_ROOT="$(mktemp -d -t hanlin-a2ui-proof)"
python3 docs/a2ui/prepare_exact_pin_proof.py --output "$A2UI_PROOF_ROOT/harness"
mkdir "$A2UI_PROOF_ROOT/evidence"
xcodebuild -version > "$A2UI_PROOF_ROOT/evidence/xcode.txt"
xcrun swift --version > "$A2UI_PROOF_ROOT/evidence/swift.txt"
xcrun --sdk macosx --show-sdk-version > "$A2UI_PROOF_ROOT/evidence/sdk.txt"
sw_vers > "$A2UI_PROOF_ROOT/evidence/os.txt"

xcrun swift package --package-path "$A2UI_PROOF_ROOT/harness" resolve \
  2>&1 | tee "$A2UI_PROOF_ROOT/evidence/resolve.log"
cp "$A2UI_PROOF_ROOT/harness/Package.resolved" "$A2UI_PROOF_ROOT/evidence/resolved-before.json"
python3 docs/a2ui/prepare_exact_pin_proof.py \
  --verify-pin "$A2UI_PROOF_ROOT/harness/Package.resolved" \
  | tee "$A2UI_PROOF_ROOT/evidence/pin-validation.json"
xcrun swift test --package-path "$A2UI_PROOF_ROOT/harness" -c debug \
  --disable-automatic-resolution --enable-swift-testing --disable-xctest \
  --filter 'A2UI(IngressTests|SDKTests)' \
  --xunit-output "$A2UI_PROOF_ROOT/evidence/results.xml" \
  2>&1 | tee "$A2UI_PROOF_ROOT/evidence/test.log"
cmp "$A2UI_PROOF_ROOT/evidence/resolved-before.json" "$A2UI_PROOF_ROOT/harness/Package.resolved"

# Swift Testing output may use results-swift-testing.xml. Pass all result XMLs;
# empty XCTest output does not substitute for the35 actual Swift Testing cases.
python3 docs/a2ui/prepare_exact_pin_proof.py \
  --verify-results "$A2UI_PROOF_ROOT/evidence/"*.xml \
  --resolved "$A2UI_PROOF_ROOT/harness/Package.resolved" \
  --inputs "$A2UI_PROOF_ROOT/harness/proof-inputs.json" \
  | tee "$A2UI_PROOF_ROOT/evidence/result-validation.json"
```

SwiftPM's CLI offers forced resolved versions and Swift Testing selection;
see its [official test command reference](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/SwiftTest.md).
The installed Windows6.3.3 `swift test --help` also exposes these flags.
The exact Apple toolchain's acceptance remains unverified. If its XML format
does not identify all35 methods, validation fails closed: retain the files
and correct the evidence adapter using actual output rather than treating
zero discovery or a green heading as success.

Retain the whole temporary evidence directory, `proof-inputs.json`, the
generated harness manifest and actual complete Package.resolved. Root location
and revision must match the official pin. All transitive pins and their lock
hash must be recorded; `--disable-automatic-resolution` and the final `cmp`
prevent silent re-resolution during execution. Authenticate the commit,
job/process, source hashes, compiler identity and returned artifacts separately.
`RESULT_CONTENTS_VALID` checks evidence contents, not their provenance or
independent acceptance. Compile failure or missing/skipped/duplicate/zero cases
cannot pass. No fallback to a stub, rewritten test body or moving root branch
is provided.
