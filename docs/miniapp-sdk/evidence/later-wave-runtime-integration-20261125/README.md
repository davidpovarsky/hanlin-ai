# Later-wave runtime integration from Wave 2

This is a separate candidate based on `89f758d56a4945acc52dfe604b78835539d5df85`. Its functional source commit is `4c9c1451f10e8c1a71c5dc07bfe3b858d2f37f51`; this evidence commit adds no functional changes. Wave 1 c309 and the published Wave 2/3 branches were not modified by this lane.

## Changes and consumers

| Change | Original donor | Consumers and required next work |
|---|---|---|
| Emit NativeScript ESM using native-loader extensions, preserving local graph/source maps and original dependency bytes | 3109d5e2 | Shared authoring Host and CLI; rebuild the original Host/SDK and authored packages, then native import/render acceptance. |
| Deliver existing NativeScript pending callbacks through the active default main run loop | 2b327182 | Shared original Objective-C session bridge used by both apps; compile actual consumers and verify original parity/reopen assertions. |
| Add the original ExpoAsset native module, producer, binary target and catalog item | 9784a446 | Both Expo consumers and shared extension dependency graph; exact original source device/simulator artifact required. Native framework count14 becomes15. |
| Expose original ExpoAsset SDK types/version/admission | edd5bcf4 | Canonical dependency updater, SDK staging, script analyzer and shared host version contract; refresh inventories and embedded SDK. |
| Map the exact embedded ExpoAsset plugin contract | 1812bff5 | Original Host source audit; exact plugin-set and version checks remain strict. |

The generated intent of d72b1625 was incorporated by running the original `generate_manifest.py` and `update_project.py` on this actual combined source, followed by both original `--check` commands. All four exited0. Only root `Package.swift` and its generated receipt changed: targets113 becomes114. The Xcode project is byte-identical to Wave2.

`validate_graph` and `validate_agent_sdk_linkage` passed using the original provider manifest. The514 application source paths are exactly preserved, with SDK-only implementation ownership. The complete Presentation SDK tree, original UI assertions/fixtures, workflows, catalog projection, case-preserving action IDs and schema are unchanged. The new bridge regression is discovered by the existing synchronized `HanlinMiniAppsTests` source group; no test target was rewritten.

## Evidence reuse

- NativeScript ESM producer: **REUSED_VERIFIED_PASS**,5cases, from its actual original Mac Node24.5.0/TypeScript5.9.3 run. Baseline one ESM failure and passing CommonJS control remain retained.
- Original Objective-C callback scheduling: **REUSED_VERIFIED_PASS**,3cases, from the original Apple Foundation/XCTest harness. Baseline20-second timeout, initial harness compilation failure and corrected raw logs remain retained.
- Exact implementation/test/CLI/header hashes match those original proofs. The applicable source closure and toolchain identity are listed in `qualification.json`. No passing tests were repeated.
- Fresh work here consists of portable canonical generation, source/graph checks and Git integration. It makes no Apple compilation, UI, runtime52, physical-device, signing or upload claim.

The two original failed raw logs contain their original trailing whitespace/ANSI diagnostics. They are preserved byte-for-byte for authentic hashing. `generation/full-diff-check.json` records the unfiltered whitespace findings; the exact two archived log exclusions and passing source check are recorded separately. No implementation/test whitespace error is suppressed.

## Remaining acceptance

The new native graph requires a15-framework catalog, current Host/SDK/inventories, actual application/extension builds and the original affected runtime selectors. The existing foreign owner retains original52 execution. Its focused passes do not resolve the earlier failed UI cases. ModularTextSearch completion, physical iPad observations and signing/account work remain separate.

`source-changes.json` records the complete integration diff against Wave2, including before/after hashes and original evidence. `qualification.json` records the exact functional source, donor history, protection checks, executed portable checks, qualified reuse and pending native obligations.

## Native preparation reuse boundary

All16 original native-artifact source inputs are byte-identical to foreign published source1812bff5. At00:49:58 UTC the owner reported attempt9 paused after split-inputs; the only recorded catalog was still prepared attempt7 with14targets. This supports reviewing later exact native outputs, but does not qualify that old catalog for this15-target candidate. Final-source Host/SDK and support payloads must be generated and verified separately. See `native-reuse-preparation.json`.
