# SDK15 actual preparation and later test-only consumer closure

This record reconciles the actual immutable SDK15 snapshot captured at 2026-11-25T06:05:33.140285+00:00 from c259b72243ccb62188f24e551648544bc57cc7c1 (tree 1d8028c6980426557e31a88f2efb60bd2ea6ddc8). Its controller checkpoint is PAUSED_AFTER_PHASE through split-inputs. The successful preparation is distinct from subsequent consumer compilation, native case results and OS notification delivery.

## Actual artifact identities

| Artifact | Bytes / count | SHA-256 |
|---|---:|---|
| RuntimeHostResources.zip | 81,823,833 | 602669f4d915cb3dd216ad14cb07a23f4da3885ef0fadf772ea3c6f2d1f06e0d |
| Decompressed SDK manifest | 5,223,957 | 580fee9e709aa8cd57fafb961a50538c244abc30228952231b8dbe68f00ce2f7 |
| Ordered source inputs | 234 | 6b1347a88bcd22ddc077f150be3e62f4f1e825160ba42a10911446ba9d17a71f |
| Top-level miniapp-authoring.mjs | 50,327 | fa5121902e231d5d44ad08bf47699784fd4d0bc2a98102f3a156e6e4ae79b9b9 |
| Original handoff receipt | 15523 | 53bc530ba90408db729da24119fa0cd7f1d2c963f39d62ba77245c638ed4ccf2 |

All 30 handoff file rows were independently verified, including a full streamed hash of the real ZIP. The archive was inspected in place: the decompressed manifest matched its separate retained bytes, the authoring module matched the exact source commit, the SDK member inventory matched all 25,669 manifest file names, and the three changed SDK members matched their actual bytes. All 234 input hashes bound to the exact source or actual prepared payloads; their ordered identity was recomputed.

## Exact change from actual SDK14

| Comparison | Unchanged | Changed | Added / removed |
|---|---:|---:|---:|
| SDK file rows | 25,666 | 3 | 0 / 0 |
| Source-input rows | 230 | 4 | 0 / 0 |
| Prepared source paths | 10 | 3 | 0 / 0 |

The three changed SDK members are source-inventory.json, extension-reachability.json and extension-reachability.md. The fourth changed source input is HanlinNotificationApplicationDelegate.swift, now eacf5e748287603ef4e6796d2f2d0016b7563aa5de62bca4478a693d2b82eb83: the exact two-line correction to the installed SDK’s imported async Int callback. The new ZIP is independently measured; it is not treated as byte-identical to SDK14. raw/manifest-comparison.json contains every exact before/after row.

All engine metadata, original API/type package file rows, the application-owned notification declarations, schema/documentation and both exported example projects are unchanged from SDK14. @hanlin/notification-events 1.0.0 remains present in both engine contracts. Expo has 22 version keys including this application-owned contract, not 22 original upstream libraries.

## Actual generation and native declaration provenance

The three generated project outputs, the existing five declaration-correction receipt and original ExpoAsset producer/staged bindings are byte-identical to SDK14. Their original project generation remains the actual b0 generation; it was not rerun or relabeled as c259. The retained generation state/logs preserve that origin. The unchanged-project-and-declaration binding points to SDK14’s exact independently verified project/source/declaration record.

The actual exported native framework catalog still contains 15 required targets and no missing targets. The generated HanlinMiniAppsNotificationService target is an additional project-level extension, not a sixteenth vendor/native framework target. Its product/bundle/Info/entitlement/source/embed/dependency graph is unchanged from the verified SDK14 project. Actual compiled and installed extension identity remains a later build observation.

The five pre-existing deterministic declaration compatibility corrections remain in place and retain their original/corrected/source hashes. No claim is made that every shipped declaration byte is an unmodified upstream byte. No upstream package, lock, declaration correction or native framework was changed by this reconciliation.

## Documentation result and test-only consumer head

The actual SDK15 documentation report binds manifest580fee9e and input6b1347a8 and reports four projects passed with zero diagnostics: expo-guide, nativescript-guide, scriptwidget-guide and scriptwidget-controls. These are the original guide-snippet projects. They do not stand in for an execution of the separately exported hello-world projects; the unchanged example contents and prior type proof are retained under their own original evidence.

Consumer test head 46225e5af9aa253c8aa3b7d0d6ce2f282c88e7ad adds only the separate OS notification UI method, its external observation script and four evidence files. Neither test path appears in the 234-input SDK closure or the 93-source audit inventory. Every one of the 230 Git-bound input blobs and four retained prepared documentation inputs was rebound to that consumer head. All 93 inventory source hashes also match it. The actual SDK producer and generated audit sourceCommit remain c259. This is verified unchanged input reuse for the later test head, not another SDK production or a consumer PASS.

raw/test-only-consumer-impact.json preserves the exact six-path Git delta, all 234 bindings, the 93-source inventory result and both commit/tree identities. The original paired selectors and the separately selected OS UI case still require their own actual execution evidence.

## Exact prepared-source materialization

Thirteen path payloads total 3,088,099 bytes: three generated graph files, six original Expo fixture archive copies (two unique archive contents) and four generated SDK documentation/provenance files. All before hashes/modes match c259; the later test-only commit leaves all these paths unchanged. Every retained after payload has the verified 0644 mode. No production path was materialized by this agent.

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
| docs/miniapp-sdk/extension-reachability.json | 153229 | 25003ece56c9c4b6 |
| docs/miniapp-sdk/extension-reachability.md | 23332 | 7f36a7e3b3def224 |
| docs/miniapp-sdk/source-inventory.json | 493798 | 1eb0f6f00994274b |

materialization-plan.json gives full before/after hashes, modes, source contentFrom and retained evidencePayload/encoding for each path. Canonical binding: 9a85dafa2d26774b1e9475d0505413e40401665e3681d497867cc0e3ccf77da1. Before applying, verify current before content/mode, decode the retained payload only when its encoding is gzip, verify its complete after identity, and write the exact recorded bytes/mode. Duplicate archive destinations intentionally share one retained content object.

## Retention and boundaries

All 40 retained original objects and their lossless gzip roundtrips were checked before sealing. The full Host ZIP remains at the immutable shared snapshot path; it is not duplicated in Git. Its measured identity and actual manifest/source/member closure are retained here.

The source audit and 80-cell surface disposition matrix remain source evidence, not 80 runtime passes. The earlier actual notification package result, actual SDK14 consumer failure and scoped signature compiler proof remain separately timestamped records. This packet does not claim consumer build success, installed notification-extension execution, original25+27 completion, OS push delivery, real APNs provider delivery or physical-device behavior. No compiler, generator, native query, simulator action, test, repack or product mutation was performed by this agent.
