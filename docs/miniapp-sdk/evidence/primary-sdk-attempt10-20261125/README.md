# Prepared SDK10 and completed consumer binding

## Verified result

The actual SDK10 archive is reconciled to execution source `fda6948ca6a1f541293a1a1dd20e97f75eb0a527` and its nine preserved prepared outputs. All **25,661 SDK members (294,393,847 uncompressed bytes)**, their exact path set and **222 source-input hashes** were verified. Every one of the **3,102 outside-SDK Host members** was compared byte-for-byte with the sealed SDK9 archive.

Only three SDK members and source-input rows changed: `extension-reachability.json`, `extension-reachability.md` and `source-inventory.json`. These record the new source commit and NativeScript metadata-wrapper hash. The other 219 inputs and 25,658 SDK file rows are unchanged. All **5,210 declaration files**, 29 examples, original compiler bytes and all engine/package metadata remain identical to SDK9.

| Identity | Exact value |
|---|---|
| Snapshot receipt SHA256 | 20ee3233d5094aec1e3f476fecfa66dd43c9b64129f8e235a96529a6e9cfbb35 |
| Host archive bytes | 81,813,686 |
| Host archive SHA256 | 86733eba5d80156edf52da87f0f371c208122d6e60f618f182990330514984c3 |
| SDK manifest bytes | 5,219,389 |
| SDK manifest SHA256 | 19726b5eecc1459e30dae9e7ec4ca6761001de92b22055ac41b9a96aabdd7a88 |
| SDK source-input identity | 998e474dfeb225185e91ac4886d4b3aec517dfc55cd16cac0f46366b55494d56 |
| Host miniapp-authoring.mjs SHA256 | fa5121902e231d5d44ad08bf47699784fd4d0bc2a98102f3a156e6e4ae79b9b9 |

The changed full ZIP identity is preserved; it is not equated with SDK9 merely because API and compiler bytes are unchanged. The archive was inspected in place and is not duplicated in this Git evidence directory.

## Original libraries, declarations and documentation

Expo has the same 21 canonical package-version entries, including original ExpoAsset 58.0.21 and original React types 19.3.1. All 109 original ExpoAsset package members remain unchanged, and its package/type-resource and native-plugin authority remain present.

Five existing deterministic declaration compatibility corrections, comprising seven exact substitutions, remain explicit. The current producer hash, corrections receipt, corrected declaration bytes and original implementation-authority hashes match the already sealed SDK9 proof. This does not claim that every shipped declaration byte is unmodified. The prior automatic @types/react update remains original upstream content; it was not replaced or reverted.

The TypeScript alias identity is also unchanged: the declared original wrapper package reports 6.0.2 while its bound compiler API is 6.0.3. Both original package/compiler byte identities are retained through the exact prior proof, without executing the compiler again.

The actual producer reran the four original documentation projects with the current manifest: **expo-guide, nativescript-guide, scriptwidget-guide and scriptwidget-controls all passed with zero diagnostics**. Their original snippets, contexts and type-checking options are unchanged. The report distinguishes 14 source fences, 7 JSON fences and 8 existing nonauthoring exclusions.

## Native and producer checkpoint

The frozen producer snapshot was captured at **02:26:38.857016 UTC** with the controller paused after split-inputs. Native preparation and the original native artifact export had passed. Its lifecycle entry is the explicitly reused actual attempt8 PASS with its original time, not a new lifecycle execution.

The native catalog has all **15 required targets, none missing**. Existing framework library records and binary hashes match SDK9. The declared metadata-wrapper input changed from `0c053414f573ff2f88498099d7f1ae591d289ca3029390cd421dd938bf089ba3` to `71bf1d521abff7cc29c1e8d397a9ef2a55b09f758afb36f0a148be12350b664f`. The NativeScript and Node support archive checksums changed and remain reported separately; support bundles have no framework-library rows, so no binary equality is inferred for their entire archive.

Original ExpoAsset producer input `a85fc86c413d87679e62878cc4b7b512e925c36806a9b383daf095dab9c55159`, original package tarball `2bfbb115da9111702530e5df550eac7e2a074aa12b6297fcc332744767623126`, both XCFramework slices and all 23 owner-observed staged/prepared members remain bound. Full native exports were not copied again.

The actual Host producer reported **170 tests: 169 passed, 0 failed, 1 existing opt-in long-duration skip**. These are producer tests, not the 52 application acceptance cases. Source inventory covers 93 sources and 335 manifest fields, with 176 local public exports; the 80 reachability cells retain their source-analysis scope.

## Later completed consumer observation

A separate actual receipt at **02:34:55.936748 UTC**, SHA256 `d40cec6574c779f8e7dd191b28f5f11eeb57ef7c7d2a436ecb76ca330f63496e`, binds both completed consumers to this exact prepared archive:

| Consumer | Actual build result | Seconds | Embedded copies |
|---|---|---:|---:|
| HanlinMiniApps.app | exit 0, completed 02:31:11.210143 UTC | 104.742132791 | 1 |
| AI_Hanlin.app | exit 0, completed 02:34:30.328216 UTC | 197.404058500 | 4 |

All five actual app/test/framework resource copies match the complete archive, authoring module and SDK manifest identities above. The manifest binding also fixes the SDK input identity. The earlier prepared snapshot remains unchanged and accurately says consumer work was pending at its capture time. Installation, metadata validation and subsequent runtime cases are separate later observations. **The original 52 acceptance cases remain NOT_RUN in these retained receipts.**

## Later installed native metadata observation

The actual installed-metadata receipt at **02:35:37.625671 UTC**, SHA256 d58a79c7815fc9e7a14ae0c9d11bea492b1d08449aab761f2ee5ea6fd0c98234, retains both built/installed paths and exact native binary identities. The sole native execution owner and root reported their actual successful byte comparison. This lane verified the shared receipt and its section/name records without another Mac query.

Both installed __TNSMetadata sections contain **TNSLabel, NSCCrypto, UIView and HanlinNativeServicesBridge**:

| Product | Metadata bytes | Metadata SHA256 |
|---|---:|---|
| HanlinMiniApps.debug.dylib | 3,363,373 | 8720bf1bb3b498c049300d10b25ee137f6463ffdada5a68b4dbc1874f164e528 |
| AI_Hanlin.debug.dylib | 3,359,846 | 5a3385b02b9f1c626301a326d32068aadc5d6ef6ceb4fa5bae486a978321fbba |

This resolves the observed missing-name boundary from the retained metadata baseline. It does not establish a runtime test pass or complete API-by-API coverage.

## Exact prepared-source materialization plan

All nine actual payloads and their published before hashes/modes were verified. Total: **1,150,910 bytes**, nine content changes, zero mode changes; every Git mode remains **100644**. Six outputs are byte-for-byte identical to the prepared SDK9 outputs. The other three contain current provenance only.

| Prepared path | Bytes | Compared with SDK9 prepared output |
|---|---:|---|
| AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved | 9960 | Same as SDK9 |
| Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Resources/ExpoWidgets.bundle/original-runtime-receipt.json | 6085 | Same as SDK9 |
| Scripts/Expo/package-lock.json | 336324 | Same as SDK9 |
| Scripts/Expo/package.json | 1759 | Same as SDK9 |
| Scripts/MiniApps/upstream-resolution.json | 15092 | Same as SDK9 |
| docs/miniapp-sdk/MANIFEST_REFERENCE.md | 118804 | Same as SDK9 |
| docs/miniapp-sdk/extension-reachability.json | 147521 | Current provenance |
| docs/miniapp-sdk/extension-reachability.md | 21494 | Current provenance |
| docs/miniapp-sdk/source-inventory.json | 493871 | Current provenance |

The immutable payload root is `/mnt/development/projects/transfers/hanlin-primary-ce49-20261124/prepared-snapshot-attempt10`. Use each row's exact `contentFrom` in `prepared-materialization-plan.json`. The tracked ledger SHA256 is `0d97b8de1b354c375d5d47b4405f3cd10aa83d2cd6cf5c8ca5901b5796ad9e9a`. The canonical path/before/after/size/contentFrom binding is `2ede76e578db6102b726978de94fbd15507028644926cf5404af7cd0f8734834`.

| Path | Published before SHA256 | Prepared after SHA256 |
|---|---|---|
| AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved | 08fe8608ac946c2759a05389b69c5601039cff61f41ad24fa55cee8d222cc2c2 | 610bcbb9a7f90c27e3bd3ecd3b1d139fe3ff72ed18086327d1d96c437de932f5 |
| Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Resources/ExpoWidgets.bundle/original-runtime-receipt.json | f7ad6d7bf5841f5a0be2f722a1b2735620aa06dcf4801cb73210688a7a135e64 | 3d619674297acb22ae4d0a97f5e7d8a878b0eccbc3bfc49769cfdb5a05248a0b |
| Scripts/Expo/package-lock.json | 9ee1d2babe6266148d8f969b25f542c00897c569969e5aae6dd6f744e2a0c53c | c08757cf46ac4d5c86a873f676af4a3be585db64ae2e1aa1e8288277d4eb63b8 |
| Scripts/Expo/package.json | da083105462f40368adb89acba0dbc1b623d2249b26b2ac1cbe1d326edc2bd3d | e2b50fae013276229c78619bbbe0b63d8c29b00fefde3afeccea98af117aa206 |
| Scripts/MiniApps/upstream-resolution.json | 2bf8f371f06949fbe56858c38addeb417a07f9b598fc38ff72aedb39d5f364eb | e0c2944ea24c09330825dee58badedcec58606ba603ccdedc888abf1a63a13cb |
| docs/miniapp-sdk/MANIFEST_REFERENCE.md | ad9c59d1962d516cd480de78cf5ee01fad11159cc0a73ee1a9cb3ea2f324b8a1 | 768731f0c748276aeab4d34f57ad3ad89fd38aa30f562ff0cc9b5ad9a3767368 |
| docs/miniapp-sdk/extension-reachability.json | 152806a609b662c373eedd382758f1298bf945883f0c467dc5595050f8f0fa29 | 9a9843d277a3e76ad64fc7589029801960c5c98b9aba09f3ed7746552ee3d42d |
| docs/miniapp-sdk/extension-reachability.md | f2cd972c7366043028bbaea078291717ae363b288d29ecf242fd358103f7a9b1 | cae21720cab9b31211796a5d82309d6e779f46ddb1d946d1ec1e322f4cf952cb |
| docs/miniapp-sdk/source-inventory.json | b126e18f8a228e2235ef8ef324a31f0b9b6e3384e6af0f82755e35c4bcccaeef | 856bc8aca1473f8f4255b324e840ef2ebcdf5eb7352d1041d2433391e9f4bfd8 |

This lane did not materialize these generated production outputs. The integration owner must confirm the exact before hashes and modes before applying them. Detailed parsed differences and the unchanged 39 Package.resolved pins are retained in `prepared-source-delta.json`.

## Evidence and limits

`receipt.json` binds every file in this evidence directory except itself. The original snapshot receipt, controller checkpoint, source advance, capacity admission, producer logs, native catalog, corrections receipt and the later consumer receipt remain raw and unchanged. Only the SDK manifest uses lossless gzip. The supplied SDK ZIP remains at its shared immutable path.

The read-only inspector initially addressed the prior receipt with the wrong member-array key. Its small schema error is retained, the key was corrected to the actual `files` schema, and the completed final inspection passed. This did not run or fail any product test. The final report separately clarifies empty support-archive library arrays so they cannot be mistaken for complete binary equality.

No compiler, test, generator, Mac query, source materialization or archive repack was executed by this reconciliation lane. Actual producer/compiler/build results above are reused from the sole native execution owner's retained evidence. No application, physical-device or task-completion claim is inferred.
