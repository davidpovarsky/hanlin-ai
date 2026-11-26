# SDK19 preparation and exact export — 25 November 2026

## Result and scope

Independent streamed verification passed for the actual SDK produced from a2c8a1b1be746461272ba77254603304567c309d (tree c3cfefa7775c91e2b2a9eaff980bbde6e681cc37). The producer completed its original ten-step preparation at 10:44:03.195469 UTC. It charged 266.8272158750042 seconds; earlier unsuccessful attempts remain in the original records.

This evidence establishes exact source, generated output, SDK and export identity. It does not turn earlier UI failures or the new focused/full acceptance gates into passes. Historical SDK18 is unchanged.

| Item | Bytes/count | SHA-256 |
|---|---:|---|
| Host archive | 81,824,721 | 7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc |
| Exact SDK manifest | 5,224,120 | 4505c28495d8b6ecd1073254e0e395adcc898cc02dd1d40699591f51db4dee92 |
| Canonical source input list | 235 | ba8f3f1f09054887eed62532fa1d5ca2ac3bd60e6aa99a98ab1035c7653882a2 |
| User SDK export | 68,726,642 | 1bf347311b9547054725f8674419a11b3c502a4994feb6dbd9283c3af7400210 |
| SDK18 to SDK19 exact delta | 2,683,094 | 6974fe7da2dceadec9cac10a328f9053e079c5dc92956081b1f35715bff22de9 |

## What changed

Exactly four SDK source-input rows and four packaged file rows differ from SDK18: the TextEditor JavaScript wrapper and the three generated source/reachability documents. All other 231 inputs and 25,665 file rows retain their SDK18 identities. The source sets and engine package versions are unchanged. The wrapper is b95b387fce797a3c0ffe8c258e1fe0b411e76956e6cd50ae9235267f5b638da6; the matching native adapter is independently bound to canonical source 3ad8217ce87005fab1fe3dc256e7d7680ced7c330f7cd9dc5561f1a5e5905e09. Native adapter execution requires the newly built consumer, which this SDK-only record does not claim.

The broader prepared source has 25 exact rows totaling 14,676,062 bytes: seven logical Expo fixture archives copied into two original locations, and eleven original generated project/lock/runtime-receipt/documentation outputs. The eight additional paths relative to SDK18 are the four NativeAPIProbe archives at the two original locations. The original producer rebuilt them; this reconciler did not generate or compile them. Both copies of each logical fixture are byte-identical.

Package.swift, the generated Xcode project, Expo package.json/package-lock.json and unified-package-manifest.json retain their actual SDK18 prepared bytes. Their new generation receipts correctly bind the new a2c8 source. The resolver still selected @types/react19.3.2; it was not forced back to an old version.

## Verification performed

All 43 original retained files were checked against their receipt hashes, byte counts and modes. The complete Host archive hash was checked; its exact manifest matched the retained manifest. The canonical JSON source-input hash was independently recomputed, and every input was checked against the exact a2c8 Git blob or retained generated payload. All 25,669 manifest members were streamed and checked for byte count and SHA-256; the complete unique SDK ZIP member set is those files plus the manifest.

The user ZIP contains all 25,670 MiniAppSDK members, including original modules, declarations, licenses, documentation and both complete authoring examples. Original compressed local records were copied; only relocated directory offsets/EOCD were rewritten. An independent second read compared every decompressed member byte-for-byte and all seventeen metadata attributes (the exact ledger corrects an eighteen-versus-seventeen prose typo in the original export receipt; see metadata-count-clarification.json). Total uncompressed size is 299,642,745 bytes. The exact delta was independently streamed against the authenticated SDK18 base and reconstructed the full new ZIP hash without writing a redundant ZIP or expanding the SDK tree.

The full 25-row before/after table is in prepared-source-materialization.json. Every before hash/Git mode matched a2c8; every after hash/byte count/mode matched its immutable retained payload. Nothing was materialized into production source by this work. The fourteen binary fixture payloads and complete Host/user ZIPs remain at their authenticated shared transfer paths; this evidence directory does not make redundant binary copies.

## Original declaration and compiler boundaries

All five existing deterministic declaration-only corrections were bound to their exact shipped members: three React Native0.88.1 generated declarations and native-api9.1.2 Runtime/UIKit declarations. These are documented compatibility transformations, not a claim that every declaration is an untouched upstream byte. Their reasons, original/corrected hashes and implementation-source bindings are preserved in provenance-details.json and the original corrections receipt.

Four actual documentation projects passed with zero diagnostics. Expo and both ScriptWidget projects checked dependency declarations with skipLibCheck=false. The existing NativeScript guide policy uses strict=true, checkJs=true and skipLibCheck=true; this record does not claim that its dependency declarations were all compiler-checked. These four guide projects are distinct from the separately executed SDK-only example UI cases.

The Expo package wrapper reports TypeScript6.0.2 and its locked actual compiler API reports6.0.3, as explained by the previously sealed original-wrapper/alias provenance; the bytes did not change here. NativeScript uses5.9.3. ScriptWidget's mixed revision string continues to include two explicitly authored host-adapter derivation rows; its current original source group and adapter boundaries are unchanged and separately documented.

## Generated graph and surface claims

The actual native artifact catalog has fifteen original framework targets and zero missing targets. The generated shared Xcode project separately includes HanlinMiniAppsNotificationService; that app-extension target is not a sixteenth vendor framework. The original ExpoAsset device/simulator producer has input4939d8a43c4a36e9373396d26fbf46f12c30eff34ee57f486dc1a07acb0c4d83, and all23 retained stage/target member comparisons agree.

The refreshed source inventory contains94 scoped API/source rows and the reachability matrix80 cells. Both identify a2c8 and retain IN_PROGRESS_SOURCE_AUDIT semantics. Their generated acceptance fields do not claim real surface passes or a physical device run. Actual app, OS-surface and device evidence is reported separately.

## Prepared source table

Full before/after hashes and exact absolute payload paths are in the JSON materialization plan. SHA prefixes below are navigation aids only.

| Prepared path | Bytes | Git mode | After SHA-256 prefix |
|---|---:|---|---|
| AI_HLY.xcodeproj/project.pbxproj | 252023 | 100644 | a80e2947b4dedf0c |
| AI_HLYUITests/Fixtures/ExpoNativeAPIProbeA.hanlinExpo | 1403392 | 100644 | c050720db91ffb2c |
| AI_HLYUITests/Fixtures/ExpoNativeAPIProbeB.hanlinExpo | 1403384 | 100644 | 794c7a2237c32166 |
| AI_HLYUITests/Fixtures/ExpoNativeAPIProbeIncompatible.hanlinExpo | 1403399 | 100644 | c83750124f425972 |
| AI_HLYUITests/Fixtures/ExpoNativeAPIProbeMissingGrant.hanlinExpo | 1403397 | 100644 | 9bf9cd16e84d7c1c |
| AI_HLYUITests/Fixtures/ExpoSwiftUIProbe.hanlinExpo | 325934 | 100644 | 6475c3f5d37620ad |
| AI_HLYUITests/Fixtures/ExpoSwiftUIProbeA.hanlinExpo | 325934 | 100644 | 6475c3f5d37620ad |
| AI_HLYUITests/Fixtures/ExpoSwiftUIProbeB.hanlinExpo | 325935 | 100644 | 6131172f65aaeab7 |
| Fixtures/ExpoNativeAPIProbe/ExpoNativeAPIProbeA.hanlinExpo | 1403392 | 100644 | c050720db91ffb2c |
| Fixtures/ExpoNativeAPIProbe/ExpoNativeAPIProbeB.hanlinExpo | 1403384 | 100644 | 794c7a2237c32166 |
| Fixtures/ExpoNativeAPIProbe/ExpoNativeAPIProbeIncompatible.hanlinExpo | 1403399 | 100644 | c83750124f425972 |
| Fixtures/ExpoNativeAPIProbe/ExpoNativeAPIProbeMissingGrant.hanlinExpo | 1403397 | 100644 | 9bf9cd16e84d7c1c |
| Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIProbe.hanlinExpo | 325934 | 100644 | 6475c3f5d37620ad |
| Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIProbeA.hanlinExpo | 325934 | 100644 | 6475c3f5d37620ad |
| Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIProbeB.hanlinExpo | 325935 | 100644 | 6131172f65aaeab7 |
| Package.swift | 88328 | 100644 | 392ece3430f8e61e |
| Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Resources/ExpoWidgets.bundle/original-runtime-receipt.json | 6085 | 100644 | 930fa2685c39e238 |
| Scripts/Expo/package-lock.json | 336324 | 100644 | 3b31e1c8fd34145d |
| Scripts/Expo/package.json | 1759 | 100644 | bb447094c0ef2250 |
| Scripts/MiniApps/upstream-resolution.json | 15092 | 100644 | 28a724580a5c7b03 |
| docs/agent-sdk/unified-package-manifest.json | 3901 | 100644 | dd14c80e4223465e |
| docs/miniapp-sdk/MANIFEST_REFERENCE.md | 118804 | 100644 | 283c96260a51c095 |
| docs/miniapp-sdk/extension-reachability.json | 153644 | 100644 | 84849e4928f42f1b |
| docs/miniapp-sdk/extension-reachability.md | 23332 | 100644 | 3742686d8b088e8c |
| docs/miniapp-sdk/source-inventory.json | 494020 | 100644 | de8326436f4ecb7f |
## Immutable history and pending acceptance

The historical MiniApps25 result remains22 passed /3 failed /0 skipped. The separate AI diagnostic remains21 executed,19 passed /2 failed /0 skipped with six selected methods absent; it does not replace the original27 gate. The corrected source preserves those actual failures and addresses the native TextEditor lifecycle/acknowledgement, exact deletion locator, wide-chat repair composer, ActivityKit state observation and six Swift Testing selector identities. This preparation/export record does not assert those corrected native cases have passed.

The focused Mini3+AI8 controller is separately reviewed and executed by the sole native owner. Original52, NS5, notification OS callback, and physical owner-route results remain distinct. No native test, compiler, SDK generator, package download, Mac query, Asana operation or production-source mutation was performed by this reconciliation.
