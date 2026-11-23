# AppIntents exports and NativeScript libssh2 discovery — 45230545076

## Original result and scope

[Run 45230545076](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45230545076), attempt 1, source `7523f45cf8ea180a8e30f511ff0fbd3bb5ccae6d`, ended **FAIL** during the original full app/test build. The prior AppIntents bundle errors are absent, and specific original extractor targets positively wrote their output. The subsequent NativeScript metadata stage reported one genuine Clang redefinition of `libssh2` and failed its completeness guard.

All **310 authored method definitions / 342 expected invocations** in the selected inventory remain **NOT_RUN**. The artifact has no downstream unit/UI result export or test-result bundle. The original unit build receipt remains `PREPARED`; the native job never reached the test-suite step. Native publication is **BLOCKED**; a metadata binary containing required names is insufficient when its own receipt reports a compiler error.

## Authenticated evidence

The unique [smoke artifact 14849715568](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45230545076/artifacts/14849715568) was downloaded once: 3,893,728 bytes, SHA256 `822d58b4853deb384896071ade17f4982599b61bbb7dfb72faf5cbc3a258c695`. GitHub run/source/size/digest, all ZIP CRCs and all 62 original member hashes were verified. `original-simulator-smoke.zip` retains the exact archive bytes, including compiler logs, original const values, NativeScript umbrella/inventory, raw stderr and metadata binary.

The root-owned job log was reused, not downloaded again: 20,390,015 bytes, SHA256 `cc9b73270d8cdcad0702430ae5fca0e410b05c771e61227c7e1e864b60a07dd8`. The evidence receipt binds exact original lines and source hashes to it.

## AppIntents: what actually passed

The original appintentsmetadataprocessor logged `Writing Metadata.appintents` and the matching output root for:

- Shared `HanlinScriptingWidgets` SDK target at 18:08:53.600 UTC.
- Original widget executable, module `HanlinScriptingWidgetsHost`, at 18:08:56.360 UTC.
- Shared `AI_Hanlin` SDK target at 18:09:09.912 UTC.

`appintents-extractor-log.json` preserves the full original command/result blocks. This proves those exports occurred; it does not assert that the final main executable completed its build or that runtime translations passed.

All ten retained compiler metadata/file-list files match their original nested hashes. Four SDK const files contain 32 serialized `LocalizedStringResource` initializer nodes, including synthesized parameter-wrapper repetitions, with 18 distinct literal keys. Every node uses table `HanlinAppIntents` and the **`Foundation.LocalizedStringResource.BundleDescription`** overload. Their default bundle is recorded as `valueKind: Runtime`, not as a serialized `.main` literal. The generated table and documented default-main source form remain the source of that default. The actual final `Metadata.appintents` payload directories are not in this artifact; the authentic export evidence is the original processor command/output, supported by retained const metadata. The widget executable const payload is a thin wrapper, while the declarations belong to the shared SDK.

## libssh2 provenance and discovery

The original job log records two `ProcessXCFramework` actions from **the same** input `build/SourcePackages/artifacts/hanlin-ai/libssh2/libssh2.xcframework`, using the same `ios-arm64_x86_64-simulator` slice. Xcode stages it into both `Build/Products/Debug-iphonesimulator/libssh2.framework` and `Build/Products/Debug-iphonesimulator/PackageFrameworks/libssh2.framework`. The original app subsequently embeds that same upstream slice. Both root and child package manifests bind upstream `holzschu/libssh2-apple` v1.11.0 with checksum `cacfe1789b197b727119f7e32f561eaf9acc27bf38cd19975b74fce107f868a6`. This is a single pinned binary target, not a separately introduced system-library wrapper or second vendor implementation.

The metadata input umbrella has no libssh2 import. However, the original metadata Clang `-cc1` command contains the PackageFrameworks search root 105 times and the general Debug products root twice, with `-fimplicit-module-maps`. Upstream separately injects `-idirafter .../PackageFrameworks/libssh2.framework`. There is no explicit `-fmodule-map-file` argument naming libssh2. The Clang diagnostic names the general-products modulemap as a redefinition of the already-seen PackageFrameworks modulemap; both start with `module libssh2`.

The host-baseline umbrella filtering does not constrain the upstream launcher's raw framework search paths or its independently injected directory paths. The smallest appropriate repair belongs to **metadata discovery ownership**: expose each equivalent framework interface once across both mechanisms, preserve all unique framework owners, and reject genuinely conflicting duplicates. Removing the SDK dependency, dropping an entire search root containing unique frameworks, or accepting the generated binary despite `clangErrorCount: 1` would lose scope or conceal the failure. Root owns that implementation separately.

The actual duplicated modulemap/header bytes are not retained in this artifact. The same input/slice staging is proven, but duplicate-interface byte equality must be checked by the repair at build time before coalescing. No source, package graph, Native binary, CI selection or test was modified by this review.
