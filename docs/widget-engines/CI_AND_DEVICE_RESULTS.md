# Pass 3 execution evidence — 2026-10-30

Status: SOURCE_CHANGED_NOT_EXECUTED for Apple widget code. No new widget Xcode test pass is claimed yet.

Starting branch: integration/hanlin-dual-widget-engines-20261029; starting local/remote SHA: ce586667b7103a6c2c7243d33461768c51a9dd8d. The 55 dirty files were backed up outside Git at C:/Users/DAVID/.codex/backups/hanlin-widget-pass3-2026-10-30T12-58-01-757Z. Before-patch SHA256: 5aaa8d3ea937bd5cc6e6731a412e3104cf2e4be75088d568c0eac5cb8aa23c14. No other active Hanlin Codex chat was reported by the app inventory.

| Executed check | Actual result | Scope |
|---|---|---|
| node --test Scripts/Widgets/Tests/compiler-and-actions.test.mjs | EXECUTED_PASS, 6 tests, Node 22.17.0 / Windows | Original bundle JS, real JSX compiler, callback props, slots, typed script storage model, reproducible ZIP bytes. Does not test JSExport, native views or WidgetKit. |
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
