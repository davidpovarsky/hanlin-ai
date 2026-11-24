# Acknowledged navigation context transitions

## Scope and source

This is an additive change to the original Hanlin SDK for Otzaria UI06 / Hanlin SDK03. It starts from the exact consumed SDK commit `080d1a2b264ead9e3f9df690f2dd0d3e81ebd07e`. The original dispatcher, context and integration source at that pin were independently compared with Hanlin continuation `f3bcb19d068473a8bdc6297f16b149e9cf7b8483`; those files were unchanged. Work is isolated on `codex/hanlin-otzaria-navigation-20261119`.

Otzaria's actual Reader navigation changes the native workspace mapping epoch. The original `open` correctly rejects the old context after this effect, and correctly rejects a reply that merely substitutes a new context. Its post-await checks must remain.

## Additive Host API 1.2

A host explicitly implements `HanlinHostNavigationTransitionSource` and advertises API 1.2 before the dispatcher accepts `openWithContextTransition`. Existing `HanlinHostIntegration.open` keeps its unchanged-context semantics.

The host returns `HanlinHostNavigationReceipt`: the complete original session, the original exact-target navigation acknowledgement, and an optional host-issued successor session. A successor requires an acknowledged presentation, a fresh session UUID and context generation, the same conversation, exact namespace and native scene. Queued requests cannot issue a successor.

The dispatcher validates the original request UUID, full origin identity, object and block bytes. It asks the original host for the resulting session's live context and checks cancellation and revocation after that await. Origin revocation is checked independently of successor revocation. A correctly correlated effect receipt is retained before delivery can be suppressed.

The original session cannot start another dispatcher action while its transition is in flight. A completed context transition retires that identity. A failed or cancelled call after host entry also retires it and any undelivered successor because the SDK cannot infer rollback. A historical receipt therefore cannot restart that successor through this dispatcher. The reservation remains and is never automatically reentered, including after a queued response. The host reconciles the original request; an uncertain operation is not repeated with a newly invented request ID.

## Host responsibilities and remaining integration

Only the actual native authority can correlate the request with an exact visible destination and its resulting context. A DTO, fixture host or SDK pass cannot prove a native screen appeared. The host must fence the original session at its last mutation boundary and distinguish the requested navigation from an unrelated account, workspace, scene or selection change.

The host must stop the old original `HanlinAgentSession` and compose any continuation with a fresh host-issued identity using the original engine, store, UI and provider path. Old tool catalogs, permissions and in-flight engine runs do not migrate. The SDK adds no permission store, host registry, replacement engine or automatic session mutation.

Otzaria production composition, real model-to-Core-to-UI journeys, provider/Keychain configuration, native cancellation and physical-device acceptance remain separate obligations. This source does not claim that those obligations passed.

## Validation

`VALIDATION_PLAN.json` records impact before execution. The changed admission helper affects original dispatcher callbacks, tool reservations, progress and old navigation, so both existing dispatcher regressions and the new transition cases require execution.

The portable proof compiles the complete original Platform and Host contract modules and whole original dispatcher, with explicit host doubles. It excludes the engine, AgentSession, model provider and native UI. The original repository Apple workflow compiles the real complete SDK graph, runs the affected HostAssociation/AgentSession/Context/Callback suites and the new navigation suite, and builds the iOS Simulator SDK product.

Results and exact source manifests will be recorded after execution. Build or portable proof alone does not close SDK03 or UI06.

### Portable execution result

The corrected source passed all **28** named Swift Testing cases on Windows Swift 6.3.3 with strict concurrency and zero compiler warnings. The complete raw XML, log, toolchain and 30 compiled original input hashes are retained under `portable/`. This is not an Apple graph or native UI pass. The earlier 27-case result is separately preserved as a historical source checkpoint; its initial report failed only because the wrapper looked for the XCTest XML filename instead of SwiftPM's `tests-swift-testing.xml`.

The actual Apple plan selects 58 cases: one HostSchema original-byte correlation case, 22 AgentSession cases, six Context cases, one callback convention case and these 28 navigation cases, followed by the original iOS Simulator SDK build.

## Integration with the existing original consumer

The implementation was replayed without conflict onto the original SDK commit `6d62957852ffcb428810b065b4252e5384f1374b`, already consumed by Otzaria branch `codex/otzaria-hanlin-consumer-20261119` at `7be3af6b`. This preserves the original editor-ownership and transport/Keychain source instead of replacing it with an older SDK. Code commit: `d49801160dd7e84d84db3903a0c6f7dedfe9c017`.

`SOURCE_FREEZE.json` verifies every one of the 30 portable compiled inputs against that integration source. All are byte-identical except the newly added contract file, whose CRLF-to-LF conversion is explicitly recorded and whose original bytes remain in the archive. The actual full SDK graph, including the original AgentSession/engine changes already present in the consumer base, is scheduled for fresh Apple verification; portable passes do not cover that graph.

## Full Apple SDK result — 2026-11-19 16:39 UTC

[Run 44567189233](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44567189233) completed successfully on the exact candidate `e00498e33f106cc43be0476ffa2e09329c8ca300` (code change `d49801160dd7e84d84db3903a0c6f7dedfe9c017`, integration base `6d62957852ffcb428810b065b4252e5384f1374b`). Xcode 27.2 / Apple Swift 6.4.2 executed all 58 distinct selected controls on macOS 27.0.1 arm64: 28 navigation-transition, 22 original AgentSession, six Context, one callback-convention and one original-byte HostSchema test. The original full SDK dependency graph compiled; the generic iOS Simulator 27.2 package build also exited 0. The workflow and artifact upload both succeeded.

The downloaded xcresult-derived case identities exactly equal the immutable 58-case selection, with no failures, omissions or duplicates. All 389 archived input hashes were verified against both the preserved source archive and the actual Git blobs at the tested commit. `apple-44567189233/REVIEW.json` records that independent comparison. The complete downloaded artifact, including raw xcresults, compiler/test logs and source archive, is retained losslessly in `apple-44567189233/raw-proof.zip`; its manifest identifies this as a local repack rather than claiming the GitHub upload ZIP's digest.

This closes the focused SDK compile/regression gate for this change. It does not establish actual Otzaria UI, provider calls, source opening, physical-device acceptance or release readiness. The existing Otzaria consumer at `7be3af6b977823fb02e64859ab10e79c4eef410f` still pins the prior SDK; its separate Native run 44480833870 passed reader presentation/return but failed reopening global chat after an actual process restart. That consumer repair remains separate.
