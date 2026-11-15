# Native hosted Composer source-review packet

Status: **SOURCE ONLY — no Apple build/test or remote dispatch.** `full_app_acceptance` is false.

This new infrastructure replaces the synthesized SwiftPM validation project with a native application/module `AI_Hanlin` and a real `AI_HanlinTests` unit-test bundle. It does not change the actual application project, deployment target, SDK pins, production files, owner tests, geometry, assertions, or existing probes. The new app has only a clear SwiftUI scene and the eight complete production component files. It is a test host, not a published app or another Composer renderer.

The immutable component source is `e8ccd81452843609285a0cd7e017a759bda6a6ef`, including owner diagnostic `20980c9448f0a5d78eefcaec38da6e92364de37d`. `review/native-inputs.json` records all **12 original file hashes**: eight production files, two complete owner test files (seven Morph and five Native methods), and two APP files retained only for reference. The future native project compiles those ten canonical files plus one new infrastructure Swift file. No source is mirrored, sliced, patched, or shimmed. The local packet contains the generated PBX graph and shared scheme; its `Canonical/` references are intentionally not materialized locally. On an authorized Mac staging call the generator writes the exact Git blob bytes to those paths.

`prepare_native.py` reuses the existing read-only `extract_target.render` and project parser, with generation patterns from `prepare_parity_project.py`. The manifest records their frozen Git-blob hashes and the checked-in `AI_HLYTests` Debug/Release host-loading pattern. The generated native graph has a real application target dependency/proxy, `TEST_HOST=$(BUILT_PRODUCTS_DIR)/AI_Hanlin.app/AI_Hanlin`, and `BUNDLE_LOADER=$(TEST_HOST)`. Both targets have Debug, Swift 6, `-Onone`, testability, simulator SDK/platform and iOS 27 minimum settings. There are zero Swift package references, dependencies or products, and no inherited Parity Platform dependencies.

The earlier actual SwiftPM compiler flags (run `43691033216`, source `51d3fa350f6908526c6a78e4858b40122cc4f2f0`) included `SWIFT_PACKAGE`, `DEBUG`, `SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE`, `Xcode`, `-enable-testing`, `-Onone` and Swift 6. The UTF-8 GitHub CLI log export SHA is recorded as an export hash, not a native log archive hash. The new project explicitly preserves `DEBUG` and `Xcode`; the ten frozen compiled files contain no `SWIFT_PACKAGE` or unavailable-resource condition references, so those package-only flags are omitted. The manifest includes every conditional-directive location. The only platform conditional is `canImport(UIKit)` in the popup coordinator; its actual compiler evaluation still requires an Apple run. No app-specific concurrency overrides are copied. Prior Clang flags also included `DEBUG=1`, `SWIFT_PACKAGE` and Debug libc++ hardening; the new project explicitly sets `DEBUG=1`, omits the package flag and leaves libc++ defaults to the selected toolchain. Effective inherited flags remain unverified.

The real native app host, explicit iOS 27 minimum (prior package: iOS 26), absence of package resource synthesis, and new host scene are declared environment differences. This packet makes no byte-equivalent runtime, geometry-fix, resolver-cause, full-app, physical-device or release claim.

Source controls run entirely in Python memory with bytecode disabled:

```powershell
py -3 -B Scripts/CI/ComposerValidation/native_host/freeze_review.py --check
```

The check compares generated review bytes and validates target membership, whole-source bytes/hashes, the 12 unique method identities, the complete host dependency/loading graph, package absence, Debug settings and the serial shared scheme. Nine intentional corruptions must be rejected. `review/source-controls.json` is a portable source-control receipt, not Apple test evidence. No Swift compiler, package resolver, build cache, dependency installation, or artifact download is used.

## Current standing scope and source review

The immutable generated host packet at `67642faaa8f16c89eb0e2330db56291c35c61c06` remains unchanged. The earlier remote attempts are CLOSED: `43707216442/e7789af1` stopped at the broad post-boot inventory timeout, and `43711740465/70a74580` stopped when the reviewed parser rejected actual help grammar. Both executed zero authored tests. This repair uses that observed help and a strict returned-identity proof. Under the current standing assignment, independent Roni source acceptance is the quality gate before ONE focused manual run; no further START/ACTIVATE or human approval round is required. No new remote action has occurred during this preparation.

Run the portable source review with:

```powershell
py -3 -B Scripts/CI/ComposerValidation/native_host/review_guard.py --check
```

Eleven positive and105 negative in-memory predicate controls plus seven control-flow mutations are checked. These are Python source controls, not native fixtures or Apple results. The native settings/loader, initial environment, SDK eligibility and raw observation predicates retain their source-byte hashes from e778. The workflow remains byte-identical to e778, including19 other-job exclusions, exact expected commit input, attempt1 restriction,37-minute step/40-minute job, and14-day always-upload retention. The generated graph, whole ten canonical source files, twelve reference hashes and twelve authored identities remain frozen.

## Actual documentation and one owned-name query

`simctl-list-help-43711740465.txt` preserves the exact750-byte actual stderr transcript, SHA256 `4c7f0c98a485121183a1bc0b5ae8549958692117107664b4ee1c3fbf0f3c4693`. It came from `xcrun simctl help list`, exit0, in run43711740465, artifact14160935813 (42,397B; full ZIP SHA256 `653531d1ce1da284d9eea93e8a9d0d3311189633b02056d21a2be6fd6250a174`). Completed full ZIP/RAM audits belong to Tomer and Roni. Root independently checked run metadata; Root's ZIP transfer was cancelled and is not a completed ZIP audit.

The actual help documents optional JSON flags, the devices category and case-insensitive search against an item's description. It does not establish UUID filtering or identity. The future bounded installed-help capture must match the retained transcript; different/insufficient output stops without another grammar or query. The identity route does not demand invented affirmative UUID prose.

After actual initial inventory selects installed iOS27.0/24A434/arm64 and iPhone18Pro, the deterministic unique name is `Hanlin-NativeComposer-<GITHUB_RUN_ID>`. Its search token must be absent from every actual initial device name; the returned UUID must also be new. The actual successful create command, raw UUID output hash, name, selected runtime/type and initial inventory references are retained together. The only post-boot state command is:

```text
xcrun simctl list --json devices <owned_unique_name>
```

Every returned runtime bucket must be a well-formed list of device objects. Well-formed empty other-runtime buckets are permitted and recorded as empty headers, not runtime measurements. Across ALL buckets there must be exactly ONE actual device, in the exact selected runtime, with BOTH the created UUID and unique name, actual Booted state, Boolean isAvailable=true, and the selected iPhone18Pro device type. Wrong/missing/extra/malformed records fail. Duplicate JSON keys fail. No matching-any-device shortcut, constructed inventory, global post-boot query or fallback is used. Runtime build/architecture/type context remains explicitly attributed to the actual initial inventory; the returned device record supplies current state and identity.

## Native settings, selected method and retained outcome

After creation and BEFORE boot, BOTH actual native target settings must be nonempty and pass the unchanged simulator SDK/platform/minimum27/arm64/Debug/Swift6/-Onone/testability/conditions predicates and resolved TEST_HOST/BUNDLE_LOADER-to-actual-app executable check. Settings, destinations and test now use the same explicit owned DerivedData directory as well as native project/scheme/SDK/configuration. Created/settings state never declares boot readiness. Actual filtered boot proof and independent SDK-aware exact-UUID eligibility are also mandatory before the only test.

The whole frozen owner files still compile, preserving all12 method identities, but only `NativeComposerLineSizingTests/wrappedLinesAndScrolling()` is selected:

```text
-only-testing:AI_HanlinTests/NativeComposerLineSizingTests/wrappedLinesAndScrolling()
```

This uses Apple's documented [TestTarget/TestClass/TestMethod selector form](https://developer.apple.com/library/archive/technotes/tn2339/_index.html) with the full frozen Swift Testing identity. Actual matching is established only by the resulting xcresult: focused success requires exactly ONE observed selected PASS, no duplicates/extra authored or infrastructure cases, and actual owned-device execution binding. Zero selected execution is NOT_RUN/BLOCKED, with no selector retry. Other11 methods are NOT_RUN for this invocation, not failures or reused passes. If an unselected method actually executes, that observation is retained and blocks focused success rather than being hidden.

The runner retains raw commands/outputs/toolchain, exact graph and whole-source archive, focused-selection.json, initial inventory/create receipt, help/state/settings/eligibility receipts, xcresult/export when produced, and all12 per-method observations. Numeric signedDelta text is retained only if actually emitted; no signed value, geometry cause, old fix or runtime equivalence is inferred. Product Composer acceptance stays OPEN even if this changed-host component case passes. `full_app_acceptance` is always false; no physical iPad, app acceptance or TestFlight claim.

Caps remain2100 seconds overall; tool/help/initial inventory/create/boot/owned-state commands30 each, bootstatus180, settings and eligibility120 each, the ONE serial selected test900, export120 and owned shutdown60. The180-second export/shutdown reserve remains required before testing. No cap increase, runtime/tool installation, global Xcode selection, other-device mutation, erase/delete, second device, broad rerun or test retry is present.
