# Original versioned native framework export

## Observed failure and repair

Hanlin run [45119023783](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45119023783) at `d49a4fd4115b8335105d2991bf74ab4d7f6aad2d` passed native preparation and RuntimeCore preflight, then stopped in **Export original prepared Hanlin SDK native artifacts**, before app compilation or XCTest. The exporter looked for `TNSWidgets.framework/Info.plist` in the Catalyst slice.

The exact locked `@nativescript/core` 9.1.0 package reproduces the failure in both original frameworks. Its Catalyst metadata is in `Resources/Info.plist`; its XCFramework descriptor explicitly declares `BinaryPath` under `Versions/A`. The package has no root executable alias. This is a versioned framework layout, not a missing native slice.

The exporter now reads framework metadata from the flat or Resources layout and honors the original descriptor's `BinaryPath`. The binary must remain inside that framework and match `CFBundleExecutable`. Catalog hashes point to the actual regular executable member, including when an original alias resolves through `Versions/Current`. All original platform, arm64 device/simulator, native header, archive inventory, checksum and boundary checks remain in effect.

A separately reproduced packaging defect involved a normal framework link chain: root Resources and executable aliases were checked before `Versions/Current` had been recreated. Extraction now creates all already-validated internal links before checking their resolved destinations and existence. A chained escape still fails. No runtime source, framework byte, platform slice, workflow or package manifest was changed.

## Genuine original artifact evidence

The source is the exact registry archive already selected by the failed producer's unchanged package lock:

- URL: https://registry.npmjs.org/@nativescript/core/-/core-9.1.0.tgz
- Size: 10,343,109 bytes.
- SHA256: `555ff58109fc8662c04e5c7dd119a93b596f44812b71928c27b1e201e3ecbf78`.
- Its complete SHA512 integrity matched the checked-in lock before extraction.
- Both original framework trees were extracted without executing npm scripts or compiling a runtime. The original preparation copies these trees unchanged.

The real exporter produced both ZIPs; the real verifier, checksum-protected extraction and complete post-extraction inventory comparison passed. Every file byte, directory/file mode and original entry was retained. `swift package compute-checksum` independently matched each generated ZIP checksum.

| Framework | Original slices retained | Exported bytes | SHA256 / SwiftPM checksum |
| --- | ---: | ---: | --- |
| TNSWidgets | 5 | 5,898,178 | `366ce209935200fbfb88074fb78592f24ea37067a42cc2f1724fd71d8a586f66` |
| NSCWinterTC | 5 | 2,843,711 | `134273c20e633b6f4ac3cf54bf0ebe0b9fd0c233b79ab3be4cc660bd46703f59` |

Each keeps iOS device, iOS simulator, Mac Catalyst, visionOS device and visionOS simulator. `original-framework-roundtrip.json` records the original archive integrity, all per-slice native hashes and complete before/after-equivalent inventories. These are original native bytes, not generated substitutes.

## Focused controls and evidence limits

Three new packaging controls passed once (six cases, 0 failures, 0.034 seconds): versioned metadata/explicit binary path with a Current-link roundtrip; foreign binary, mismatched executable, escaping metadata and missing simulator refusal; and a chained resolved-link escape refusal. The small unit fixtures test packaging only. The separate genuine-framework evidence above proves the actual locked artifacts can be exported and restored.

The original baseline exceptions remain in `baseline-reproduction.json` and `baseline-chain-reproduction.json`. `receipt.json` binds the failed producer/source/log and before/after exporter hashes; `focused-controls.json` binds the exact executed source and raw control log. The six earlier exporter controls were not rerun. Runtime builds and Apple test executions in this repair: **0**.

This selected-target packaging acceptance is not full SDK publication or an Apple app-build result. The next coherent producer must still export and verify all **14 native artifacts plus four support archives**, compile the current application, and execute its selected acceptance. Public catalog publication and the full consumer installer remain pending that actual producer outcome.
