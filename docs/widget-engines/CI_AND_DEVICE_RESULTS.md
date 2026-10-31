# Pass 3 execution evidence — 2026-10-30

Status as of 2026-10-31: PARTIAL / SOURCE_BLOCKERS_REMAIN. Apple package tests have executed; native iPad Simulator and signed device acceptance are still open.

## Executed Apple evidence, separate from acceptance

- [41235678022](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41235678022), source `33f1c66b2cd3b738752861933d2ecef19c4f3343`: Xcode 27.1 (27A9275), Swift 6.4, arm64 macOS. Seven archive analyses, all five valid archive installations and verified preparations, source Expo callbacks, named ScriptWidget actions/Boolean state, real A1/A2 registry creation, concurrent actions/publication/replay, artifact attacks, real old v1 reader/encoder, crash recovery and timeline storage persistence passed. The 25-test extension run had ONE failing helper-test assertion: it cast canonical Int64 JSON numbers to Swift Int. This assertion has been corrected, with a fresh run required. The ten affected analyzer tests passed. Overall run FAILED; no whole-suite PASS is inferred.
- The same run produced 29 native ScriptWidget tag rasters and ten chart-variant rasters. Charts compare valid native data with the original invalid-data output; grid/date/element-value assertions also passed. The broad 29-tag check only distinguishes the original unknown-tag diagnostic and is PARTIAL semantic evidence, not complete parity or WidgetKit acceptance. Raw PNGs are in its `widget-package-evidence-41235678022` artifact.
- [41073849232](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41073849232), source `1b15b961d612d4eaa2fb9a6f6a349d23970ccdde`: production Swift compilation and most affected tests passed; two ScriptWidget execution tests FAILED because SPM flattened `support.bundle`. Explicit resource-directory copying fixes that measured defect. Subsequent runs exercised the actual JSExport/source lifecycle successfully.
- [41073589471](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41073589471), source `507aa9d2eac8d4b2b0a23e75735000215cf105df`: `HanlinExpoWidgetNative` compiled for arm64 iOS 27 Simulator, including the original AnyChild renderer. The overall app build FAILED on a missing ScriptWidget `clockHandRotationEffect` helper. The public upstream SwiftUI helper has since been restored. No finished appex, SpringBoard action, xcresult or app/appex digest is claimed from this failed build.
- [EXISTING_EXPO_BINARY_AUDIT.json](EXISTING_EXPO_BINARY_AUDIT.json) records the actual prebuilt device/simulator framework hashes, Mach-O flags and load commands. Result: FAILED_EXTENSION_CLOSURE. ExpoUI/Core/Worklets load React/Hermes and lack MH_APP_EXTENSION_SAFE. This finding remains open; successful source compilation does not make that binary closure extension safe. Pinned upstream `withPodsLinking.ts` also explicitly calls `use_react_native!`; a source subset or compatible extension-safe rebuild must be proven before closing G02/B07.

Earlier compiler failures were retained as raw run evidence: 41068302268 (MineGaugeViewSection Sendable), 41071355498 (missing upstream link fallback), 41072414347/41072421229 (nested shape MainActor), 41073204770 (test-only old/current error-type collision). Runs 41235364744 and 41235526183 then exposed the importer target's missing explicit compiler dependency, corrected in 33f1c66b. These failures are not accepted as execution passes.

The table below preserves the initial local-check record; subsequent matching Apple evidence above supersedes its NOT_RUN rows only for the stated scope.

Starting branch: integration/hanlin-dual-widget-engines-20261029; starting local/remote SHA: ce586667b7103a6c2c7243d33461768c51a9dd8d. The 55 dirty files were backed up outside Git at C:/Users/DAVID/.codex/backups/hanlin-widget-pass3-2026-10-30T12-58-01-757Z. Before-patch SHA256: 5aaa8d3ea937bd5cc6e6731a412e3104cf2e4be75088d568c0eac5cb8aa23c14. No other active Hanlin Codex chat was reported by the app inventory.

| Executed check | Actual result | Scope |
|---|---|---|
| node --test Scripts/Widgets/Tests/compiler-and-actions.test.mjs | EXECUTED_PASS, 7 tests, Node 22.17.0 / Windows and Node 24.5.0 / CI | Original bundle JS, real JSX compiler, callback props, slots, reachable module closure, typed script storage model, reproducible ZIP bytes. Does not test JSExport, native views or WidgetKit. |
| swift build --target HanlinScriptContracts | EXECUTED_PASS, Swift 6.3.3 / Windows, 34.24s | Portable contracts only. ZIPFoundation/zlib environment warnings remain outside this target. |
| swiftc -frontend -parse affected Swift sources | EXECUTED_PASS | Syntax only; no Apple typechecking. |
| Apple SDK symbol lookup | EXECUTED_PASS for lookup only | [41061281231](https://github.com/davidpovarsky/apple-devtools/actions/runs/41061281231), xcode-27-arm64 image 20261026.0314.1. SetValueIntent and value/ValueType found; iOS availability 18. Raw log is retained locally. No project compilation. |
| Failed SDK dispatch attempts | FAILED before any job executed | 41060887409 and 41061048365: local helper passed runner labels without the JSON encoding now required by its remote workflow. Corrected with a structured dispatch; no project source ran in these attempts. |
| New Swift widget suites | NOT_RUN | Actual importer/installer, source actions, A1/A2 creation, concurrency/replay, artifact attacks, historical v1 encoder/reader, interrupted publication and state preservation are implemented as tests. Await Apple execution. |
| SpringBoard widget native UI | NOT_RUN_SIMULATOR_UI | No Home Screen tap is claimed from an intent helper or a foreground preview. |
| Signed physical iPadOS 27 | BLOCKED_DEVICE | No connected/provisioned signed iPad test was performed. See DEVICE_ACCEPTANCE_CHECKLIST.md. |

Historical [40994342575](https://github.com/davidpovarsky/hanlin-ai/actions/runs/40994342575) at e92265179d044d30f04827863e849674767ef136 passed the prior 11 selected foreground Expo UI tests. Importer/publication/extension dependencies changed here; this is historical evidence, not a new widget result or an automatic reuse decision.

Frozen Chat check: all four paths have zero diff from the actual starting SHA ce586667. Comparing 37ba73ba to the starting SHA already shows changes in ChatView.swift, ChatViewBottom.swift and ChatViewComponents.swift (1,592 insertions / 1,998 deletions); those historical changes were not reverted. ChatandFile.swift also remains untouched.

Fixture archive and per-source SHA256 values: [SHA256.json](../../Fixtures/Widgets/SHA256.json). Five archives are positive imports pending native tests; Invalid-Cases must be rejected; Mixed-Native-Widget is an intentionally rejected ABI-0 optional fixture, DEFERRED_OPTIONAL. ZIP creation alone is not import or render evidence.

Native source provenance is in UPSTREAM_SOURCE_MANIFEST.json. ExpoUI native linkage, extension-safe Mach-O dependencies, app/appex digests, memory/latency metrics and simulator results remain pending. B03 IPv4 ordering and B04 explicit RN bounds remain mitigations without new embedded-device evidence. Asana has not been modified.
