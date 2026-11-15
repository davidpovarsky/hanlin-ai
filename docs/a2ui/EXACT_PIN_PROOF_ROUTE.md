# Isolated exact-pin proof route

Prepared after source review of `3a24003e`. No native job, package resolution,
dependency download, temporary harness creation or product wiring ran during
preparation. Actual status remains8 portable passes /17 SDK NOT_RUN.

`prepare_exact_pin_proof.py` prepares the same3 source files, the unchanged25
Swift Testing selectors and all7 fixtures in an isolated SwiftPM consumer.
It does not dispatch jobs or invoke a compiler. Its default `--plan` and
`--self-test` modes are portable, read-only checks. No product manifests,
locks, project files, workflows, build flags or upstream source are edited.

The generated temporary consumer uses the official exact root revision and
four real products. It names its source module `AI_HLY` so the actual
`@testable import AI_HLY` tests need no source rewrite. Both targets enable
`HANLIN_A2UI_POC` and `DEBUG` for the Debug build; the standalone portable
runner flag is absent. Source/fixture bytes and the harness manifest are
hashed. The compiler and all25 tests, including the byte-budget assertions,
remain **NOT_RUN** until the approved Apple execution happens.

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

## Native execution — prepared, NOT_RUN

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
# empty XCTest output does not substitute for the25 actual Swift Testing cases.
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
does not identify the25 methods, validation fails closed: retain the files
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
