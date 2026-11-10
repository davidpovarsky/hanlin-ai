# Original chat and Runtime Autonomy V3 implementation

## Entry and authorization

- Owner authorized implementation of CHATUX-01…08 and Asana `1220369388989551` on the existing branch, using CLI/API only, on 2026-11-10. This explicitly opens the scoped original-chat files previously frozen by the older assignments; it does not authorize a second chat UI, a Split redesign, main merge, or another distribution.
- Branch: `fix/hanlin-approved-plan-20261108`; clean entry SHA: `2f38a3ec272e2ce498640c7243c1540391d916a4`. Pass 7 ancestor: `507cd0409e722d933e7fd568a24b4221a7a5d346`.
- Previous delivery: [TestFlight 93401](../voice-recording/TESTFLIGHT_93401_DELIVERY.md), source `7fa8fe26257c20f57846702fd13db515a0441bfc`; available to the owner's existing internal audience. iPad zoom/audio/widgets acceptance remains OPEN.
- V3 plan imported verbatim from documentation-only commit `644f1dcd1bd446239a1a8b755b3a14a521ccbf32`, blob `9935b1023a4ffcf3d273aae914c00ca33bde0a9c`. That branch is not the code base. Its audit at `d04afe3d` must be reconciled with this entry SHA.
- Execution: `[נועם | DEV] [MAIN_SESSION]` / `[מיה | UX] [MAIN_SESSION]`; NORMAL, no delegated agents.

## Impact and acceptance obligations

| Group | Implementation closure | Required fresh evidence | Existing evidence eligibility |
|---|---|---|---|
| Original chat rendering/selection/browser/saves | ChatBubbleView, original ChatView/ListView, SwiftData schema, selected renderer and pinned dependencies | Hebrew/English/emoji, Markdown + automatic math, streaming, partial selection callbacks, opaque original preview, persistence/deletion/jump, internal web links | No existing chat UX acceptance; NOT_RUN |
| Original agent activity | AgentRun/projection/composer, original bubble activity ownership | Single disclosure per group, stable expansion, ordered distinct parallel calls, failures/cancellation, rich results outside activity | Existing projection evidence requires source-closure review; no blanket reuse |
| V3 A/B | Runtime capabilities, embedded invocation, step orchestration, persistent full results/jobs | Embedded/ordinary parity, stale identity/cancel, >40 actual steps, >50 results and >10MiB digest, real >300s Node/Python and explicit timeout | Prior native/SDK tests do not prove new V3 behavior |
| V3 C/D/E/F/G | Resolver/install/shell/process adapters, WASM/fetch, storage/import/environment/background | Exact plan's acceptance matrix, real execution and truthful platform limitations | Native engine evidence is invalidated only if engine/ABI inputs change; Host/consumer changes require affected checks |
| Physical iPad | Gestures, Stage Manager, background, actual Widget/Intent/Expo/ScriptUI consumers | Owner/device run | BLOCKED_DEVICE until performed; simulator is not equivalent |

Before dispatch, record exact impacted tests/source SHA and toolchain. Do not count zero-test filters, build success, library README claims, or mock execution as behavior PASS. No new TestFlight is part of this implementation request.

## Work state

- T0 entry/handoff: verified. Source audit in progress.
- CHATUX renderer: Textual POC integrated in the original bubble, translations and transcript text. Pinned `PSchmiedmayer/textual@9f4b100e582a8500c1845acc46cd818197296de1` is the MIT-licensed source of upstream PR [88](https://github.com/gonzalezreal/textual/pull/88), based on upstream `01b51875a5406eefc95f52a058cb059e7bc94dc4`. It includes the public selection-action hook and lazy streaming selection fixes absent from main. This is an explicitly pinned **unmerged** contribution, not a stable upstream release. SDK/interaction acceptance remains NOT_RUN; upstream test claims are not Hanlin evidence.
- Alternatives examined: [LiYanan2004/MarkdownView](https://github.com/LiYanan2004/MarkdownView) `bc8f5fbcb068426b7029da51522ff0124b66ac89` supports MarkdownText/math, but its RichText dependency has no public selected-text action hook; deferred rather than adding introspection. [EnrichedMarkdown](https://github.com/software-mansion-labs/enriched-markdown-ios) documents selectable text and Markdown-copy actions, but its current standalone API documents math parsing without rendering; deferred. Microsoft cross-block modal selection does not meet the in-place requirement; deferred. GetStream remains excluded due to its proprietary license. No whole chat SDK is imported.
- V3 T1: embedded ScriptUI file/storage grants removed to match ordinary execution; actual session creation/disposal, package ownership and OS permission paths retained. Capability reporting reads engine snapshots instead of fabricating Ready/version/timeout support.
- V3 B: no default agent step/schema cap; explicit caller budgets remain available. Default full results are persisted to a run-scoped directory without count/byte eviction. Finishing/resetting exposed schemas does not delete history. Read limits bound page transport only. Existing explicitly selected bounded-store policy is retained for compatibility; it is not the normal session default.
- EXECUTED_PASS (Windows portable Swift, 2026-11-10): production `ToolResultStore.swift` compiled and executed with 64 results / 18,350,080 bytes; reopened store returned every original payload byte-for-byte, paginated mixed Hebrew/family emoji at 4093-byte pages reconstructed the complete payload, traversal reference rejected, explicit bounded-policy compatibility verified. Harness `build/ToolResults-main.swift`. This does not prove Apple integration, agent >40 steps, long jobs, or device behavior.
- New Apple tests: `ChatPresentationTests`, `RuntimeAutonomyV3Tests`; package `HanlinAISDKAgentEngineTests/defaultRunContinuesPastFortyWithDiscovery` executes real orchestration/tool calls with deterministic provider responses. NOT_RUN until raw results exist.
- V3 long jobs/resolver/Shell/WASM/fetch/import/storage/background: still pending. The original plan remains the acceptance authority; the task is not complete.

## First verification batch

- Final source SHA: the code commit containing this entry (resolved by workflow `head_sha`; no guessed hash).
- Fresh app obligations: `AI_HLYTests/ChatPresentationTests`, `AI_HLYTests/RuntimeAutonomyV3Tests`, `AI_HLYTests/AgentSkillsExposureTests`, `AI_HLYUITests/AgentRuntimeConversationUITests/testRealChatUISendsPromptShowsToolActivityAndFinalAnswer`, `AI_HLYUITests/AgentRuntimeConversationUITests/testUI04CollapsedProgressAndInspectorWithoutRawCoT`.
- Fresh package obligations: `HanlinAISDKAgentEngineTests` (all cases; orchestration stop behavior changed). Compile/package pins/Swift concurrency and new persistence APIs require the actual Xcode SDK; Windows parse is not sufficient.
- Reuse candidate only: native Runtime bundle `42687189577` remains byte-identical; no V8/ABI/FD/Host JS files changed in this batch. Download the exact private candidate; no new native build or public release. Prior zoom/audio/widget physical acceptance is still OPEN.
- Missing: direct native selection gesture/custom Save menu, opaque long-press preview coexistence, exact excerpt highlighting/ambiguous quotes, additive old-schema migration, browser interaction, accessibility and physical Stage Manager. These must not be inferred from layout/unit/build success.
