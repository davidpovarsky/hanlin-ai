# Attempt10: actual NativeScript parity startup failure

The exact original parity case executed and **failed** on source fda6948ca6a1f541293a1a1dd20e97f75eb0a527: **0 passed, 1 failed, 0 skipped**, 68.975 seconds. The test's result bundle finalized, and its raw exit65, summary, node tree and collector error are preserved. This is a single controlled diagnostic; **the original 52 acceptance remains NOT_RUN**.

## Directly observed cause boundary

The retained actual process sample caught the main thread inside NativeScript runMainApplication -> executeNodeSync -> HanlinExecuteSyncWithTimeout while the worker was inside NodeRuntimeService.prepareHostRuntime -> ZIPFoundation.unzipItem. The JSC job had already completed successfully in 8 ms with the expected nonce. Python later completed in 231 ms; no parity Node job or completed host-ready event is present in this frozen packet.

This localizes an actual main-thread compatibility wait during cold Node preparation. It does not support blaming a failed JSC computation or a stale callback binary. The sample starts approximately 0.48 seconds after RUN_MAIN_BEGIN: its header's 31 seconds since process launch is **not** a 31-second unzip measurement.

Both the original “Parity-App-Launched” and failure PNGs were visually inspected. They show the Apps catalog and HanlinScript Parity card, without a presented runtime screen or nonce labels. The corresponding AX records agree. The existing test's title predicate can match that catalog card; an exact runtime-title identifier is a justified strengthening.

## Async and fixture impact review

The original async Node provider invokes the broker without a local 20-second timer. The broker starts the engine before submitting its request, whose default execution deadline is nil. Node's distinct 20-second Host-ready handshake starts **after** archive extraction and native startup. The existing sync bridge's 20-second wrapper is a separate compatibility deadline.

The reviewed fixture candidate prefers the existing async selectors. Invoking a void-returning Objective-C method counts as acceptance and returns immediately; there is no second fallback call. Receiver binding, original payloads, error conversion, nonce checks, storage/relaunch and inter-app callbacks remain intact. This read-only review is not a native test pass. The original 25-second Node UI wait did not establish cold-start readiness. After this review, root reported a separate test-only correction using a 180-second Node-readiness assertion within the unchanged 420-second case budget, with exact runtime-title identification and all real nonce/error/storage/relaunch assertions retained. Its corrected native result is still pending; no completed cold-start duration is inferred from the old failure.

The parity archive is copied into Documents by the original paired runner and hash-checked. It is not a direct SDK source input, SDK member, source-inventory row, native-catalog input or Xcode project resource. The six-member baseline archive is 7,396 bytes, SHA256 2c31e104d2b8e7a8c7356e3d2a15c2537e79266a1df1a8de7846deeddc923cc3, and matches its source members after CRLF-to-LF normalization, exactly as the existing fixture test requires. All six archived members differ in raw line endings from Git. In particular, the actual archived bundle hash is f266852fe1217562d2f92b3437cc8c95e4185800ed7e72ee9c4c25448a98494a, while its Git source hash is 7d0fb4935d1727e04d656bb4ba026509fb0720178d27d442d480b6dfcb102204; neither identity is substituted for the other. A fixture-only correction needs matching source/archive and exact restaging; a separate Swift title-assertion edit requires a test-bundle rebuild.

Full Host preparation always regenerates source-commit provenance before checking its cache. Reinvoking it unnecessarily would create a fresh SDK identity even though the fixture is outside that dependency. Existing SDK10/build evidence may be reused only with the actual unchanged relevant input closure and explicit source-delta accounting.

## Preserved artifacts and limits

All 46 original members (5,082,912bytes) and the original receipt 56cd644b34012d4e4f690621f7c734bc0d3b58143d3fa9e6605e822a8c91161f are retained. The two large text files use lossless gzip; every PNG, attachment mapping, finalized result, job journal and raw controller checkpoint is preserved. The earlier immutable packet continues to describe the separate remaining three-case command as pending at its capture time.

raw-bindings.json maps original and stored identities. assessment.json contains exact sample/job/result boundaries and visual observations. fixture-impact.json binds the read-only source and archive dependency trace. No Mac query, generator, compiler, test, fixture mutation or production-source edit was performed by this evidence lane.
