# Attempt 10 remaining focused runtime diagnostics

This checkpoint preserves the finalized actual three-case result on source `fda6948ca6a1f541293a1a1dd20e97f75eb0a527`: **two passed, one failed, none skipped**. The native owner completed the command at **2026-11-25 02:44:43.510666 UTC**, exit 65. Every selected case appears in the actual xcresult nodes.

| Actual case | Result | Case duration |
| --- | --- | ---: |
| SDK-only Expo import, native rendering and events | PASS | 95.161 s |
| SDK-only NativeScript import, native rendering and events | PASS | 66.491 s |
| Modular live Sefaria search and full text | FAIL | 241.374 s |

The Modular case failed at `HanlinMiniAppsUITests.swift:1184`, the parent native-list hittability assertion after its bounded readiness wait. The preassert screenshot and accessibility tree show populated source detail, version disclosure groups and Full text buttons. The actual test did not reach its later disclosure/full-text assertions. These observations preserve the failure rather than treating visible content as a passing interaction test.

The earlier unchanged parity case failed separately. Its sample, screenshot and original source/archive evidence remain in [the parity startup checkpoint](../primary-parity-startup-diagnostic-attempt10-20261125/README.md). Across the two diagnostic commands, the actual four-case result is **two passed and two failed**. The original 25 + 27 acceptance run remains **NOT_RUN**.

## Retained evidence

The untouched native handoff receipt `87672e323f4c8cb463fb56916cd8ecb9547d71bf4eb417c74e082ee57c59c767` binds **23 members / 2,339,777 bytes**. Every member was verified and copied byte for byte. The already compressed runtime stream round-trips losslessly to **13,566,194 bytes**, SHA-256 `b3d0a847b4e44067df1217740d7c21e2fdf792c649e36dc57f43d267f3b8488d`. The full attachment manifest is retained, together with the eight selected attachments listed by the handoff; this is not a complete xcresult export.

[reconciliation.json](reconciliation.json) records exact source hashes, case nodes, attachment mappings, scope and container/readiness boundaries. [raw/receipt.json](raw/receipt.json) is the unchanged producer receipt. The generic collector error about not executing every selected case is preserved; actual nodes and the selected-tests log demonstrate that all three cases executed and one failed.

The reconciler visually inspected both retained PNGs. The detail image is fully populated and normally oriented. The separate search-results image shows horizontally mirrored SwiftUI glyphs while system/status/search chrome is normally oriented. This is recorded as a visual observation without an inferred cause or a correction claim.

The later `.ready` observation belongs to the subsequent diagnostic container and cannot establish completion of the earlier failed parity cold start. Cleanup reports the owned simulator shut down and no owned runners. No new native query, build, test, generator or SDK repack was performed to produce this checkpoint.

The [SDK10 checkpoint](../primary-sdk-attempt10-20261125/README.md) separately preserves original SDK identity, five completed consumer-resource copies and installed metadata. Later fixture/test corrections are outside this immutable execution checkpoint and require their own actual result.
