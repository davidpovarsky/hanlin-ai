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

## Dispatch boundary

There is deliberately no workflow dispatch or execution runner in this source packet. Independent source acceptance must precede any execution wiring/remote action; any later runner change must remain reviewable. This packet alone is not permission to run.

The authorized future diagnostic is bounded to at most one fresh iPhone 18 Pro / iOS 27.0 `24A434`, using Xcode 27.2 `27B52` through per-process `DEVELOPER_DIR`, an explicit installed simulator SDK, this native `-project` and `-scheme`, and its concrete owned UDID. Before testing, nonempty **actual native-target** build settings must establish SDK/platform/deployment/architecture for both targets plus the unit bundle's resolved `TEST_HOST` and `BUNDLE_LOADER`; CLI headers or an empty array do not qualify. The SDK-aware native-project destination listing must contain that exact compatible owned UDID. Either missing prerequisite stops the run before tests. A positive guard permits one 900-second serial whole-bundle run with 12 expected unique identities, no retry loop/third device, and only owned-device teardown. The original two-point plateau assertion and owner probes must remain unchanged. Capture the effective flags/settings and actual results separately from this source receipt. No claim extends to the full app or physical iPad.
