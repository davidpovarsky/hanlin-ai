# Full build passed; original SDK resource scan blocked run 45246711373

**Full arm64 application and test build: PASS. Current unit products validation: PASS. Runtime copy signature verification: PASS. Resource scan: FAIL. All 342 authored expected test invocations: NOT_RUN. Native publication: BLOCKED.**

[Run 45246711373](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45246711373), attempt 1, used `36d3c51bdba93ada2c2722ed0e9b99109d84a616`. The overall producer failed. Its native job was `137945550349`. The original API records, smoke archive and selected original scan/build receipts are retained here. This review ran no build, simulator or test.

## What actually completed

| Original workflow stage | UTC interval | Result |
|---|---|---|
| Build full arm64 simulator app | 19:30:54–19:50:10 | PASS |
| Validate current build-for-testing unit products | 19:50:10–19:50:11 | PASS |
| Locate and scan simulator app | 19:51:27–19:51:42 | FAIL |
| Run simulator test suite | Skipped | NOT_RUN |

The original job log records final application CodeSign at 19:49:39, Validate at 19:49:54 and `TEST BUILD SUCCEEDED` at 19:49:58. The separate runtime-copy signature log reports valid-on-disk and satisfaction of its Designated Requirement. These support a completed build and code-signature validation. They do not establish launch, conversation, EventKit, native tool, UI or model behavior.

The original unit descriptor receipt is now **SEALED**, with no prior descriptors and five original binary/plist hash references. Its build-log hash, generated xctestrun hash and diagnostics-provenance hash were matched to the actual original artifact bytes. The two retained xctestrun copies are identical. Product binaries are absent from this small archive, so their hashes are authenticated original runner references rather than independently rehashed binaries. The receipt records a modified tracked workspace and its exact diff hash; it makes no pristine-checkout or all-fresh-compilation claim.

## Exact scan failure and ownership evidence

The original scanner stopped on:

> Expected one AI_Hanlin SDK resource bundle, found 2: Frameworks/HanlinApplication_3ED3A7D0B493F0DF_PackageProduct.framework/HanlinSDK_AI_Hanlin.bundle, HanlinSDK_AI_Hanlin.bundle

The original copy commands identify one source build-product path, `Debug-iphonesimulator/HanlinSDK_AI_Hanlin.bundle`, used by the dynamic `HanlinApplication` framework and app root. A third copy goes into the unit-test plug-in. The runtime scanner reports the two application copies. The same source path explains the graph; it is not a post-copy byte comparison of the two bundles. Full bundles are not present in the smoke artifact. `original-log-excerpts.json` retains the exact copy and final-build headers with raw-log line numbers and digest binding.

The integration owner owns the scanner/resource-ownership correction. This evidence change modifies no production or validator code and does not remove either runtime bundle.

## Existing metadata evidence reused

The current NativeScript original metadata files and all ten retained AppIntents compiler metadata/file-list files were compared with the previously authenticated [452388 evidence](../nativescript-metadata-45238831508/README.md). Exact per-file results are in `metadata-reuse.json`. The current original NativeScript visibility remains `HOST_BASELINE_ONLY`, with zero Clang errors and all ten required names present. No unsupported-AppIntents-bundle diagnostic appears in the original job log. This comparison authenticates retained output and reuses the prior scope; it executes no metadata or acceptance control again.

The build-result xcresult is retained inside the smoke ZIP. It is not an executed test-result tree. The workflow skipped the test step, so the 32 requested scopes and 342 authored expected invocations remain **NOT_RUN**. The 27 unit selectors in the sealed receipt do not represent 27 passing tests; the remaining requested scopes are UI selectors.

## Acquisition and release boundary

Artifact `14856943977`, `AI_Hanlin-iOS26-simulator-smoke-logs`, was acquired once. Its API run/source identity, unexpired status, advertised byte count and digest, all 70 member CRCs, safe paths and non-symlink entries were verified.

| Original retained material | Bytes | SHA256 |
|---|---:|---|
| Smoke ZIP | 3,812,403 | b0e060b4472132dae4b938ad36e8abf1d23ac35d9604f1ebe1efbded0b5c9e0a |
| Parent-owned native job log, reused without download | 18,670,980 | 36ec059cdadb68070c67db73ddc2bf935c3a475bddef228204aa16cf538f735b |
| Original xcodebuild log inside ZIP | 14,585,027 | 5d581a3ce3c747a662ef06ae77519c968a809e6e4a0c00d34bad101dbb77b86e |

Prepared Native artifact `14855355631` remains **INELIGIBLE** because this producer failed. It was not acquired or published. All 18 Native publication slots and final Host installation/pin updates remain held pending an eligible successful producer. The source-qualified historical Host acceptance remains at its previously documented scope; a successful build alone does not expand it.
