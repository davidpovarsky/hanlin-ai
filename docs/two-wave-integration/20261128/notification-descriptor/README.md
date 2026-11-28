# Notification test descriptor admission

## Source and purpose

This candidate changes only `Scripts/ProductSplit/run_native_acceptance.py` and its existing portable notification controls, on exact source `3634078f89c5fa469199da1f69d6f4bad6686d96`. It has no workflow, product, fixture, test-selector, SDK producer, or Apple-native change.

The existing current build still runs the same `build-for-testing` command. For the notification scope alone, the subsequent original test invocation uses the one current generated descriptor beneath that owned DerivedData's `Build/Products`. The unchanged public helper removes only the `-project`, `-scheme`, and `-derivedDataPath` option/value pairs and appends `-xctestrun <original-file>`. Destination, package arguments, signing flags, nonparallel setting, result destination, and the one exact notification selector remain.

## Admission and preservation

The original build command, prepared source and fixture diff, app/runner/test executable bindings, simulator creation, installed container and MCM identities, actual runtime fixtures, and final five notification observations remain required. The source capture also binds the existing descriptor helper's exact loaded bytes.

The descriptor must be the sole regular, nonlinked generated file at the original product root. Its plist must expose exactly one enabled UI target with destination artifacts disabled and no embedded test restriction. The original helper resolves the UI host, app, and test paths; every component within the owned root is checked before resolving, and the resolved paths must equal the original three products. A final no-follow open and stat/readback check bind the raw file without rewriting it. A lossless original copy and the original/transformed argv are retained in the attempt evidence.

Admission occurs before `state.command` is recorded. The actual notification controller revalidates the descriptor and current product bindings before launching XCTest, again before launching the original worker, and after owned-child cleanup at native terminal. A changed terminal descriptor records a distinct failure and preserves an earlier native failure reason and the real exit codes. An exit zero cannot override that failure.

All eleven other original runner functions are AST-identical. The complete original runner bytes are recovered by the explicit inverse script after removing only these additions. The original fourteen control method bodies and old helper bodies are unchanged; the existing controlled-child assertion still compares its actual child argv with the admitted `self.argv`. Only setup now supplies the complete original command, current source helper, and a synthetic valid generated descriptor.

## Limits

The original build limit is 2400 seconds; the notification command remains 1200 seconds, its worker 650 seconds, and its Swift case allowance 600 seconds. The same original native selector is retained. Descriptor checks add no native time or alternative execution route. The original source, product, container, worker, push, result, and cleanup checks remain.

## Actual validation and retained failures

The final focused portable module executes all 23 controls successfully: the original fourteen and nine new descriptor controls. The new controls exercise unchanged argv/bytes, v1/v2 plist admission, missing/duplicate/disabled/restricted selections, wrong or escaped products, symlink/hardlink paths, unbound helper bytes, raw mutation before launch or worker admission, replaced admission evidence, and mutation at terminal with either zero or nonzero original exit.

These are ordinary temporary-file and controlled-child tests. No XCTest, notification delivery, simulator, SDK producer, app compilation, or OS acceptance ran for this candidate.

The first portable preparation stopped before any substantive controls because the isolated sparse checkout lacked the original `project_graph` import dependency. Materializing that existing directory fixed the environment. The second invocation ran all 23 controls, with the original fourteen passing; one new malformed-host case failed closed with `FileNotFoundError` rather than the expected admission `RuntimeError`. The path reader now reports that same original exception family consistently; no expectation was weakened. The final invocation passes all 23. All three original logs, source hashes, and receipts are retained.

## Historical mechanism evidence and limits

The original 9a notification log is 12,191 bytes, SHA-256 `bfe4e3b80073b70f67a8bb198bfca5ae672d8c0c11aee2f3dff03688c651edf9`. It contains 155 `Resolve Package Graph` markers and no XCTest starts. It also contains the Folder Reference warning for the generated Expo `.swiftpm/xcode` path.

The independently retained c990 origin descriptor-run log is 234,171 bytes, SHA-256 `eaf532ae7e343b92acdc3d5cec9e51a84cffff996cb8e91f8aef48dfe062612b`. It contains no such resolution markers and nine actual XCTest starts. Its terminal outcome is two passes, six failures and one interrupted case under the original 1200-second limit. This is evidence that the supported descriptor dispatch can reach XCTest in that different run. It does not establish the warning's inner cause, a cache defect, a notification repair, or current acceptance.

Apple's original TN2339 documents that build-for-testing creates an xctestrun file, that test-without-building accepts that file instead of a scheme, and that descriptor mode locates bundles at the paths recorded in the file. The new code reuses the project's already-reviewed implementation of that invocation. See `public-contract.json`.

## Source impact and next gate

The two changed paths have zero intersection with the measured 396-input SDK inventory at the same base. This does not qualify a later combined Share product change; root owns that source/producer boundary.

The candidate is source-only and uncommitted for independent root review. After reviewed integration, original CI and exact source/product admission, the required next acceptance is the original notification scope with its one unchanged UI method and five real push observations. No old successful native result is relabelled.
