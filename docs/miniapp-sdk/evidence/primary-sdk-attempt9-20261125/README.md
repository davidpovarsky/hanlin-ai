# Actual attempt9 SDK and original native preparation reconciliation

**The actual SDK and completed preparation identities are reconciled. Application builds, focused runtime observations and the original 52-case acceptance remain separate.** Execution source is `1812bff50571c9907d15cd8b4bfbe4874be24756`. The immutable snapshot was captured at **2026-11-25 00:37:54.446694 UTC**, after preparation, export and input phases completed, with the controller paused after `split-inputs`.

## Exact identities

| Item | Actual value |
|---|---|
| Host resource ZIP | 81,813,684 bytes |
| Host ZIP SHA-256 | `3c94ebea1e314c280031ac475e2d42b63ebcf2dc2eb32d2c6e31905e3eda3240` |
| SDK manifest | 5,219,389 bytes |
| SDK manifest SHA-256 | `6fbba77d588e292b291864f0cae9e5eb5d602a4e2f208379ce1c331dedf412c9` |
| Recomputed SDK input SHA-256 | `4904d0a46e4c653587fa1503a059834e9b6f35eac821a286d5eb9e96b8a92011` |
| Shipped authoring module SHA-256 | `fa5121902e231d5d44ad08bf47699784fd4d0bc2a98102f3a156e6e4ae79b9b9` |
| Actual native catalog SHA-256 | `c2c8a3624236d252ad82fd42db967cbf76902c54c89f8cfb39a0f7be77fb710b` |
| Native catalog producer content identity | `9b3b714bf5a29ac92472e5ffe530ec0c2f6ebf79f65faa506ad0d7f8ce88e37b` |

The inspector verified all **23 transfer members**, all **222 SDK source inputs**, and the hash, size and exact set of **25,661 actual SDK archive members** comprising 294,393,847 uncompressed bytes. The archive was inspected in place without extraction or duplication. Against SDK7, 11 source inputs changed and 211 remain equal; 11 SDK member records changed and 25,650 remain equal. All 3,102 actual outside-SDK Host members were also compared: only `miniapp-authoring.mjs` changed; 3,101 remain byte-identical.

## Original ExpoAsset and the current type publication

The prepared SDK has **21 Expo package-version keys**, including original `expo-asset@58.0.21`, and the native-plugin host contract contains the same exact version. All 109 shipped ExpoAsset package members are byte-identical to SDK7's original transitive package. This correction makes the package an explicit authoring/API/type authority and supplies its previously missing native host module.

The unchanged public `readMiniAppSDK` implementation derives these actual resource locators from the new manifest/package metadata:

| Resource | SDK-relative path |
|---|---|
| Original package metadata | `expo/node_modules/expo-asset/package.json` |
| Original public declarations | `expo/node_modules/expo-asset/build/index.d.ts` |

The TypeScript module/type/config resolver and Metro canonical-package authority read the same package-version keys. The inspector bound those source rules and actual resources; it did not execute a second SDK endpoint or compiler.

The original upstream resolver selected **`@types/react 19.3.1`** during attempt8, and those prepared package/lock bytes were preserved into attempt9. Four original package members changed: package metadata, README publication date, and two declaration entrypoints. Both declaration changes are exactly `TouchList.item(index: number): Touch` becoming `Touch | null`. Thus **5,208 of 5,210 declaration members remain byte-identical to SDK7**; the two changed members come from the newly locked original publication, not a new Hanlin patch. The exact original tarball URL/SRI and byte diffs are retained.

The existing TypeScript alias binding is unchanged: original `@typescript/typescript6@6.0.2` contains the 45-byte wrapper for the locked `typescript@6.0.3` implementation under `@typescript/old`. All four wrapper/implementation package and code hashes match the retained prior proof. The new whole Expo lock hash is not mislabeled as unchanged.

## Five pre-existing declaration corrections

`Scripts/Expo/prepare-types.mjs` is unchanged from SDK7. Its actual fresh `corrections.json` names current original packages `react-native 0.88.1` and `@nativescript/react-native 9.1.2`. The five current corrected declaration bodies remain identical to SDK7 and the prior audited substitutions:

| Original package/file | Exact compatibility correction |
|---|---|
| React Native, `AnimatedProps.d.ts` | The style property and index signature admit the nullable/optional style accepted by the original Flow implementation. |
| React Native, `VirtualizedList.d.ts` | Uses `InstanceType<VirtualizedListType>` for the actual exported class constructor. |
| React Native, `ReadOnlyNode.d.ts` | The base `textContent` getter admits `null` returned by the original Document implementation. |
| NativeScript React Native, `Runtime.d.ts` | Keeps `timezone` and `dyld_shared_cache_ranges` as interfaces; the actual conflicting globals are constants and are not installed as struct constructors. |
| NativeScript React Native, `UIKit.d.ts` | Exposes `description` as the string property returned by the original JS host object. |

Reversing only the **seven exact substitutions** reconstructs all five pinned original declaration hashes. The corresponding original JS/Objective-C implementation hashes also match. The producer rejects changed/unrecognized source bytes; strict checking is retained. The older 2026-11-14 proof remains historical: it named React Native 0.88.0, while the same affected original bytes remain present in current 0.88.1. No historical result was relabeled. The report does **not** claim every shipped declaration byte is unmodified, or that these five corrections describe every other previously documented preparation transform.

## Original native product binding

The actual prepared catalog contains **15 required targets, zero missing**, adding ExpoAsset without removing an existing target. All 16 direct catalog input hashes bind to the current source/prepared payload; four differ from SDK7. Existing 14 targets retain identical library records and binary hashes when compared by slice identifier. The ExpoUI and ExpoModulesJSI outer archive checksums differ and are reported separately; raw archive equality is not inferred from equal binary hashes.

The actual ExpoAsset producer used its original npm publication, Expo CLI/CocoaPods definition and Xcode device/simulator builds. Its 23-member staged-product to prepared-XCFramework comparison matches, including device arm64 and simulator arm64/x86_64 binaries. The native catalog binds the same two binary hashes. These distinct identities are retained explicitly:

| Identity role | SHA-256 |
|---|---|
| Original npm tarball | `2bfbb115da9111702530e5df550eac7e2a074aa12b6297fcc332744767623126` |
| Original source build input fingerprint | `a85fc86c413d87679e62878cc4b7b512e925c36806a9b383daf095dab9c55159` |
| Actual source-build receipt file | `78a6b4b85330189dd162c09ae250cb280bf7dbe62608ca6438e6f3fabde6ee3b` |
| Exported ExpoAsset XCFramework ZIP, 236,835 bytes | `5786adf1e037e948ec74cc722bb4eb4f59089aad839e7abc8c254196c143d53e` |
| Actual device binary | `bc4ec32879fe696af9246f6d2280c75f95ac7a136b712ba4e823d7e9c8e5c90e` |
| Actual simulator binary | `61fb7c7abb126eb34b1b7c5ce7cd99b6d0c0ba22bc1767f19da38a9a191bbd94` |

The source build was completed during attempt8 and reused by the normal attempt9 producer only after its input fingerprint matched. The 4MB original attempt8 log is retained losslessly compressed. The inspector did not fetch or extract the full native export or rebuild the framework.

## Nine prepared source files

All nine payloads total **1,150,910 bytes**, mode `100644` with no mode changes. Full paths, before/after hashes and exact handoff selectors are in `prepared-source-delta.json`. Canonical materialization binding: `651412fc7d95567ac27daa6c757bd3aa2f3cacaf6e50f85e6e96348073f64600`.

| Prepared path/group | Verified classification |
|---|---|
| Xcode `Package.resolved` | Serialization-only; parsed JSON, all 39 pin records/revisions and originHash unchanged. |
| Original Expo Widgets runtime receipt | Only package-lock and producer-input hashes change. |
| Expo `package.json` and `package-lock.json` | Original React types 19.3.0→19.3.1; root pin plus original version/tarball/SRI. |
| `Scripts/MiniApps/upstream-resolution.json` | Adds actual original ExpoAsset publication/artifact and React types 19.3.1; all nine prior native-artifact records equal. |
| `MANIFEST_REFERENCE.md` and `source-inventory.json` | One new ExpoAsset plugin field, the already-published actionIdentifier schema reference, current source hashes and line anchors. 335 mapped fields versus 334; 13 source hashes update. |
| `extension-reachability.json` and `.md` | Source commit and source-hash provenance; the existing 80-cell matrix and other source/acceptance data remain equal. |

No production payload was materialized by this lane. The root owner decides exact publication using the verified nine-file binding. The four older SDK7 generated documents remain historical and must not be substituted for this current payload.

## Actual executions and timing

All four original documentation projects passed with **zero diagnostics** against this exact SDK/authoring module: Expo, NativeScript, ScriptWidget and ScriptWidget controls. The report binds 14 source fences, seven JSON fences, eight explicit non-authoring exclusions and each original checking policy. All 29 example members are unchanged.

The actual full Host test run reports **170 tests: 169 passed, zero failed, one existing opt-in long-duration test skipped**. The exact skipped case and raw log are retained. Changed Host regression sources participate in the existing producer's source fingerprint; Tests are not shipped in the ZIP. These counts do not stand for the 52 application cases.

Attempt8 remains a terminal preparation failure at **00:19:13.587171 UTC** with the exact unmapped-ExpoAsset diagnostic. The one-row audit mapping fix is published in execution source 1812. Original attempt9 audit generation and checking now passed against 93 sources /176 local exports, and the 80-cell source reachability check passed. No source-only check is relabeled as runtime acceptance.

Actual source advance: **00:28:24.313552 UTC**. The attempt9 admission began at 00:28:43.295691, admitted after 210.879522 seconds, and heavy preparation began at **00:32:14.426385**. Preparation passed at **00:36:12.754085** after 238.327093 seconds; native export passed at **00:36:34.899130** after 22.142236 seconds. Inputs completed at 00:36:45.990397. The Host lifecycle prefix retains its actual attempt8 timestamps and is explicitly recorded as reused, not freshly executed in attempt9.

The capture at 00:37:54 was paused after inputs. Consumer builds, installation, real callbacks, original 52-case outcomes, physical-device evidence and screenshot inspection/export are separate subsequent obligations. Later observed results supersede this checkpoint without rewriting its raw evidence.

## Inspection method

The three retained inspection scripts only read immutable Git objects and actual shared output bytes, and write evidence in this worktree. They ran no product generator, TypeScript compiler, native build/test, package manager, Mac query, CI or SDK repack. Every artifact in this commit is evidence. The complete archive remains in the shared immutable handoff; its verified identity is recorded instead of copying 81MB into the repository.
