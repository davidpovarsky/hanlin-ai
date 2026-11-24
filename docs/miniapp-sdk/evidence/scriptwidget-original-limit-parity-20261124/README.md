# ScriptWidget original limit parity

This isolated change starts from `25b14790e5c79b8ddd821984ed97d37e6af0bfa4`. It repairs two Hanlin enforcement differences while preserving all seven original ScriptWidget limits, original engine code and its refresh path.

The native compiler now begins/checks the original timeout separately for every actual ScriptWidget Babel operation, including module and imported-source compilations. There is no package-wide deadline or clock charged to output assembly. The compiler bootstrap retains the original limit check. The root freezer mirrors the authoritative upstream behavior: after resolving custom components, a single-element root Fragment is unwrapped at the same depth before node/property accounting. Child arrays flatten for that decision. Non-root Fragments and roots with multiple/scalar children retain their shape; cycle detection and original excess rejection remain.

## Evidence

The new deterministic compile-operation lifecycle case first failed against the old adapter, then passed against the correction. It calls actual original Babel through the production adapter, observes each operation's begin/check boundary, and contains no sleeping or invented elapsed time. The affected portable cases passed **7/7**: three compiler/action cases and four native-presentation compiler cases. Their VM render/service fixtures do not establish native UI or Apple timekeeping behavior. Exact commands, stdout/stderr and source hashes are retained.

The changed runtime, compiler and new native test source passed Swift syntax parsing with Swift 6.4.3 on Linux aarch64. This is **parse only**, not an Apple import/macro/type check. The final test and compiler revisions have separate final parse receipts; no previous native PASS is reused.

## Required Apple verification

The new method is an extension of the existing `HanlinDualWidgetEnginesTests` suite, which previously declared 33 methods. The narrow selection is one new method plus one directly related existing method:

```text
HanlinDualWidgetEnginesTests/(rootFragmentsPreserveOriginalElementAllowances|scriptWidgetUsesOriginalElementLimitsWithoutExtraMaterialQuotas)
```

The new method passes real typed local module source through `HanlinWidgetCompiler`/JavaScriptCore before freezing a Fragment-wrapped tree exactly at the original node limit. It also checks original maximum depth, both excess rejections, repeated root Fragments, retained non-root and multiple-child/scalar Fragments, element cycles, and independent Dynamic Island region roots. Neither native method was executed here. Actual Apple compilation and these two methods remain **NOT_RUN**. No timing/performance test or CI was run.

## Provenance boundary

`provenance/` is the unchanged earlier read-only review, separate from this implementation. Its exact original blob is `1504079272e64447a0cba422492ab6a8313c80c9`; SHA-256 `7040cab9a460f5845ee96114c396b7e27e46caf8c9e62614a717e25adb1af574`. It preserves the single successful authoritative blob retrieval, the earlier raw `gh` authentication error, all seven declaration comparisons and the initial two findings. The original runtime remains byte-identical to this change's base (`15a60ffc1a6171dde86fa442a7a51764fd073eee4f615e329b6593dc5cf9b34a`). Only two Hanlin host-adapter manifest entries were updated to match their new bytes. Frozen legacy Scripting/ScriptUI policy and the independent SDK-only authoring proof were not changed.

The two verbatim source/diff payloads are stored in `provenance/verbatim-original-sources.tar.gz` because the original contains trailing whitespace. `VERBATIM_SOURCES.json` records member hashes; extracting the archive reproduces the exact original evidence bytes. The initial staged whitespace diagnostic is retained separately. No source normalization was applied.

`RAW_LOG_STORAGE.json` similarly maps compressed raw diagnostic logs to their exact original byte hashes. The original red test output is preserved, not trimmed or rewritten.
