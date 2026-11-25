# SDK14 actual preparation reconciliation

This evidence records the actual prepared SDK captured at 2026-11-25T05:25:15.260415+00:00 from source b0cf26a668a698682f5307252f14cf0af8c6d00a (tree 1446c01003a90df66bf60b36529f815f02c6621d). The immutable controller snapshot is PAUSED_AFTER_PHASE through split-inputs. This record establishes preparation, archive/source identity, generated target wiring, and documentation results. Consumer builds, selected runtime tests, the original 25 + 27 acceptance cases, and notification OS delivery are separate observations.

## Actual identities

| Artifact | Bytes / count | SHA-256 |
|---|---:|---|
| RuntimeHostResources.zip | 81,823,821 | 14fac1d2497efea1041553debf4c60afe2305053b10f8eee94491d50fce0ffa8 |
| Decompressed MiniAppSDK/miniapp-sdk.json | 5,223,957 | 039f061558cc53d51e929f07e2df222709ab078d8417af527bc448750bda5593 |
| Ordered SDK source inputs | 234 | b8a4d934a145530a5a1095d719c19e16f0c790ee234c1999637a42c0f88c4f99 |
| Top-level miniapp-authoring.mjs | 50,327 | fa5121902e231d5d44ad08bf47699784fd4d0bc2a98102f3a156e6e4ae79b9b9 |
| Original immutable handoff receipt | 15,008 | 57e4fba2ae918a08448b32561be51e3617adf9468f16488439898debae459fb2 |

All 30 handoff file rows were checked against their actual shared bytes, including the full ZIP. The ZIP was inspected in place. Its decompressed manifest matched the separately retained manifest; its top-level authoring module matched the source commit. The exact SDK member inventory matched all 25,669 manifest file rows. All 234 source inputs matched either the exact source Git blob or one of the retained generated outputs, and their ordered input identity was recomputed. No compiler, generator, native command, SDK repack, or product mutation was performed in this reconciliation.

## Change from the actual SDK10 baseline

The baseline is the separately retained SDK10 manifest 19726b5eecc1459e30dae9e7ec4ca6761001de92b22055ac41b9a96aabdd7a88 and archive 86733eba5d80156edf52da87f0f371c208122d6e60f618f182990330514984c3. SDK14 is a newly measured archive; no full-archive equality is assumed.

| Manifest comparison | Unchanged | Added | Changed | Removed |
|---|---:|---:|---:|---:|
| SDK files: 25,661 to 25,669 | 25,655 | 8 | 6 | 0 |
| Source inputs: 222 to 234 | 215 | 12 | 7 | 0 |

The eight new SDK files are the notification contract declaration/package in both engine trees, notification documentation and schema, and one typed notification-event example in each exported hello-world project. The six changed files are the four generated documentation/provenance files and the two example tsconfig files. All fourteen actual added or changed archive member bytes were checked against their manifest hashes. The full before/after comparison is raw/manifest-comparison.json.

Both engine contracts now name @hanlin/notification-events 1.0.0 and the matching versioned schema/documentation metadata. This is an application-owned typed Host contract, not an additional upstream library. Expo has 22 package-version keys: 21 previous keys plus this contract. NativeScript has 9 keys, including its original packages and the two application-owned Host contracts. Original package/compiler identities remain distinct from application-owned declarations.

## Actual producer results and their limits

Original graph generation and its target/plist checks passed. The captured original Host lifecycle, native preparation, 15-target native artifact export, restore-inputs, and split-inputs phases all passed. Native preparation ran for 269.774950 seconds and native export for 36.589196 seconds. Its retained Host test result is 169 passed, 0 failed, with 1 pre-existing opt-in skip.

The actual documentation report contains four successful projects with zero diagnostics: expo-guide, nativescript-guide, scriptwidget-guide, and scriptwidget-controls. It explicitly binds this manifest and input identity. These four guide-snippet projects are distinct from the exported Expo and NativeScript hello-world projects. This reconciliation verifies the latter projects’ new notification-event.ts bytes and tsconfig inclusion; it does not invent a new execution of their compilation. The earlier notification contract compiler proof remains in notification-ingress-20261125, and actual later SDK-only fixture results belong to their own native execution record.

The 80-cell generated surface matrix remains a source-audit/disposition document. Its notification rows now describe partial wiring; this SDK snapshot does not turn those cells into runtime PASS or establish OS authorization, service-extension execution, APNs provider delivery, or physical-device behavior.

## New notification target versus the native framework catalog

The actual vendor/native catalog remains 15 required targets with 0 missing. HanlinMiniAppsNotificationService is a separate project-level app extension, so the vendor catalog should not be inflated to 16.

The actual generated project contains bundle com.itorah.hanlinminiapps.notification-service, the HanlinNotificationExtension and HanlinExtensionContracts products, a dependency from HanlinMiniApps, and one app-extension embed phase. Its Debug and Release settings point to the product-specific Info.plist and entitlements. NotificationService.swift is included by the original PBXFileSystemSynchronizedRootGroup; only Info.plist and the entitlement file are excluded from that synchronized membership. An empty explicit sources list is therefore expected. The shared early application delegate is present in both the generated AI framework sources and the direct MiniApps source phase. The original generated Swift package gives HanlinNotificationExtension its required HanlinScriptExtensions dependency.

The project proof binds these generated objects and the three exact source wrapper/configuration files. It proves source wiring. Actual compiled, embedded, signed, and installed extension identity remains a later consumer-build observation.

## Existing five declaration compatibility corrections

The actual correction receipt c5e5322a6177f36a713380134006d4beb3a0ebd275e435e66b7de93a4cb60f82 is byte-identical to SDK10. Each corrected SDK14 archive declaration was verified against that receipt. These are existing deterministic corrections to original published declarations; shipped declarations are not claimed to be universally byte-for-byte upstream copies.

| Original declaration | Existing correction |
|---|---|
| react-native AnimatedProps.d.ts | Allow the optional nullable style already admitted by the original Flow source. |
| react-native VirtualizedList.d.ts | Infer the actual constructor instance without the unrelated React static-lifecycle generic constraint. |
| react-native ReadOnlyNode.d.ts | Preserve the concrete Document getter’s actual nullable return. |
| @nativescript/react-native Runtime.d.ts | Preserve actual constants when the original bridge avoids overwriting them with conflicting struct constructors. |
| @nativescript/react-native UIKit.d.ts | Match the original JS host object’s string-valued description behavior. |

Raw original, corrected, and implementation-source hashes are retained in the producer receipt and raw/project-and-declaration-binding.json. The current original React Native publication is 0.88.1; historical correction documentation referring to 0.88.0 does not change the verified current affected bytes. The published TypeScript wrapper identity and actual aliased compiler identity remain separately described by the earlier original-compiler evidence.

The retained ExpoAsset producer comparison contains 23 staged/target rows, all equal. It binds original expo-asset 58.0.21 and source input a85fc86c413d87679e62878cc4b7b512e925c36806a9b383daf095dab9c55159. This agent reconciled that immutable native producer record; it did not copy or rebuild frameworks.

## Exact prepared-source materialization plan

Thirteen paths changed during original preparation: three graph outputs, six archive copies representing two unique archive contents, and four generated SDK documentation/provenance outputs. Total path payload size is 3,088,099 bytes. Every before hash and 100644 Git mode matched source b0cf26a; every retained after payload and 0644 mode was verified. No npm resolver/lock input changed in this attempt.

The table below is a readable index. materialization-plan.json carries every full before/after SHA-256, exact byte count and mode, immutable contentFrom path, retained evidencePayload path, and compression encoding. Canonical binding: 856b65cbbcc0ba386ee0b3fb8c5a8cd1adc2998c65ece7b13b9aa4cb89f2995f.

| Prepared path | Bytes | After SHA-256 prefix |
|---|---:|---|
| AI_HLY.xcodeproj/project.pbxproj | 251761 | 71409346bb25cdc8 |
| AI_HLYUITests/Fixtures/ExpoSwiftUIProbe.hanlinExpo | 325823 | b81e8ecccb8e8495 |
| AI_HLYUITests/Fixtures/ExpoSwiftUIProbeA.hanlinExpo | 325823 | b81e8ecccb8e8495 |
| AI_HLYUITests/Fixtures/ExpoSwiftUIProbeB.hanlinExpo | 325825 | cdf1b95be3e21062 |
| Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIProbe.hanlinExpo | 325823 | b81e8ecccb8e8495 |
| Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIProbeA.hanlinExpo | 325823 | b81e8ecccb8e8495 |
| Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIProbeB.hanlinExpo | 325825 | cdf1b95be3e21062 |
| Package.swift | 88332 | c58ad5f37b35c38e |
| docs/agent-sdk/unified-package-manifest.json | 3901 | 2dce00d3544b324e |
| docs/miniapp-sdk/MANIFEST_REFERENCE.md | 118804 | 283c96260a51c095 |
| docs/miniapp-sdk/extension-reachability.json | 153229 | 54e72317c384d85c |
| docs/miniapp-sdk/extension-reachability.md | 23332 | a132faaf5a40550b |
| docs/miniapp-sdk/source-inventory.json | 493798 | b4752902d3097f4d |

Before applying any path, compare current content and mode with its recorded before identity. Read its retained payload; decompress only entries marked gzip; verify the full after identity; then write the exact recorded content and preserve the recorded mode. Duplicate archive destinations intentionally reuse one retained content blob. This agent has not materialized any production path.

## Retention and execution boundary

raw/retained-members.json maps all compact retained proof/payload objects to their original sizes and hashes. Compression is deterministic and lossless; every retained object and gzip roundtrip was verified before sealing. The 81 MB Host archive remains at the immutable shared snapshot path and is not duplicated in Git. Its measured full identity, actual decompressed manifest, changed members, and source closure are retained here.

This record preserves the frozen preparation checkpoint. Subsequent build failures or passes, native companion results, the 25 + 27 paired suite, built resource bindings, and actual OS notification callbacks require separately timestamped evidence. They do not retroactively change the immutable handoff or its successful preparation result.
