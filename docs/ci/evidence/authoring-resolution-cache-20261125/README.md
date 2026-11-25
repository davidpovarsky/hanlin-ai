# Operation-local authoring module resolution cache

Source donor: 707f9c2e3ea8488fafb284e14a7b7636ebb25a48, based on 5204240a3d0d5e05e366123bb7f7bbdb9d0ebfd0. Only AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs changes.

## Measured result

One candidate profile used the retained original profile-validation.mjs, real sdk-only-departure-budget Expo example, original SDK and TypeScript 6.0.3 on arm64 macOS with Node 24.5.0 --jitless. The full structured validation report and consumer/compiler/SDK input identities matched the original baseline: strict checking remained enabled, dependency declarations were checked, skipLibCheck remained false, and diagnostics stayed empty.

| Measurement | Original | Cache candidate |
|---|---:|---:|
| Validation | 10.316 s | 8.187 s |
| Module resolution, 1,284 calls | 2.753 s | 0.720 s |
| Program construction | 5.344 s | 3.294 s |
| Diagnostics | 4.928 s | 4.796 s |
| Host file reads | 5,296 | 992 |
| Host file existence checks | 11,395 | 4,949 |
| Peak RSS | 397,344 KiB | 382,624 KiB |

Observed total reduction: 20.64%. Measured module-resolution time decreased 73.85%. This is one matched component-profile observation. Nested counter times must not be added; it is not a native startup or end-to-end performance guarantee.

## Correctness and isolation

All original 14 miniapp-authoring.test.mjs cases and all original 3 miniapp-sdk-resolution.test.mjs cases genuinely passed: **17 passed, 0 failed, 0 skipped, 0 cancelled**. Exact identities, original test hashes, commands and raw TAP output are retained.

Existing canonical-resolution cases cover SDK module/type references, nested SDK dependencies, canonical packages overriding project aliases, additional project dependencies, emitted runtime bodies, and rejected ancestor fallbacks for missing canonical exports/configs/dependencies. Multiple operations and changed fixtures continue to receive fresh program-local state. Other original cases verify compiler diagnostics and locations, source revalidation, actual CLI packaging, retained source/output integrity and runtime package copying.

Caches are created inside each parseProject call. Project and restricted SDK hosts retain separate caches with their own unchanged options and canonical filename rules. All five resolveModuleName calls use the appropriate cache, including the SDK type-reference module fallback. Lookup priority, boundary predicates, compiler options, diagnostics, compiler version and the type-reference directive resolver are unchanged.

The installed typescript entry delegates to @typescript/old. An actual Node identity check established that both exports are the identical TypeScript 6.0.3 object. Tests used their existing compiler override to the underlying package. The original CLI child invocation was retained as written.

## Retained unsuccessful setup

The initial combined controller completed the sole candidate profile, then both test files failed before any of the 17 case bodies ran: Python encoded @typescript as %40, while unchanged test bootstrap treated URL.pathname as a filesystem path. Missing tests resumed using Node pathToFileURL serialization of the same compiler path. Tests, assertions and CLI bytes stayed unchanged; the profile was not repeated. Original failed receipt and log remain alongside the passing test-only receipt.

## Integration obligations

The experiment modified only the owned expanded diagnostic Host. Shipping source and original Host052c archive were not modified.

Scripts/Runtime/runtime_host_archive.py validates source modules and SDK/dependency identity. Its synchronize_archive path can update top-level Host modules while preserving an unchanged verified dependency closure. Preflight that closure before invoking the module-only path, retain resulting archive and source-input hashes, and preserve original versus newly executed test provenance. An old full-Host success marker must not be silently relabelled as a new run.

No native UI test, app build or full Host suite was executed by this experiment. These component results do not close unrelated native or physical-device requirements.

## Evidence

qualification.json records source, hashes, cases, environment, counters and limits. raw-evidence.tar.gz contains 23 original files: both CPU profiles/reports, immutable baseline evidence, candidate inputs/controllers, original failed setup, and passing 17-case TAP/receipt. Archive SHA-256: f89705364e40f462a106429203edd9b02cb43ff6233ca2b36c77f5813f3ea0aa.
