# NativeScript parity: asynchronous startup

## Observed defect and scope

On the actual cold attempt10, the unmodified parity case failed at its verified-JSC-label assertion while the screen was still the catalog. The finalized native diagnostic is preserved separately under receipt `56cd644b34012d4e4f690621f7c734bc0d3b58143d3fa9e6605e822a8c91161f`.

The owned app sample `665ce904e621bec6564098cb4aef3e8a24475aab276f172e1f933105d8726f8f` records the main thread inside `executeNodeSync` / `HanlinExecuteSyncWithTimeout` during module evaluation, with a concurrent worker inside `NodeRuntimeService.prepareHostRuntime` / ZIPFoundation extraction. JSC itself had already returned a correct nonce. The three-second sample does not measure a complete cold startup duration.

## Change

The shipped parity package now tries its already supported asynchronous Objective-C Completion selectors before synchronous compatibility fallbacks. Starting a void-returning asynchronous method accepts the request; no result-value check can accidentally trigger another execution. Existing result/error callbacks, nonce calculations, HTTPS checks, inter-app payload, state persistence and relaunch behavior are unchanged. No provider, bridge, runtime deadline or native dependency was changed.

The archive is regenerated deterministically from its six source files. The old archive used CRLF while the Git source used LF; the old files were semantically identical after line-ending normalization. The new archive matches current source bytes exactly.

The UI title predicate now requires the actual runtime accessibility identifier, both initially and after relaunch. The previous OR-label match could succeed on the catalog card. The independent Node output assertion retains its verified runtime/version/nonce and no-error conditions, with a180-second readiness wait inside the existing420-second total case allowance. This permits original first-use Host preparation to finish; it is not an application execution limit or a claim of a measured180-second preparation time. All remaining assertions retain their semantics.

## Portable verification

The new behavioral tests execute the actual shipped helper declarations in a JavaScript VM with controlled asynchronous callbacks. They establish async precedence, member-call receiver binding, acceptance of void returns, no duplicate fallback, delayed success/error delivery and preserved compatibility results when asynchronous selectors are absent. The original synchronous-first implementation fails these cases; the corrected helpers pass all15. The four existing archive/manifest/fixture tests also pass. The discoverable Python fixture suite now invokes the15-case JavaScript gate as its fifth test; that integrated five-test suite passes. Raw original and corrected logs are retained.

These are Oracle Node v24.22.0 helper-contract and source/archive checks. They do not replace the pending native cold-start UI execution, the original25+27 acceptance coverage, or physical-device verification.
