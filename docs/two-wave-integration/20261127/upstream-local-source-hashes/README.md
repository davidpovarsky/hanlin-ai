# Canonical upstream local-hash correction

Source base: 4cce12cfe277ba5849c5de0b0d5bc43eb564f7f1. Candidate changes only eight top-level localSHA256 values in docs/widget-engines/UPSTREAM_SOURCE_MANIFEST.json. No product source, package graph, pin, upstream publication, renderer, test, workflow, or historical provenance file changes.

The complete Git-object audit reads all 259 canonical records /258 unique tracked paths. Before correction251 match and8 do not. After correction259 match, with no missing path. The111 Subset entries and27 producer-selected original Expo module entries were already current and stay byte-identical. All other JSON fields are identical; candidate byte length is unchanged255664.

Each old digest identifies an actual retained Git preimage. Current source bytes equal both pre-boundary a729bc63 and executed226e7cfc. Source changes predate this repair: e42e78f8 for three drawing attributes,3a4936dd for ScriptWidgetElementView,86d8deb8 for Expo ViewRenderer/typed Native widget bridge,629853b2 for HanlinScriptWidgetRuntime. source-history.json and seven original historical-source.patch files retain exact commits/blobs/hashes and deltas. This metadata repair introduces no new source behavior and claims no new native result.

Consumer impact:

- Scripts/Expo/build-original-widget-runtime.mjs:22-30 checks only ExpoWidgets/Original entries; the8 stale adapter records do not intersect those27 rows. The current original Expo producer guard is not weakened or bypassed.
- Scripts/MiniApps/generate-scriptwidget-manifest.mjs:135-141 checks three original ScriptMetadata/ScriptWidgetPackage/network policy sources, which are outside these8 rows and already match.
- Scripts/MiniApps/stage-sdk.mjs:112 includes the whole canonical provenance manifest in its SDK input hash. Consequently this metadata correction changes one declared SDK input; fresh canonical SDK/Host fingerprint/packing qualification is required. A zero executable diff does not mean unchanged packed metadata. Current passing source/test receipts remain attributed to their actual source.
- Scripts/Widgets/audit-changed-paths.mjs reads provenance rows for its changed-path report; it is not an all-row hash gate.
- latestUpstreamContract objects and Scripts/MiniApps/upstream-resolution.json are original upstream comparison records produced together by refresh-original-sources.mjs:258-259. Their hostSHA256 captures that comparison's historical host input. They remain intact; no upstream refresh/comparison was performed or falsely reissued. Only top-level current-local inventory hashes are corrected.
- The frozen docs/miniapp-sdk/evidence/scriptwidget-original-limit-parity-20261124/provenance/UPSTREAM_SOURCE_MANIFEST.json is historical evidence and remains untouched.

Verification is the complete before/after Git-object hash comparison, exact eight-field semantic/byte diff and git diff --check. No separate mirrored test or native producer was run. Original native app/OS/device acceptance and current SDK/Host qualification remain owned by root/Mac.

Raw receipt retention includes the initial unpopulated sparse-worktree assertion and the Python JSON-literal setup error. Readbacks established no source edit before the successful correction. They are operational setup failures, not native test failures. Original tool outputs are gzip-compressed without byte changes; original UTF-8 JSON SHA e640d296c2d14bcdf92ed630312e01933532c6a8fca26c1b3cf197fb244873b2 (104078 bytes); gzip SHA5a40d3db83089b0d32b592d8d777396e90e1c69746ffd68da17dfe7a19681b33 (28465 bytes).

Sealed source commit: 2c98cbcf1f6feb20cd670ed9eaa71e1c854f98d2. Independent root integration review is pending separately. The unchanged original receipts/history/patch are contained in original-source-evidence.tar.gz and verified by original-source-evidence-manifest.json.
