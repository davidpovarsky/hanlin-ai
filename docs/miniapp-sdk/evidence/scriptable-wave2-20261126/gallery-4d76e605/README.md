# Original SDK gallery acceptance — 26 November 2026

## Executed result

All five shipped SDK examples completed the original `validate` and `build` operations successfully, with strict user-source typing and no diagnostics. The exact source was `4d76e6053662957281ffbcb0a2ad28fc4f0c2f89`; SDK input SHA256 was `48f09da9dc0ec43b5591db3a701d9572204b31785bf5049bae0044a78b191289`.

The driver called the production `runMiniAppOperation` from `AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs`. That module and its sibling `miniapp-assistant-tools.mjs` were byte-verified against the retained original Host ZIP before execution. The Mac owner separately owns Host/JITless acceptance. No SDK, compiler, dependency, or product source was changed by this gallery run.

| Example | Original compiler | Source files retained | Compiled files verified |
| --- | --- | ---: | ---: |
| nativescript-hello-world | TypeScript 5.9.3 | 7 | 7 |
| sdk-only-table-share | TypeScript 5.9.3 | 7 | 7 |
| nativescript-image-drawing | TypeScript 5.9.3 | 7 | 7 |
| expo-hello-world | TypeScript 6.0.3 | 8 | 4 |
| sdk-only-departure-budget | TypeScript 6.0.3 | 8 | 4 |

Every recorded source hash matched both the immutable SDK example and the prepared package's retained source. Every compiled hash matched the prepared output.

## Original typing boundary

NativeScript uses original `@nativescript/core 9.1.4`, `@nativescript/types 9.1.4`, `@nativescript/ios 9.1.1`, and TypeScript 5.9.3. Its original SDK base configuration has `skipLibCheck=true`. All user source was strict-checked; this receipt does not claim that every dependency declaration was checked.

Expo uses Expo 58.0.26, React Native 0.88.1, React 19.3.0 and the actual reporting compiler TypeScript 6.0.3. The original pipeline reports `skipLibCheck=false` and `dependencyDeclarationsChecked=true`.

The first driver added an unnecessary receipt condition requiring NativeScript dependency declarations to be checked. Its original validation operations succeeded, but the added receipt condition rejected their reports and stopped before building those three projects. This first receipt and log remain unchanged. The continuation reused all successful original operations and performed the three remaining NativeScript builds, preserving the original compiler configuration and acceptance contract. No original check or assertion was weakened.

The earlier recovery-graph drawing proof using types 9.1.0 is now superseded for authoring by this actual 9.1.4 consumer proof.

## Evidence

- `gallery-original-contract-receipt.json`: authoritative combined acceptance, SHA256 `df4b7b743999f0f48400f6e8dbad78f9500a34a66e119db8f993138252fa427b`.
- Ten separate original validate/build reports and the corresponding drivers/logs.
- `gallery-receipt.json` and `gallery-authoring.log`: preserved first additional-condition attempt; not the original product acceptance result.
- `preflight.json`: original Host module hashes and exact SDK identity.
- `transfer-receipt.json`: all 17 Mac-to-Oracle evidence file hashes.
- `asana-milestones.json`: verified milestone story IDs for Task10 and Task11.
- `wave2-required-native-gates-a356.json`: read-only reconciliation of the affected87 and separate paired selectors; no native execution claim.

The original operations ran on the pinned Mac Node 24.5.0 in `/Users/m1/builds/hanlin-wave2-gallery-4d76e605-20261126`. Prepared outputs remain there for the native owner. The continuation job was `job_9f5a30a9fcee`; the first additional-condition attempt was `job_100cd7c3f68e`.

## Still required

This is original authoring and package-build evidence. Native Studio tests, actual Files/iCloud behavior, gallery install/launch, the drawing example's four-angle UI and eight built-in invalid-input checks, original image raster tests, and OS Shortcuts/system widget acceptance remain separate gates. Build SDK iOS27.0 and available simulator runtime iOS27.2 (24B8117) are distinct. This proof does not certify the later a356 source fingerprint or physical-device execution.
