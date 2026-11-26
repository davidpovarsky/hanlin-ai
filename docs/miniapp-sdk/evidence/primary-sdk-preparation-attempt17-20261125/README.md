# Prepared SDK16 — actual attempt17 snapshot

Status: **PREPARED_SDK_RECONCILIATION_PASS**. This evidence records source preparation and exact authoring SDK contents; it does not claim current consumer builds or application acceptance.

## Exact identities

| Object | Bytes / count | SHA-256 |
|---|---:|---|
| Source commit | cffe | cffe7f75436aa2e37ec5d82891937965c0407d2d |
| RuntimeHostResources.zip | 81,823,972 | 4c71d23f55391e0b7eb87073bea65bec8b323d6f688214b60e49b9600c80e857 |
| miniapp-sdk.json | 5,224,120 | 0ef02a708019c0401c50222e4186f0bbad2e6576fdc333b7d748eb7702cad66f |
| SDK input identity | 235 | d381e9db6bce1c74e1c52ff43d7f948d23f5ad07a103701dbf442327f420ed31 |
| User SDK ZIP | 68,725,893 | e2aa6797377c3dc805c9557c73beba7d2d9f60af02285e6d04a6687041ab08ec |

The user ZIP contains all25,670 MiniAppSDK members. A separate read of source and export verified every member’s bytes, metadata and CRC, plus all25,669 SDK manifest file rows. Original compressed records were copied without regeneration or recompression.

## Source and package reconciliation

All34 original handoff files, the full Host ZIP, retained SDK manifest and235 source-input bindings were verified. Relative to SDK15,229 inputs are unchanged, five changed and the existing canonical project parser is one new explicit input. The five changes are the notification delegate, SDK input declaration and three generated provenance documents. Exactly three packaged file rows changed; the other25,666 and all engine contracts are identical.

The project target list now matches all15 actual root-declared PBXNativeTarget objects, including both products and their own notification extensions. This15-project-target count is separate from the original15 vendor/native framework catalog targets. All80 source matrix rows are unchanged. Notification’s10 rows remain partially-wired with realSurfaceE2E=false and onDeviceProof=null.

The earlier narrow93-source API/runtime inventory retains its stated scope. The notification wire, delegate and target closure is bound through the full SDK source inputs and separate reachability source references.

## Prepared source materialization

No generated product file was materialized by this commit. The complete13-row plan supplies before/after hashes and modes plus losslessly retained payloads. Only the last three provenance documents differ from SDK15; graph generation still originates from actual b0 generation.

| Path | Bytes | Before SHA-256 prefix | After SHA-256 prefix |
|---|---:|---|---|
| AI_HLY.xcodeproj/project.pbxproj | 251,761 | 24206ae0f0f66d36 | 71409346bb25cdc8 |
| AI_HLYUITests/Fixtures/ExpoSwiftUIProbe.hanlinExpo | 325,823 | e9b662011c5ef37c | b81e8ecccb8e8495 |
| AI_HLYUITests/Fixtures/ExpoSwiftUIProbeA.hanlinExpo | 325,823 | e9b662011c5ef37c | b81e8ecccb8e8495 |
| AI_HLYUITests/Fixtures/ExpoSwiftUIProbeB.hanlinExpo | 325,825 | 843b3147f81c4022 | cdf1b95be3e21062 |
| Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIProbe.hanlinExpo | 325,823 | e9b662011c5ef37c | b81e8ecccb8e8495 |
| Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIProbeA.hanlinExpo | 325,823 | e9b662011c5ef37c | b81e8ecccb8e8495 |
| Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIProbeB.hanlinExpo | 325,825 | 843b3147f81c4022 | cdf1b95be3e21062 |
| Package.swift | 88,332 | 2238e4db391c3460 | c58ad5f37b35c38e |
| docs/agent-sdk/unified-package-manifest.json | 3,901 | 3051ec46a9e5bcde | 2dce00d3544b324e |
| docs/miniapp-sdk/MANIFEST_REFERENCE.md | 118,804 | 768731f0c748276a | 283c96260a51c095 |
| docs/miniapp-sdk/extension-reachability.json | 153,517 | 9a9843d277a3e76a | e8532f65e6dca533 |
| docs/miniapp-sdk/extension-reachability.md | 23,332 | cae21720cab9b312 | f164b2e5c8b1271d |
| docs/miniapp-sdk/source-inventory.json | 493,798 | 856bc8aca1473f8f | e2aa1346d6c5409f |

## Actual documentation and upstream boundaries

| Guide project | Diagnostics | Compiler | skipLibCheck |
|---|---:|---|---|
| expo-guide | 0 | 6.0.3 | false |
| nativescript-guide | 0 | 5.9.3 | true |
| scriptwidget-guide | 0 | 6.0.3 | false |
| scriptwidget-controls | 0 | 6.0.3 | false |

These are the four original guide-snippet checks, not a new execution of the exported complete example projects. The original Expo TypeScript wrapper6.0.2 resolves its locked actual compiler6.0.3; prior source/lock/member proof remains applicable.

Five existing source-backed declaration corrections remain byte-identical to SDK15: React Native AnimatedProps, VirtualizedList and ReadOnlyNode, plus NativeScript NativeAPI Runtime and UIKit declarations. Their original, corrected and implementation-source hashes are retained in the producer receipt and completeness record. No declaration patch was added here.

Original ExpoAsset stage/target bindings and source-build receipt remain unchanged. The vendor catalog has15 required targets and zero missing; exported binaries, source receipt and archive checksum are distinct identities.

## Export recovery and acceptance boundary

Preparation passed once in148.339252042s. The first export’s original framework export/slice checks passed, then its final copy failed because the new evidence directory lacked upstream-inputs.patch. The failure/state are retained unchanged. The native owner authenticated the identical prior patch, restored it and reran only original export/restore/input phases, which passed in21.744382667s,6.746599458s and4.892271583s respectively.

The immutable capture is PAUSED_AFTER_PHASE through split-inputs. Consumer builds, installed notification .appex identity, original52, NS5 and real notification OS delivery require their separately observed results. This review ran no compiler, native command, test or SDK producer.
