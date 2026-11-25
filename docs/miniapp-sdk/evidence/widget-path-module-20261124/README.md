# Widget compiler path module boundary — 2026-11-24

The original native run 45335292541 failed while compiling HanlinWidgetCompiler.swift:40: HanlinArchivePolicy belongs to HanlinScriptCompiler, which already depends on HanlinWidgetCompiler. Adding a reverse import/dependency would introduce a cycle.

## Change

The original pure normalizedRelativePath and Unicode-aware drive-prefix implementation now live in HanlinPlatformContracts/HanlinPackagePath.swift. HanlinArchivePolicy retains its existing public normalizer and private drive helper as forwarding methods. HanlinWidgetCompiler uses the shared contract directly and retains the original equality-to-source-path check. Both package manifests and all existing archive test assertions are unchanged.

The two original function bodies are byte-identical after relocation, including backslash conversion, leading ./, one trailing slash removal, traversal stack behavior, Unicode-letter drive detection and NFC normalization. There are no changes to package acceptance rules, quotas, formats, serialized ABI or native test selection.

## Executed evidence

- archive-policy/archive-import-policy.txt: the existing **12 Swift Testing methods in 2 suites passed**, including parameterized escaping-path and malformed ZIP64 cases. This harness compiles the actual production ArchivePolicy, the actual relocated helper as a separate module, the original archive contracts and the existing private directory parser. Tests were run once after the production change.
- module-compile.log: all **24 actual PlatformContracts Swift sources** compiled through SwiftPM with the **verbatim root-package target declaration and original Resources folder**. No dependency installation was required.
- before-consumer-typecheck.log: the original production path predicate reproduced the undefined HanlinArchivePolicy error in a separate Swift module importing PlatformContracts.
- after-consumer-typecheck.log: the new production predicate passed real Swift typechecking across that same module boundary.
- module-boundary.json: exact commands, exit codes, source/resource hashes, unchanged manifests/assertions and identical moved-body hashes.
- native-before-compiler-error.log and validation-plan.json: authentic native failure excerpt and original full-log/artifact provenance.
- receipt.json: focused results and scope boundaries.

The initial direct-swiftc probe failed because it did not generate SwiftPM's Bundle.module resource accessor. Its original script, receipt and raw failure remain under initial-direct-swiftc/ as historical evidence. Only the probe setup changed; the product implementation and the twelve passing tests were not changed or rerun.

The successful follow-up uses SwiftPM's actual resource generation rather than a replacement Bundle implementation. Reproduce the focused module proof with:

    python3 docs/miniapp-sdk/evidence/widget-path-module-20261124/verify-module-boundary.py

## Limits

This proves the shared module compiles on the installed Swift 6.4.3 Linux toolchain and the formerly invisible path predicate resolves from another module. It does **not** claim that the full Apple-dependent WidgetCompiler target, native gate38, ZIPFoundation extraction, UI or physical-device scenarios passed. Those remain subject to the root-owned native run.

Independent read-only review of source checkpoint 1b34855035c7a4d22bd9ac3d41a47ed1229405e1 found no module-visibility, dependency-cycle, source-membership or path-semantics blocker. The final evidence amendment leaves that source delta unchanged.
