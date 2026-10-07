# Hanlin — SDK-first consolidation, capability preservation, current-platform modernization, and full runtime/tool completion
## FINAL MASTER execution prompt for a fresh coding-agent session

**Research/audit date:** 2026-10-04  
**Repository:** `davidpovarsky/hanlin-ai`  
**Required working branch:** `codex/agent-skills-embedded-results`  
**Verified reference HEAD when this document was prepared:** `89068b77d8a752a5a3d5c9b7dc48735f665245ec`  
**This document supersedes every earlier completion/architecture prompt.** It incorporates the full R01-R26 requirements and their test matrix, adds the SDK-first consolidation work, and records the owner’s explicit decision to **leave the existing Hanlin chat UI unchanged in this assignment**. No chat-UI framework migration or replacement is in scope. Where older wording conflicts with this FINAL MASTER section, this document wins.

---

## MASTER-0 — Mission and non-negotiable strategy

This is an implementation assignment, not an architecture proposal. Inspect the current branch first, then execute the whole plan. Do not stop after an audit or after the first subsystem. Continue automatically through all work that is not blocked by a genuinely external decision. A dependency/license decision that cannot be inferred is allowed to block only that dependency-specific subtask; it must not block unrelated work.

**Owner product decision for this assignment:** keep the existing Hanlin chat interface exactly as the product UI. Do not add, evaluate, migrate to, or substitute any third-party chat-UI framework in this implementation. Backend, agent, runtime, Skills, package and dependency work must integrate behind the current UI without redesigning or structurally replacing it.

The project strategy changes now:

> **Hanlin is an independently maintained fork. Upstream mergeability is no longer a primary architecture constraint. Preserve clean module boundaries for Hanlin's own maintainability, not to avoid editing old CherryHQ files. Directly edit or delete former upstream-owned code when doing so removes duplication, obsolete paths, or unnecessary wrappers. Do not preserve dead/legacy code merely because it came from upstream.**

At the same time, do **not** turn the repository into a monolith. The desired rule is:

> **SDK-first, one implementation path, thin Hanlin adapters, custom code only for Hanlin-specific capabilities and orchestration.**

Do not replace a Hanlin-specific feature just because a lower-level SDK exposes a related primitive. Replace generic duplicated infrastructure; preserve the product-specific behavior built above it.

### The architecture we want

```text
User / Chat UI
      |
      v
Hanlin conversation + persistence + agent presentation
      |
      v
Swift AI SDK agent loop (streamText / tools / prepareStep / stopWhen)
      |
      +---- Hanlin Skills + progressive tool discovery
      |          |
      |          +---- load_skill / read_skill_resource / tool_search
      |
      +---- Hanlin canonical tool authority + thin SDK tool adapter
                   |
                   +---- Native tools / Apple services
                   +---- MCP official Swift SDK -> embedded Node transport
                   +---- RuntimeCore -> Node / TypeScript / Python / JSC / QuickJS / ios_system
                   +---- ScriptUI / Scripting packages
                   +---- NativeScript / Expo / Mini Apps
                   +---- Embedded results / AgentActivity / evidence / diagnostics
```

The target is **not** to reduce the number of engines. Node, TypeScript, Python, JavaScriptCore, QuickJS, ios_system, NativeScript and Expo serve different purposes and must remain available unless a concrete capability-equivalent replacement is proven and accepted by all tests.

---

## MASTER-1 — Capability invariants: nothing below may be lost

Before deleting or replacing any existing code, create a machine-readable `capability-invariants.json` and a human-readable `capability-invariants.md`. Map every invariant to tests. At minimum preserve all of the following:

1. Remote AI providers can stream text, surfaced reasoning/summary data, usage, files/sources where supported, and native tool calls through the Swift AI SDK path.
2. The SDK, not a parallel Hanlin loop, owns recursive multi-step tool execution for the primary agent path.
3. `prepareStep` continues to support request-scoped dynamic tool visibility and Skill-driven progressive disclosure.
4. A request can begin with only meta-tools visible, load a Skill or use `tool_search`, expose a previously hidden tool, execute it, return the result to the model, and continue the same agent run.
5. No hard-coded Swift intent classifier replaces Skill selection.
6. Canonical tool aliases remain stable enough for installed Skills, while collisions from different providers remain disambiguated.
7. Native/legacy tools, compiled MiniApp tools, Script tools and MCP tools can all enter the canonical authority and become agent-callable.
8. Tool execution still emits progress/activity, diagnostics, user-facing presentation, evidence, embedded result payloads and durable result references where applicable.
9. `NativeUIBlock` and every existing rich result family continues to render: maps/routes, calendar/events, health/nutrition, knowledge, code, HTML/web content, evidence/resources, images/audio, canvas, MiniApp launches and future unknown blocks.
10. Existing chat persistence **and the current chat UI contract remain unchanged**: conversations, role/model metadata, attachments, activity/transcript information, rich results, message behavior and composer behavior must continue to work without a chat-UI migration.
11. Node JavaScript execution works.
12. Node TypeScript compilation/execution works.
13. JavaScriptCore lightweight execution works where selected.
14. QuickJS scripting remains available as a distinct engine.
15. Embedded CPython works and package persistence survives relaunch.
16. ios_system-backed command execution remains agent-callable and is broadened to the real backend capabilities rather than narrowed by Hanlin policy.
17. Node package preview/install/list/probe/use/uninstall works through canonical agent tools.
18. Python package preview/install/list/probe/use/uninstall works through canonical agent tools.
19. MCP npm packages can be installed, registered, started in embedded Node, discovered via the official MCP Swift SDK, publish tools, execute tools, restart/recover and remain selectable per chat.
20. MCP tool-list-change notifications continue to refresh the canonical catalog.
21. Scripting packages can import/preview/compile/install/relaunch/update/rollback/uninstall according to the package semantics that are actually implemented.
22. ScriptUI can render its native SwiftUI tree and receive events/state updates.
23. Scripting tools can publish into the agent catalog and return rich/embedded results.
24. Host services shared by engines continue to work: files, storage, network, SQLite, Apple/device services, open URL, pasteboard and assistant bridge where implemented.
25. NativeScript MiniApps continue to support both direct iOS Metadata Bridge access and `@nativescript/core`, and can present UIKit/SwiftUI through Hanlin.
26. Expo/React Native brownfield MiniApps continue to launch in their engine and coexist with the other engines.
27. Native/Swift MiniApps continue to appear in the Apps Hub and expose tools/UI.
28. Cancellation stops the correct run, leaves no stale UI spinner, and a new request can start immediately.
29. Cold launch and relaunch restore installed packages/Skills/runtime state without exposing stale tool schemas from a prior request.
30. The agent can inspect real runtime capabilities rather than hallucinating that it is isolated merely because a schema is progressively hidden.
31. Long tool results remain retrievable through the result store/reference path without silently truncating semantic output.
32. Search/Sefaria/Wikipedia/Text Studio and every current built-in domain tool continue to be discoverable and callable.
33. File/document handling, PDF, ZIP-based Office extraction and web parsing remain functional.
34. RTL, Dynamic Type, keyboard/pointer interaction, iPad resizing/multitasking and accessibility remain acceptable after the backend/runtime/platform changes; the chat UI itself is frozen except for minimal compatibility fixes required to keep the existing behavior working.
35. No migration may claim success solely because it compiles. Every preserved capability must have functional evidence at the strongest practical layer.

Any proposed deletion that cannot be mapped to preserved invariants is blocked until the agent proves it is dead/duplicated code.

---

## MASTER-2 — Verified current architecture facts: do not rediscover incorrectly

The following were verified from the branch and must be treated as starting facts, then revalidated against the live HEAD before editing:

### Agent / provider path

`Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKAgentEngine.swift` imports `SwiftAISDK`, `AISDKProvider`, and `AISDKProviderUtils`. It uses `streamText`, dynamic tool definitions, `prepareStep`, and `stopWhen`. This is the primary modern agent/tool loop. Keep it.

`HanlinAISDKProviderFactory.swift` already uses Swift AI SDK provider implementations for OpenAI, Anthropic, Google and OpenAI-compatible endpoints. Keep this provider abstraction unless a specific unsupported provider proves a need for a narrow adapter.

`APIManager.swift` still contains a legacy/manual request + tool-call accumulation/recursive continuation path. Treat that path as a strong consolidation target, not the SDK path.

`HanlinAISDKToolAdapter` is Hanlin-specific and justified: it bridges Skills, dynamic tool exposure, canonical tools, progress, diagnostics and embedded results into Swift AI SDK. Do not delete it merely because Swift AI SDK has tools.

### MCP

The app already depends on `modelcontextprotocol/swift-sdk` 0.12.1. `MCPClientSession` uses the official `Client`; `EmbeddedNodeMCPTransport` conforms to `MCP.Transport`. Do not create a second MCP protocol implementation. Preserve Hanlin-specific embedded-Node lifecycle/install/selection/registry behavior around the official SDK.

### Runtime engines

Current runtime inputs include NodeMobile, BeeWare Python Apple support, TypeScript, ios_system, JavaScriptCore and vendored QuickJS-NG. npm mechanics already use `@npmcli/arborist`, `pacote`, `semver`, and `ssri`. Do not write a new npm dependency resolver.

### NativeScript / Expo

NativeScript is already based on official NativeScript iOS runtime artifacts and `@nativescript/core`. Expo is built as a brownfield runtime package. Preserve both engines as product capabilities.

### Chat UI

Current `ChatBubbleView` is not merely text bubbles. It carries reasoning, tool activity, documents, resources, maps/routes, events, health cards, code, knowledge, `NativeUIBlock`, `AgentRun`, audio, canvas, embedded results and more. **This entire existing chat UI is out of scope for replacement/refactoring in this assignment.** Preserve the current message list, bubbles, composer, controls, streaming presentation and rich-result rendering as they are, aside from the smallest compatibility changes strictly required by unrelated platform/dependency work.

---

## MASTER-3 — Dependency research baseline and binding decisions

Refresh all versions at implementation time before changing pins. The table below is the researched baseline as of **2026-10-04**. “Latest” is never permission to adopt a beta/RC or to hand-mix dependency families. Prefer the newest **stable, mutually compatible** closure that exists when the work is executed.

| Dependency / candidate | Verified state at research time | Decision | Required treatment |
|---|---|---|---|
| `davidpovarsky/swift-ai-sdk` fork of `teunlao/swift-ai-sdk` | Hanlin fork was 13 commits ahead, 0 behind; upstream latest stable `v0.19.0`; active; Apache-2.0 | **KEEP; make it the one remote agent/provider path** | Keep `streamText`, tools, `prepareStep`, stop conditions and provider adapters authoritative. Maintain the fork as a small documented patch queue; upstream/drop patches when possible. Do not add another agent framework. |
| `modelcontextprotocol/swift-sdk` | Hanlin exact `0.12.1`; `0.12.1` was latest stable; official MCP SDK | **KEEP** | One MCP protocol stack only. Preserve Hanlin embedded-Node transport/lifecycle/registry/selection as thin product-specific layers. |
| MarkdownUI | Hanlin resolved `2.4.1`; already used by the existing chat UI | **KEEP CURRENT UI STACK** | Do not change its version merely for a chat-UI migration. Update only if independently required by another accepted dependency and only after current rendering parity tests pass. |
| `swift-markdown` | official Swift project, researched `0.9.0`, active, Apache-2.0 | **OPTIONAL STRUCTURED PARSER** | Add only if a real AST/parser use replaces custom parsing. Not required for rendering already covered by MarkdownUI. |
| Yams | researched `6.2.2`, active, MIT | **ADOPT FOR `SKILL.md` YAML FRONTMATTER** | Replace the hand-written pseudo-YAML parser; preserve unknown keys, multiline/quoted/Unicode values and deterministic round-trips. |
| GRDB | researched `7.11.1`, active, ~8.7k stars, MIT | **EVALUATE WITH A REAL PROTOTYPE; ADOPT ONLY IF IT SHRINKS THE BRIDGE** | It must preserve arbitrary SQL, positional/named binds, blobs, transactions, multiple handles and scripting semantics. Do not add a second persistence source of truth. |
| Runestone | researched `0.5.2`, active, ~3.2k stars, MIT | **EVALUATE FOR EDITABLE CODE SURFACES** | Candidate for code/Skill/canvas editors; not required for static chat code blocks. |
| ZIPFoundation | Hanlin `0.9.19`; latest researched `0.9.20` | **KEEP + UPDATE** | Use one archive primitive; remove duplicate Hanlin security/policy scanners that veto valid archives. |
| SWCompression | Hanlin `4.9.0`; latest researched `4.9.1` | **KEEP + UPDATE** | Continue for TGZ/TAR paths that actually need it. |
| SwiftSoup | Hanlin `2.8.7`; latest researched `2.13.9` | **KEEP + UPDATE** | Preserve WebRead extraction fixtures. |
| `swift-log` | Hanlin `1.6.2`; latest researched `1.15.1` | **KEEP + UPDATE AFTER API CHECK** | One logging abstraction; no new logging framework. |
| RichTextKit | Hanlin `1.2.0`; active line | **KEEP WHILE CURRENT UI USES IT** | The chat UI is frozen; do not remove or replace this dependency as part of UI consolidation. Only reconsider it in a future explicit chat-UI project. |
| LaTeXSwiftUI | Hanlin `1.5.0`; latest researched `2.0.0` | **MAJOR MIGRATION WITH PARITY TESTS** | Upgrade only when current math fixtures, selection, RTL and Xcode 27 compile/run tests pass. |
| CoreXLSX | Hanlin `0.14.2`; no clearly better maintained Swift XLSX reader was found | **KEEP FOR NOW** | Preserve XLSX extraction. Do not replace merely because its release cadence is old. |
| LLM.swift | Hanlin resolved `1.8.0`; latest researched `3.0.3`; active MIT | **UPGRADE IN AN ISOLATED LOCAL-MODEL MIGRATION IF PARITY PASSES** | 3.x adds embedded chat templates, incremental context, reasoning separation, structured output, tool calling and embeddings. Do not let its own tool loop become a second Hanlin canonical tool executor. |
| Apple Foundation Models | iOS 27 provides `LanguageModel`, improved `SystemLanguageModel`, multimodal prompts and dynamic profiles | **ADD AS A FIRST-PARTY LOCAL PROVIDER** | Integrate through a thin Hanlin/Swift-AI-SDK-compatible adapter where feasible. Keep Hanlin canonical tools authoritative; no second tool orchestration engine. |
| Apple Core AI / `apple/coreai-models` | iOS 27/Xcode 27; `.aimodel`; `CoreAILanguageModel` conforms to Foundation Models `LanguageModel` | **ADD AS AN OPTIONAL ADDITIONAL LOCAL MODEL ENGINE** | Complement, not replace, GGUF/LLM.swift. Use for supported `.aimodel` models and device-specialized inference. |
| MLX Swift / mlx-swift-lm | active Apple ML ecosystem | **OPTIONAL FUTURE ENGINE, NOT REQUIRED FOR THIS MIGRATION** | Do not add merely to increase engine count. Revisit only for a concrete model/performance need after Foundation Models/Core AI and LLM.swift are stable. |
| `quickjs-ng/quickjs` | Hanlin vendored `v0.16.1`; latest researched `v0.17.0` | **KEEP MINIMAL VENDORED ENGINE + UPDATE** | Rebase only the required Hanlin allocator/typed-OOM patch. Do not swap to an obscure wrapper. |
| BeeWare `Python-Apple-support` | Hanlin `3.14-b10`; latest researched `3.14-b11` | **KEEP + UPDATE THROUGH RUNTIME BUNDLE PIPELINE** | Preserve embedded CPython. Package support still needs Hanlin/Python mechanics; do not invent subprocess assumptions. |
| `holzschu/ios_system` | Hanlin `v3.0.5`; latest researched `v3.0.7` | **KEEP + UPDATE** | Remove Hanlin’s artificial command allowlists/parser bans and expose what the linked backend actually supports. |
| NodeMobile | Hanlin verified fork `heylogin/nodejs-mobile` Node `24.5.0` | **KEEP CURRENT VERIFIED FORK** | Do not downgrade to older public-release metadata. Upgrade only to a newer tested mobile Node closure. |
| NativeScript `ios-spm` | Hanlin exact `9.1.0`; core repo had `9.1.2-core`, but no matching `ios-spm` 9.1.2 ref was verified | **KEEP MATCHED 9.1.0 CLOSURE UNTIL MATCHING OFFICIAL SET EXISTS** | Never mix runtime/core/native binary versions just to chase a newer JS package. |
| Expo | Hanlin currently uses **SDK 58 preview** + RN `0.88.0-rc.0`; official Expo changelog on 2026-10-04 says **SDK 58 is still beta** and SDK 57 is stable | **MOVE TO NEWEST STABLE EXPO CLOSURE, NO PREVIEW/RC** | At execution time re-check. If 58 stable exists, use its official matched set. Otherwise migrate to latest SDK 57 patch (research baseline says `expo@57.0.23+` supports opt-in iOS 27 scene lifecycle) with official RN/React/Hermes alignment. |
| Apple `swift-collections`, `swift-atomics` | active official packages, currently transitive | **KEEP TRANSITIVE UNLESS DIRECT USE IS JUSTIFIED** | Do not create direct pins without a concrete API use. |
| Keychain/network/storage primitives | Hanlin wrappers are already thin over Security, URLSession, UserDefaults | **KEEP APPLE APIs; NO EXTRA LIBRARY** | Simplify Hanlin policy layers, not the underlying Apple primitives. |
| Third-party chat UI frameworks | Previously researched, but the owner has now frozen the existing Hanlin chat UI for this assignment | **DEFER / DO NOT ADD** | Do not add or migrate to any chat UI framework. Preserve `ChatView`, `ChatBubbleView`, `ChatViewBottom` and the existing rendering/composer behavior. |
| ManifoldKit / full-stack AI frameworks | overlap Hanlin agent loop, MCP, persistence, RAG/runtime ownership | **REJECT FOR THIS CONSOLIDATION** | They would add a second architecture instead of simplifying Hanlin. |

### Dependency adoption rule

A new dependency is allowed only when all of these are true:

1. It replaces generic infrastructure rather than a Hanlin-specific capability.
2. It is actively maintained or an official/stable platform component.
3. Its license permits Hanlin’s actual use and distribution model.
4. It materially reduces maintenance, custom LOC, or error-prone parsing/protocol code.
5. It does not introduce a second agent loop, MCP protocol stack, persistence source of truth, permission system, tool executor, or runtime registry.
6. Hanlin retains a narrow adapter seam so the dependency can be upgraded or replaced without rewriting domain models.
7. Capability-parity tests are green before old code is deleted.
8. “Popular” is supporting evidence, not a substitute for suitability, stable APIs, license compatibility and real repository fit.

## MASTER-4 — Chat UI freeze: preserve the current Hanlin interface as-is

The owner has explicitly changed scope: **do not replace, migrate, redesign, decompose or re-platform the current chat UI in this assignment.** The existing Hanlin chat surface is the product UI for now. All SDK-first/backend consolidation must happen behind it.

### 4.1 Files and behavior under UI freeze

Treat the following as behaviorally frozen unless a minimal compatibility edit is strictly necessary to keep the app building/running after an unrelated accepted change:
- `ChatView.swift` and the current message-list/scrolling behavior;
- `ChatViewComponents.swift`, `ChatBubbleView` and all current assistant/user message rendering;
- `ChatViewBottom.swift`, `InputTextField`, `ActionButtonsView`, model selector and all current composer controls;
- reasoning/tool activity presentation, `AgentRun` inspector/evidence, `NativeUIBlock`, MiniApp launch surfaces and every current rich-result section;
- current Markdown, code, LaTeX, images, documents, resources, maps/routes, events, health, knowledge, HTML, canvas and audio rendering;
- current send/observe/stop/retry/delete/copy/share/TTS/translate actions;
- current photo/camera/document/paste/URL/prompt/model/MCP/tool/search/knowledge/reasoning/audio/image/local-model controls;
- current iPad responsive behavior, RTL, Dynamic Type, keyboard/pointer and accessibility behavior.

### 4.2 Explicitly out of scope

For this assignment:
- do **not** add a third-party chat UI dependency;
- do **not** create a new chat message model or projection layer solely for a future UI framework;
- do **not** replace the message list, bubble renderer, composer, streaming UI, reasoning UI or tool activity UI;
- do **not** move thousands of lines into new files merely to claim decomposition;
- do **not** delete current chat UI code as “legacy” or “superseded”;
- do **not** change chat persistence schemas for a UI migration;
- do **not** change MarkdownUI/RichTextKit/LaTeX rendering just because another UI library would prefer different dependencies.

A future chat-UI migration is a separate project and requires a new explicit owner instruction.

### 4.3 Allowed chat-UI edits during this assignment

Only make chat-UI edits when they are strictly necessary to preserve existing behavior after another approved change, for example:
1. a compiler/API compatibility fix required by Xcode/iOS migration;
2. adapting an internal backend callback because the authoritative agent path changed, while keeping identical visible behavior;
3. fixing an actual regression discovered by the mandatory chat regression suite;
4. wiring a newly available backend/tool result into an **existing** generic result mechanism without redesigning the chat UI.

Every such edit must be minimal, documented, and accompanied by a before/after behavioral regression test. Do not opportunistically restyle, rename, reorganize, or simplify the UI while touching it.

### 4.4 Integration boundary for backend work

The backend consolidation target is:

```text
Existing Hanlin Chat UI (unchanged)
        |
        v
existing Hanlin conversation/state callbacks
        |
        v
Swift AI SDK agent loop + Skills + canonical tools + runtimes
```

The backend may become substantially simpler, but the existing UI-facing state/events must remain compatible. Where old backend types are removed, provide the smallest adapter needed at the existing UI boundary rather than redesigning the UI.

### 4.5 Mandatory current-UI regression baseline

Before broad backend deletions, capture deterministic regression coverage for the current UI: plain/long/streaming text, reasoning, tool activity, rich result families, attachments, all composer controls, cancellation, existing conversations after relaunch, RTL, iPad resizing and accessibility. Re-run the same suite after each migration group. The purpose is to prove **no visible or interactive chat behavior changed**.

## MASTER-5 — Platform modernization is now in scope

The current project file still targets iOS 26.0 and Swift 6.0. Apple released stable Xcode 27 (`27A266a`) and iOS/iPadOS 27 in September 2026; Xcode 27 includes Swift 6.4 and the iOS 27 SDK. The repository's own policy says to prefer the newest stable stack and no backward compatibility.

Therefore this assignment includes a controlled migration to the **latest stable Xcode 27 toolchain available on the runner and iOS/iPadOS 27 deployment target**, with these rules:

- Do not use Xcode 27.1/27.2 beta just because it is newer; use latest stable.
- Move app deployment target from iOS 26 to iOS 27 after dependency compatibility is verified.
- Update package `.iOS(.v26)` declarations to `.iOS(.v27)` where they are product/runtime targets.
- Do **not** blindly raise macOS host-test deployment targets to macOS 27 if the CI runner OS cannot execute those tests; host-only package targets may keep the minimum required to run verification, while the product remains iOS 27-only. Document this distinction.
- Use Swift 6 language mode and Xcode 27's Swift compiler. Adopt Swift 6.4 syntax/APIs where they simplify modified code, but do not churn unaffected files for style.
- Rename Xcode-26-specific workflow/display names only after the migrated workflow passes; preserve `workflow_dispatch` inputs and artifact semantics.
- Update Apple API usage only when touched or when Xcode 27 reports deprecation/availability issues; do not invent private APIs.

---

## MASTER-6 — New independent-fork repository policy

As an early commit, update `AGENTS.md`, `PROJECT_AGENT_GUIDANCE.md`, and relevant architecture docs so future agents do not reintroduce the old constraint. Preserve useful modern-Apple and verification rules, but replace the upstream section with:

- Hanlin is an independently maintained derivative of CherryHQ/hanlin-ai.
- Future upstream changes may be cherry-picked selectively after review; mergeability is not a design constraint.
- Direct edits/deletions in former upstream files are allowed when they reduce duplicate implementation or improve Hanlin architecture.
- Keep modules clean, avoid giant files and separate domain responsibilities for Hanlin's maintainability.
- Prefer one authoritative implementation path over wrappers kept only for historical ownership boundaries.
- Do not duplicate files merely to claim downstream separation.
- Report large architectural deletions and migrations with tests, not “upstream touchpoints”.

Do not delete attribution/license history required by the original project license.

---

## MASTER-7 — Execution order and deletion discipline

Use this order. The sequence is designed to protect capabilities while removing duplication:

1. **Inventory and baseline:** branch, dependency graph, packages, runtime lock, tool catalog, Skills, message model, tests, workflows, source LOC and capability map.
2. **Freeze capability tests:** add/repair tests for every MASTER-1 invariant before broad deletions.
3. **Update project policy docs:** independent-fork strategy.
4. **Modernize build baseline to stable Xcode 27/iOS 27** with no functional refactor yet; fix compiler issues only.
5. **Dependency refresh in small groups** with focused verification: pure Swift utilities first, then runtime bundles, then local-model/platform candidates. The current chat UI dependency stack is not a migration target in this assignment.
6. **Consolidate remote AI/provider/tool loop onto Swift AI SDK.** Keep a narrow non-SDK path only for proven unsupported modalities/providers.
7. **Fix Skills/import/tool discovery/package-manager exposure** and all runtime restrictions from R01-R26.
8. **Freeze and regression-test the existing Hanlin chat UI.** Do not replace/refactor the chat surface. Route backend/agent changes through the existing UI-facing state and callbacks with minimal compatibility adapters only when required.
9. **Simplify RuntimeCore/MCP/package policy layers** while keeping official SDKs and real engine capabilities.
10. **Simplify Scripting/HostServices** by removing redundant policy/broker layers only after cross-engine tests prove behavior.
11. **Upgrade QuickJS/Python/ios_system and stable Expo/NativeScript matched closures** where verified. Never adopt preview/RC Expo dependencies merely to claim “latest”.
12. **Adopt Yams for Skill frontmatter; evaluate GRDB/Runestone independently; migrate LLM.swift separately; add Apple Foundation Models/Core AI local-provider paths without replacing existing engines.**
13. **Delete dead backend/runtime legacy paths and now-unused dependencies.** Do not delete or restructure current chat UI code under this step; the UI is explicitly frozen. Do not leave two backend engines “temporarily” after parity is proven.
14. **Run the full verification ladder and device acceptance.** Produce final architecture/dependency/tool/capability reports.

### Delete-old-path rule

For each legacy path:

1. Identify its callers and behavior.
2. Add a parity test that fails if its unique behavior disappears.
3. Route all production callers to the new authoritative path.
4. Run focused tests.
5. Remove the old implementation, tests that only validate obsolete policy, unused symbols/resources/dependencies.
6. Run the regression suite again.

Never keep a second provider/tool loop “just in case” without a documented unsupported use case and a test proving why it remains.

---

## MASTER-8 — Additional implementation requirements R27-R47

### R27 — Consolidate the AI/provider path around Swift AI SDK

Map every remote provider/model mode currently handled in `APIManager`, `HanlinChatRequestBuilder`, `HanlinChatStreamParser`, and the Swift AI SDK path. Build a provider/modality parity matrix covering text streaming, reasoning, usage, native tool calls, images, audio, files/sources and provider-specific options.

For every text/tool-capable provider supported by Swift AI SDK, route production through `HanlinAISDKAgentEngine` and SDK providers. Move only genuinely Hanlin-specific configuration into thin mapping code. Delete manual request/SSE/tool recursion that has no remaining caller.

Do not delete image/audio/local-model paths merely because `streamText` does not own them. Keep each unsupported modality as a named narrow path with tests and a reason.

### R28 — Minimize and maintain the Swift AI SDK fork

Create `docs/dependencies/swift-ai-sdk-patches.md` listing all fork-only commits/files versus `teunlao/swift-ai-sdk`, the Hanlin bug/use case each patch fixes, upstream issue/PR if any, and whether the patch can now be dropped.

Keep the fork current with upstream after tests. Prefer an immutable tagged/revisioned Hanlin fork version. Do not copy SDK source into Hanlin. Add an automated/manual dependency check that reports upstream drift without auto-merging.

### R29 — One MCP protocol stack

Keep `modelcontextprotocol/swift-sdk` as the protocol authority. Audit Hanlin MCP code and remove only protocol/parsing functionality duplicated by the SDK. Preserve embedded Node transport, registry, secrets, installer, lifecycle, per-chat selection, tool publication and recovery where they are Hanlin-specific.

Do not switch to the MCP implementation inside Swift AI SDK unless a proof shows it can replace the official MCP SDK plus embedded transport without capability loss; the default decision is **no**.

### R30 — Freeze the current chat UI; no third-party UI migration

The current `ChatView`, `ChatBubbleView`, `ChatViewComponents`, `ChatViewBottom`, `InputTextField`, `ActionButtonsView` and related chat presentation are **not migration targets in this assignment**. Do not add a chat framework, do not build a replacement surface, and do not restructure these files merely for cleanliness.

Preserve every current result section and action exactly as product behavior: translation, TTS, copy/share, retry/delete, images, docs, citations/resources, code, knowledge, HTML, events, health, maps, canvas, audio, evidence, AgentActivity, `NativeUIBlock`, MiniApp launch, model metadata and message grouping/scrolling.

Any edit to these files must be justified by an unrelated required backend/platform compatibility change and must be the smallest possible patch with regression evidence.

### R31 — Preserve the current chat rendering/state contract during backend consolidation

As old provider/tool-loop/runtime code is removed, keep the UI-facing state and callbacks compatible. Do not introduce a new third-party message model, presentation projection model, tool-approval UI state machine or duplicate conversation state.

The existing UI must continue to receive streaming text, surfaced reasoning/summary data, tool activity, evidence, `AgentRun`, `NativeUIBlock`, rich tool results, cancellation state and final completion in the same semantic order and ownership model as before. If an internal adapter is necessary because the backend path changes, keep it narrow and located at the existing UI boundary.

### R32 — Preserve the current composer and all controls unchanged

Do not replace the composer. Preserve the existing implementation and semantics in `ChatViewBottom.swift`, including:
- text entry, return/send and paste-file behavior;
- send, observe and stop/cancel;
- model selector, model management and `@model` suggestions;
- photos/camera and arbitrary document picker/previews;
- selected URL previews and prompt chips;
- voice/dictation;
- tool-use mode and MCP server selection;
- knowledge and web-search toggles;
- reasoning/thinking mode and effort controls;
- model capability badges/states;
- image-generation reverse prompt and aspect/size controls;
- voice/audio generation mode;
- canvas shortcut and scroll-to-bottom behavior;
- local-model-specific controls;
- narrow iPad/window responsive behavior.

Backend refactors may change the implementation behind callbacks, but must not remove, rename, reposition or redesign these product controls. No new chat UI package may be introduced by this assignment.

### R33 — Skills YAML/frontmatter simplification

Adopt Yams for `SKILL.md` YAML frontmatter if it resolves and compiles under the selected stable toolchain. Parse standard YAML correctly, preserve unknown keys/forward-compatible metadata, handle multiline/quoted/Unicode content and serialize deterministically. Remove the hand-written pseudo-YAML parser after parity tests. Do not introduce Yams into unrelated JSON paths.

### R34 — SQLite/GRDB evidence-based decision

Prototype GRDB behind `HanlinSQLiteService` only if it can preserve current arbitrary SQL statements, named/positional binding, blobs, transactions, multiple handles and script/host-service behavior with materially less custom code. Measure source reduction and test complexity. If it does not materially simplify the bridge, keep the SQLite3 wrapper and remove only its obsolete self-imposed policy limits from R01-R26.

### R35 — Code editor/highlighting evidence-based decision

For editable code/Skill/canvas surfaces outside the frozen chat UI, evaluate Runestone against current text views for Python, JS, TS, JSON, shell, Swift, large files, selection/copy and iPad hardware-keyboard behavior. Adopt only if it improves maintainability/performance. **Do not replace the current chat code renderer in this assignment.**

### R36 — Runtime dependency refresh

Refresh runtime pins through the existing reproducible bundle pipeline, one engine group at a time:
- Python Apple support: evaluate/update `3.14-b10` -> `3.14-b11` or the newest stable compatible release available at execution time.
- ios_system: evaluate/update `v3.0.5` -> `v3.0.7` or newer stable compatible release.
- QuickJS-NG: update vendored `v0.16.1` -> `v0.17.0` or newer stable compatible release and reapply only the necessary Hanlin allocator patch.
- NodeMobile: keep current verified Node `24.5.0` mobile fork unless a newer tested mobile closure exists; never downgrade to older public release metadata.
- TypeScript: preserve the project’s intentional compiler/runtime split; update only with scripting/compiler acceptance.

Recompute provenance/hashes through existing scripts; do not hand-edit hashes.

### R37 — NativeScript matched closure

The current iOS runtime is exact `ios-spm 9.1.0`. Although `@nativescript/core` had a newer `9.1.2-core` release during research, no matching `ios-spm` 9.1.2 ref was verified. At execution time re-check official releases. Upgrade only when the official iOS runtime, core JS package, native binary targets and types form a verified compatible set. Until then keep 9.1.0 and simplify Hanlin wrappers/restrictions instead of creating a mismatched pair.

### R38 — Expo stable-channel migration for Xcode 27/iOS 27

Current Hanlin tooling is on `expo 58.0.0-preview.3` and React Native `0.88.0-rc.0`. This violates the project’s stable-only policy.

At execution time query Expo’s official current stable SDK and compatibility metadata:
- If Expo SDK 58 has become stable, use the latest stable SDK 58 matched dependency set.
- If SDK 58 is still beta (research state on 2026-10-04), migrate to the newest stable **SDK 57** patch instead. Official Expo guidance says `expo@57.0.23` adds opt-in scene lifecycle support required for Xcode 27/iOS 27; enable the documented `ios.enableSceneSupport` path where required.
- Use Expo’s official version alignment (`expo install --fix`/documented brownfield tooling) so Expo, React Native, React, Hermes, modules, `@expo/ui`, `expo-brownfield` and build artifacts are a supported set.
- Do not independently select RN `0.88` while it remains RC.

Keep the existing brownfield Hanlin runtime architecture. Rebuild/provenance-check XCFramework artifacts and run the full Expo production E2E suite.

### R39 — Utility dependency updates

Update compatible stable dependencies with focused tests: ZIPFoundation, SWCompression, SwiftSoup, swift-log and other resolved patch/minor updates that do not create incompatible major migrations. Treat LaTeXSwiftUI 2.x and LLM.swift 3.x as isolated major migrations with dedicated parity suites. Keep CoreXLSX unless an actual maintained replacement proves fixture parity and lower maintenance.

### R40 — Local-model modernization without a second agent architecture

Preserve all local inference capabilities. Upgrade/evaluate LLM.swift 3.x in its own commit series, covering GGUF local files, HuggingFace download/load, streaming, reasoning separation, cancellation, embeddings/structured output if used, memory and relaunch behavior.

LLM.swift 3.x’s internal function-calling capability must **not** become a second Hanlin canonical tool loop. If local-model tool calling is enabled, adapt its requested calls to the same Hanlin canonical tool authority/executor and return results through the same activity model, or leave tool calling disabled until that adapter exists.

Add Apple Foundation Models and Core AI as additional local-provider options according to R45/R46. Do not remove the GGUF/LLM.swift path merely because Apple engines exist; they serve different model formats/device capabilities.

### R41 — Scripting/HostServices de-customization

Audit `HanlinPlatform`, `ScriptingPlatform`, `Scripting`, `HostServices`, ScriptUI and package store for layers created primarily to enforce isolation/trust/upstream separation. Remove redundant policy/broker hops when direct typed adapters can preserve the same cross-engine behavior. Keep contracts that genuinely allow multiple engines to share one service or extension surface.

Do not collapse all engines into one. Do not expose raw app internals merely to reduce line count. The goal is fewer duplicated policy layers, not loss of runtime abstraction.

### R42 — Dependency/update automation

Extend the existing dependency-update reporting so it covers direct SwiftPM packages and major embedded ecosystems in report-only/PR-candidate form. Do not auto-merge. Distinguish safe patch/minor candidates from major/manual migrations. Reuse current RuntimeCore updater rather than writing a second updater for the same lock.

### R43 — Dead-code and duplicate-path removal

After migrations, run compiler-assisted/static dead-code review plus call-site search. Remove obsolete request builders/parsers, old tool loops, compatibility wrappers, policy scanners and package dependencies only when no invariant requires them. **Exclude the frozen chat UI from opportunistic dead-code/decomposition work unless code is proven unreachable and unrelated to the visible chat surface.** Record before/after LOC by subsystem and binary-size delta. Do not chase LOC at the expense of clarity.

### R44 — Final architecture documentation

Update dependency map, runtime map, agent/tool flow, the **existing unchanged chat rendering flow**, package lifecycle and test matrix to describe only production reality. Delete/mark obsolete architecture docs that instruct future agents to recreate removed restrictions or duplicate legacy paths. Document that chat UI replacement is explicitly deferred.


### R45 — Apple Foundation Models as an additional first-party local provider

Add an iOS 27 local-provider path using Apple’s Foundation Models framework where device/model availability permits. The implementation goal is not a second product agent: it is a thin provider/adapter feeding the same Hanlin conversation, streaming, cancellation, diagnostics and canonical-tool architecture.

Requirements:
- detect `SystemLanguageModel` availability and capability without crashing unsupported devices/simulator;
- support text streaming and the surfaced reasoning/metadata APIs Apple exposes publicly;
- support multimodal prompts where the selected Apple model and Hanlin request contain compatible images;
- investigate a `LanguageModel` -> Swift AI SDK/Hanlin model adapter so the existing `HanlinAISDKAgentEngine` can remain the loop owner;
- if full tool-call adaptation is not cleanly possible yet, ship the Apple path as a text/multimodal local provider first rather than creating a parallel Foundation Models tool executor;
- never expose hidden/private chain-of-thought; render only reasoning/summary data the framework publicly surfaces;
- write device capability tests and prompt regression fixtures because Apple’s on-device model changes with OS releases.

### R46 — Core AI / `.aimodel` engine as a complementary local runtime

Add/evaluate Apple Core AI for custom on-device models on iOS 27. Use the official Core AI / `apple/coreai-models` integration and `CoreAILanguageModel` where appropriate so a Core AI model can participate in a Foundation Models `LanguageModelSession`.

Requirements:
- keep this engine distinct from GGUF/LLM.swift;
- add a provider/runtime descriptor rather than special-casing UI;
- load/specialize asynchronously, surface progress/error state, cache specialization according to official APIs and support cancellation where the API permits;
- include a small supported `.aimodel` fixture only if licensing/size permits; otherwise make real-model E2E `BLOCKED_INPUT_MODEL_FIXTURE` rather than fake-pass it;
- record load latency, first-token latency, peak memory and steady-state throughput on a real iPad/iPhone test device;
- do not make Core AI a prerequisite for devices that cannot run the chosen model.

### R47 — Chat/agent/runtime compatibility contract with the current UI frozen

After all backend/runtime/agent migrations and capability tests are green:
- prove the existing chat UI still renders and behaves identically for all covered semantic content and controls;
- do **not** delete old message-list/composer/streaming UI code as part of this assignment;
- do **not** add third-party chat UI dependencies or projection models;
- report every touched chat-UI file and the specific compatibility reason it had to change; an empty list is preferred;
- ensure any backend adapter added solely to preserve the current UI is narrow and documented;
- prove that there is exactly one remote agent loop, one canonical tool executor, one MCP protocol stack and one conversation persistence source of truth, while the current chat presentation remains intact.


---

# PART II — Full original completion requirements R01-R26, corrected and carried forward

## 0. קרא עד הסוף לפני שינוי הקוד

**Precedence:** MASTER-0 through MASTER-8 and R27-R47 above override any conflicting historical wording in R01-R26 below. All non-conflicting R01-R26 requirements and tests remain mandatory.

בצע את **כל** הדרישות, המיפוי, התיקונים, אריזות ה־Skills ותסריטי הבדיקה במסמך זה. זו משימת השלמה אחת. חלק פנימית לתת־משימות לפי הצורך, אך אל תחזיר לבעלים “שלב 1 הושלם, לאשר שלב 2?” ואל תסתפק בכתיבת TODO או בדוח audit.

היעד: האפליקציה תחשוף לסוכן את יכולותיה האמיתיות באמצעות Skills וגילוי כלים; תתקין Skills תקינים; תריץ קוד ופקודות; תנהל חבילות Python/Node; ותפסיק לחסום שימוש אישי בגלל בדיקות אבטחה, רשימות מילים, מכסות שרירותיות או אישורים פנימיים שהמוצר אינו זקוק להם. התוצאה חייבת להישען על backend אמיתי ותוצאות אמיתיות, לא על תשובות מודל משכנעות.

**אל תוסיף תחליף אבטחה חדש במקום זה שהוסר.** לא risk engine, לא סורק קוד חדש, לא intent router קשיח, לא אישור חדש לכל פקודה, לא “trusted mode” שכבוי כברירת מחדל ומחזיר את אותן חסימות. השתמש בהגדרת הפיתוח האישית הקיימת ככל שהיא קיימת; אחרת, בצע שינוי מדיניות מצומצם בשכבות הנוכחיות, בלי מערכת מקבילה.

עם זאת, “הסרת חסימות” אינה מחיקת כל `guard` או טענה שכל דבר יכול לרוץ על iOS. שמור הפרדה מפורשת בין:
- **מדיניות יישומית שניתן להסיר:** סריקת מילות קוד, אישורי Hanlin חוזרים, allowlists של סיומות/פקודות, תקרות שרירותיות, חסימת התקנה על סמך ניחוש תאימות.
- **חוזה פעולה/תקינות:** JSON שניתן לפענוח, בחירת package/entrypoint אמיתיים, כתיבה אטומית, identity עקבית, schema תקין, טיפול בשגיאות ולא הצלחה מזויפת.
- **יכולת שאינה ממומשת:** למשל בניית sdist, resolver נוסף או כלי Agent חסר. צריך לממש את המסלול, לא למחוק תנאי ולקרוא לזה תמיכה.
- **מגבלת פלטפורמה מוכחת:** הרשאת מערכת, ABI/חתימה, API שלא קיים, או יצירת תהליך שאינה נתמכת על המכשיר. דווח ספציפית והמשך בשאר המשימה.

אל תשאיר מגבלה בשם “בטיחות” בלבד. לכל תנאי שיישאר לאחר המיפוי צריכה להיות סיבה נקודתית, קובץ/סמל, סוג הסיבה ובדיקה. אל תבטל אפשרות שהמשתמש עצמו כיבה בממשק, ואל תהפוך אוטומטית שגיאת ריצה להצלחה.

### הרשאת עבודה ובדיקות

הבקשה הזו מאשרת לסוכן לבצע את שינויי הקוד והבדיקות הרלוונטיות כאן, לרבות בדיקות מקומיות, build/test ממוקדים דרך סביבת Apple הקיימת או GitHub Actions ידניים, ובניית IPA ניסיוני אם זה מסלול האימות הקיים. היא **אינה** אישור למזג ל־`main`, לפרסם Release, להעלות ל־TestFlight/App Store, לשנות bundle ID/חשבון חתימה, למחוק נתוני משתמש, או להרחיב טריגרים אוטומטיים.

אל תריץ תסריטי בדיקה כותבים על נתונים אמיתיים. צור test profile, fixtures ותיקיות זמניות בבעלות הבדיקה. זו דרך לבודד את הבדיקות, לא דרישה להוסיף מגבלות מוצר חדשות.

### שימור העבודה והענף

1. קרא `AGENTS.md`, `PROJECT_AGENT_GUIDANCE.md` וכל `AGENTS.md` רלוונטי בתת־תיקייה.
2. רשום `git status --short`, הענף, `HEAD`, remote והבדלי העבודה הקיימים.
3. אמת שאתה בריפו ובענף לעיל. אל תעבוד בטעות ב־`main`, ב־vreader או ב־Maktabah.
4. בצע fetch לא־הרסני ובדוק את הראש העדכני. ה־SHA לעיל הוא נקודת ייחוס, **לא** הוראה לעשות reset לקוד ישן. אם הענף התקדם, התאם את הדרישות למצב העדכני.
5. אל תדרוס שינויים לא־מחויבים. אל תשתמש ב־`reset --hard`, force push או ניקוי גורף.
6. Hanlin is now an independently maintained fork. Directly edit/delete former upstream-owned files when that removes duplication or obsolete architecture. Preserve clean Hanlin module boundaries for maintainability; do not create downstream duplicates merely to protect hypothetical future merges.
7. צור commits ממוקדים בענף לאחר אימות. Dependency/platform migrations explicitly required by this MASTER plan are in scope; keep them in dedicated commits rather than mixing them into unrelated logic changes. אל תדחוף רק כדי להפעיל CI.

---

## 1. בסיס הראיות והדיוקים המחייבים

### 1.1 מה נצפה

- בלוג `agent-session-2026-10-04T10-18-25-14798257` הייתה תשובת מודל אחרי סבב אחד ו־**אפס קריאות כלי**, בלי capability/availability denial. זו אינה ראיה שה־runtime סירב.
- בלוג `agent-session-2026-10-04T10-10-29-ea114ccb` התבצע `tool_search` ואחריו הפעלות runtime. היו גם כשלי קוד/תלות; אין להציג את כל ההרצות כהצלחות.
- ה־runtime כולל CPython, Node, JavaScriptCore, TypeScript ו־ios_system. ניהול חבילות פנימי קיים. יש לבדוק מחדש את כל נתיבי החשיפה לסוכן ולא להניח שלכל שירות פנימי יש Agent tool.
- שני ה־ZIP packs המקוריים מכילים עשר אריזות פנימיות. בגרסה הראשונה יש wrapper; בגרסת FIXED הקבצים בשורש. שני המבנים כשלעצמם ניתנים לתמיכה.
- הודעת השגיאה `Archive entry escaped extraction staging directory` משמשת לפחות שני תנאי כשל שונים ב־`SkillImporter`: normalization ו־containment.

### 1.2 אל תקבע מראש סיבת שורש שלא הוכחה

בתשובות המקדימות יוחסה התקלה פעם ל־wrapper ופעם ל־containment. **שום ייחוס כזה אינו תחליף לשחזור על מסלול Foundation/ZIPFoundation של האפליקציה.** בבדיקת Foundation קטנה על Linux, הנוסחה הישנה קיבלה `SKILL.md` תחת שלוש תיקיות רגילות. זה לא אימות iOS ולא שלילה של בעיית trailing slash, percent encoding או alias של `/private/var`.

מצא את הענף המדויק שנכשל. בדוק במיוחד:
`SkillImporter.swift:221–233,344–348` מול `HanlinPackageCenter.swift:189–196` במצב הבסיס. ב־PackageCenter כבר קיים טיפול שונה ב־trailing slash וב־`path(percentEncoded:false)`. השתמש בידע ובקוד הקיים, לא בעוד resolver/“הגנה” מקבילים.

### 1.3 תקלה נוספת מוכחת באריזות — אין להחמיץ

בכל `hanlin.json` שנבדק באריזות שסופקו יש תאריכי ISO-8601, למשל:

```json
{
  "preferredToolIDs": ["execute_local_python_code"],
  "triggerHints": ["run code"],
  "keywords": ["python"],
  "baseSkillID": null,
  "originURL": null,
  "sha256": null,
  "isEnabled": true,
  "installedAt": "2026-10-04T12:00:00Z",
  "updatedAt": "2026-10-04T12:00:00Z"
}
```

ב־`SkillImporter` וב־`SkillStore.loadDescriptor` קיימים שימושים ב־`JSONDecoder()` ללא מדיניות תאריכים מתאימה. שחזור קטן עם `Codable` על Swift 6.2.1/Linux הראה `typeMismatch(Double)` ב־`installedAt`; decoder עם `.iso8601` קיבל את אותה דוגמה. במסלול `try?` הנוכחי metadata עלול להיות מוחלף ברשימות ריקות. לכן “הייבוא הצליח” אינו מספיק: צריך להוכיח שה־hints וה־preferredToolIDs שרדו עד הקטלוג והבקשה למודל.

אל תפתור זאת באמצעות החלפת כל ה־decoders ל־ISO בלבד: נתוני store ישנים עשויים להכיל מספרים במבנה `Date` של Foundation. נדרש codec תואם ומפורש.

### 1.4 תיקוני דיוק טכניים למסקנות המקדימות

הסעיפים הבאים מתקנים במפורש ניסוחים גורפים קודמים, ולא מצמצמים את מטרת הסרת המדיניות:

- כיבוי `ignoreScripts` ב־npm לבדו **אינו** תמיכת lifecycle על iOS. יש לוודא שמסלול ההרצה פועל דרך המנועים המוטמעים ולא מניח `/bin/sh` או subprocess.
- מחיקת התנאי `py3-none-any` לבדה **אינה** installer ל־sdist או ל־native wheel. יש לממש התאמה לפרופיל הריצה ומסלול build אמיתי במקום לדווח על תמיכה שאינה קיימת.
- ב־iOS רגיל, ניסיון `fork/spawn` אינו בהכרח שגיאה ניתנת לתפיסה; מקורות Python מתארים אפשרות של עצירת התהליך הקורא. לכן אין לבצע “ננסה כל syscall ונראה” בתוך תהליך האפליקציה. הסר את סריקות המילים והמדיניות; השאר רק התאמת פלטפורמה צרה לפעולה שבאמת אינה קיימת, או גשר in-process אמיתי.
- `.wasm` כנתונים ו־`.pth` של Python אינם שקולים אוטומטית ל־native Mach-O שניתן לטעון. אל תשתמש בסיומת בלבד כהוכחה לאי־תאימות.
- בדיקת חתימת dependency הנדרשת ל־SwiftPM, תקינות registry ו־artifact identity אינן אותה דרישה כמו approval לכל script. אל תשבור אותן בשם ביטול אישורים.
- “קיימת הגבלה בקוד” אינו מוכיח שהיא מופעלת במסלול production. למשל מגבלות MiniApp data עשויות להיות `nil`; broker עשוי להיות test-only; agent כבר מקבל wildcard במסלול מסוים. עקוב אחרי call sites.
- ATS שייך למסלולי networking הרלוונטיים של Apple; אל תייחס אוטומטית ל־curl/Node כל התנהגות של URLSession.
- לא ניתן להבטיח שהמודל יבחר Skill נכון בכל ניסוח באמצעות metadata בלבד. נדרש אימות ספק אמיתי, בנפרד מבדיקות deterministic. אל תמציא הבטחה של 100% התנהגות רק כי mock עבר.

**מצב הראיות במסמך:** מקור ריפו/אריזות + שחזור metadata נייד; אין כאן טענה שקוד האפליקציה קומפל או שהתקלה כבר שוחזרה במכשיר. עליך להשלים את ראיות הקבלה.

---

## 2. ניהול השלמות — אין להשמיט דרישה או כלי

צור תחת תיקיית תיעוד downstream קיימת, או תחת `docs/hanlin-platform/personal-runtime-completion/` אם אין חלופה מתאימה:

- `requirements.md`: כל מזהי `R01`–`R44`, כל הוראות `MASTER-*`, capability invariants, קבצי המימוש, תסריטי הקבלה ומצבם.
- `restriction-inventory.json`: כל restriction שנמצא; schema מתואר להלן.
- `tool-inventory.json`: כל הכלים ב־production, גם כאלה שכובו בהגדרות, בנפרד מ־meta tools.
- `acceptance-results.json` ו־`acceptance-results.md`: תוצאות כל מזהי הבדיקות במסמך, עם evidence.
- `remaining-limitations.md`: רק מגבלות אמיתיות/חוסרים שנותרו והראיה לכל אחד.
- `architecture-migrations.md`: שינויים/מחיקות ארכיטקטוניות גדולות, מסלול ישן שהוסר, המסלול החדש, capability invariants שהוגנו והבדיקות שהוכיחו parity. מקור upstream היסטורי יכול להירשם כ־provenance בלבד.

השמות האלו הם **תוצרים נדרשים חדשים**, לא טענה שהם קיימים היום.

רשומת restriction חייבת לכלול:
`id`, `path`, `symbol`, `lineAtBaseline`, `productionCallers`, `condition`, `effect`, `classification`, `decision`, `reason`, `replacementBehavior`, `requirementIDs`, `testIDs`, `evidence`.

ערכי decision:
`removed`, `relaxed`, `diagnosticOnly`, `retainedCorrectness`, `retainedPlatform`, `inactiveOrTestOnly`, `notApplicableWithEvidence`.

רשומת tool חייבת לכלול:
`logicalID`, `alias`, `provider`, `sourceKind`, `schema`, `executor`, `settingState`, `runtimeAvailability`, `skillIDs`, `discoveryStatus`, `invocationStatus`, `testIDs`.

השתמש במצבי בדיקה נפרדים:
`PASS`, `FAIL`, `BLOCKED_EXTERNAL`, `NOT_RUN`, `NOT_APPLICABLE_WITH_EVIDENCE`.
הוסף שדה `layer` כגון `unit`, `integration`, `simulator`, `device`, `provider`.
**Mock PASS אינו Device PASS; build PASS אינו functional PASS.**

השלמות נבדקת לפי חיתוך קבוצות: לכל כלי שפורסם ולכל restriction production יש שורת מיפוי ובדיקה. היעדר תוצאה בחיפוש טקסט אינו ראיה שדבר אינו קיים. חיפוש שמוגבל ל־default branch או רשימת compare של 300 קבצים אינו audit של הענף.

---

## 3. דרישות המימוש


### R01 — מיפוי מלא של הקוד וה־call graph

סרוק את כל `git ls-files`, ולא רק קבצים ששמם מכיל Policy. כלול `AI_HLY/Downstream`, `NativeAgentExtensions`, `NativeAppPlatform`, `Services`, כל `Packages/*/Sources`, native bridges, קוד JS שנארז במשאבי runtime, schemas, SDK-generated wrappers, בדיקות ו־CI. הפרד vendor/reference/fixtures מקוד שבאמת רץ. חפש גם guards, numeric clamps, default values, string scanners, denied outcomes, `ignoreScripts`, approval, `minimumTrust`, `isEnabled`, `canInstall`, `isAvailable`, timeout, output truncation, unsupported fallbacks ו־checksums.

עקוב מכל חסימה עד נקודת שימוש אמיתית. אל תסווג state machine guard, mutex, GIL, continuation-resume-once, טיפול ב־UTF-8 או בדיקת schema כסריקת אבטחה. צור snapshot של הכלים עם כל domain מופעל בפרופיל בדיקה, ואז snapshot נוסף תחת הגדרות המשתמש בלי לשנות אותן.

### R02 — תיקון Skill import והסרת מדיניות האריזה המיותרת

**קבצים:** `AI_HLY/Downstream/AgentSkills/SkillImporter.swift`; `Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinArchivePolicy.swift`; רכיבי ה־import UI; `HanlinPackageCenter.swift` לצורך השוואה ושימוש חוזר.

שחזר את שתי האריזות המדויקות ואת `SKILL.md` השורשי. הפרד diagnostic codes ל־entry normalization, destination resolution, archive decoding, filesystem writing ו־markdown parsing. אל תשאיר שתי סיבות שונות מאחורי אותה הודעה מטעה.

הסר מייבוא Skill את ה־extension allowlist ואת חסימות 25MB / 1,024 files / 256 directories / depth 16 / expanded 64MB / compression ratio 100 כמדיניות קשיחה. אל תחסום assets כגון `.xlsx`, `.docx`, `.ttf`, `.bin`, `.wasm`, קובץ ללא סיומת או קובץ בשם `LICENSE`. ה־Skill הוא חבילת הוראות ומשאבים, לא רשימת סיומות שאנו מאשרים. אין להריץ asset כדי לייבא אותו.

השתמש בחילוץ של ספריית ZIP הקיימת וב־destination resolution אחד. אל תוסיף סורק חלופי. קבל root, wrapper, תיקיות עם רווחים/עברית, entries מסוג directory ונתיבים פנימיים שקולים לאחר normalization. אל תבצע double-percent-decoding. בדוק trailing slash ו־`/var` לעומת `/private/var` על Apple Foundation.

**גבול הפעולה נשאר גלוי ולא מוסווה:** פעולה בשם “התקן Skill” מחלצת לתיקיית ההתקנה שנבחרה, לא כותבת בשקט ליעד מוחלט שרירותי מתוך ZIP. אל תבטל את מנגנון יעד החילוץ של ספריית ZIP או תשתמש ב־`allowUncontainedSymlinks:true` כדי להשתיק bug. נתיב שלא ניתן לפרש בתוך פורמט החבילה מקבל שגיאת פורמט/יעד ברורה; זו אינה חסימה של אותם נתיבים בכלי filesystem או runtime. symlink פנימי תקין אינו סיבה לפסול חבילה שלמה; תמוך בו כאשר הספרייה וה־filesystem יכולים לייצג אותו.

המשך לשמור על install transaction ו־rollback במקרה של I/O failure. CRC שגוי, ZIP קטוע, entry unreadable או יעד לא־ניתן לכתיבה אינם “הגבלות אבטחה” שיש להפוך להצלחה.

תמוך גם ב־import מרובה: outer pack עם כמה תיקיות Skill, או עם `skill.zip` אחד בכל תיקייה, כמו שתי החבילות שסופקו. הצג preview של רשימת Skills, התקן אותם בפעולת import אחת, והצג תוצאה מפורשת לכל פריט. אל תבחר שרירותית SKILL ראשון. כאשר שני פריטים מצהירים על אותו ID, הצג resolution של conflict; אל תדרוס בשקט. תמיכה ב־bulk אינה רישיון לסרוק ארכיונים שרירותיים בלי סוף; בחר את מבנה pack המוצהר וייבא רק את חבילות ה־Skill שלו.

### R03 — metadata, Markdown ומיגרציה ללא אובדן

**קבצים:** `SkillModels.swift`, `SkillStore.swift`, `SkillImporter.swift`, editor/export/import UI.

ממש codec אחד לכל `hanlin.json`: קבל ISO-8601 רגיל ועם fractional seconds, תאריכים מספריים ישנים בפורמט Foundation, ושדות תאריך חסרים. בכתיבה חדשה השתמש בפורמט יציב ומתועד. אל תשתמש ב־try? שמחליף metadata קיים ורלוונטי בריק. `preferredToolIDs`, `triggerHints`, `keywords`, `baseSkillID`, origin ומצב enablement חייבים לשרוד install, refresh, relaunch ו־export/import.

אל תהפוך חוסר תאריך לחוסר כל ה־metadata. על JSON פגום הצג שגיאה ברורה או preview לתיקון; אל תכתוב מעל המקור בשקט. שמור unknown fields הנדרשים ל־forward compatibility במקום להשמידם.

תקן את parser ה־frontmatter כך שיטפל בתיאור חד־שורי מצוטט, `:` בתוך מחרוזת, multiline `>`/`|`, BOM/CRLF, Unicode ומפרידי `---` בגוף. העדף parser קיים ומתוחזק בפרויקט אם קיים; אל תכתוב מימוש חצי־YAML שמוצג כתמיכה מלאה. ID יציב ומכני נפרד מ־display title. אל תסריאל `name: Code Execution` במקום ID חוקי ב־export.

במסלול `.md` בודד אין `hanlin.json`; אל תמציא metadata שלא נמסר. אפשר לייבא ולגלות כלים דרך ההוראות. הוסף UI/ייבוא sidecar היכן שהוא כבר מתאים, והבהר מה נשמר. אין לטעון שזה זהה לחבילת ZIP עשירה.

### R04 — קטלוג Skills, משאבים, overrides וסנכרון

**קבצים:** `HanlinSkillCatalog.swift`, `SkillStore.swift`, `HanlinSkillIndex.swift`, `LoadSkillTool.swift`, `ReadSkillResourceTool.swift`.

שמור מנגנון precedence קיים, אך ודא ש־import אינו “מצליח” ואז נעלם בגלל collision עם built-in. override מפורש חייב להחליף את ה־Skill הנכון; custom אחר נשאר נפרד. import של `baseSkillID` לא יישאר metadata מת במקום מימוש ברור.

`read_skill_resource` נשאר כלי משאבים של Skill, לא דלת אחורית כללית ל־filesystem. אפשר נתיבי משאבים תקינים גם עם רווחים/עברית/נקודות בשם. הסר `contains("..")` גורף שפוסל `release..notes.md`; הבדל בין רכיב נתיב לבין substring. ודא שמשאב binary זמין לכלי הביצוע/קבצים המתאים או מקבל descriptor/path handle שימושי, לא “חסר” רק כי אינו UTF-8.

טען מצב Skill בכל request באופן עקבי. אין לאבד instructions בין סבבים באותה ריצה; אין להשאיר schema של כלי שנמחק כשמתחילה ריצה חדשה. עדכון catalog בזמן run צריך snapshot עקבי, לא ערבוב revisions.

### R05 — Skills-driven discovery, בלי intent router קשיח

**קבצים:** `SystemSkillsProvider.swift`, `HanlinSkillIndex.swift`, `AssistantCapabilitySession.swift`, `AssistantToolExposurePlanner.swift`, `HanlinAISDKToolAdapter.swift`, `AssistantToolBridge.swift`, `APIManager.swift`, `HanlinAISDKAgentEngine.swift` וה־provider adapters.

שמור:
`user request -> model selects skill -> load_skill -> tools available -> execution`.

אל תוסיף Swift `if text contains python/npm/...` שבוחר tools במקום Skills. כן הוסף להוראת המערכת הכללית הסבר שמותקן catalog דחוי: היעדר schema גלוי אינו היעדר יכולת; לפני טענת אי־יכולת יש לעיין בקטלוג/לטעון Skill/לבצע discovery. זו הנחיה כללית, לא classifier של תשובות ולא censor שמחליף את תשובת המודל.

בטל את ה־4KB hard cap של `preferredToolIDs` כש־Skill נטען במפורש. כל preferred tool שקיים וזמין ייחשף, בלי לחשוף אוטומטית את כל קטלוג האפליקציה. כאשר ספק מציב מגבלת request אמיתית, פצל גילוי/טעינה והסבר אותה; אל תמציא מגבלה פנימית חדשה.

תקן `tool_search`: התאמה לקסיקלית/semantic אמיתית קודמת ל־skill boost. Boost לא יגרום להחזרת כלים בלתי רלוונטיים כשאף term אינו מתאים. exact alias חייב לקבל עדיפות. תמוך בעברית ובאנגלית בתיאורים/טריגרים, ב־pagination וללא max=10 שמסתיר את שאר התוצאות. חיפוש אינו חייב להפעיל את כל תוצאות כל הדפים בבת אחת.

החזר `isError` ו־outcome נכונים ל־load/search/resource/result failure. כיום טקסט “Error:” יכול להירשם כ־succeeded במסלולי meta tools; תקן זאת, בלי parsing שביר של מילים אם אפשר להחזיר תוצאה typed.

### R06 — השלמת כל ה־Skills ולא רק עשרת הקבצים הקודמים

עדכן built-in Skills ושחזר חבילות התקנה הנגזרות מאותה הגדרה, לא שני נוסחים שמתפצלים. כיסוי חובה לפחות:
Memory, Calendar/Reminders, Maps/Location, Weather, Web/arXiv/Remote Documents, Knowledge, Canvas/Web Preview, Python/Node/JSC/TypeScript/Shell, Health/Nutrition, Sefaria, Wikipedia, Text Studio, Package Management, Tool/Runtime Audit. חבר Skill קיים של MiniApp במקום לייצר כפילות.

הוסף משפחה אחרת לכל production tool שאין לו כיסוי. לא צריך Skill אחד לכל function; צריך workflow ברור לכל יכולת. גוף ה־Skill יתאר בדיוק את הכלים האמיתיים ושדותיהם, שימוש ב־runtime הנכון, בדיקת תוצאה, fallback רק לפי החלטת משתמש כשמשתנה execution locality, וטיפול בשגיאות. אל תמציא כלי שלא פורסם.

ה־Code skill יכלול במטא־דאטה המוצג לפני טעינה: קוד, הרצה, בדיקה, טרמינל, פקודות, סקריפטים, התקנה, חבילות, תלות, Python, JS, Node, TypeScript, shell, npm, pip/PyPI, runtime. לאחר הטעינה יבחין בין JSC לבין Node, ולא ידרוש `require()` ב־ESM. `ModuleNotFoundError` אינו הוכחה ש־Python אינו רץ.

אל תשאיר ב־Skills החדשים הוראות הישנות כגון “אין package tool” או “מותרות רק 23 פקודות” אחרי שתוקנו המימושים. אין לטעון שכלי נבדק על device רק כי הוא מוזכר ב־Skill.

כל ZIP של Skill יהיה עצמאי, עם `SKILL.md`, metadata תקין וכל משאב שאליו הוא מפנה. החזר גם pack לייבוא מרובה ומדריך התקנה קצר. עדכן את `hanlin-tool-audit` כך שיסתמך על enumeration אמיתי, ולא יעמיד פנים שחיפוש של 10 תוצאות הוא כל הקטלוג.

### R07 — Enumeration ואבחון יכולות אמיתיות

השתמש ב־API קיים מתאים; אם חסר, הוסף meta tool קטן בשם מוצע `list_tools` עם pagination ו־metadata בלבד, ו־tool בשם מוצע `get_runtime_capabilities`. אלו **שמות למימוש חדש**, לא שמות כלים שנמצאו בבסיס.

`list_tools` יציג logical ID, alias, provider, מצב enabled/disabled, האם discoverable, וסיבת unavailable כשידועה. אפשר לפרופיל audit לראות כלים כבויים בלי להפעילם. `get_runtime_capabilities` יחזיר את מצב runtime בפועל, גרסה מדווחת, תמיכת syntax/commands, cwd, מסלול חבילות ותקרות אפקטיביות; אל תכלול סודות. health check כושל לא משאיר runtime מסומן ready.

בלי “11 כלים = כל האפליקציה”: ספור meta/native/legacy/MCP/Script/compiled MiniApp בנפרד. סכמה קיימת, כלי חשוף, כלי שנקרא וכלי שעבר בדיקה הם ארבעה מצבים שונים.

### R08 — כלי Agent לניהול חבילות Node/Python

**קבצים:** `PythonPackageManager.swift`, `NodePackageManager.swift`, `NativeToolCatalog+RuntimeTools.swift`, schema/adapter/canonical registration וה־Skills.

אם עדיין אין ממשק Agent, הוסף wrapper typed לשירותים הקיימים. העדף כלי קוהרנטי אחד, לדוגמה `manage_runtime_packages`, עם `runtime: node|python` ו־`action: list|preview|install|uninstall|probe`; הוסף `status|cancel` אם נדרש למסלול ארוך. אם קיימים כבר כלים מקבילים, הרחב אותם בלי aliases כפולים מיותרים.

תמוך ב־package spec/version/extras ובמקורות מקומיים/URL שה־manager אכן תומך בהם; ממש את החסר שבתחום המשימה ולא תעביר shell `pip install` לכלי שאינו יודע להריץ pip. רשום source/version requested/resolved, dependencies, install status, probe status וה־runtime שאליו הותקן.

מצבי `installed`, `importVerified`, `importFailed`, `unverified`, `cancelled`, `failed` אינם שקולים. CLI-only או subpath-only package יכול להיות מותקן גם כש־`import(packageName)` אינו כניסה חוקית. אל תחזיר success לפני commit של ההתקנה. אל תתקין בסביבה של סוכן הקוד ותטען שהותקן באייפד.

פעולה כותבת דורשת בקשת משתמש בהקשר המשימה, לא מנגנון Hanlin approval חוזר לכל package/version/hash. rollback נחוץ על כשל כתיבה/רישום; probe failure שאינו כשל התקנה מקבל status נפרד.

### R09 — filesystem נגיש, cwd משותף ונתיבים תקינים

**קבצים:** `RuntimeFileLayout.swift`, `HanlinFileService.swift`, `HanlinMiniAppDataStore.swift`, `HanlinHostServicesBroker.swift`, `HanlinRuntimeBroker.swift`, `MCPServerPathResolver.swift`, runtime bridges.

הסר עבור שימוש הפיתוח האישי את ההכרח שפעולת runtime תהיה דווקא תחת `clients/<id>` או MiniRoot פנימי. אפשר נתיב מוחלט חוקי, `..` שנפתר ליעד נגיש, symlink חוקי ותיקייה שהמשתמש בחר. יכולת גישה נקבעת לפי הרשאות התהליך וה־security-scoped URL האמיתי, לא רשימת directories חדשה של Hanlin.

שמור defaults שימושיים ו־cwd עקבי לאותו agent context; Python, Node ו־shell חייבים לראות קובץ שאחד מהם כתב כשמתבקש workflow משותף. אל תערבב namespaces של MiniApps או של שתי שיחות כתוצאת לוואי.

בחירת תיקייה חיצונית צריכה לשמר bookmark/security scope לאורך הפעולה, לטפל ב־stale bookmarks ולהסביר OS denial. אל תחשוף file paths אמיתיים בסכמה של כלי שאינו אמור לקבל path, ואל תמציא הרשאה שקיצור path אינו מעניק.

MCP: אפשר package root קיים שנבחר על ידי המשתמש. אל תדרוש UUID directory כמדיניות execution. שמור ownership metadata כדי ש־uninstall של רישום external package לא ימחק תיקייה חיצונית של המשתמש. relative entrypoint נשאר טוב לניידות, אך אינו מנגנון כלא ל־runtime.

### R10 — משתני סביבה: defaults ולא איסור override

**קבצים:** `RuntimePolicy.swift`, `RuntimeEnvironment.swift`, `host.mjs`, `runtime-probe.mjs`, CPython bridge, ios_system runner.

בטל reserved-name rejection גורף של `PATH`, `HOME`, `NODE_PATH`, `PYTHONPATH`, `NPM_CONFIG_*` ואחרים עבור הפיתוח האישי. סדר ההכרעה יהיה מפורש: runtime defaults, הגדרות משתמש, override של הקריאה. הצג ערכים אפקטיביים לא־סודיים ב־diagnostics.

אל תשבור bootstrap של CPython על ידי שינוי מאוחר כאילו interpreter חדש נוצר. הגדרות initialization-only יקבלו טיפול נכון/הודעת restart נדרשת, לא התעלמות. שמור module search paths נדרשים והרחב אותם במקום לאבד את stdlib.

שמור locks ו־restoration סביב env/cwd process-global. הרצות מקבילות לא ידליפו HOME, cwd או credentials ביניהן. אל תבטל redaction של סודות רק כי הוסרו gates.

### R11 — Shell אמיתי בגבולות ה־backend הקיים

**קבצים:** `ShellRuntimeService.swift`, `ExecuteShellCommandTool.swift`, `Packages/IOSSystemLite/Sources/IOSSystemLite/IOSSystemRunner.swift`, שני command dictionaries, `Packages/IOSSystemLite/Package.swift`, בדיקות resources וה־workflow.

הסר “בדיוק 23 פקודות”, “extra dictionary חייב להיות ריק” ודחיית פקודה נוספת רשומה. גזור catalog מהפקודות שבאמת קיימות, linked/registered וברות הרצה. אם framework כבר מוטמע אך commands שלו הושמטו מן המילון, פרסם אותם. אם פקודה דורשת linking חדש, עשה זאת רק אחרי בדיקת dependency אמיתי ורלוונטי, ותעד; אין להמציא binary.

ספק שני מצבי קלט נבדלים:
1. `program + arguments`: argv מובנה; `|`, `>`, `;` במחרוזת argument הם **נתונים**, לא תחביר.
2. `command`: command string למסלול parser של ios_system/מסלול shell הנתמך בפועל, עם pipes/redirection/chaining/substitution רק לפי תמיכת backend מוכחת.

אל תאפשר “raw command” ואז תעטוף כל token ב־quotes כך שכל התחביר נהפך לליטרלים. מצד שני, אל תפרש argv מובנה כ־shell string ותשנה את כוונת הקורא.

הסר סריקת כל argument כ־path: ביטוי `sed 's/a/b/'`, ביטוי awk או regex שמתחיל `/` אינם filesystem path. הסר חסימת absolute/parent paths של Hanlin. הסר miniRoot המצומצם כאשר אינו דרישת backend; אל תגע ב־OS sandbox.

פרסם stdin, cwd ו־exit semantics אמיתיים. בדוק set-directory לפני execution וטיפול בשגיאת chdir. serialization של streams/cwd נשארת הכרחית. פקודה חסרה מחזירה `commandUnavailable`, לא הצלחה ולא “sandbox forbidden”. אין להבטיח bash/git/npm רק בגלל שה־allowlist נמחק.

### R12 — JavaScript/TypeScript: להסיר source scanning ולבחור runtime נכון

**קבצים:** `host.mjs::rejectUnsafeSource`, `ExecuteJavaScriptTool.swift`, `ExecuteTypeScriptTool.swift`, `NodeRuntimeService.swift`, `TypeScriptRuntimeService.swift`, `JavaScriptCoreRuntimeService.swift`.

הסר את `rejectUnsafeSource` ואת כל חוסמי המילים `child_process`, `cluster`, `docker`, `sudo`, `curl | sh`. מחרוזת או comment אינם קריאת API. אל תחליף regex אחד ב־AST security scanner.

אפשר import אמיתי של modules שקיימים. הבחנה בין JSC ל־Node היא מימוש/יכולות, לא הרשאה. Skill או explicit runtime יעדיפו Node עבור async/timers/Node packages. `auto` צריך להיות עקבי ומתועד; בדוק timers ללא `import` שלא סומנו בעבר כמחייבי Node. JSC שלא תומך ביכולת יחזיר עובדה מדויקת, לא יעביר קוד בשקט ל־remote service.

`compile_only` לא יריץ side effects. Node availability שגויה לא תכשיל compilation שאינו זקוק ל־Node execution. health check אמיתי יקבע האם backend ניתן להפעלה.

### R13 — MCP Node: הפרדת anti-bypass policy מתאימות פלטפורמה

**קבצים:** `server-worker.mjs`, `runtime-probe.mjs`, `host.mjs`, `NodeRuntimeService+MCP.swift`, fixtures של `child_process`/bindings/cluster.

הסר חסימת import של `cluster`/`child_process`, חסימת `.node` על סמך שם בלבד, ואת מנגנון “מניעת bypass” כמדיניות כללית של האפליקציה. module hooks שמשמשים TypeScript/module resolution יישארו רק לתפקידם הטכני.

לפני הסרת shim של process APIs, אמת בפלטפורמה וב־NodeMobile המוטמע אילו פעולות נתמכות. פעולה שאינה נתמכת על iOS צריכה לקבל adapter צר או `platformUnsupported` עם הראיה, **לא** להפיל את host, ולא “permission denied”. import ללא invocation יעבוד. כאשר target הוא macOS/Windows בדיקתי ותהליך רגיל נתמך, אין להפעיל את חסימת iOS שם.

אל תשתמש ב־`process.binding` פרטי כדרך ליצור יכולת חדשה. בדוק נתיבי API ציבוריים; fixtures קיימים של binding יכולים להישאר כבדיקות שגיאה/אי־קריסה, לא כמטרה “להריץ private process internals”. הסרת סורק אינה רישיון להזיק לתהליך המתמשך.

אימות host ללא security hooks לא צריך להיכשל רק משום שאין `module.registerHooks`, אם feature הזה נדרש רק למדיניות שהוסרה. אם הוא נדרש גם ל־resolver/TypeScript, הפרד את התלות והצג צורך טכני אמיתי.

### R14 — npm/MCP installation בלי compatibility veto ואישורי lifecycle

**קבצים:** `package-compatibility.mjs`, `package-installer.mjs`, `global-package-manager.mjs`, `lifecycle-planner.mjs`, `LifecycleExecutionBroker.swift`, `NodePackageManager.swift`, MCP installation UI.

הפוך scans/graphs/probes לאבחון אופציונלי, לא `rejectUnsupported` שמונע התקנה על סמך ניחוש. native build files שאינם נטענים, optional dependencies, examples ו־comments לא יפסלו package. הימצאות `binding.gyp` או `child_process` אינה כשל installation בפני עצמה.

הסר approval ledger לפי package/version/integrity/script hash למסלול האישי. הפעל lifecycle שנדרש להתקנה באמצעות runtimes/commands מוטמעים כשהם תומכים בו. הרחב את planner הקיים בהתאם; אין “תיקון” שמחליף רק `ignoreScripts:true` ל־false וגורם ל־npm לנסות `/bin/sh` שאינו קיים.

שמור semantics של npm לגבי הצלחה, כשל ו־optional dependency. כאשר lifecycle הכרחי אינו ניתן לביצוע, דווח על action המדויק, stage, stdout/stderr, וחוסר backend; אין להציג `installed-and-ready`. lifecycle שאינו נדרש לשימוש המבוקש יכול להישאר במצב מפורש `installed-with-unexecuted-lifecycle` לפי פעולת המשתמש, לא hidden failure.

ל־missing integrity metadata אפשר להתקדם כ־unverified ולחשב content identity מקומי. אם bytes אינם תואמים digest מוצהר, אל תסמן “verified”; ההבחנה בין קובץ מושחת, גרסה אחרת והתקנה מפורשת כקלט מקומי חדש חייבת להישאר גלויה. אין צורך לסרוק magic bytes כסריקת אבטחה.

אל תשבור integrity pins שמשמשים לפתרון תקלה מוכחת ב־dependency מוטמע בלי בדיקת regression. אל תחליף מנהל npm קיים במימוש package resolution חלקי משלך.

### R15 — Python installation שימושי, לא ביטול תנאי בלבד

**קבצים:** `PythonPackageManager.swift`, `PythonRuntimeService.swift`, native Python bridge, packaging UI וה־Agent wrapper.

הסר סריקות filename/magic bytes כהחלטת “אסור”, את חסימות `.pth`/`.wasm` כנתונים, את תקרת 64 dependencies ואת 100MB hard cap. השתמש בכתיבה/חילוץ streaming וביטול עבודה לפי דרישת משתמש במקום טעינת archive גדול כולו לזיכרון.

ממש wheel installation לפי מבנה החבילה, כולל `.data`/dist-info ונתיבי import. החלף `py3-none-any` כמסנן יחיד בהתאמה אמיתית לגרסת Python/ABI/platform של runtime. wheel לפלטפורמה אחרת יכול להישמר או להיבדק כאבחון, אבל אין לטעון שיובא בהצלחה. native module בר־טעינה דורש backend וחתימה אמיתיים; אל תבטיח טעינת `.so` של Linux באייפד.

ל־pure-Python sdist הוסף מסלול build דרך backend Python מתאים כאשר ניתן להריצו in-process. לפרויקט שדורש toolchain שאינו מוטמע, החזר `buildBackendUnavailable`/`nativeToolchainUnavailable` עם פרטים. אם ניתן להשלים תמיכה בתחום התשתית הקיימת, בצע; אל תסגור “native לא עובד ב־iOS” באופן גורף.

תקן dependency parsing/markers/extras בפועל: distribution name אינו תמיד import name; אין לדלג על כל `extra` או לעשות comparison טקסטואלי של versions במקום semantics נדרשים. השתמש במימוש packaging קיים ומתאים היכן שניתן, בלי לשבור התקנות קיימות.

`probe` נפרד מהתקנה; package שמכיל assets/CLI או import שמצריך configuration אינו סיבה ל־rollback של התקנה תקינה. כשל commit, partial extraction או registry corruption כן מחייבים rollback. stdlib/imports מותקנים חייבים להיות זמינים לריצה חדשה ולא רק ל־probe הזמני.

### R16 — רשת, HTTP, downloads ו־redirects

הסר HTTPS-only של Hanlin ב־Skill download, curl, custom package sources ו־service brokers כשיכולת backend מתירה אחרת. localhost, LAN או registry אישי ב־HTTP הם use cases אמיתיים. אל תגביל PyPI artifact hosts ב־hardcoded hostname allowlist כשמשתמש בחר מקור אחר.

שמור status codes, handling של HTTP 404/500, redirect resolution, שגיאות TLS ו־cancellation. אל תחליף בדיקות TLS ב־“accept any certificate”. הסרת HTTPS-only אינה בקשה לשבור אימות תעודה.

בדוק ATS/Local Network configuration רק במסלולים הרלוונטיים. כאשר נדרש לשימוש האישי וה־API תומך, הגדר את החריג המצומצם הנכון ותעד. אין להבטיח שכל URL scheme ניתן להורדה ב־URLSession. אין לאפשר credentials ב־URL ואז להדפיסם בלוג.

החלף limits קשיחים של 8/16MB, 5 redirects ו־300s בהגדרות/streaming. שמור זיהוי redirect loop ו־cancellation, לא cutoff שרירותי שמוצג כ־permission denied.

### R17 — יכולות, grants ו־trust במסלול הפיתוח האישי

**קבצים:** `HanlinHostCapabilityAuthority.swift`, `HanlinScriptPermissionAuthority.swift`, `HanlinScriptServiceBroker.swift`, `HanlinHostServicesBroker.swift`, `HanlinSystemServicesBroker.swift`, `HanlinScriptingProviderRegistry.swift`, `HanlinAtomicScriptStore.swift`, `HanlinScriptingApplicationSession.swift`.

בטל את Hanlin default-deny/required grant/approval/minimumTrust עבור השימוש האישי הנשלט על ידי הבעלים. התקנה/הפעלה של local package אינה צריכה עשרה approvals פנימיים. אל תשאיר ב־session snapshots כגון `filesAllowed=false` בזמן שב־authority כבר בוטלה החסימה.

שמור רק את הפעלת הרשאות המערכת האמיתיות עבור Contacts/Camera/Microphone/Health/Location/Calendar וכו'. שמור user-disabled tool/group/app כמנגנון שליטה של המשתמש. אל תפעיל אותם בחזרה בכל load_skill.

אחד source of truth קיים: אל תשאיר broker אחד שקורא grant store ושני שמסתמך על Boolean ישן ומחליט אחרת. אין צורך להוסיף framework permission חדש. agent wildcard שכבר קיים לא יוצג כתיקון חדש.

שמור type/context validity: הצגת UI בלי scene פעיל יכולה להצריך delegation למסך קיים או שגיאה ספציפית; אין צורך לסווג אותה כ־authorization. הסר userGesture gate יישומי ב־openURL כשאינו דרישה של API.

### R18 — גבולות שרירותיים, streaming וביטול אמיתי

**קבצים:** `RuntimeModels.swift`, worker runtimes, `HanlinQuickJSSession.swift`, `HanlinJavaScriptCoreSession.swift`, `HanlinScriptSessionCoordinator.swift`, `HanlinScriptRuntimeContracts.swift`, `ToolResultStore.swift`, `ReadToolResultTool.swift`, `HanlinAISDKAgentEngine.swift`.

החלף hard maxima ב־configuration מתועד עם אפשרות לבטל תקרה היכן שה־backend תומך. כלול runtime 300s, output 8MB, workers 30s/1MB, QuickJS memory/stack, input/output, מספר callbacks/promises/handles/events, 50 תוצאות/10MB, פרוסת קריאה 16KB ו־32 agent steps. defaults יכולים להישאר שימושיים, אבל לא חסם בלתי ניתן לשינוי או clamp שקט.

אין לממש “ללא הגבלה” על ידי `Int.max` שגורם overflow/allocation בלתי אפשרית. timeout/limit optional עם semantics ברורים. אל תבצע truncation מאבד־מידע לתוצאת קוד ארוכה; השתמש ב־disk-backed result/file reference וב־pagination. משאב שלא ניתן לשמור יחזיר שגיאה אמיתית, לא תוצאה “מלאה”.

שמור backpressure ו־cleanup הדרושים ליציבות בלי לתייגם כ־security. JSC אינו מבטיח hard interruption של קוד sync; timer מחוץ למנוע לא מוכיח שהקוד נעצר. בצע cancellation אמיתי היכן שניתן ודווח truthfully היכן שלא.

### R19 — Scripting analyzer/compiler: להפסיק ניחושים חוסמים

**קבצים:** `HanlinScriptAnalyzer.swift`, `HanlinScriptingBundler.swift`, `HanlinNodeMobileScriptingCompiler.swift`, `HanlinPackageCenter.swift`, runtime module resolver.

הסר חסימת import/התקנה עקב regex של source/comments או רשימת bare imports שרירותית. analyzer findings יהיו diagnostics כשהם אינם הוכחה לכשל. `preview.canInstall` לא יסתמך על warning כאילו compiler נכשל.

כאשר החבילה באמת משתמשת ב־bare dependency, resolver/bundler חייב לספק אותה מתוך חבילה/תלויות זמינות. מחיקת “bare imports not allowed” בלי לכתוב resolver אינה תיקון. ה־runtime הספציפי קובע איזו module system קיימת; אל תעביר package JSC ל־Node בחשאי כדי להסתיר missing bridge.

הפרד syntax/type diagnostics, unresolved dependency, unsupported platform API, permissions שהוסרו ו־ABI mismatch. כשל compiler אמיתי לא נהפך להצלחה. יש לקמפל ולהריץ fixture של module graph רב־קבצי, לא רק snippet אחד.

### R20 — NativeScript, Expo ו־MiniApps ללא מגבלות מותג/גרסה שרירותיות

**קבצים:** analyzer, package registries, `HanlinNativeScriptProductionBootstrap.swift`, adapters, runtime packages וה־embedded result resolver.

במקום blacklist של כל plugin שאינו plugin יחיד מוכר, בדוק האם היכולת נמצאת ב־native providers המוטמעים או ניתנת לטעינה כמקור JS. pure-JS plugin לא צריך להיחסם בגלל שמו. דרישת native provider חסר תקבל אבחנה מפורשת; אין להבטיח שניתן להתקינו דינמית.

שמור ABI/version checks שמונעים שימוש בפורמט לא־נתמך באמת; החלף exact equality שרירותי בטווח התאימות שה־backend תומך בו, עם fixture וראיה. אל תדלג על גרסת runtime שבלעדיה bridge קורס. מגבלת single-active-session של runtime מסוים, אם קיימת, היא lifecycle constraint שיש לטפל בו/לדווח, לא feature להכריז שהוסר בלי מימוש.

בדוק app, assistant tool, embedded result, widget, App Intent ו־Live Activity בנפרד. אין למחוק entrypoint context checks ולהניח שאותו native UI runtime נטען בכל extension. תמיכה מחוץ ל־foreground דורשת ה־target וה־bridge האמיתיים.

### R21 — מידע אישי ושירותי מערכת: להרחיב מגבלות שאינן של Apple

בדוק בפרט `HanlinScriptingRuntimeServices.swift`, system broker וה־Apple service adapters:
Health date range של שנה, workouts limit 500, sort descriptors; גדלי notification/reminder text/userInfo/arrays; storage/files quotas של brokers ישנים.

הסר/הרחב מגבלות Hanlin כאשר ה־API יכול לבצע את הבקשה. השתמש ב־pagination/streaming לפלט גדול. אל תשאיר fallback שחותך נתונים בלי לציין זאת. preserve time zones, date ordering, enums ו־typed values שה־API דורש. למשל ערך תאריך לא־תקין או מספר NaN הוא קלט שגוי, לא “הגנה מיותרת”.

אל תחליף transport חסר בנתון מומצא. מסלול unsupported או unavailable device צריך להירשם ככזה, ולא כ־no data.

### R22 — תקינות, artifacts, locks ו־migrations שנשארים

שמור atomic transactions, rollback, registry schema handling, recovery, stable app/package identity, cancellation cleanup, mutex סביב process cwd/streams, Python GIL, double-resume prevention ו־JSON/UTF-8 validity.

בדיקות compiler version/provenance/hash קשיחות ייבדקו אחת־אחת: אם משמשות cache invalidation או ABI, תן migration/rebuild נכון; אם הן רק אישור אמון מיותר, הסר gate. שינוי source חוקי צריך ליצור artifact generation חדש, לא “security violation” ולא שימוש stale בקוד הישן.

אל תמחק state, grants ישנים, user packages או sources כדי “להתחיל נקי”. migration תישא את המידע הקיים עד שמבנה חדש נכתב ומאומת. content mismatch אינו “verified” רק כי policy הוסרה.

### R23 — כלים: schemas, executors, תוצאות ו־presentation

כל כלי production עובר:
registration -> catalog -> Skill/search/list -> schema לספק -> validated invocation -> executor אמיתי -> model result -> UI result -> diagnostics.

השווה schemas ל־executor. תקן missing args, fields שאינם נצרכים, aliases שמצביעים לכלי שגוי ו־catch שמחזיר `NativeToolResult` עם ברירת־מחדל `.succeeded` למרות כשל. בדוק במיוחד native Sefaria/Text Studio ו־meta tools. Text `Missing ...` או `... failed` בלי outcome מתאים אינו acceptable.

שמור embedded results ו־copy/open/share actions. “הריצה הצליחה אבל המודל לא קיבל פלט” אינו PASS. “המודל טען שהריץ אבל אין ToolCall/ToolResult” הוא FAIL.

### R24 — אבחון ומידע שצריך להגיע למודל

רשום catalog revision, loadedSkillIDs, selected/exposed aliases, schema sizes, tool-call id, logical ID, backend/runtime, duration, exit code, stderr category, result reference, package transaction/probe status ו־cancellation.

אל תטשטש כשל ל־`python_worker_failed` בלבד אם יש error ממשי שניתן להחזיר. שמור פרטי סוד מחוץ ללוג; hashing/redaction של credentials אינו חסם יכולת שיש להסיר. אפשר trace מפורט בפרופיל בדיקה עם נתונים סינתטיים.

המודל יקבל הבחנה בין tool absent, tool disabled by user, runtime unavailable, argument error, package missing, OS denial, network error, compiler error ו־platform unsupported. לא תשובה גורפת “סביבה מבודדת”.

### R25 — התאמת הבדיקות וה־CI לשינוי ההתנהגות

עדכן assertions שבדקו דווקא “חייב לחסום”. החלף אותם בבדיקות חיוביות של פעולה שהותרה, או בבדיקות platform/format אמיתיות לפי המסמך. אל תמחק suite כדי לקבל ירוק, ואל תמחק בדיקת data-corruption מפני ששמה מכיל safety.

ב־CI עדכן exact-23-command checks, old skill schema budget checks, source-word block fixtures, Python forbidden-suffix tests והגבלות ישנות. שמור compiler, linking/dyld, runtime resource packaging ו־registry tests. רשום אילו בדיקות הוחלפו ומדוע.

אל תריץ 20 full builds סריאליים. השתמש במפות validation קיימות, focused tests ו־build-for-testing פעם אחת כאשר אפשר. הרץ full affected regression בסיום. עקוב אחרי workflow מורשה עם watcher אחד; אין polling ידני חוזר לסוכן.

### R26 — תוצרים סופיים ושער סיום

השלם קוד, schemas, Skills, metadata migration, חבילת install, dependency/platform migrations, תרחישי בדיקה, תוצאות וקובץ מגבלות. החזר commit SHA מדויק, branch, diff summary, architecture/dependency migrations, test counts לפי שכבה, מיקום logs/xcresults/IPA אם נבנה, והרשימה המלאה של BLOCKED/NOT_RUN.

אל תצהיר “מושלם” או “הכול עובד” כאשר simulator בלבד עבר, כאשר נעשה שימוש ב־mocks בלבד או כאשר לא נבדק אותו IPA. אם חסר device/API key/שירות חיצוני, סיים את כל שניתן לאמת והשאר item ספציפי עם תסריט מוכן. אסור להסתיר אותו כ־PASS או לעצור בגללו את כל שאר העבודה.


---

## 4. חוזה תסריטי הבדיקה

כל שורה להלן היא תסריט מחייב, לא רעיון כללי. הפוך אותה לבדיקה automated בשכבה המתאימה, או לתסריט device מובנה כאשר רק חומרה/הרשאת מערכת מאפשרות זאת. אין לדלג על תסריט כי שמו אינו תואם test class קיימת: חבר אותו ל־suite הקיימת או צור test file downstream.

### 4.1 סביבות

- **U:** בדיקת יחידה של הקוד האמיתי, עם dependencies מוזרקים רק בגבול חיצוני.
- **I:** integration בין registration/adapter/service/store/runtime; לא מימוש מדומה שמחזיר את הטקסט הצפוי.
- **S:** ה־app target בפועל ב־iOS Simulator עם משאבי runtime ו־package bundle.
- **D:** IPA מותקן על device, לפי build SHA; ללא פירוש הצלחת simulator כהצלחת device.
- **P:** provider אמיתי דרך request builder וה־agent loop של האפליקציה.
- **B:** compiler/build/packaging/CI.

כאשר כתוב `U/I/S`, התנהגות המימוש נבדקת ב־U/I ומסלול האפליקציה ב־S. כאשר כתוב `S/D`, שמור תוצאת simulator ותוצאת device בנפרד. תוצאה חסרה באחת מהן אינה עוברת בירושה.

### 4.2 Fixtures אחידים

כל בדיקה תתחיל ב־`testRunID` ייחודי, `tempRoot`, ואפליקציה/registry test-only. בחר port פנוי דרך bind בפועל והזרק את הכתובת כ־`${FIXTURE_BASE}`; אל תקבע שפורט מסוים פנוי.

**F01 — קבצים ו־workspaces**
- `workspace-a`, `workspace-b`, `shared`, `external-selected`, ותיקיית sentinel שהיא sibling של extraction root.
- `sample.txt` = בדיוק `alpha\nbeta\nalpha\n`.
- `numbers.txt` = בדיוק `3\n1\n2\n`.
- `עברית space % #?.txt` = `שלום\n`.
- `nested/data.json` = `{"answer":42,"text":"שלום"}`.
- symlink פנימי אל `sample.txt`, ו־symlink אל sibling זמני שהבדיקה עצמה יצרה.
- עבור בדיקת package import בלבד, `outside-sentinel.txt` יכיל `UNCHANGED`. זה קובץ test, לא קובץ משתמש.

**F02 — Skills**
- `name: fixture-runtime`; תיאור קצר; גוף הכולל `tool_search` ובקשת Python; `preferredToolIDs:["execute_local_python_code","execute_javascript_code"]`; טריגרים בעברית ובאנגלית.
- root ZIP ו־wrapper ZIP עם bytes זהים של `SKILL.md`/`hanlin.json`.
- וריאנטים: ISO dates, ISO fractional dates, מספרי Foundation ישנים, ללא dates; YAML quoted/multiline; metadata malformed; ללא metadata.
- resource text: `references/release..notes.md`; resource binary: `assets/data.bin` עם bytes `00 01 02 ff`; משאב `.wasm` תקין זעיר ומשאב ללא סיומת.
- שני ה־packs המקוריים ישמשו fixtures אם נמסרו לסוכן. אם אינם זמינים, אין להעמיד פנים שנבדקו: שחזר את המבנים שלעיל ורשום missing original input.

**F03 — fixture HTTP server**
- `/ok.json`: status 200; `{"marker":"HANLIN_OK","answer":42}`.
- `/page.html`: title `Hanlin Fixture`; body `HANLIN_WEB_MARKER alpha beta`; לינק אחד ל־`/detail.html`.
- `/article.xml`: arXiv Atom feed קבוע עם רשומה אחת, title `Hanlin Fixture Paper`, ID `https://arxiv.org/abs/0000.00000` שהוא fixture בלבד.
- `/redirect-1` עד `/redirect-7`: שרשרת 302 ל־`/ok.json`.
- `/loop-a` ו־`/loop-b`: loop.
- `/not-found`: 404; `/server-error`: 500; `/slow`: streaming עד שהבדיקה מבטלת.
- `/large`: גוף deterministic בגודל `20 * 1024 * 1024 + 17` bytes.
- `/skill.zip`: F02; `/truncated.zip`: ZIP מקוטע.
- רשום requests כדי לבדוק method/headers בלי סודות.

**F04 — packages מקומיים בלבד**
- `hanlin-fixture-cjs@1.0.0`: `module.exports = n => n * 2`; `require(...)` עבור 21 מחזיר 42.
- `hanlin-fixture-esm@1.0.0`: `export default n => n + 1`; import וקריאה עם 41 מחזירים 42.
- `hanlin-fixture-subpath@1.0.0`: exports כולל רק `./feature`, ללא root export; `./feature` מחזיר 42.
- `hanlin-fixture-cli@1.0.0`: bin מדפיס `HANLIN_CLI_OK`; ללא root import API.
- `hanlin-fixture-lifecycle@1.0.0`: lifecycle של JS כותב `generated.json` עם `{"generated":42}`; שימוש בחבילה קורא את הקובץ.
- `hanlin-fixture-lifecycle-fail`: אותו setup אך action מסתיים ב־exit 7.
- `hanlin-fixture-platform-action`: lifecycle עם command שלא מוטמע; אל תחליף אותו להצלחה.
- `hanlin_fixture_py` wheel: import מחזיר `answer = 42`; dist-info תקין.
- distribution בשם `hanlin-fixture-different-name` שמייבא `hanlin_fixture_import_name`.
- 66 dependencies קטנות מקומיות בשרשרת, metadata תקין וללא cycle; variant עם cycle מוגדר.
- pure-Python sdist עם backend build קטן מקומי; variant הדורש toolchain שאינו זמין.
- wheel עם `.pth` שמוסיף subdirectory חוקי וקובץ נתון `.wasm`; wheel עם `.data/purelib` ו־dist-info.
- artifact native מדומה לצורך בדיקת סיווג/שמירה, **לא** כדי לטעון bytes שרירותיים לתהליך production.

אלה שמות fixtures שהבדיקות ייצרו; אין להוריד אותם מ־npm/PyPI כאילו הם packages ציבוריים.

**F05 — backend fixtures**
- Calendar test store: אירוע `Hanlin Fixture Meeting` ב־2030-01-15, 10:00–10:30 UTC; תזכורת `Hanlin Fixture Task` ב־11:00 UTC.
- Memory store ריק; Knowledge bag עם מסמך יחיד `HANLIN_KNOWLEDGE_MARKER answer 42`.
- Health fixture: 1,234 steps, active energy 56 kcal, nutrition עם values ידועים; fixtures נוספים למצב unavailable/denied/no data.
- Maps fixture: מיקום A `(31.778,35.235)`, B `(31.780,35.240)`, תוצאת route עם distance `900` ו־duration `720`; אלה נתוני test ולא עובדה גאוגרפית.
- Weather fixture: 21°C ו־marker קבוע; אין להשתמש בנתון הזה כתחזית אמיתית.
- Sefaria/Wikipedia: responses מקומיים קבועים עם מזהה/טקסט/URL שנבדקים אחד־לאחד מול ה־fixture.
- הפעלת live services היא smoke נוסף; השוואת ערכי אמת נעשית מול fixtures.

**F06 — ספק מודל deterministic**
- server שמחזיר בתורו: `load_skill`, execution, final answer.
- וריאנטים: `tool_search`, tool error, retry מוצדק, tool alias לא־קיים, invalid JSON, streaming מפוצל, cancel, 33 סבבים.
- ה־server יקליט את schema/instructions שבאמת התקבלו בכל סבב.
- אין לשנות את agent engine רק עבור test, מלבד dependency injection/test transport שכבר מותרים.

**F07 — שקיפות התוצאות**
תוצאה מלאה בגודל מעל 10MB עם UTF-8 בעברית ואימוג'י, marker בתחילה `START_42` ובסוף `END_42`. השוואה באמצעות bytes/hash אחרי pagination, לא לפי התקציר שמוצג למודל.

### 4.3 כלל בדיקה לכל tool production, ללא יוצאים מן הכלל

בנוסף לתסריטים הנקובים בשם, צור data-driven contract test לכל רשומת `tool-inventory`:
1. valid minimal invocation עם fixture אמיתי של ה־executor.
2. שדה חובה חסר/טיפוס שגוי -> error typed, לא קריסה ולא success.
3. שגיאת backend -> outcome כושל ופרטים תואמים.
4. success -> model payload ו־UI payload עקביים.
5. enabled/disabled לפי בחירת המשתמש -> discovery behavior נכון.
6. discovery/Skill association -> alias נחשף ואכן ניתן לקריאה.
7. cancellation/idempotency כאשר הפעולה אסינכרונית/כותבת.
8. אין side effect כפול בעקבות streaming delta או retry של הספק.
9. schema, executor ו־Skill מסכימים על field names/enum values.
10. אין source scan או gate נוסף במסלול חלופי שעוקף רק את התיקון הראשי.

להשלמת הכיסוי אין די ב־hardcoded רשימה של כלים מוכרים. הבדיקה תיכשל אם מופיע כלי חדש בקטלוג בלי fixture והגדרת expected result.


## 5. מטריצת בדיקות מחייבת

בכל טבלה: הקלט והציפייה מתייחסים ל־fixtures שבסעיף 4. נתונים ציבוריים חיצוניים נבדקים בנפרד. הוסף test fixture לכל implementation שה־inventory מגלה מעבר לרשימת הבסיס.


### 5.1 — מיפוי, branch והוכחת הסרת המדיניות

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| AUD-01 | R01,R26 | U/B | רשום git remote, branch, HEAD ו־status לפני עבודה; השווה לענף המוגדר. | אין שינוי ב־main או ריפו אחר; שינויים קיימים נשמרים; baseline SHA מתועד. |
| AUD-02 | R01 | U | מנה את כל git-tracked production sources, כולל generated runtime resources ו־native bridges. | כל קובץ מסווג reviewed/not-applicable; אין הסתמכות על 300 קבצי compare או default-branch search. |
| AUD-03 | R01,R22 | U/I | לכל candidate gate עקוב מה־call site עד backend; נסה אותו בפרופיל production. | ה־inventory מבדיל gate פעיל, declaration בלבד, test-only ו־correctness guard. |
| AUD-04 | R01,R25 | U/B | השווה restriction-inventory לפני/אחרי; חפש את אותם תנאים גם בקוד ארוז. | אין gate שהועבר לשם/קובץ אחר; לכל retained restriction יש סיבה ובדיקה. |
| AUD-05 | R01,R23 | I | בנה קטלוג עם כל משפחות הכלים מופעלות בפרופיל בדיקה; השווה schemas, aliases ו־executors. | אין tool שאין לו executor, Skill/דרך גילוי או test mapping; meta tools נספרים בנפרד. |
| AUD-06 | R01,R17 | I | בנה קטלוג עם חלק מהכלים כבויים לפי UserDefaults fixture. | המשתמש נשאר בעל שליטה; audit מציג disabled, והבדיקה לא משנה preference. |
| AUD-07 | R22,R25,R43 | B | השווה baseline מול final diff ובמיוחד קבצי מקור היסטוריים ששונו/נמחקו ובדיקות שנמחקו/עודכנו. | Direct edits to former upstream files are allowed; every large deletion/migration is explained by the new authoritative path and parity evidence; no suite is deleted merely to hide a failure. |
| AUD-08 | R26 | U/B | בדוק שלכל R ולכל מזהה test במסמך יש תוצאה ונתיב evidence. | חוסר mapping, NOT_RUN או BLOCKED מוצגים במפורש; לא נספרים כ־PASS. |


### 5.2 — ייבוא ZIP ו־bulk Skills

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| ZIP-01 | R02 | I/S/D | ייבא F02 root ZIP עם SKILL.md, hanlin.json ו־agents/openai.yaml. | preview/install/refresh/relaunch מצליחים; אותם metadata וגוף זמינים. |
| ZIP-02 | R02 | I/S/D | ייבא אותם bytes תחת fixture-runtime/ wrapper. | אותה תוצאה כמו ZIP-01; wrapper לבדו אינו שגיאה. |
| ZIP-03 | R02 | I/S | בדוק תיקיות staging שנוצרו עם ובלי directory hint ועם slash מסיים. | SKILL.md מתקבל בשני המקרים; diagnostic מזהה את תנאי הכשל אם קיים. |
| ZIP-04 | R02,R09 | S/D | שחזר Foundation URL aliases של /var ו־/private/var באותו temp directory. | אין false escape על אותו יעד; אין הנחה שבדיקת Linux מספיקה. |
| ZIP-05 | R02 | I/S/D | ייבא מתוך תיקייה בשם עברית space % #? וב־entry עם שם כזה. | אין double encoding, no missing file, bytes ושמות נשמרים. |
| ZIP-06 | R02 | U/I | ZIP עם entries מפורשים לתיקיות ו־ZIP בלי directory entries. | שניהם מיובאים; parent directories נוצרים כנדרש. |
| ZIP-07 | R02,R04 | I | SKILL יחד עם LICENSE, assets/data.bin, sample.xlsx, source.swift ו־module.wasm. | אין unsupportedFileType של Hanlin; כל bytes נגישים לאחר install. |
| ZIP-08 | R02,R18 | I/S | ייבא archive מעל 25MiB ונתון expanded מעל 64MiB עם marker בסוף. | אין cutoff ישן; bytes מלאים, cancellation זמין ו־memory אינו צומח לפי כל archive. |
| ZIP-09 | R02 | I | ייבא 1,025 קבצים קטנים, 257 תיקיות ו־resource בעומק 17. | אין limits הישנים; הכל נשמר או כשל OS קונקרטי מתועד. |
| ZIP-10 | R02 | I | resource חוזר בעל compression ratio מעל 100 עם CRC תקין. | אין דחיית ratio; גודל/תוכן לאחר חילוץ נכונים. |
| ZIP-11 | R02 | I/S | נתיב פנימי ./references/a.md ו־references/x/../a.md לאחר normalization חד־משמעי. | ה־resource נפתר נכון בתוך החבילה; אין blanket rejection של substring. |
| ZIP-12 | R02 | I/S | symlink פנימי תקין אל resource, על filesystem שתומך בו. | אין דחיית package שלם; משאב נקרא לפי semantics מתועדים של ספריית ZIP. |
| ZIP-13 | R02,R22 | I | ZIP קטוע או CRC שגוי במקום F02. | import נכשל כ־archive/data error; Skill קודם לא נפגע; אין installation חלקי. |
| ZIP-14 | R02,R22 | I | ZIP תקין ללא SKILL.md או עם SKILL.md שאינו UTF-8. | שגיאת פורמט מדויקת; אין טענת escape/permission ואין רישום ריק. |
| ZIP-15 | R02 | I/S | outer pack מכיל שתי תיקיות Skill עצמאיות. | preview מציג 2; install רושם את שתיהן; אין בחירת SKILL ראשון בלבד. |
| ZIP-16 | R02,R06 | I/S/D | ייבא Hanlin-Skills-Pack-FIXED.zip שסופק, עם 10 קובצי skill.zip פנימיים. | 10 תוצאות פריט ו־10 Skills זמינים; אם המקור חסר ציין BLOCKED_INPUT ולא PASS. |
| ZIP-17 | R02,R06 | I/S/D | ייבא Hanlin-Skills-Pack.zip המקורי באותו מסלול bulk. | wrapper פנימי מתקבל; metadata מלא לכל 10; אין דרישה ל־ZIP שלישי. |
| ZIP-18 | R02,R04 | I/S | bulk pack שבו שני Skills שונים מצהירים על אותו ID. | מוצג conflict שמאפשר resolution מפורש; אין דריסה/בחירה שקטה. |
| ZIP-19 | R02,R22 | I | כשל write מוזרק באמצע install ועדכון Skill קיים; לאחר מכן הפעל relaunch. | הגרסה הישנה תקינה; אין orphan catalog entry; staging מנוקה. |
| ZIP-20 | R02,R22 | I/S | בטל download/extraction של package גדול אחרי קבלת כמה chunks. | אין installed success; task מפסיק; גרסה קודמת נשמרת. |
| ZIP-21 | R02,R22 | I | ZIP עם entry המפנה מחוץ ליעד החילוץ; sentinel זמני מחוץ ל־root. | אין כתיבה שקטה מחוץ ליעד import; שגיאת פורמט/יעד או mapping מפורש; runtime filesystem אינו מושפע. |
| ZIP-22 | R02,R22 | I/S | ZIP עם paths שמתנגשים אחרי Unicode normalization/case folding ב־filesystem המטרה. | conflict מדויק או טיפול מפורש ללא השחתת bytes; אין סריקת אבטחה נוספת כללית. |


### 5.3 — metadata, frontmatter ו־store

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| META-01 | R03 | U/I | פענח hanlin.json המקורי עם installedAt/updatedAt כמחרוזות ISO-8601. | אין typeMismatch; preferredToolIDs/triggerHints/keywords זהים לקלט. |
| META-02 | R03 | U/I | אותו metadata עם תאריך 2026-10-04T12:00:00.123Z. | fractional date נקרא; אין fallback שמרוקן metadata. |
| META-03 | R03 | U/I | טען store ישן עם מספרי Date של Foundation. | תאריך מפוענח ביחס epoch הנכון; migration אינו משנה סדר או hints. |
| META-04 | R03 | U/I | metadata עם arrays תקינים וללא שדות תאריך. | ברירות מחדל מתועדות; arrays נשמרים; אין reject. |
| META-05 | R03 | U/I | metadata עם שדה unknown ו־baseSkillID; בצע import -> export -> import. | המידע הידוע אינו נאבד; unknown data נשמר לפי codec מתועד. |
| META-06 | R03 | U/I/S | hanlin.json פגום, אך SKILL.md תקין. | error/preview correction גלוי; אין overwrite שקט לקובץ metadata ריק. |
| META-07 | R03 | U/I | description מצוטט עם ':' ומרכאות escaped. | הטקסט המלא נשמר ומופיע באינדקס. |
| META-08 | R03 | U/I | frontmatter עם description: > ועם description: \| בשני fixtures. | multiline נקרא נכון; ערך אינו התו > או \| בלבד. |
| META-09 | R03 | U/I | קובץ עם BOM, CRLF, עברית ו־--- בתוך גוף Markdown. | frontmatter מופרד רק בגבול שלו; גוף לא נחתך. |
| META-10 | R03 | U/I | export של Skill עם display title 'Code Execution' ו־ID מכני קיים. | ה־name/ID המיוצא נשאר importable; display title אינו משחית מזהה. |
| META-11 | R03,R04 | I/S | install, refresh קטלוג, terminate/relaunch ואז load_skill. | אותו גוף, IDs, triggers ו־preferred tools בכל השלבים. |
| META-12 | R03,R04 | I/S | המשתמש כיבה Skill ואז עדכן/ייבא אותו מחדש. | בחירת disable אינה נעלמת בלי פעולה מפורשת. |
| META-13 | R03 | I/S | ייבא .md בלי hanlin.json. | import מצליח; אין invented hints; workflow דרך הוראות/tool_search עדיין בר־ביצוע. |
| META-14 | R04 | I/S | ייבא override מפורש ל־code, ו־custom Skill אחר בשם שונה. | override פעיל במקום הנכון; custom לא נעלם ולא מוחק unrelated skill. |
| META-15 | R04 | I/S | קרא references/release..notes.md, UTF-8 resource ו־binary asset. | .. בתוך שם חוקי אינו נדחה; binary חוזר descriptor נגיש ולא missing. |
| META-16 | R03,R22 | I | הזרק כשל בשמירת metadata/state במהלך update. | ה־store והקבצים חוזרים למצב עקבי; אין Skill רשום עם body/metadata מגרסאות שונות. |


### 5.4 — חשיפה דרך Skills וגילוי כלים

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| DISC-01 | R05 | I/S | בצע round 0 בפרופיל עם כלים קיימים אך ללא Skill טעון. | meta tools ואינדקס metadata קיימים; schemas של כל העולם אינם נשלחים. |
| DISC-02 | R05 | I/S | load_skill ל־Code כאשר סכום preferred schemas גדול מ־4,096 bytes. | כל preferred tool קיים וזמין נחשף; אין חיתוך בגלל 4KB. |
| DISC-03 | R05 | I | טען Skill אחד עם schema גדול יותר מ־4KB לבדו. | הכלי ניתן לקריאה; אין starvation של schema יחיד. |
| DISC-04 | R05 | I | טען שני Skills באותה ריצה עם alias משותף. | הוראות שני ה־Skills זמינות; alias לא מוכפל. |
| DISC-05 | R05 | I/S | אחרי load_skill בצע tool call בסבב הבא ונתח request בפועל. | ה־schema וה־instructions מגיעים לספק לפני קריאת הכלי. |
| DISC-06 | R04,R05 | I/S | סיים run והתחל run חדש אחרי שינוי catalog revision. | אין schema ישן של כלי שנמחק; metadata העדכני קיים. |
| DISC-07 | R05 | U/I | tool_search עבור exact alias אחרי טעינת Skill לא־רלוונטי. | exact alias קודם; skill boost לא מסתיר אותו. |
| DISC-08 | R05 | U/I | tool_search עם query שאין לו שום התאמה לאחר טעינת Code. | אין תוצאות רק בגלל boost; חזרה מפורשת של no matches. |
| DISC-09 | R05 | U/I | חיפוש בעברית 'הרצת פייתון' ובאנגלית 'python execution'. | מתגלה הכלי המקומי המתאים דרך metadata; אין router קשיח של prompt. |
| DISC-10 | R05,R07 | I | fixture catalog עם 27 כלים מתאימים; עבור בכל דפי החיפוש. | כל 27 זמינים בגילוי; אין cutoff של 10, ואין כפילויות. |
| DISC-11 | R05 | I | load_skill עבור ID לא־קיים ו־tool_search עם arguments לא־תקינים. | isError/outcome מתאימים; אין succeeded עבור טקסט Error. |
| DISC-12 | R05,R24 | I/S | מודל מחזיר תשובה 'אין כלים' בלי קריאת discovery בתסריט F06. | ה־test מזהה התנהגות שגויה; לא משכתב את תשובת המודל ומציג כאילו בוצע כלי. |
| DISC-13 | R05 | U/B | סקור diff ובצע assertion שאין intent routing hardcoded למילים Python/npm/shell. | בחירת Skill נשארת של המודל; metadata/catalog הם מנגנון הבחירה. |
| DISC-14 | R04,R05 | I | load_skill חוזר פעמיים לאותו ID באותה ריצה. | פעולה idempotent; instructions לא מוכפלים; רשימת exposed tools נכונה. |
| DISC-15 | R05,R17 | I | preferredToolID מפנה לכלי שהמשתמש כיבה. | הוא מסומן unavailable/disabled; load_skill אינו מפעיל אותו מאחורי הגב. |
| DISC-16 | R05,R23 | I | preferred logical ID/alias נדרש לעבור canonical resolution. | מוצג alias נכון; אין פרסום שם שאינו callable. |
| DISC-17 | R05,R24 | I/S | provider מפצל שם/arguments של tool על streaming chunks. | נוצרת קריאה אחת עם arguments מלאים; אין execution חלקי/כפול. |
| DISC-18 | R05,R23 | I | provider מחזיר alias לא־ידוע או invalid JSON. | כשל מובנה הניתן להמשך; אין קריסת loop/dispatch לכלי אחר. |
| DISC-19 | R05,R18 | I/S | F06 מבצע 33 סבבים קצרים תחת maxSteps=40. | הסבב ה־33 מגיע; אין עצירה קשיחה ב־32. |
| DISC-20 | R05,R18 | I/S | אותו F06 תחת maxSteps=3 ואז cancellation ידני בהרצה בלי תקרה. | עצירה לפי ההגדרה/ביטול בלבד; reason מפורש ומצב UI עקבי. |
| DISC-21 | R05 | U/I | בנה פעמיים אותו exposed alias set ו־provider request. | ordering יציב ודטרמיניסטי; אין churn בגלל איטרציה על Set. |
| DISC-22 | R05 | I/P | בקשת 'שלום' או כתיבה יצירתית שאינה דורשת כלי. | אין טעינה כפויה של Code/כל הכלים; הנחיית discovery לא הופכת לכלי חובה בכל תשובה. |


### 5.5 — Enumeration וכלי ניהול חבילות חדשים

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| TOOLS-01 | R07 | I/S | list_tools/המקבילה האמיתית עם native, legacy, MCP ו־Script fixtures. | כל logical IDs מופיעים פעם אחת עם provider ומצב נכון. |
| TOOLS-02 | R07 | I | catalog כולל 150 כלים ו־pagination בגודל 17. | איסוף כל הדפים שווה לקטלוג בדיוק; אין ניחוש של מספר כלים. |
| TOOLS-03 | R07 | I/S | get_runtime_capabilities לפני startup ואחרי הפעלת Python/Node. | גרסה ומצב נלקחים מה־backend; אין hardcoded ready. |
| TOOLS-04 | R07,R24 | I | health check נכשל ואז retry אמיתי מצליח. | מצב unavailable מתעדכן ל־ready רק אחרי הצלחה; אין stale false/true. |
| PKGT-01 | R08 | I/S | גלה את package manager דרך Skill ו־tool_search ואז action=list לשני runtimes. | schema פורסם; הרשימות משקפות את managers האמיתיים ולא subprocess חיצוני. |
| PKGT-02 | R08 | I/S | preview ל־F04 CJS ול־Python wheel. | פרטי spec/version/source/dependencies חוזרים בלי התקנה כפויה. |
| PKGT-03 | R08 | I/S/D | install ל־F04 CJS ואחריו execute_javascript_code עם runtime=node. | קריאה עם 21 מחזירה 42; הותקן באותו runtime שבו הסוכן עובד. |
| PKGT-04 | R08 | I/S/D | install ל־F04 Python wheel ואז import בשתי ריצות חדשות. | answer=42 בשתיהן; לא הצלחה רק בתוך probe זמני. |
| PKGT-05 | R08 | I/S | probe של package subpath-only ו־CLI-only. | installed status נשמר; root-import failure אינו כשל התקנה מדומה. |
| PKGT-06 | R08 | I/S | uninstall package של fixture ואז list ו־import חדש. | הרשומה והגישה הוסרו; packages אחרים נשמרים. |
| PKGT-07 | R08,R24 | I | action/runtime לא־תקינים או spec חסר ב־install. | schema validation מדויקת; אין צד־אפקט. |
| PKGT-08 | R08,R18 | I/S | install איטי, status/progress ואחריו cancel. | אין timeout שרירותי ישן; ביטול משחרר task/transaction ומסומן cancelled. |
| PKGT-09 | R08,R22 | I | הזרק commit failure אחרי extraction והפעל list/relaunch. | אין installed success; rollback נכון; state וקבצים תואמים. |
| PKGT-10 | R08,R23 | I/S | אותה קריאת install מתקבלת פעמיים עם אותו call ID עקב retry streaming. | אין side effect כפול; תוצאה עקבית עם transaction המקורי. |
| PKGT-11 | R08 | I/S | שני package installs שונים במקביל. | אין החלפת cwd/dependencies/transaction IDs; כל תוצאה שייכת לחבילה הנכונה. |
| PKGT-12 | R08,R24 | I | שגיאת registry 404/500 או no network. | כשל מפורש עם stage/source; לא sandbox denial, לא install success. |


### 5.6 — קבצים, workspaces ומשתני סביבה

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| FS-01 | R09 | I/S/D | Python כותב F01 sample.txt, Node קורא ומוסיף שורה, shell קורא את התוצאה באותו context. | שלוש השכבות רואות אותו cwd ותוכן; אין workspace מנותק לכל tool. |
| FS-02 | R09 | I/S | קרא path מוחלט לתיקייה נגישה בתוך app container, מחוץ ל־clients. | אין Hanlin pathEscapesRoot; התוכן נכון. |
| FS-03 | R09 | I/S | מתוך workspace-a גש ל־../shared/data.json שהבדיקה יצרה. | היעד הנגיש נקרא; .. אינו blacklist של runtime. |
| FS-04 | R09 | I/S/D | קרא וכתוב דרך symlink פנימי ו־symlink ל־sibling test directory נגיש. | לינק תקין אינו נחסם; אותה תוצאת filesystem שהפעולה אמורה לתת. |
| FS-05 | R09 | I/S | קרא/כתוב את עברית space % #?.txt דרך file URL ודרך string path. | אין double encoding; bytes זהים בכל מסלול. |
| FS-06 | R09 | S/D | בחר תיקייה ב־Files, הענק security scope, כתוב fixture והפעל relaunch. | bookmark מתחדש כנדרש; גישה חיצונית נבחרת עובדת ללא hardcoded root. |
| FS-07 | R09 | S/D | בטל/יישן את bookmark והרץ אותה קריאה. | שגיאת OS/scope ספציפית; אין fabricated success או בקשת אישור Hanlin חדשה. |
| FS-08 | R09,R22 | I/S | צור שני agent contexts במקביל, עם cwd ו־קובץ marker שונים. | אין החלפת cwd/נתונים בין contexts; shared access רק כשהנתיב מבוקש. |
| FS-09 | R09 | I/S | רשום MCP package root חיצוני שנבחר, הפעל entrypoint ואז הסר את הרישום. | השרת רץ; uninstall אינו מוחק קבצים שאינם בבעלות ההתקנה. |
| FS-10 | R09,R22 | I/S | בצע migration של MCP descriptor ישן בעל path container קודם. | resolved path מצביע לחבילה הקיימת; אין דרישה להורדה חוזרת ללא צורך. |
| FS-11 | R09,R22 | I | נתיב לא־קיים/קובץ במקום directory/יעד read-only. | כשל filesystem מדויק; לא permission policy כללי ולא קריסה. |
| FS-12 | R09,R22 | I | directory עם sentinel; בצע uninstall/update/rollback של package סמוך. | רק קבצים בבעלות transaction משתנים; אין מחיקה גורפת. |
| ENV-01 | R10 | I/S | override ל־HOME ול־PATH באותה קריאת runtime. | ערכים אפקטיביים לפי ההגדרה; אין reservedEnvironmentName. |
| ENV-02 | R10 | I/S | Python module בתיקייה נוספת באמצעות הגדרת PYTHONPATH/search path. | import של המודול מצליח ו־stdlib עדיין זמין. |
| ENV-03 | R10 | I/S | הגדר NODE_PATH עבור CJS resolution ותיקיית package fixture. | CJS פותר לפי המסלול הנתמך; לא נטענת טענה ש־NODE_PATH לבדו פותר ESM. |
| ENV-04 | R10 | I/S | הגדר npm cache/prefix שונים ל־package operation. | manager משתמש בנתיבים המתועדים; אין reset שקט ל־default. |
| ENV-05 | R10,R22 | I/S | הרץ Python ו־ios_system במקביל עם cwd/env שונים והזרק exception. | ערכי process-global משוחזרים; אין leak אחרי success או exception. |
| ENV-06 | R10 | I/S | שנה setting שמוגדר initialization-only לאחר ש־CPython כבר רץ. | המערכת מבצעת reconfiguration נתמכת או מסבירה restart; אינה משקרת שהערך הוחל. |
| ENV-07 | R10,R24 | I | הכנס env בשם FIXTURE_API_KEY עם ערך סינתטי; הפעל diagnostics. | ה־runtime מקבל את הערך כשהתבקש, אך logs/results ציבוריים לא מדפיסים אותו. |
| ENV-08 | R10,R22 | I | env name לא־ניתן לייצוג כגון מפתח ריק/עם NUL. | שגיאת פורמט טכנית; אין ניסיון setenv לא־תקין או crash. |


### 5.7 — ios_system ותחביר shell

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| SH-01 | R11 | I/S/D | השווה commandsAsArray/ios_executable, dictionary entries ו־tool catalog. | קטלוג הפקודות משקף backend בפועל; אין exact-23 assertion. |
| SH-02 | R11 | I/S | רשום command בדיקתי נוסף בשם hanlin_fixture_echo במנגנון הקיים. | ה־runner וה־tool יכולים להפעילו; extraCommandsDictionary אינו חייב להיות ריק. |
| SH-03 | R11 | I/S | הסר framework/סמל של command אחד ב־fixture package. | הפקודה מסומנת unavailable עם dependency מדויק; פקודות קיימות ממשיכות לעבוד. |
| SH-04 | R11 | I/S/D | program=cat, arguments=[path של F01 sample.txt]. | stdout בדיוק alpha\nbeta\nalpha\n; exit 0. |
| SH-05 | R11 | I/S | program=grep, arguments=['alpha','sample.txt']. | שתי שורות alpha; parser אינו מסווג alpha כנתיב שחייב להתקיים. |
| SH-06 | R11 | I/S | program=sed, arguments=['s/alpha/A/','sample.txt']. | stdout A\nbeta\nA\n; ביטוי sed אינו נחסם בגלל slash. |
| SH-07 | R11 | I/S | program=awk, arguments=['{print $1}','sample.txt']. | אותן שלוש מילים; braces/$ בביטוי אינם policy violation. |
| SH-08 | R11 | I/S | raw command: cat sample.txt \| grep alpha. | פלט שתי שורות כאשר ios_system המוטמע תומך ב־pipeline; אחרת failure טכני מתועד, לא blacklist של Hanlin. |
| SH-09 | R11 | I/S | raw command: cat sample.txt > copied.txt; קרא copied.txt. | redirection נתמך מגיע ל־backend; copied.txt שווה למקור; לא literal filename '>'. |
| SH-10 | R11 | I/S | raw command: cat < sample.txt; ובהרצה נוספת append >>. | stdin/redirection/append תואמים ל־backend המוצהר; אין פרשנות שגויה ב־argv mode. |
| SH-11 | R11 | I/S | raw command עם ;, && ו־\|\| ב־fixtures הצלחה/כשל. | צור capability matrix לפי syntax backend; כל syntax נתמך עובד, unsupported אינו מוסתר. |
| SH-12 | R11 | I/S | raw command עם $VAR, ${VAR}, $(...) ו־backticks תחת fixture חסר side effects. | כל צורה מסווגת לפי תמיכה אמיתית; אין חסימה בשל טקסט בלבד ואין טענת bash מלא. |
| SH-13 | R11 | I/S | argv מובנה לפקודת echo fixture: ['a\|b','x>y','a;b','$(text)']. | כל argument חוזר מילולית; לא נוצר קובץ ולא מופעלת פקודה נוספת. |
| SH-14 | R11 | I/S | argv עם מחרוזת ריקה, רווחים, apostrophe, double quote ועברית. | נשמרת ההפרדה וה־bytes; empty argument לא נעלם. |
| SH-15 | R11 | I/S | קרא path מוחלט חוקי ו־../shared path. | אין חסימה של Hanlin; ios_system מקבל יעד נכון ולא MiniRoot מצומצם שקט. |
| SH-16 | R11,R16 | I/S/D | curl אל ${FIXTURE_BASE}/ok.json ב־HTTP, ללא allow_network=true. | תוצאת HANLIN_OK מתקבלת במסלול הנתמך; אין permission prompt פנימי. |
| SH-17 | R11 | I/S | program=wc, stdin=bytes של sample.txt, ללא קובץ. | count תואם ל־3 שורות; stdin מגיע ל־command. |
| SH-18 | R11 | I/S | program=sort על numbers.txt ואז uniq על sample fixture מסודר. | פלט מספרים 1,2,3; פקודות אינן רק listed אלא באמת invoked. |
| SH-19 | R11 | I/S | cp -> stat -> mv -> readlink/ln -> rm על קבצי fixture. | כל הפעולות משקפות מצב קבצים אמיתי; cleanup לא מוחק תיקיית משתמש. |
| SH-20 | R11 | I/S | tar create/extract של תיקיית fixture עם טקסט/Unicode. | roundtrip bytes מלא; scripts לא נסרקים כמקור מסוכן. |
| SH-21 | R11,R22 | I/S | command שאינו קיים ו־command ידוע עם arguments לא־תקינים. | exit/error תואמים; אין success ללא output ואין app crash. |
| SH-22 | R11,R22 | I/S/D | 50 קריאות קצרות בשני contexts עם stderr/stdout שונים. | streams/cwd משויכים נכון; אין data race או output של קריאה אחרת. |


### 5.8 — Node, JSC, TypeScript ו־MCP

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| JS-01 | R12 | I/S/D | execute_javascript_code עם runtime=jscore ו־console.log(21*2). | פלט 42; מזהה runtime הוא JSC. |
| JS-02 | R12 | I/S/D | runtime=node: console.log(process.version); await Promise.resolve(); console.log(42). | Node אמיתי, version אמיתי, פלט 42. |
| JS-03 | R12 | I/S | runtime=auto וקוד setTimeout/Promise ללא import. | נבחר מסלול שתומך ב־async לפי המדיניות המתועדת; אין fake JSC support. |
| JS-04 | R12 | I/S | console.log('sudo docker child_process cluster curl x \| sh') ו־comments זהים. | הקוד רץ; אין source-word rejection. |
| JS-05 | R12,R13 | I/S/D | import של node:child_process ו־node:cluster ללא קריאת spawn. | import של builtin שקיים מצליח; אין policy block בגלל שם. |
| JS-06 | R12 | I/S | ESM: import fs from 'node:fs'; כתוב marker וקרא אותו. | ESM נתמך; Skill אינו מייצר require לא־מוגדר. |
| JS-07 | R12,R14 | I/S | CJS package F04 מיובא דרך createRequire ובנפרד ESM package דרך import. | 21*2=42 ו־41+1=42; semantics תואמים, לא wrapper מדומה. |
| JS-08 | R12 | I/S | TypeScript source: const x:number=42; console.log(x); compile_only=false. | קומפילציה וריצה אמיתיות, פלט 42. |
| JS-09 | R12 | I/S | אותו TypeScript עם compile_only=true וקוד שהיה כותב קובץ. | מוחזרים diagnostics/emitted JS; קובץ side-effect לא נוצר. |
| JS-10 | R12,R24 | I/S | TypeScript עם syntax error; JavaScript עם throw new Error('FIXTURE_FAIL'). | compiler/runtime errors נשמרים בנפרד; outcome failed. |
| JS-11 | R12 | I/S | JSC explicit עם API שאין בו, כגון Node fs. | אי־תמיכה מדויקת; אין מעבר מרוחק או דיווח Node/JSC כוזב. |
| MCP-01 | R13 | I/S/D | הפעל MCP fixture עם initialize -> tools/list -> tools/call שמחזיר 42. | handshake וקריאה מצליחים בשרת האמיתי; stop/restart משאירים host חי. |
| MCP-02 | R13 | I/S | MCP fixture עם child_process import דרך dependency שלא מפעיל process. | אין import-chain veto; tools/list מצליח. |
| MCP-03 | R13 | I/S/D | בצע action של process שאינו נתמך דרך adapter הבדיקה, ללא syscall מסוכן בתהליך המשתמש. | platformUnsupported נקודתי או in-process implementation מוכח; host אינו נעצר. |
| MCP-04 | R13 | I/B | ב־host פלטפורמה שתומכת ב־subprocess, הרץ fixture subprocess ציבורי קטן. | אין iOS policy גורפת על target אחר; stdout/exit אמיתיים. |
| MCP-05 | R13 | I/S | package כולל .node file שאינו נטען, וכן .wasm כנתונים. | אין rejection של package רק בגלל assets; MCP fixture הרגיל ממשיך לרוץ. |
| MCP-06 | R13,R24 | I/S | fixture מבקש native module באמת אך loader אינו תומך בו. | module/ABI/platform error מפורש; לא anti-bypass denial ולא success. |
| MCP-07 | R13 | I/S | host ללא module hooks שהיו רק עבור policy; בדוק גם TypeScript resolver. | JS רגיל אינו נחסם ללא סיבה; צורך טכני ב־hook עבור feature מסוים מדווח בנפרד. |
| MCP-08 | R13,R22 | I/S/D | startup error, rapid stop/start, cancel בזמן handshake, ואז שרת תקין. | אין orphan worker, deadlock או host לא־נגיש; השרת התקין מצליח אחריהם. |


### 5.9 — smoke נפרד לכל אחת מ־23 פקודות הבסיס

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| CMD-01 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=awk, arguments=['{print $1}','sample.txt']. | alpha\nbeta\nalpha\n; exit code 0. |
| CMD-02 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=cat, arguments=['sample.txt']. | alpha\nbeta\nalpha\n; exit code 0. |
| CMD-03 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=cp, arguments=['sample.txt','copy.txt']. | copy.txt שווה byte-for-byte למקור; exit code 0. |
| CMD-04 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=curl, arguments=['${FIXTURE_BASE}/ok.json']. | JSON עם marker=HANLIN_OK ו־answer=42; exit code 0. |
| CMD-05 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=grep, arguments=['alpha','sample.txt']. | alpha\nalpha\n; exit code 0. |
| CMD-06 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=head, arguments=['-n','1','sample.txt']. | alpha\n; exit code 0. |
| CMD-07 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=ln, arguments=['-s','sample.txt','sample-link']. | sample-link הוא symlink אל sample.txt; exit code 0. |
| CMD-08 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=ls, arguments=['.']. | הרשימה כוללת sample.txt ו־numbers.txt, ללא דרישת סדר בלתי מובטחת; exit code 0. |
| CMD-09 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=mkdir, arguments=['new-dir']. | new-dir קיים והוא directory; exit code 0. |
| CMD-10 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=mv, arguments=['copy.txt','moved.txt']. | מכין copy.txt מראש; moved.txt קיים ו־copy.txt אינו קיים; exit code 0. |
| CMD-11 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=readlink, arguments=['sample-link']. | sample.txt (ייתכן newline לפי הפקודה); exit code 0. |
| CMD-12 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=rm, arguments=['moved.txt']. | מכין moved.txt מראש; הקובץ הוסר והמקור נשמר; exit code 0. |
| CMD-13 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=rmdir, arguments=['empty-dir']. | מכין empty-dir ריקה; התיקייה הוסרה; exit code 0. |
| CMD-14 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=sed, arguments=['s/alpha/A/','sample.txt']. | A\nbeta\nA\n; exit code 0. |
| CMD-15 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=sort, arguments=['numbers.txt']. | 1\n2\n3\n; exit code 0. |
| CMD-16 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=stat, arguments=['-f','%z','sample.txt']. | הערך המספרי 17; exit code 0. |
| CMD-17 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=tail, arguments=['-n','1','sample.txt']. | alpha\n; exit code 0. |
| CMD-18 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=tar, arguments=['-cf','fixture.tar','sample.txt']. | archive קיים; רשימת entries וחילוץ מחזירים sample.txt עם אותם bytes; exit code 0. |
| CMD-19 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=touch, arguments=['touched.txt']. | קובץ touched.txt קיים; exit code 0. |
| CMD-20 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=tr, arguments=['a-z','A-Z']; stdin='alpha\nbeta\n'. | ALPHA\nBETA\n; exit code 0. |
| CMD-21 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=uniq, arguments=[]; stdin='alpha\nalpha\nbeta\n'. | alpha\nbeta\n; exit code 0. |
| CMD-22 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=unlink, arguments=['sample-link']. | הלינק הוסר; sample.txt המקורי נשמר; exit code 0. |
| CMD-23 | R11,R23 | I/S/D | על F01 חדש ומבודד לכל שורה: program=wc, arguments=['-l','sample.txt']. | שדה count הוא 3; אל תשווה whitespace של BSD; exit code 0. |


### 5.10 — Node packages ו־lifecycle

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| NPM-01 | R14 | I/S | התקן F04 CJS ו־ESM דרך manager אמיתי. | list מציג שתי גרסאות 1.0.0; execution מחזיר 42; אין scanner veto. |
| NPM-02 | R14 | I/S | package מכיל comment/string על sudo/docker/child_process. | התקנה וריצה רגילה מצליחות; אין סריקת מקור כ־security. |
| NPM-03 | R14 | I/S | package כולל binding.gyp ו־.node בדוגמה שלא נטענת. | מותקן; metadata מזהה assets בלי להכריז unsupported לכל החבילה. |
| NPM-04 | R14 | I/S/D | התקן hanlin-fixture-lifecycle והריץ את הפונקציה שקוראת generated.json. | lifecycle JS רץ in-process ויוצר generated=42; אין approval gate. |
| NPM-05 | R14 | I/S | התקן את אותו package version עם שינוי lifecycle חוקי והפעל update. | הפעולה המבוקשת מתבצעת בלי exact-hash approval חדש; generation ותוצאה מעודכנים. |
| NPM-06 | R14,R22 | I/S | lifecycle-fail יוצא ב־7. | stage/action/exit 7 נרשמים; אין installed-ready כוזב; גרסה קודמת נשמרת. |
| NPM-07 | R14 | I/S | lifecycle דורש command שאינו linked או /bin/sh שלא זמין. | כשל יכולת ספציפי או adapter ממומש; לא ignore שקט ולא host crash. |
| NPM-08 | R14 | I/S | package CLI-only ו־package subpath-only ללא root export. | מותקנים; probe אינו מבטל התקנה תקינה; CLI/subpath האמיתיים נבדקים. |
| NPM-09 | R14 | I | dependency graph עם optional dependency שאינו נתמך ב־target. | semantics של manager נשמרים; package usable אינו נדחה רק בגלל optional asset. |
| NPM-10 | R14 | I | registry fixture ללא integrity metadata. | מצב unverified עם content identity מקומי; לא חסימת אמון בלבד. |
| NPM-11 | R14,R22 | I | registry מכריז digest אך מחזיר bytes אחרים. | לא מסומן verified; mismatch גלוי; אין stale identity או שינוי שקט בגרסה. |
| NPM-12 | R14,R16 | I/S | התקן tgz ממקור local file ומ־HTTP fixture. | שני המסלולים עובדים לפי פורמט אמיתי; אין HTTPS-only gate. |
| NPM-13 | R14,R22 | I | בטל install בזמן download ואז בזמן lifecycle; נסה התקנה חוזרת. | אין orphan state; retry פועל; משאבים קודמים לא נמחקים. |
| NPM-14 | R14,R18 | I | package tree מעל תקרת count/size הישנה, עם fixtures קטנים ורבים. | אין cutoff שרירותי; רשום גודל מלא ותוצאה. |
| NPM-15 | R14 | S/D | הרץ גם fixtures הציבוריים שהריפו כבר מצמיד: is-number@7.0.0, yocto-queue@1.2.2. | נבדקת ריצה אמיתית; registry outage הוא BLOCKED_EXTERNAL/FAIL נפרד, לא החלפת גרסה שקטה. |


### 5.11 — Python packages, wheels ו־sdists

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| PY-01 | R15 | I/S/D | התקן hanlin_fixture_py מתוך F04 wheel וייבא אותו. | answer=42; interpreter ו־site-packages הם של האפליקציה. |
| PY-02 | R15 | I/S | distribution בשם שונה מה־import name. | התקנה תקינה אינה נכשלת בגלל הנחת name.replace('-', '_'); import הנכון עובד. |
| PY-03 | R15 | I/S | wheel עם .data/purelib ומודול שמועבר לנתיב import. | מודול נגיש; data layout מיושם ולא נשאר רק directory zip. |
| PY-04 | R15 | I/S | wheel עם .pth חוקי שמוסיף subdirectory שבו module answer=42. | activation לפי semantics מתועדים; אין איסור גורף על .pth. |
| PY-05 | R15 | I/S | wheel עם .wasm/.bin/assets שלא נטענים כ־native extension. | הנתונים מותקנים; אין suffix/magic scanner veto. |
| PY-06 | R15 | I | wheel tag תואם runtime שאינו בדיוק py3-none-any. | resolver מתאים לפי tags אמיתיים; אין מסנן יחיד קשיח. |
| PY-07 | R15 | I/S | wheel עם ABI/architecture לא־תואמים. | שגיאת התאמה מדויקת בעת שימוש/התקנה לפי contract; אין טענת import מוצלח. |
| PY-08 | R15 | I/S | pure-Python sdist עם build backend המקומי של F04. | נוצר wheel/תוצר התקנה אמיתי ואז import=42; לא רק ביטול guard. |
| PY-09 | R15 | I/S | sdist שדורש compiler/מערכת build שאינם מוטמעים. | backend/toolchainUnavailable עם הצעד המדויק; אין מצג של תמיכה מלאה. |
| PY-10 | R15 | I | 66 dependencies מקומיות וקטנות בשרשרת. | כל התלויות נפתרות ומותקנות; אין safety limit של 64. |
| PY-11 | R15 | U/I | dependency cycle ו־version constraints סותרים בשני fixtures. | cycle אינו רקורסיה אינסופית; conflict אמיתי מדווח, בלי false success. |
| PY-12 | R15,R18 | I/S | wheel מעל 100MiB עם נתון deterministic גדול. | streaming install ללא max 100MB; marker/hash מלאים; אין RAM spike של archive כולו. |
| PY-13 | R15 | U/I | markers של python_version/sys_platform עם extras שונים. | רק dependencies המתאימות מותקנות; extras שנבחרו אינם נזרקים גורפית. |
| PY-14 | R15 | U/I | versions 1.9, 1.10, pre-release ו־~= ב־fixture registry. | פתרון לפי semantics packaging, לא השוואת substring שרירותית. |
| PY-15 | R15,R16 | I | artifact ממirror/local source שהמשתמש בחר, ולא רק pypi.org/pythonhosted. | המקור נתמך דרך מסלול אמיתי; אין hostname allowlist כמדיניות. |
| PY-16 | R15 | I | package ש־import שלו צריך configuration או שאין לו import root. | installed נשמר עם probe status נפרד; אין rollback על ניחוש שגוי. |
| PY-17 | R15,R22 | I | wheel קטוע, metadata לא־קריא ו־write failure. | כשל תקינות אמיתי; transaction/registry נשארים עקביים. |
| PY-18 | R15 | I/S/D | restart של האפליקציה אחרי install; import מחדש; uninstall; import שוב. | לפני uninstall import עובד, אחריו נכשל כ־module missing; תלות של package אחר לא נעלמת. |
| PY-19 | R15,R22 | I/S | Python probe/execute ו־shell פועלים במקביל; inject cancellation. | GIL/cwd/streams עקביים; אין deadlock ושאר האפליקציה ממשיכה. |
| PY-20 | R15 | S/D | הרץ fixture הציבורי המוצמד בריפו requests==2.34.2 רק אם registry מאמת שקיים. | תוצאת רשת והתקנה אמיתית מתועדות; חוסר גרסה/רשת אינו מוחלף בשקט ואינו PASS. |


### 5.12 — הרשאות יישומיות, OS ושירותי מערכת

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| CAP-01 | R17 | I/S | local package ללא רשומות grants מפעיל files/storage/network/assistant על fixture. | אין missingGrant/default-deny של Hanlin במסלול האישי. |
| CAP-02 | R17 | I/S | אותו package דרך ScriptUI, NativeScript, Expo ו־compiled MiniApp adapters, ככל שהמסלול קיים. | אין broker צדדי שמחזיר policy denied; תוצאות היכולות זהות. |
| CAP-03 | R17 | I/S | ה־authority מאפשר פעולה אך session נוצר קודם עם filesAllowed=false. | מצב אישי עקבי; אין Boolean ישן שמשאיר את החסימה פעילה. |
| CAP-04 | R17 | I/S | הפעל provider localUnverified/minimumTrust בלי אישור אמון נפרד. | התקנה/רישום מבוצעים; אין trust review gate חדש. |
| CAP-05 | R17 | I/S | המשתמש כיבה tool group או app בהגדרה קיימת. | המצב מכובד; אין auto-grant/auto-enable שמבטלים את בחירתו. |
| CAP-06 | R17,R21 | S/D | מצבי OS notDetermined/authorized/denied עבור Camera/Microphone/Contacts/Location. | prompt מערכת במקום הנכון; denied מתועד כהחלטת OS, לא מוסתר או עוקף. |
| CAP-07 | R17,R21 | S/D | Health/Calendar/Reminders זמינים מול target שאינו תומך או OS authorization denied. | unavailable/denied/no data מובחנים; אין נתונים מומצאים. |
| CAP-08 | R17 | I/S | openURL ללא userGesture יישומי כאשר host API מאפשר זאת. | אין gate פרטי נוסף; תוצאת OS אמיתית נשמרת. |
| CAP-09 | R17,R22 | I/S | בקשת UI מתוך context ללא foreground scene, ואחריה מתוך scene פעיל. | delegation/שגיאת context מדויקת; כשה־scene פעיל הפעולה מוצגת. |
| CAP-10 | R21 | U/I | Health fixture על פני 2 שנים ו־601 workouts, עם pagination. | אין תקרת שנה/500 של Hanlin; כל הרשומות מתקבלות בלי truncation שקט. |
| CAP-11 | R21 | U/I | Health sort נוסף שה־API/transport תומך בו. | sort אינו נדחה כי אינו descriptor יחיד hardcoded; סדר תוצאות נכון. |
| CAP-12 | R21 | U/I | Notification/reminder text ו־arrays מעל caps הפנימיים הישנים. | הקלט עובר כאשר backend תומך; מגבלת backend אמיתית מדווחת ספציפית. |
| CAP-13 | R21,R22 | U/I | NaN/תאריך לא־תקין/end לפני start/enum לא־קיים. | validation טכני נשאר; אין side effect invalid ואין קריסה. |
| CAP-14 | R17,R22 | I/S | legacy grants store ו־app IDs מהתקנה קודמת לאחר migration. | נתונים נשמרים; הפיתוח האישי עובד בלי צורך לאפס registry. |


### 5.13 — networking

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| NET-01 | R16 | I/S/D | Skill download מ־HTTP fixture ו־HTTPS fixture. | אין Hanlin HTTPS-only; תוצאת backend/ATS נרשמת במדויק. |
| NET-02 | R16 | I/S | 7 redirects מ־F03 שמסתיימים ב־ok.json. | אין תקרת 5 הישנה; marker מתקבל. |
| NET-03 | R16,R22 | I | redirect loop בין /loop-a ו־/loop-b ואז cancel. | אין המתנה אינסופית; loop/cancel outcome מפורש, בלי סריקת URL נוספת. |
| NET-04 | R16,R18 | I/S | response של 20MiB+17 bytes מ־/large. | כל bytes נשמרים/נגישים; אין max 8/16MB שקט. |
| NET-05 | R16 | I/S | 404/500/TLS certificate error בכל אחד ממסלולי download. | ה־status/שגיאת TLS נשמרים; אין disabled TLS verification. |
| NET-06 | R16 | S/D | localhost/LAN access דרך מסלול Apple network האמיתי. | הגדרות ATS/Local Network מתאימות; backend error אינו מיוחס לסורק של Hanlin. |
| NET-07 | R16,R24 | I | URL/header כולל secret fixture; server recorder מאשר קבלה. | הבקשה מתבצעת, אבל secret לא מופיע בלוג המודל/דוח ציבורי. |
| NET-08 | R16,R18 | I/S | download איטי מעל timeout ישן, עם timeout=null/מורחב ואז cancel. | אין hard clamp ישן; cancel מסיים ו־cleanup תקין. |


### 5.14 — מגבלות runtime, זיכרון ותוצאות גדולות

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| LIM-01 | R18 | U/I | timeout=601 שניות נבנה ומועבר ל־backend; השתמש fake clock לבדיקת גבול. | הערך אינו נחתך ל־300; serialized config משקף 601. |
| LIM-02 | R18 | I/S | ריצה אמיתית bounded מעבר ל־30s תחת timeout מורחב. | אין worker cutoff הישן; ריצה משלימה או error אמיתי. |
| LIM-03 | R18 | I/S | פלט מעל 8MB עם START_42 ו־END_42. | פלט מלא נשמר מאחורי reference; המודל מקבל דרך גישה, לא 8MB truncation. |
| LIM-04 | R18 | I/S | 51 תוצאות ו־total payload מעל 10MB תחת config מתאים. | אין eviction מאבד־מידע בלתי מדווח; references תקינים לפי lifetime המוגדר. |
| LIM-05 | R18 | U/I | read_tool_result בפרוסות מעל 16KB ומכל offset לאורך UTF-8 Hebrew/emoji. | אין cap ישן; שחזור bytes מדויק ללא פגיעה בתווי UTF-8. |
| LIM-06 | R18 | U/I | configure limits=null ו־limits מפורשים; בדוק overflow/negative inputs. | אין שימוש מסוכן ב־Int.max; semantics ברורים ו־validation טכני. |
| LIM-07 | R18 | I/S | QuickJS workload מעל 16MB הישנים תחת memory limit מורחב. | אין hardcoded 16MB; קוד מחזיר marker או engine error אמיתי. |
| LIM-08 | R18 | U/I | רשום callbacks/promises/events מעבר ל־caps הישנים עם config מורחב. | אין דחייה ישנה; disposal משחרר את כל המשאבים. |
| LIM-09 | R18,R22 | I/S | cancel Node/Python task ואז הרץ task תקין חדש. | החדש פועל; אין zombie completion או host stuck. |
| LIM-10 | R18 | I/S | JSC sync task לא־ניתן להפרעה במנגנון הנוכחי — בדיקה bounded בלבד. | הדיווח אינו מציג timer חיצוני כ־hard cancel; אין infinite loop במכשיר המשתמש. |
| LIM-11 | R18,R22 | I | disk-full fixture בעת שמירת large result. | כשל שמירה ברור; אין reference לתוכן שלא נשמר; אין memory fallback בלתי מוגבל. |
| LIM-12 | R18,R24 | I/S | סיים run/פתח saved chat ונסה reference לפי lifetime שפורסם. | תוכן נגיש או expiration מפורש לפי contract; אין UI שמציג reference מת כתוצאה זמינה. |


### 5.15 — Scripting, artifacts ו־MiniApps

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| APP-01 | R19 | U/I/S | source עם comment ומחרוזת הכוללים import, eval, process או sudo. | אין analyzer veto של מילים שאינן פעולה. |
| APP-02 | R19 | I/S | package רב־קבצי עם relative modules, JSON ו־bare dependency מקומי זמין. | resolver/bundler אמיתי מספק dependencies; app/tool מחזירים 42. |
| APP-03 | R19 | I/S | bare dependency חסר, ובנפרד syntax/type error אמיתי. | כשל compiler/resolver מדויק; לא policy message ולא fake install-ready. |
| APP-04 | R19 | I/S | warning analyzer בלבד מול compilation מוצלח. | warning אינו חוסם canInstall; התוצר פועל. |
| APP-05 | R20 | I/S/D | NativeScript pure-JS plugin בעל שם שלא ברשימה הישנה אך עם backend נתמך. | אין plugin-name veto; UI/handler באמת פועלים. |
| APP-06 | R20 | I/S/D | plugin הדורש native provider מוטמע מוכר, ולאחר מכן provider חסר. | המוכר עובד; החסר מדווח ברמת dependency/platform, לא מוצג כתמיכה. |
| APP-07 | R20 | U/I/S | גרסה בתוך טווח תאימות backend מוכח וגרסה עם ABI לא־נתמך. | התואמת מתקבלת; אי־תאימות אמיתית אינה נבלעת. |
| APP-08 | R20 | I/S/D | פתח/סגור/פתח NativeScript ו־Expo, כולל מעבר בין שתי sessions. | אין leak או crash; מגבלת session אמיתית מטופלת ולא נמחקת כ־guard בלבד. |
| APP-09 | R20 | I/S | פרסם tool של Script package, גלה דרך Skill והרץ דרך canonical authority. | אותו logicalID/backend; אין stub service או alias לא־קיים. |
| APP-10 | R20,R23 | I/S/D | החזר embedded result מסוג Swift/ScriptUI/NativeScript/Expo לפי התמיכה הקיימת. | כל renderer הנתמך נפתח ומקבל payload; חסר מסוים מפורש ולא success ריק. |
| APP-11 | R20 | S/D | widget/App Intent/Live Activity של fixture ב־target המתאים. | ביצוע דרך target/bridge אמיתיים; אין טעינת foreground-only runtime בכוח. |
| APP-12 | R22 | I/S | ערוך source חוקי ועדכן package; הפעל לאחר relaunch. | artifact generation חדש פועל; לא stale code ולא security rejection. |
| APP-13 | R22 | I | artifact digest לא־תואם או registry קטוע אחרי crash מוזרק. | rebuild/recovery/rollback לפי contract; אין סימון corrupt bytes כ־verified. |
| APP-14 | R22 | I/S | install/update/uninstall עם שני packages ונתוני משתמש קיימים. | identity ונתוני האחר נשמרים; migration אינו מאפס storage. |


### 5.16 — כל כלי הבסיס: קלט ותוצאה צפויה

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| FUNC-01 | R06,R23 | I/S | quick_calculate: {"expression":"(12+8)*3"}. | result 60; card ו־modelText מסכימים; קריאת calculator אמיתית. |
| FUNC-02 | R06,R23 | I/S | quick_calculate: {"expression":"1/0"}. | outcome failed ו־division-by-zero; לא success עם טקסט Calculation failed. |
| FUNC-03 | R06,R23 | I/S/D | execute_local_python_code: {"source":"import json; print(json.dumps({'answer':sum(i*i for i in range(1,101))}))"}. | stdout JSON answer=338350; runtime localPython; אין fallback remote. |
| FUNC-04 | R06,R23 | I/S/D | execute_javascript_code: {"source":"console.log(6*7)","runtime":"node"}. | stdout 42; Node מופעל. |
| FUNC-05 | R06,R23 | I/S/D | execute_typescript_code: {"source":"const n:number=42; console.log(n)","compile_only":false}. | compiler ו־Node אמיתיים; output 42. |
| FUNC-06 | R06,R23 | I/S/D | execute_shell_command במצב argv: program=cat, arguments=["sample.txt"]. | תוכן F01 אמיתי; אין pretend shell. |
| FUNC-07 | R06,R23 | I/S | save_memory: {"content":"HANLIN_TEST_MEMORY answer 42"} בפרופיל ריק. | רשומה אחת נשמרת; store test בלבד. |
| FUNC-08 | R06,R23 | I/S | retrieve_memory: {"keyword":"HANLIN_TEST_MEMORY"} אחרי FUNC-07. | נמצא התוכן המדויק, לא הסקת מודל. |
| FUNC-09 | R06,R23 | I/S | update_memory: {"originalContent":"HANLIN_TEST_MEMORY answer 42","updatedContent":"HANLIN_TEST_MEMORY answer 43"}; retrieve מחדש. | התוכן החדש קיים, הישן אינו מוכפל; mismatch של original מדווח. |
| FUNC-10 | R06,R23 | I/S | search_calendar_and_reminders: {"start_date":"2030-01-15","end_date":"2030-01-15","event_type":"calendar"} על F05. | נמצא Hanlin Fixture Meeting; TZ לפי test clock; no live calendar writes. |
| FUNC-11 | R06,R23 | I/S | write_system_event: {"type":"calendar","title":"HANLIN_TEST_NEW","start_date":"2030-01-15T12:00:00+00:00","end_date":"2030-01-15T12:30:00+00:00"} על F05 ואז search. | אירוע יחיד עם שעות מדויקות; no duplicate side effect. |
| FUNC-12 | R06,R23 | I/S | write_system_event: {"type":"reminder","title":"HANLIN_TEST_REMINDER","due_date":"2030-01-15T13:00:00+00:00","notes":"Fixture only"} ואז search reminders. | תזכורת אחת עם due date תואם; test store בלבד. |
| FUNC-13 | R06,R23 | I/S | query_location: {"keyword":"Hanlin Fixture Place"} כאשר transport מחזיר F05 A. | lat=31.778, lon=35.235; לא geocoding מהזיכרון. |
| FUNC-14 | R06,R23 | I/S/D | get_current_location: {"query":"local"} עם location fixture; ב־device השתמש בהרשאת OS קיימת/בדיקת deny. | fixture A או status OS אמיתי; אין המצאת מיקום. |
| FUNC-15 | R06,R23 | I/S | search_nearby_locations: {"coordinate":{"latitude":31.778,"longitude":35.235},"keyword":"fixture"} על F05. | POI list מה־fixture בלבד; השאילתה מתועדת ב־transport. |
| FUNC-16 | R06,R23 | I/S | get_route: {"start":{"latitude":31.778,"longitude":35.235},"end":{"latitude":31.780,"longitude":35.240},"mode":"walking"} על F05. | distance 900/duration 720 כפי שה־fixture מגדיר; units נשמרים. |
| FUNC-17 | R06,R23 | I/S | query_weather: {"latitude":31.778,"longitude":35.235,"timeRange":"now"} על F05. | 21°C + fixture marker; אין תחזית מומצאת במקרה backend error. |
| FUNC-18 | R06,R23 | I/S | search_online: {"query":"HANLIN_WEB_MARKER"} דרך transport fixture. | תוצאת search fixture עם URL מזוהה; אין remote search לא־נדרש. |
| FUNC-19 | R06,R23 | I/S | read_web_page: {"url":"${FIXTURE_BASE}/page.html"}. | גוף מכיל HANLIN_WEB_MARKER; URL ועקבות הקריאה תואמים. |
| FUNC-20 | R06,R23 | I/S | search_arxiv_papers: {"query":"Hanlin Fixture Paper"} עם Atom feed F03. | כותרת/ID fixture מוחזרים; no-match/HTTP failure אינם מקבלים papers מומצאים. |
| FUNC-21 | R06,R23 | I/S | extract_remote_file_content: {"url":"${FIXTURE_BASE}/document.txt"}; צור body=HANLIN_FILE_MARKER. | הטקסט המדויק חולץ; אותו תרחיש מורחב ל־PDF/DOCX/XLSX אם extractor מפרסם תמיכה בהם. |
| FUNC-22 | R06,R23 | I/S | search_knowledge_bag: {"query":"HANLIN_KNOWLEDGE_MARKER"} על bag fixture. | מסמך fixture עם answer 42; אין מעבר לשירות web במקום מקומי. |
| FUNC-23 | R06,R23 | I/S | create_knowledge_document: {"title":"Hanlin Fixture","content":"# Fixture\nHANLIN_CREATED_DOC 42"} ואז חיפוש. | המסמך נשמר ונמצא; content מלא. |
| FUNC-24 | R06,R23 | I/S | create_canvas: {"title":"Hanlin Fixture","content":"alpha beta","type":"text"}. | Canvas אמיתי עם title/content נכונים. |
| FUNC-25 | R06,R23 | I/S | edit_canvas: {"patterns":["beta"],"replacements":["gamma"]} אחרי FUNC-24. | Canvas מציג alpha gamma; pattern invalid/arrays length mismatch -> error אמיתי. |
| FUNC-26 | R06,R23 | I/S/D | create_web_view: {"code":"<!doctype html><meta name='viewport' content='width=device-width'><button onclick=\"this.textContent='42'\">Run</button>"}. | preview נטען; tap משנה לכיתוב 42; לא קוד טקסטואלי במקום UI. |
| FUNC-27 | R06,R23 | I/S | execute_remote_python_code: {"code":"print(6*7)"} דרך remote transport fixture בלבד. | request נשלח ל־remote executor המוגדר ותוצאה 42 מסומנת remote; אין החלפה שקטה של local. |
| FUNC-28 | R06,R23 | I/S | fetch_step_details: {"start_date":"2026-10-01","end_date":"2026-10-01"} על Health F05. | 1,234 steps, units/time buckets מתאימים; unavailable אינו אפס. |
| FUNC-29 | R06,R23 | I/S | fetch_energy_details עם אותם date fields על F05. | active energy=56 kcal; המרת יחידות נכונה. |
| FUNC-30 | R06,R23 | I/S | fetch_nutrition_details עם אותם date fields על F05. | values/buckets של nutrition fixture מוחזרים בדיוק. |
| FUNC-31 | R06,R23 | I/S | make_nutrition_data: {"protein":10,"carbohydrates":20,"fat":5,"energy":165}. | נוצר nutrition card עם אותם values. אין טענה שכבר נכתב ל־Health אם נדרשת פעולת UI נפרדת. |
| FUNC-32 | R06,R23 | I/S | sefaria_search: {"query":"Hanlin fixture","limit":2} דרך F05. | שתי תוצאות fixture עם ref/snippet; error/no results אינם מושלמים מזיכרון. |
| FUNC-33 | R06,R23 | I/S | sefaria_get_source: {"ref":"Genesis 1:1"} דרך F05. | ref וטקסט בדיוק כמו response fixture; copy/open actions מצביעים לאותו source. |
| FUNC-34 | R06,R23 | I/S | wikipedia_search: {"query":"Jerusalem","language":"he","limit":2} דרך F05. | שתי תוצאות fixture בעברית; language נשמר ל־open action. |
| FUNC-35 | R06,R23 | I/S | wikipedia_get_summary: {"title":"Jerusalem","language":"en"} דרך F05. | summary fixture בלבד; error outcome אינו .succeeded. |
| FUNC-36 | R06,R23 | I/S | text_analyze: {"text":"alpha beta"}. | Characters=10, Words=2; בדוק גם Unicode לפי semantics המוצהרים. |
| FUNC-37 | R06,R23 | I/S | text_transform: text="Alpha beta", transform=ערך enum אמיתי של uppercase מה־schema. | ALPHA BETA; ערך transform לא־קיים מחזיר failed/invalidArguments. |
| FUNC-38 | R06,R23 | I/S | הרץ את החוזה הפרמטרי מסעיף 4.3 על כל tool נוסף: aliases legacy, MCP, Script ו־compiled providers. | אין published tool בלי תסריט; אין ספירת רישום בלבד כהצלחת execution. |


### 5.17 — UI, אריזות ואימות ספק אמיתי

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| UI-01 | R02,R03,R06 | S/D | Import pack מתוך Files -> preview -> install -> Skill Center -> details. | כל הפריטים מוצגים עם metadata נכון; אין שגיאת staging/תאריך. |
| UI-02 | R04,R06 | S/D | ערוך Skill, שמור, export, מחק רק את fixture וייבא מחדש. | body/metadata/resources נשמרים; ניתן לטעון את אותו Skill. |
| UI-03 | R23,R24 | S/D | הרץ tool מצליח, tool כושל ו־cancel; פתח Agent Activity. | סטטוסים, אייקון/טקסט, backend ו־result תואמים; אין success card לכשל. |
| UI-04 | R23 | S/D | פתח result card, בצע copy/open route ואז חזור לשיחה. | הפעולה משתמשת ב־payload הנכון; שיחה וריצה אינן מתאפסות. |
| UI-05 | R23 | S/D | בדוק עברית RTL, split view צר/רחב, rotation ו־Dynamic Type. | כפתורי install/cancel ו־tool result נגישים; אין clipping שמונע בדיקה. |
| UI-06 | R18,R22 | S/D | ריצה ארוכה ברקע/foreground וחזרה; לאחר מכן בקשה חדשה. | state משקף התנהגות OS בפועל; אין הבטחה לריצה אינסופית ברקע ואין orphan spinner. |
| PROV-01 | R05,R06,R24 | P/D | במודל שהוגדר בפועל: 'הרץ בפייתון מקומי חיבור ריבועי המספרים 1 עד 100 והראה את התוצאה'. | load_skill/discovery ואז local tool invocation; answer 338350 עם ToolResult אמיתי. |
| PROV-02 | R05,R06,R08 | P/D | 'התקן בסביבה המקומית את חבילת ה־fixture שהוגדרה לבדיקה והשתמש בה כדי להחזיר 42'. | Skill package/runtime, package tool ואז execution; לא 'אין לי אפשרות כי sandbox'. |
| PROV-03 | R05,R11 | P/D | 'צור קובץ עם שלוש שורות, וספור בטרמינל כמה שורות יש בו'. | פעולת כתיבה וכלי shell אמיתיים; count 3; אין ריצה פיקטיבית. |
| PROV-04 | R05,R12 | P/D | 'Run JavaScript with a timer, then print 42' וגם נוסח עברי שקול. | Node נבחר לפי workflow; פלט 42; JSC לא מוצג כתומך timers ללא backend. |
| PROV-05 | R05,R06 | P/D | 'קרא את הכתובת של דף הבדיקה וסכם מה כתוב בה'. | web Skill וכלי read אמיתי; הסיכום מבוסס marker fixture. |
| PROV-06 | R05,R07 | P/D | 'הראה לי את כל הכלים, ובדוק מי זמין ומי כבוי'. | enumeration עם pagination; אין טענה שרק עשרת תוצאות search הם כל הכלים. |
| PROV-07 | R05,R24 | P | לכל PROV-01..06: לפחות 3 שיחות חדשות באותו provider/model, ורשום request/model ID מדויקים. | מדווח pass count אמיתי מתוך ניסיונות; mock success לא מתחלף בו; rate limit/רשת מסומנים בנפרד. |
| PROV-08 | R05,R23 | P | הפעל failure fixture ואז בקשה לתיקון; אל תחליף ספק בלי לדווח. | המודל מפרש tool error מדויק ומבצע retry מתאים; אין המצאת יכולת או איבוד tools. |


### 5.18 — build, רגרסיה והשלמות

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| BUILD-01 | R25 | B | הרץ בדיקות parser/codec/exposure/registry/contracts המקומיות שנוגעות לשינויים. | PASS לכולן; full command ו־exit code נשמרים. |
| BUILD-02 | R25 | B | הרץ Node host tests ו־integration tests עם fixtures המקומיים. | אין source scanner/lifecycle policy regression; תוצאות אינן תלויות registry ציבורי. |
| BUILD-03 | R25 | B | הרץ Swift package tests עבור targets ששונו, לפי סכמות שנמצאו בפועל. | compiler/test runner אמיתיים; לא static grep במקום tests. |
| BUILD-04 | R25 | B/S | build-for-testing של app ו־test-without-building לקבוצות המושפעות. | הבדיקות רצות מתוך bundle ולא checkout fallback; xcresults נשמרים. |
| BUILD-05 | R25 | B | Compile device target ו־simulator target עם toolchain הרלוונטי של הפרויקט. | אין הורדת deployment target או שינוי signing scope בלי צורך; warnings/errors מתועדים. |
| BUILD-06 | R11,R25 | B/S | בדוק packaged command dictionaries/framework symbols/resource bundles. | כל command שפורסם באמת קיים; אין exact-23 check ישן. |
| BUILD-07 | R13,R25 | B/S | בדוק RuntimeHostResources.zip שה־IPA בפועל אורז. | ה־JS המתוקן נמצא באריזה; אין עותק stale של rejectUnsafeSource או policies ישנים. |
| BUILD-08 | R06,R25 | B/S | פתח כל Skill ZIP, פענח metadata באותו codec של האפליקציה וייבא באמצעות SkillImporter האמיתי. | כל packages תקינים; validator חיצוני בלבד אינו מספיק. |
| BUILD-09 | R25,R26 | B/S/D | הפעל suite של existing tools/miniapps אחרי השינויים, כולל cold launch ו־relaunch. | אין regression במנגנונים קיימים; device results נפרדים ומקושרים ל־IPA SHA. |
| BUILD-10 | R26 | U/B | השווה כל מזהי R/test/tool/restriction לדוח הסופי ו־git diff. | אין מזהה חסר; אין PASS ללא evidence; remaining blockers מפורטים בדיוק. |


---

### 5.19 — AI SDK consolidation and deletion of the legacy remote tool loop

| ID | Requirements | Layer | Setup / input / action | Expected result / failure condition |
|---|---|---|---|---|
| SDKAI-01 | R27 | unit | Feed an OpenAI-compatible text-only fixture through the production provider mapping. | The selected model/provider is the Swift AI SDK provider; no legacy request builder is invoked. |
| SDKAI-02 | R27 | unit | Feed OpenAI, Anthropic, Google/Gemini and OpenRouter/OpenAI-compatible configurations through provider resolution. | Each resolves to the intended SDK provider/base URL/model ID/headers without duplicate manual JSON construction. |
| SDKAI-03 | R27 | integration | Stream `hello` from deterministic OpenAI-compatible fixture in 5 chunks. | Chunks surface once, in order; final content is `hello`; no duplicate event from old parser. |
| SDKAI-04 | R27 | integration | Fixture emits provider reasoning delta + visible text. | Provider-surfaced reasoning and visible text remain separate and correctly presented; no hidden/private CoT is fabricated. |
| SDKAI-05 | R27 | integration | Fixture emits usage fields including input/output/reasoning/cached tokens. | Usage maps to Hanlin diagnostics exactly once. |
| SDKAI-06 | R27 | integration | Model calls deterministic `echo` tool, receives output, then writes final text. | Swift AI SDK performs tool loop; trace shows one tool execution and a later model step; final answer uses the tool result. |
| SDKAI-07 | R27 | integration | Model calls two tools in one step. | Both calls execute with stable call IDs; results return to SDK; no legacy recursion handles them. |
| SDKAI-08 | R27 | integration | Model calls a tool that returns typed error. | Tool error is delivered through SDK semantics, marked failed in diagnostics, and a subsequent model step can recover. |
| SDKAI-09 | R27 | integration | `prepareStep` changes active tool schemas after `load_skill`. | Next SDK step sees newly exposed tools without rebuilding a second agent loop. |
| SDKAI-10 | R27 | integration | Run more than 2 recursive tool steps but fewer than configured stop limit. | SDK continues correctly and does not terminate after one tool round. |
| SDKAI-11 | R27 | integration | Deterministic fixture reaches configured maximum step count. | Run stops with explicit stop reason and no infinite recursion. |
| SDKAI-12 | R27 | unit | Search production call graph after routing migration. | No tool-capable text provider calls the obsolete manual `finishReason == tool_calls` execution path. |
| SDKAI-13 | R27,R43 | source/build | Remove dead manual tool-loop code and compile all app targets/tests. | No unresolved references; old loop is actually deleted, not just permanently disabled by an `if false`. |
| SDKAI-14 | R27 | regression | Exercise image-generation path that is not owned by `streamText`. | Image generation still works or reports the same real provider limitation; it was not accidentally deleted. |
| SDKAI-15 | R27 | regression | Exercise configured audio/voice generation path if supported by current model fixture. | Audio-specific behavior remains on its explicit path and does not pass through incompatible text SDK path. |
| SDKAI-16 | R27 | regression | Exercise local LLM mode. | Local model remains local; no remote Swift AI SDK provider is selected. |
| SDKAI-17 | R27 | provider | Real configured provider prompt: `Use the calculator/tool to compute 19*23, then answer with only the number.` | Tool trace exists and final answer is `437`; no fake computation without the tool when tool use was required by test harness. |
| SDKAI-18 | R27 | provider | Real provider receives a tool error, then is asked to correct the arguments. | It can make a corrected second call in same SDK run. |

### 5.20 — Swift AI SDK fork/upstream maintenance

| ID | Requirements | Layer | Setup / action | Expected result |
|---|---|---|---|---|
| SDKFORK-01 | R28 | audit | Compare Hanlin fork against current `teunlao/swift-ai-sdk` upstream. | Every fork-only commit/file is listed in `swift-ai-sdk-patches.md` with rationale. |
| SDKFORK-02 | R28 | unit/upstream | For each fork patch with an upstream equivalent, drop patch on a temporary branch and run relevant SDK tests. | Patch is removed only if upstream now passes the Hanlin regression. |
| SDKFORK-03 | R28 | package | Resolve Hanlin against chosen immutable fork revision/tag. | SwiftPM resolves deterministically and app imports expected products. |
| SDKFORK-04 | R28 | integration | Run Hanlin provider/tool conformance after SDK synchronization. | No change in tool IDs, streamed event ordering or provider options without documented migration. |
| SDKFORK-05 | R28,R42 | automation | Run dependency drift checker with upstream one commit ahead in fixture metadata. | Produces report/candidate only; never auto-merges or rewrites Hanlin app code. |

### 5.21 — Current Hanlin chat UI regression contract (UI frozen)

These tests are **regression tests for the existing UI**, not a migration plan. They must run before and after backend/runtime changes. No third-party chat UI dependency is to be introduced.

| מזהה | דרישות | שכבה | הכנה / קלט / פעולה | תוצאה צפויה ומבחן כשל |
|---|---|---|---|---|
| CHAT-01 | R30,R31 | U/UI | Render a persisted user text message through the current chat surface. | Text, role, timestamp/model metadata and grouping match the current behavior; no new message model becomes source of truth. |
| CHAT-02 | R30,R31 | U/UI | Render an assistant message with text + reasoning + tool activity + evidence + `NativeUIBlock`. | Every semantic section remains independently visible in the current renderer. |
| CHAT-03 | R30 | UI | Render a plain assistant message over 20,000 characters. | Smooth scrolling; no message loss, duplicate text or new truncation. |
| CHAT-04 | R30,R31 | UI | Stream 50 KB in many small deltas through the current renderer. | UI remains responsive; final rendered text exactly equals source stream. |
| CHAT-05 | R30,R31 | UI | Stream answer text while surfaced reasoning/summary data updates rapidly. | Existing reasoning and answer presentation behave as before; no ordering loss. |
| CHAT-06 | R30 | UI | Render Markdown headings, lists, blockquote, table, links, inline code and fenced blocks. | Existing rendering/selection/copy behavior is unchanged. |
| CHAT-07 | R30,R35 | UI | Render fenced Python, JS, TypeScript, JSON, shell and Swift samples. | Current code content/labels/selection behavior remains unchanged; no renderer replacement occurs. |
| CHAT-08 | R30 | UI | Render the existing LaTeX fixture. | Mathematical content renders equivalently to baseline. |
| CHAT-09 | R30 | UI | Render resources/citations and open evidence sheet. | Existing resource/evidence navigation works unchanged. |
| CHAT-10 | R30 | UI | Render map + route tool result. | Existing map/route UI remains interactive and unchanged. |
| CHAT-11 | R30 | UI | Render calendar/event result. | Existing event card/section survives unchanged. |
| CHAT-12 | R30 | UI | Render health/nutrition result. | Existing health card survives and is not flattened to text. |
| CHAT-13 | R30 | UI | Render canvas result and use its open/edit action. | Current canvas surface/actions work unchanged. |
| CHAT-14 | R30 | UI | Render HTML/web result. | Existing web preview/open behavior works unchanged. |
| CHAT-15 | R30 | UI | Render code-execution result and use copy action. | Exact code/output is copied and remains attached to the correct message. |
| CHAT-16 | R30 | UI | Render each existing `NativeUIBlock` fixture and an unknown/future block fallback. | Known blocks render; unknown handling remains explicit rather than silently disappearing. |
| CHAT-17 | R30 | UI | Trigger a MiniApp launch action from a chat result. | Existing sheet/full-screen launch behavior and state remain unchanged. |
| CHAT-18 | R30 | UI | Open AgentActivity inspector/evidence from an assistant turn. | Activity ordering, selected item and evidence remain correct. |
| CHAT-19 | R30 | UI | Retry an assistant request through the existing retry action. | Existing retry pipeline is called exactly once; grouping stays correct. |
| CHAT-20 | R30 | UI | Delete a message through current confirmation flow. | Only the selected message and its owned presentation disappear; persistence remains consistent. |
| CHAT-21 | R30 | UI | Exercise TTS, copy, translate and share on assistant content. | All current actions work with identical semantics. |
| CHAT-22 | R30,R32 | UI/D | Attach photo, PDF and arbitrary document using the current composer. | Existing preview and request/file pipeline receive the same URLs/data. |
| CHAT-23 | R30,R32 | UI/D | Dictate text through the current voice/dictation path. | Apple/system permission flow and transcript insertion work as before. |
| CHAT-24 | R30,R31,R32 | UI | Stop generation while a model/tool run is active. | Cancels the correct Hanlin run; current composer returns to idle; no stale output appends. |
| CHAT-25 | R30 | UI | Test iPad portrait, landscape, split view and narrow window. | No new clipping/regression; current layout semantics remain intact. |
| CHAT-26 | R30 | UI | Hebrew RTL conversation mixed with English and code. | Current alignment/direction/control behavior remains correct. |
| CHAT-27 | R30 | UI/accessibility | Largest Dynamic Type + VoiceOver labels. | Current composer, message actions, tool states and rich-result actions remain usable. |
| CHAT-28 | R30,R47 | B/source | Compare SwiftPM/project dependencies before/after. | No third-party chat UI package was added; current chat dependencies remain unless an unrelated accepted update requires a tested version change. |
| CHAT-29 | R30,R47 | B/source | Diff `ChatView.swift`, `ChatViewComponents.swift`, `ChatViewBottom.swift` and related chat files. | No structural UI migration/decomposition. Every change is minimal and tied to a documented compatibility need. |
| CHAT-30 | R30,R47 | B/source | Search for newly introduced chat-framework adapter/projection/message-model types. | None exist solely for a future UI migration. |
| CHAT-31 | R30 | UI | Scroll mid-transcript while current assistant message receives streaming deltas. | User scroll position/auto-scroll behavior matches baseline. |
| CHAT-32 | R30 | UI | Prepend older messages while user is mid-scroll. | Current pagination preserves stable message order/identity and expected position. |
| CHAT-33 | R32 | UI | Change the selected model with the current model selector. | Existing model state/provider choice changes exactly as baseline. |
| CHAT-34 | R32 | UI | Open current model-management surface and return. | No loss of draft text, attachments or selected mode state. |
| CHAT-35 | R32 | UI | Type an `@model` query and select a suggestion. | Existing suggestion filtering/replacement behavior is unchanged. |
| CHAT-36 | R32 | UI | Add/remove/edit prompt chips. | Existing prompt selection and request augmentation remain exact. |
| CHAT-37 | R32 | UI | Add/remove selected URL previews. | Existing URL preview/request behavior remains exact. |
| CHAT-38 | R32 | UI | Toggle tool-use mode. | Existing canonical-tool enablement/request state changes once and UI reflects it. |
| CHAT-39 | R32 | UI | Select/change MCP chat server from the current composer. | Existing MCP selection state and request routing remain exact. |
| CHAT-40 | R32 | UI | Toggle knowledge mode including unavailable-state alert. | Existing availability logic/alert and request state remain exact. |
| CHAT-41 | R32 | UI | Toggle web-search mode including unavailable-state alert. | Existing availability logic/alert and request state remain exact. |
| CHAT-42 | R32 | UI | Toggle reasoning/thinking and effort controls across supported/unsupported models. | Current visibility, state and provider options remain exact. |
| CHAT-43 | R32 | UI | Exercise image-generation reverse prompt plus every current aspect/size choice. | Existing request payload semantics remain unchanged. |
| CHAT-44 | R32 | UI | Exercise audio/voice generation controls. | Current mode remains reachable and maps to the same request state. |
| CHAT-45 | R32 | UI | Exercise local-model-specific composer controls. | Existing local-model settings/actions remain reachable and unchanged. |
| CHAT-46 | R32 | UI | Open current canvas shortcut and scroll-to-bottom control. | Both current actions remain available and behave as baseline. |
| CHAT-47 | R32 | UI | Use current observe-send action. | Existing observe request path is called exactly once with correct state. |
| CHAT-48 | R32 | UI/D | Paste a supported file/image into `InputTextField`. | Existing paste detection, file creation/selection and preview behavior remains unchanged. |
| CHAT-49 | R30,R32 | UI | Focus/dismiss keyboard using touch, return/send and hardware keyboard. | Existing focus, submit and dismissal behavior remains unchanged. |
| CHAT-50 | R30,R31,R32 | UI/I | Cancel a long run and immediately send a second request. | Old run cannot mutate the new turn; current UI leaves no stuck spinner. |
| CHAT-51 | R30,R31 | UI/I | Run two separate conversations sequentially with different tools/models. | No UI state/tool activity leaks between conversations. |
| CHAT-52 | R30,R31 | UI/persistence | Relaunch with an existing saved mixed conversation fixture. | Existing conversation renders with no migration/data loss and all rich results/actions intact. |
| CHAT-53 | R30 | UI | Render consecutive user/assistant groups with split markers and model metadata. | Current grouping/separators/metadata display remain identical to baseline. |
| CHAT-54 | R30,R31 | UI | Background/foreground the app during a supported streaming run and after completion. | Current state recovery behavior is preserved; no duplicated deltas or stale progress UI. |
| CHAT-55 | R30,R31,R32,R47 | B/source/UI | Final frozen-UI audit: dependency graph, chat-file diff and full CHAT-01..54 suite. | No chat UI migration occurred; current Hanlin chat interface remains the product UI and all regressions are green or explicitly reported. |

### 5.22 — Skills/YAML/metadata simplification

| ID | Requirements | Layer | Setup / input / action | Expected result |
|---|---|---|---|---|
| YAML-01 | R33 | unit | Parse frontmatter with `name`, quoted description containing `:`, Unicode and CRLF. | Values are exact; body begins after closing delimiter. |
| YAML-02 | R33 | unit | Parse folded `>` description across lines. | Standard YAML folded value is returned. |
| YAML-03 | R33 | unit | Parse literal `|` multiline field. | Newlines are preserved according to YAML semantics. |
| YAML-04 | R33 | unit | Parse frontmatter with unknown nested key/list. | Known metadata parses; unknown data can survive round-trip where store contract requires forward compatibility. |
| YAML-05 | R33 | unit | Body contains a later line equal to `---`. | Only frontmatter boundary is treated as metadata delimiter; body is preserved. |
| YAML-06 | R33 | unit | UTF-8 BOM + Hebrew Skill name/description. | Valid content imports without mangling. |
| YAML-07 | R33 | unit | Malformed YAML. | Clear frontmatter parse error with location/context; no silent empty metadata fallback. |
| YAML-08 | R33 | regression | Import every built-in/exported Skill fixture from old parser suite. | Existing valid Skills remain valid or have a documented standards-correct migration. |
| YAML-09 | R33 | roundtrip | Import -> edit description -> export -> reimport. | `preferredToolIDs`, trigger hints, keywords and unknown supported metadata remain intact. |

### 5.23 — Dependency refresh and platform modernization

| ID | Requirements | Layer | Setup / action | Expected result |
|---|---|---|---|---|
| DEP-01 | R39 | package | Resolve ZIPFoundation chosen current compatible version. | Build/test passes; Skill/file Office extraction fixtures unchanged. |
| DEP-02 | R39 | package | Update SWCompression patch version. | MCP TGZ preview/extraction fixtures pass byte-for-byte semantic assertions. |
| DEP-03 | R39 | package | Update SwiftSoup to chosen current stable. | WebRead extraction fixtures return same required title/body markers. |
| DEP-04 | R39 | package | Update swift-log to current stable compatible API. | MCP/runtime logs compile and emit expected structured fields. |
| DEP-05 | R39 | migration | Evaluate LaTeXSwiftUI 2.x in isolated commit. | Existing math fixtures render; otherwise revert and document blocker rather than forcing migration. |
| DEP-06 | R39,R40 | migration | Evaluate LLM.swift 3.x in isolated commit with current local model fixture. | Model loads, streams, cancels and releases memory; otherwise keep existing version and document. |
| DEP-07 | R36 | runtime | Build Python Apple support b11 through existing runtime bundle pipeline. | Device + simulator slices link; Python version/provenance reflect chosen release. |
| DEP-08 | R36 | runtime | Build ios_system v3.0.7 through existing runtime pipeline. | Commands reported by backend match linked frameworks and acceptance suite. |
| DEP-09 | R36 | runtime | Rebase QuickJS-NG v0.17.0 and minimal Hanlin allocator patch. | QuickJS conformance, typed OOM/stack/cancel tests all pass. |
| DEP-10 | R36 | runtime | Validate current Node 24.5.0 mobile fork after all changes. | No downgrade; generic Node, npm and MCP server tests pass. |
| DEP-11 | R37 | package | Query official NativeScript `ios-spm` refs/releases. | Upgrade occurs only if a matching complete runtime/core closure exists; otherwise exact 9.1.0 remains with evidence. |
| DEP-12 | R38 | package/build | Query Expo official stable channel. If SDK 58 is still beta, align to latest SDK 57 stable patch; if 58 is stable by execution time, align to stable 58. | No `preview`, `beta`, `rc` or hand-mixed RN/Expo closure remains; official compatibility tooling determines versions. |
| DEP-13 | R38 | build/UI | With SDK 57 on Xcode 27, enable/document official scene lifecycle support; with stable SDK 58, use its default supported scene path. Launch existing Expo brownfield probe. | App launches on iOS 27, window/scene lifecycle works, probe renders/interacts and background/foreground does not lose root view. |
| DEP-14 | R42 | automation | Dependency report with safe patch, major update and unchanged packages. | Classifies each correctly; no automatic merge. |
| DEP-15 | R42 | audit | Generate SBOM/dependency inventory with direct/transitive versions and licenses. | Every production third-party dependency is listed with source and chosen pin rule. |
| PLATFORM-01 | MASTER-5 | build | Select stable Xcode 27, print `xcodebuild -version`, SDKs and `swift --version`. | Stable Xcode 27 is used; beta Xcode is not selected. |
| PLATFORM-02 | MASTER-5 | source/build | Set app deployment target to iOS 27.0. | App compiles for iOS 27 simulator and generic device. |
| PLATFORM-03 | MASTER-5 | package | Update product package iOS platform declarations to v27 where appropriate. | SwiftPM resolution/build succeeds under Xcode 27. |
| PLATFORM-04 | MASTER-5 | host-tests | Evaluate macOS package target changes. | Host tests remain runnable on actual CI host; no needless macOS 27 target blocks execution. |
| PLATFORM-05 | MASTER-5 | build | Build with Swift 6 strict concurrency diagnostics for modified modules. | No newly introduced unsafely ignored concurrency errors. |
| PLATFORM-06 | MASTER-5 | simulator | Launch app on iPadOS 27 simulator. | Cold launch succeeds to main UI; no runtime framework load failure. |
| PLATFORM-07 | MASTER-5 | device | Install signed build on iPadOS 27 device when available. | App launches and core runtime acceptance can execute. |
| PLATFORM-08 | MASTER-5 | CI | Migrate workflow Xcode-selection logic from Xcode 26 to stable Xcode 27. | Targeted and full manual validation choose correct toolchain; existing inputs preserved. |


### 5.23A — Apple Foundation Models and Core AI local-provider acceptance

| ID | Requirements | Layer | Setup / action | Expected result |
|---|---|---|---|---|
| APPLEAI-01 | R45 | build | Compile the Foundation Models adapter with stable Xcode 27/iOS 27 SDK. | Uses public stable APIs accepted by the installed SDK; no beta/private import. |
| APPLEAI-02 | R45 | unit | Inject unavailable-capability fixture/model state. | Provider reports unavailable with a typed/localized reason; no crash and no fallback to remote without explicit routing. |
| APPLEAI-03 | R45 | unit/integration | Feed text stream fixture through adapter into Hanlin presentation. | Deltas preserve order, cancellation ID and final content; same conversation model is used. |
| APPLEAI-04 | R45 | device | On Apple-Intelligence-capable iOS 27 device, send a deterministic short prompt to `SystemLanguageModel`. | Real on-device response streams; provider identity/latency recorded; no remote API key required. |
| APPLEAI-05 | R45 | device | Send text + supported image multimodal prompt. | Image is accepted only when model capability says supported; response arrives through same Hanlin message path. |
| APPLEAI-06 | R45 | device | Start long Apple model generation and cancel. | Generation stops/settles according to API; UI resets; new request starts without cross-run deltas. |
| APPLEAI-07 | R45 | architecture/source | Inspect any Foundation Models `Tool` integration. | No independent tool business logic/executor duplicates Hanlin canonical tools. Tool requests, if supported, bridge to canonical authority or feature remains text-only with explicit limitation. |
| APPLEAI-08 | R45 | regression | OS/model version prompt fixture pack across supported devices/OS images available in CI/device lab. | Semantic expectations/tolerance recorded because Apple system model may change with OS; exact-text assertions are used only when deterministic. |
| COREAI-01 | R46 | package | Resolve official `apple/coreai-models`/Core AI integration at a stable compatible revision/tag. | License/source/pin recorded; no unofficial wrapper substituted. |
| COREAI-02 | R46 | build | Compile Core AI provider/runtime for iOS 27. | Public Core AI/Foundation Models APIs compile under stable Xcode 27. |
| COREAI-03 | R46 | device/input | Load a small supported `.aimodel` fixture, specialize and create `CoreAILanguageModel`. | Model reaches ready state; load/specialization latency and cache reuse recorded. If no redistributable fixture is supplied, disposition is `BLOCKED_INPUT_MODEL_FIXTURE`, not PASS. |
| COREAI-04 | R46 | device | Stream a deterministic prompt through Core AI model in a Foundation Models session. | Output appears through Hanlin local-provider path; provider/runtime identity remains Core AI. |
| COREAI-05 | R46 | device/perf | Measure cold load, warm load, first token, tokens/sec and peak memory. | Metrics saved and compared to configured regression thresholds; no unexplained runaway memory. |
| COREAI-06 | R46 | regression | Run existing GGUF/LLM.swift local provider after Core AI is enabled. | GGUF path still loads/streams/cancels; Core AI did not replace or corrupt it. |

### 5.24 — MCP SDK consolidation

| ID | Requirements | Layer | Setup / action | Expected result |
|---|---|---|---|---|
| MCPSDK-01 | R29 | unit | Connect official MCP `Client` to deterministic in-process/mock transport. | Initialization/list tools uses SDK messages; no Hanlin duplicate protocol parser. |
| MCPSDK-02 | R29 | integration | Start embedded Node `server-everything` fixture. | Official SDK client connects via `EmbeddedNodeMCPTransport` and discovers expected tools. |
| MCPSDK-03 | R29 | integration | Invoke one MCP tool through canonical agent bridge. | Exactly one MCP SDK call; output maps to canonical tool result and presentation. |
| MCPSDK-04 | R29 | integration | Server emits tool-list-changed notification. | Hanlin refreshes tool catalog without restart. |
| MCPSDK-05 | R29 | integration | Kill/restart worker while one server selected. | Runtime state recovers; stale session/tool count is cleared and repopulated. |
| MCPSDK-06 | R29 | persistence | Relaunch with two installed MCP servers and one selected per chat. | Registry/selection restore correctly; unselected server tools do not leak into request. |
| MCPSDK-07 | R29 | source | Search for duplicate JSON-RPC/MCP message models outside official SDK adapters. | Any remaining duplicates have explicit Hanlin-specific reason or are removed. |
| MCPSDK-08 | R29 | regression | Run current MCP path-migration fixtures. | Simplification does not reintroduce old absolute path migration bug. |

### 5.25 — Scripting/HostServices simplification and engine preservation

| ID | Requirements | Layer | Setup / input / action | Expected result |
|---|---|---|---|---|
| SCRIPTARCH-01 | R41 | architecture | Build call graph for ScriptUI -> host service request -> concrete adapter. | Every hop has a reason; redundant policy-only hop is identified for removal. |
| SCRIPTARCH-02 | R41 | integration | JSC scripting fixture reads/writes package storage. | Works through simplified service path; relaunch preserves data. |
| SCRIPTARCH-03 | R41 | integration | QuickJS fixture calls asynchronous host service. | Promise/result/cancellation semantics remain correct. |
| SCRIPTARCH-04 | R41 | integration | Node scripting fixture calls permitted host file/network service. | Uses Node engine and receives real result; no fallback to QuickJS/JSC. |
| SCRIPTARCH-05 | R41 | integration | Python scripting fixture calls available host bridge. | Uses Python engine and preserves value conversion/errors. |
| SCRIPTARCH-06 | R41 | UI | Render canonical ScriptUI fixture tree and interact with button/text/state/navigation. | UI tree and events remain correct after broker simplification. |
| SCRIPTARCH-07 | R41 | agent | Installed Script package publishes tool; agent discovers and invokes it. | Tool result returns to Swift AI SDK and rich presentation survives. |
| SCRIPTARCH-08 | R41 | lifecycle | Update script package, relaunch, then rollback. | Active generation changes atomically and rollback restores previous generation. |
| SCRIPTARCH-09 | R41 | source | Remove trust/grant/policy layers designated obsolete. | No production caller still depends on removed state; no replacement security layer added. |
| SCRIPTARCH-10 | R41 | regression | Existing extension/AppIntent/Widget snapshot tests. | Extension-safe paths remain functional; Node/Python are not accidentally linked into extension targets. |

### 5.26 — SQLite/GRDB decision and data integrity

| ID | Requirements | Layer | Setup / action | Expected result |
|---|---|---|---|---|
| DB-01 | R34 | baseline | Run current SQLite open/create/insert/select/update/delete fixture through `HanlinSQLiteService`. | Baseline outputs recorded before migration. |
| DB-02 | R34 | baseline | Positional parameters, named parameters, NULL/bool/int/double/text/blob. | Values round-trip exactly under current bridge. |
| DB-03 | R34 | baseline | Transaction commit and rollback fixture. | Atomic semantics recorded. |
| DB-04 | R34 | prototype | If GRDB prototype is built, rerun DB-01..03 through same public Hanlin API. | Results match; no third-party DB model leaks into scripting protocol. |
| DB-05 | R34 | prototype | Execute arbitrary valid SQL statement supported today. | GRDB path does not artificially narrow SQL surface. |
| DB-06 | R34 | performance | Compare representative 1k inserts + 1k-row fetch and code complexity. | Adopt only with acceptable performance and meaningful maintenance reduction. |
| DB-07 | R34 | decision | Produce `grdb-evaluation.md`. | Explicit ADOPT/KEEP decision with LOC/test/dependency evidence; no half-migrated dual DB layer. |

### 5.27 — NativeScript, Expo, MiniApps and rich agent integration

| ID | Requirements | Layer | Setup / action | Expected result |
|---|---|---|---|---|
| APPENG-01 | R37 | UI/device/sim | Launch NativeScript direct UIKit fixture using Metadata Bridge. | Native UIKit controller presents through Hanlin. |
| APPENG-02 | R37 | UI/device/sim | Launch NativeScript fixture importing `@nativescript/core`. | Core module loads with runtime-matched version and renders. |
| APPENG-03 | R37 | integration | NativeScript app calls Hanlin host service and returns result. | Bridge remains functional after policy simplification. |
| APPENG-04 | R37 | agent | NativeScript/MiniApp tool is published and invoked by agent. | Canonical tool path works; rich result can open app UI. |
| APPENG-05 | R38 | UI | Launch Expo production fixture after stable SDK 58 migration. | Brownfield root renders, events cross bridge, no missing Hermes/Expo symbols. |
| APPENG-06 | R38 | concurrency | Open/close/reopen Expo app multiple times. | No duplicate runtime/session leak or stale root view. |
| APPENG-07 | MASTER-1 | UI | Apps Hub lists Swift MiniApp, ScriptUI app, NativeScript app and Expo app together. | Each identity/runtime type is correct and launchable. |
| APPENG-08 | MASTER-1 | regression | Sefaria, Wikipedia and Text Studio built-in MiniApps. | Launch, core data action and agent tool path pass. |
| APPENG-09 | MASTER-1 | multiwindow | Launch supported MiniApp in sheet/window modes used by Hanlin. | Correct presentation and dismissal; chat state survives. |

### 5.28 — Independent-fork policy, cleanup and maintainability

| ID | Requirements | Layer | Setup / action | Expected result |
|---|---|---|---|---|
| ARCH-01 | MASTER-6 | docs | Read updated `AGENTS.md`/`PROJECT_AGENT_GUIDANCE.md`. | They no longer require downstream duplication for hypothetical upstream merges. |
| ARCH-02 | MASTER-6 | docs | Search instructions for contradictory “never edit upstream files” rules. | Conflicts removed or explicitly scoped to third-party vendored code. |
| ARCH-03 | R43 | source | Generate before/after LOC by subsystem. | Report shows where complexity was reduced; generated/vendor resources excluded from misleading LOC totals. |
| ARCH-04 | R43 | source/build | Identify deleted legacy symbols and search all callers. | No production/test caller to deleted path remains. |
| ARCH-05 | R43 | package | Run SwiftPM/Xcode dependency graph after cleanup. | Unused direct dependencies removed; needed transitive packages resolve once. |
| ARCH-06 | R43 | binary | Compare app/runtime bundle sizes before/after. | Delta documented; unexpected major growth investigated. |
| ARCH-07 | R44 | docs | Follow documented Agent -> Skill -> tool -> runtime sequence against code. | Docs match actual symbols/call graph. |
| ARCH-08 | R44 | docs | Follow documented chat render sequence. | Docs identify authoritative Hanlin semantic model and optional third-party shell boundary. |
| ARCH-09 | R44 | docs | Follow documented MCP sequence. | One official MCP SDK stack shown; no obsolete duplicate protocol path documented. |
| ARCH-10 | R42,R44 | docs/automation | Run dependency inventory generator twice on unchanged tree. | Deterministic output/no meaningless churn. |

### 5.29 — End-state full regression under the new architecture

| ID | Requirements | Layer | Setup / action | Expected result |
|---|---|---|---|---|
| FINAL-01 | all | package | `swift test --package-path Packages/HanlinPlatform` under selected Xcode 27 toolchain. | All relevant package tests pass. |
| FINAL-02 | all | node | `npm test` and integration suites for RuntimeCore Node host. | All tests match new policy expectations; obsolete “must be blocked” assertions are replaced, not merely skipped. |
| FINAL-03 | all | build | Xcode build-for-testing for iPadOS 27 simulator. | Success with exact log/result bundle. |
| FINAL-04 | all | simulator | App unit/integration tests including Skills, canonical tools, runtime packages, HostServices and provider conformance. | PASS with xcresult evidence. |
| FINAL-05 | all | UI | Targeted UI tests for Skills, runtime command/install, ScriptUI, NativeScript, Expo, Agent conversation and rich chat. | PASS; screenshots/artifacts preserved for failures. |
| FINAL-06 | all | CI | Manually dispatch affected-validation groups on saved commit. | All selected groups pass; run IDs recorded. |
| FINAL-07 | all | CI | Manually dispatch full validation once focused suites are green. | Full job passes on exact commit; no TestFlight/release publication. |
| FINAL-08 | all | device | Run `ON_DEVICE_ACCEPTANCE.md` updated for new architecture on signed iPadOS 27 build. | Device-specific engines and OS services pass or are individually `BLOCKED_EXTERNAL`/`FAIL`, never inferred from simulator. |
| FINAL-09 | all | provider | Run real-provider Skill/tool prompts including Code, package install, web and one rich native tool. | Model actually discovers/loads tools and uses them; no “isolated environment” hallucination without discovery attempt. |
| FINAL-10 | all | persistence | Cold terminate/relaunch after installed Skills, npm/Python packages, MCP server and Script app. | All intended state restores; no stale request-scoped exposed-tool state survives. |
| FINAL-11 | all | cancellation | Start long model/tool/runtime operation, cancel, immediately send small request. | Old run ceases visible effects; new run completes; no cross-run result contamination. |
| FINAL-12 | all | audit | Cross-join `capability-invariants.json`, `tool-inventory.json`, requirements and test IDs. | No invariant/tool/requirement lacks final disposition/evidence. |



## 6. תסריטי end-to-end משולבים — להריץ בנוסף למטריצה

### E2E-A — שחזור ותיקון התקנת החבילות שסופקו

התחל ב־app data של fixture ללא Skills מותקנים. בחר את pack הישן ב־Files, הרץ import, ותעד root cause מדויק לפני התיקון. חזור עם FIXED pack. לאחר תיקון הרץ שניהם מתחילת ההתקנה. ודא שכל עשרת פריטי הבסיס קיימים ושאף אחד לא איבד preferredToolIDs/triggerHints עקב תאריך. הפעל relaunch, פתח Code Skill וקרא resource. ההצלחה נמדדת באמצעות הקטלוג וה־tool execution, לא באמצעות הודעת “installed”.

### E2E-B — Skill -> Package -> Python -> Node -> Shell

בקש מה־provider בפרופיל הבדיקה:
“השתמש בסביבה המקומית. התקן את חבילת Python של הבדיקה, חשב בעזרתה 42, שמור JSON, קרא אותו ב־Node, ולאחר מכן הצג את הקובץ בטרמינל.”

ה־trace חייב להציג טעינת Skill מתאים, package tool אמיתי, Python execution, Node execution ו־shell invocation באותו context. כל פלט נבדק מול `{"answer":42}`. אין remote fallback. בצע relaunch והרצה חוזרת ללא התקנה מיותרת. package disabled או OS error לא יוסתרו.

### E2E-C — Tool discovery עם קטלוג גדול

הפעל fixture catalog עם 150 כלים ממקורות שונים, כולל שני providers בעלי local tool name זהה. אינדקס Skills יהיה קומפקטי. בקש tool אחד המופיע בעמוד מאוחר. המודל חייב לקבל דרך למצוא אותו; הסכמה הנכונה נחשפת ורק ה־provider המתאים נקרא. לאחר מכן בטל tool group בפרופיל הבדיקה והתחל run חדש: לא נשארת חשיפה ישנה.

### E2E-D — הרשאות OS אמיתיות בלי Hanlin prompts כפולים

על device בדיקתי, הפעל Skill Calendar/Location/Health. עבור מצב notDetermined, פעולה תגיע לבקשת המערכת הרגילה. עבור denied, התוצאה תהיה OS-denied. לאחר שינוי הרשאת המערכת, פעולה חדשה תעבוד בלי reset או הענקת Hanlin grants נוספת. נקה רק records שהבדיקה עצמה יצרה.

### E2E-E — imported Script/MiniApp וכלי שלו

ייבא fixture רב־קבצי עם bare dependency זמין, metadata Skill ומשאב binary. פתח UI, invoke tool דרך agent, קבל embedded result, עדכן source, relaunch והפעל שוב. צריך להוכיח שזה generation החדש. נסה אותה פעולה עם native provider חסר: אין crash ואין “עובד”, אלא item ספציפי ב־remaining limitations.

### E2E-F — ריצה ארוכה, תוצאה גדולה וביטול

בתסריט bounded, הרץ יותר מ־30 שניות והפק result גדול מה־caps הישנים. קבל reference, קרא את תחילת/סוף התוצאה והוכח hash מלא. בהרצה נוספת בטל באמצע ושגר מיד בקשה קטנה. אין stuck spinner, אין zombie result, אין package/store corruption, ואין “cancel succeeded” בזמן שהפעולה ממשיכה להחזיר side effects.

לכל E2E צור מזהה בדיקה נוסף בדוח (`E2E-A`–`E2E-F`) ושמור את כל מזהי תתי־הקריאות וראיות המטריצה שבהן השתמש.

---

### E2E-G — One modern agent path: chat -> Skill -> tool -> result -> rich UI

Start from a clean request-scoped capability session with only meta-tools initially visible. Send a user prompt asking for a task that requires a hidden domain tool and produces a rich `NativeUIBlock`/evidence result. The trace must show: model receives compact Skill index -> `load_skill` or `tool_search` -> correct canonical tool becomes visible on the next Swift AI SDK step -> tool executes once -> result returns through Swift AI SDK -> final answer streams -> rich Hanlin content renders in the same assistant turn. Assert that the old manual APIManager tool recursion is never entered.

### E2E-H — Local developer workflow across package managers and runtimes

Prompt the agent: `Work locally. Install the Python test dependency, produce {"python":42}, install/use the Node test dependency to add {"node":42}, read the JSON in TypeScript, and inspect the final file with the terminal.` Use deterministic safe fixture packages where registry/network independence is needed, then one real registry acceptance. The run must use canonical package tools, Python, Node/TypeScript and ios_system in one coherent workspace. Relaunch and prove packages remain installed. No Hanlin policy message may substitute for an actual runtime/platform result.

### E2E-I — MCP official SDK over embedded Node plus agent tool loop

Install the pinned MCP `server-everything` acceptance package, start it in embedded Node, connect via the official MCP Swift SDK transport, list tools, publish them into canonical authority, start a new agent run, discover an MCP tool through Skill/tool search, invoke it, return the output to Swift AI SDK, and finish the answer. Trigger tool-list-changed and prove refresh. Stop/restart server and invoke again. No parallel MCP protocol implementation may participate.

### E2E-J — Four app/runtime families from one Apps Hub

Install/prepare fixtures for: Swift MiniApp, ScriptUI app, NativeScript app, Expo app. Launch each from Apps Hub, exercise one visible UI interaction, invoke one host service, and where supported publish/invoke one assistant tool. Close and reopen. The test passes only if all four remain distinct runtime identities while sharing the intended common Hanlin services/catalog surface.

### E2E-K — Current rich chat regression parity (no UI migration)

Using a deterministic saved conversation fixture, render a transcript that contains: user text + photo/document; assistant streaming Markdown; surfaced reasoning summary; two tool calls; evidence/resources; code result; map/route; calendar event; health card; knowledge card; HTML preview; canvas; audio; `NativeUIBlock`; AgentActivity inspector; MiniApp launch action. Capture baseline semantic and interaction assertions before backend/runtime migrations and rerun the exact same assertions afterward. **The chat UI itself must not migrate or change framework/chrome in this assignment.**

### E2E-L — Platform/dependency modernization on Xcode 27/iPadOS 27

On exact saved commit, use stable Xcode 27. Resolve packages, build HanlinPlatform tests, build simulator/device targets, launch iPadOS 27 simulator, run affected unit/UI suites, build runtime bundle with chosen updated Python/ios_system/QuickJS inputs, run ScriptUI/NativeScript/Expo E2E, and produce unsigned IPA. If signed device access exists, run the same commit on iPadOS 27. Record Xcode build number, Swift version, SDK version, commit SHA, runtime dependency hash and IPA SHA.

### E2E-M — Cold relaunch restoration across the whole extensibility stack

Before termination install: at least one custom Skill, one Python package, one npm package, one MCP server, one Script app and one MiniApp selection/state item. Execute each once. Kill the app fully and relaunch. Assert persistent installations/registries restore, MCP/Script/MiniApp tools republish when appropriate, request-scoped `exposedToolAliases` does **not** restore, and the first new agent request starts with the correct progressive disclosure state.

### E2E-N — Cancellation/concurrency under the SDK-first architecture

Begin a long provider generation that invokes a long tool/runtime operation. Cancel while tool work is active. Immediately start a second request that calls a different quick tool. Assert old Swift AI SDK stream, tool activity, diagnostics and UI settle as cancelled; the old call cannot append text/results into the new turn; second request completes normally; runtime/package stores remain usable. Repeat while an MCP tool is active and while Python is active.

### E2E-O — Existing Hanlin chat UI full acceptance after backend/runtime consolidation

Launch a saved mixed conversation in the **existing Hanlin chat UI** and send a new request using the existing composer. The run must cover: model selection; prompt/document/photo attachment; MCP/tool/search/knowledge/reasoning controls; streaming text; surfaced reasoning; at least two tool calls; cancellation; and final rich results containing evidence, code, map/route, health/event/canvas and a `NativeUIBlock`. Prove that backend consolidation did not change the visible/interactive chat contract. Record the chat-file diff and confirm that no third-party chat UI dependency or migration was introduced.

### E2E-P — Apple local provider alongside GGUF

On a capable iOS 27 device, run the same short conversational prompt once through Apple `SystemLanguageModel` and once through the existing GGUF/LLM.swift provider. Verify both appear in the same Hanlin chat surface, stream/cancel independently, preserve provider identity and do not change Skills/canonical tool ownership. If Foundation Models tool bridging is enabled, invoke one deterministic Hanlin tool and prove it executes through canonical authority exactly once. If not yet supported, the Apple provider must explicitly advertise text/multimodal-only rather than starting a second tool engine.

### E2E-Q — Core AI coexistence and cold relaunch

When a redistributable Core AI model fixture is available, install/bundle it, load/specialize it, stream one prompt, kill/relaunch Hanlin, perform a warm load and prompt again, then run an existing GGUF model and a remote Swift AI SDK model. All three provider families must coexist without persistence or runtime registry corruption. If no lawful fixture is supplied, report `BLOCKED_INPUT_MODEL_FIXTURE` with all compile/unit adapter tests still executed.



## 7. פקודות ואסטרטגיית הרצה לסוכן

הפקודות הבאות הן נקודות התחלה שמבוססות על מבנה הענף שנבדק. קרא את `Package.swift`, `package.json`, schemes ואת workflow inputs בפועל לפני הרצה. אם HEAD התקדם ושם השתנה, עדכן את invocation ורשום את ההבדל; אל תמציא success.

### 7.1 בדיקות מקומיות

```bash
git status --short
git branch --show-current
git rev-parse HEAD
git remote -v

# On a host that supports the package targets:
swift test --package-path Packages/HanlinPlatform

# Use the pinned Node host package and its actual package.json scripts:
cd AI_HLY/Downstream/RuntimeCore/Node/Host
npm ci
npm test
npm run test:integration
```

הרץ קודם fixtures מקומיים דטרמיניסטיים; אחר כך registry-backed tests. אל תחליף import probe אמיתי ב־Node test על מחשב Windows ותטען שנבדק NodeMobile במכשיר. תוצאת Swift על Linux/Windows אינה מוכיחה שימוש ב־Apple frameworks.

קבוצות קיימות שצריך למצוא ולשלב, ולא להחליף ב־suite מבודדת בלבד:
`AI_HLYTests/AgentSkillsExposureTests.swift`,
`AgentRuntimeConversationAcceptanceTests.swift`,
`RuntimePackageAcceptanceTests.swift`,
`HanlinUnifiedHostServicesAgentAcceptanceTests.swift`,
`AI_HLYUITests/HanlinRuntimeCommandAcceptanceUITests.swift`,
`Packages/HanlinPlatform/Tests/HanlinScriptCompilerTests/HanlinArchivePolicyTests.swift`,
Node `Tests/compatibility.test.mjs`, `runtime.test.mjs`, `host.test.mjs` ו־integration tests,
וכן Python source/workflow tests ב־`Scripts/Runtime/Tests` וב־`Scripts/CI/Tests`.

אל תסיק ששמות המתודות קיימים; גלה אותם מהקוד. הסף לסגירה הוא התרחישים לעיל, לא היצמדות לשם test file.

### 7.2 Apple compilation ו־Simulator

המשתמש עובד מ־Windows. השתמש בתשתית `davidpovarsky/apple-devtools` המותקנת אצלו וב־macOS authority layer אם זמינה, או ב־workflow הידני הקיים. אין לטעון שקיים Xcode מקומי במחשב Windows.

בדוק SDK/toolchain מתוך הפרויקט וה־runner. **This MASTER assignment explicitly includes migration to stable Xcode 27 / iOS 27 as described in MASTER-5.** Use stable, not beta, and record the exact Xcode/Swift/SDK versions. דוגמת shell על macOS לאחר שהסוכן פתר את משתני הסביבה לערכים אמיתיים:

```bash
xcodebuild \
  -project AI_HLY.xcodeproj \
  -scheme AI_HLY \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${SIMULATOR_UDID}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -resultBundlePath "${BUILD_RESULTS}" \
  build-for-testing

xcodebuild \
  -project AI_HLY.xcodeproj \
  -scheme AI_HLY \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${SIMULATOR_UDID}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -resultBundlePath "${TEST_RESULTS}" \
  test-without-building
```

`SIMULATOR_UDID`, `DERIVED_DATA`, `BUILD_RESULTS`, `TEST_RESULTS` הם משתנים שעל הסוכן לפתור, לא placeholders להשאיר לבעלים. השתמש `-only-testing` עבור סבבי תיקון ממוקדים, ואז הרץ regression רלוונטי מלא. אין להשתמש באותו resultBundlePath לכתיבה על bundle שכבר קיים.

### 7.3 GitHub Actions ידניים, אם נבחר מסלול זה

התחל מה־workflow הקיים `.github/workflows/build-ios26-unsigned-ipa.yml` ומה־affected-validation map, אך במסגרת MASTER-5 יש למודרנו ל־Xcode 27/iOS 27 ולשנות שם/תצוגה לאחר שהמסלול החדש עבר. בזמן הכנת המסמך נמצאו inputs כגון `full_validation`, `target_validation_group` ו־`testflight_upload`; אמת אותם מול HEAD ושמור את הסמנטיקה שלהם.

הפעל רק את הענף הנכון, עם `testflight_upload=false`, ועל commit שנשמר. אין להוסיף push/pull_request/schedule triggers. ניתן להתחיל בבדיקה ממוקדת ולסיים full affected validation במקום להריץ build שלם אחרי כל שורה.

לאחר dispatch, פתור run ID אחד ושמור אותו. השתמש ב־watcher אחד:

```bash
gh run watch "${RUN_ID}" --exit-status --compact --interval 30
```

אם CLI מותקן אינו תומך ב־flag מסוים, השתמש בגרסה הנתמכת שלו תוך שמירה על `--exit-status` ו־watch יחיד. אחרי היציאה משוך metadata/logs/artifacts פעם אחת. אל תממש polling חוזר בתורות מודל.

### 7.4 Device ו־provider

ארוז את אותה גרסה שנבדקה, הצג SHA של commit ושל IPA, והשתמש במכשיר בדיקתי אם נגיש. אם אין device לסוכן, הפק הוראות tap-by-tap ותסריטי prompt עבור הפריטים המסומנים D; רשום `NOT_RUN` במפורש.

לבדיקות ספק השתמש רק בהגדרה/credentials קיימים ומורשים. הלוג המקורי מציין OPENROUTER ומודל `nvidia/nemotron-3-ultra-550b-a55b:free_repeat_OPENROUTER`, אך אל תניח שזו עדיין אפשרות זמינה: קרא את בחירת המודל הנוכחית. alias פנימי ומודל ספק אינם בהכרח אותה מחרוזת. תעד אותם בנפרד, בלי להדפיס API key. חוסר מודל/מכסה/רשת אינו הצלחה ואינו סיבה לדלג על הבדיקות הדטרמיניסטיות.

---

## 8. דוח הסיום שהסוכן חייב להחזיר

הדוח יהיה קצר ביחס לחומר המלא, אבל יכלול קישורים לקבצי הראיות:

1. Branch ו־final commit SHA; מצב working tree; SHA שנבדק ו־SHA שנארז.
2. סיבת השורש המשוחזרת של ZIP import והראיה, כולל root/wrapper המקוריים. אל תייחס אותה ל־containment רק מתוך טקסט השגיאה.
3. תיקון codec התאריכים והוכחה שה־preferredToolIDs/triggerHints שרדו עד request הספק.
4. רשימת gates/scanners שהוסרו, ומגבלות שנשארו עם סיבה טכנית נקודתית.
5. כל Agent package tools שנוספו ואיפה הם נרשמים; כל Skills וחבילות import שנוצרו.
6. מספר הכלים בפועל לפי מקור, מספר הכלים שנבדקו, וכלי שאין לו בדיקה.
7. מספרי PASS/FAIL/BLOCKED/NOT_RUN לפי שכבה, ובפרט D/P.
8. נתיבי test results/logs/xcresult, חבילת Skills, IPA אם נבנה, ו־architecture/dependency migration report (former upstream touchpoints may be listed only as historical provenance, not as a constraint).
9. Known limitations אמיתיות והפעולה המדויקת הנדרשת להשלמה — לא “הכול מושלם” כאשר משהו לא רץ.

בדיקה שציפתה ל־`platformUnsupported` ועברה מוכיחה **טיפול נכון בחוסר תמיכה**, לא תמיכה ביכולת. שמור את ההבדל בדוח.

### MASTER additions to the final report

In addition to the report items above, include:

- the before/after architecture diagram and production call path for remote agent execution;
- exact legacy AI/provider/tool-loop files/symbols deleted and the parity tests that justified deletion;
- direct/transitive dependency inventory, version changes, licenses and why each new dependency was adopted;
- Swift AI SDK fork delta versus upstream after synchronization;
- exact MCP SDK version and proof that only one MCP protocol stack remains;
- chat UI freeze compliance: list every chat-UI file touched (preferably none), the exact compatibility reason for each change, and proof that no third-party chat UI dependency/migration was introduced;
- proof that the existing Hanlin chat surface, composer, rich-result rendering and persistence behavior remain unchanged after backend/runtime consolidation;
- Xcode/Swift/iOS SDK/deployment-target versions after modernization;
- runtime dependency versions/hashes after Python/ios_system/QuickJS/Node validation;
- before/after LOC by subsystem excluding generated/vendor baselines, and app/runtime bundle size deltas;
- all MASTER capability-invariant IDs mapped to concrete PASS/FAIL/BLOCKED/NOT_RUN evidence.

### תנאי סיום שאסור לעקוף

- אין R או test ID ללא disposition.
- אין tool production בלי inventory, Skill/discovery ובדיקת executor.
- אין “הגנה” שהוסרה ממקום אחד ונשארה במסלול חלופי או במשאב runtime ארוז.
- אין successful import שמוחק metadata.
- אין “התקנת package” שבוצעה רק במחשב הפיתוח.
- אין success כאשר stdout/stderr/exit/semantic outcome מעידים על כשל.
- אין device/provider claim מתוך mock או simulator.
- אין hardcoded intent router במקום Skills.
- אין שינוי ב־main או publication בלי אישור נפרד.
- אין דרישה לבעלים לעבור על עוד סדרת שלבים כדי שתבצע את המשימה שכבר הוגדרה כאן.

**בצע עכשיו את כל המשימה לפי המסמך, עם מיפוי מלא וראיות, ואל תעצור לאחר תיקון ה־ZIP בלבד.**

---

## 9. מקורות וייחוס לצורך הביצוע

### 9.1 מקורות הריפו

כל הנתיבים לעיל מתייחסים ל־`davidpovarsky/hanlin-ai` ב־SHA הבסיס שנרשם בראש המסמך, אלא אם ה־HEAD התקדם והסוכן תיעד זאת.

- [Branch source](https://github.com/davidpovarsky/hanlin-ai/tree/codex/agent-skills-embedded-results)
- [SkillImporter — extraction, metadata decoding and containment](https://github.com/davidpovarsky/hanlin-ai/blob/89068b77d8a752a5a3d5c9b7dc48735f665245ec/AI_HLY/Downstream/AgentSkills/SkillImporter.swift)
- [SkillStore — descriptor persistence and metadata loading](https://github.com/davidpovarsky/hanlin-ai/blob/89068b77d8a752a5a3d5c9b7dc48735f665245ec/AI_HLY/Downstream/AgentSkills/SkillStore.swift)
- [HanlinPackageCenter — existing path handling](https://github.com/davidpovarsky/hanlin-ai/blob/89068b77d8a752a5a3d5c9b7dc48735f665245ec/Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinPackageCenter.swift)
- [HanlinArchivePolicy — archive rules and normalization](https://github.com/davidpovarsky/hanlin-ai/blob/89068b77d8a752a5a3d5c9b7dc48735f665245ec/Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinArchivePolicy.swift)
- [SystemSkillsProvider — built-in instructions and hints](https://github.com/davidpovarsky/hanlin-ai/blob/89068b77d8a752a5a3d5c9b7dc48735f665245ec/AI_HLY/Downstream/AgentSkills/SystemSkillsProvider.swift)
- [Legacy tool schemas](https://github.com/davidpovarsky/hanlin-ai/blob/89068b77d8a752a5a3d5c9b7dc48735f665245ec/AI_HLY/Services/ChatServices/ChatTools.swift)
- [RuntimeCore](https://github.com/davidpovarsky/hanlin-ai/tree/89068b77d8a752a5a3d5c9b7dc48735f665245ec/AI_HLY/Downstream/RuntimeCore)
- [IOSSystemRunner](https://github.com/davidpovarsky/hanlin-ai/blob/89068b77d8a752a5a3d5c9b7dc48735f665245ec/Packages/IOSSystemLite/Sources/IOSSystemLite/IOSSystemRunner.swift)
- [Native Sefaria tools](https://github.com/davidpovarsky/hanlin-ai/blob/89068b77d8a752a5a3d5c9b7dc48735f665245ec/AI_HLY/NativeAppPlatform/BuiltinApps/Sefaria/Assistant/NativeAppSefariaTools.swift)
- [Native Wikipedia tools](https://github.com/davidpovarsky/hanlin-ai/blob/89068b77d8a752a5a3d5c9b7dc48735f665245ec/AI_HLY/NativeAppPlatform/BuiltinApps/Wikipedia/Assistant/NativeAppWikipediaTools.swift)
- [Native Text Studio tools](https://github.com/davidpovarsky/hanlin-ai/blob/89068b77d8a752a5a3d5c9b7dc48735f665245ec/AI_HLY/NativeAppPlatform/BuiltinApps/TextStudio/Assistant/NativeAppTextStudioTools.swift)

### 9.2 הקבצים שסופקו בשיחה

- `Hanlin-Skills-Pack.zip` — SHA-256:
  `6a72f690be661de53d38ae636d145a45a506229b5773afedca40c36c582a9ca9`.
- `Hanlin-Skills-Pack-FIXED.zip` — SHA-256:
  `7e4ec83b4eff180c830849ed35f0c1e36b13ed578f7983251e34626ea4c315a7`.
- `ארכיון 7.zip` — לוגי השיחה והריצות שנזכרו בסעיף 1.
- צילומי שתי שגיאות ה־import.

קובץ שקיים בשיחת ChatGPT אינו מופיע אוטומטית בריפו/בסביבת הסוכן. בדוק אם צורף/הועלה שם. כאשר הוא אינו זמין, השתמש ב־fixtures המתוארים כאן והותר את בדיקת bytes המקוריים כ־BLOCKED_INPUT; אין לטעון שבדקת אותם.

### 9.3 מקורות חיצוניים ששימשו לתיקוני הדיוק

- [Python PEP 730 — iOS support, POSIX/process limitations](https://peps.python.org/pep-0730/). משמש לסיבה שלא לבצע fork/spawn בלתי נתמכים בתוך תהליך המשתמש ולהניח שתמיד ייזרק exception.
- [ios_system — upstream integration and available command model](https://github.com/holzschu/ios_system). משמש להבחנה בין command dictionary/linked implementation לבין shell מלא; בדוק את הגרסה המוטמעת בפועל.
- [Apple — NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking). משמש להבחנה בין מדיניות HTTP של Hanlin לבין הגדרות מערכת במסלול Apple הרלוונטי.

המקורות החיצוניים אינם טענה שה־SDK הספציפי של ה־IPA נבדק. במקרה של פרט API/ABI, השתמש ב־SDK/compiler של סביבת Apple בפועל ובתסריט integration מתאים.

### 9.4 MASTER research sources and version/licensing evidence (2026-10-04)

These links are research inputs, not permission to upgrade blindly. Re-check chosen tags/releases at implementation time and record the exact resolved revision.

- Swift AI SDK upstream: https://github.com/teunlao/swift-ai-sdk — research baseline latest stable `v0.19.0`; Apache-2.0. Hanlin currently uses `https://github.com/davidpovarsky/swift-ai-sdk` as a patch fork.
- Official MCP Swift SDK: https://github.com/modelcontextprotocol/swift-sdk — research baseline latest stable `0.12.1`; already used by Hanlin.
- Apple Foundation Models updates: https://developer.apple.com/documentation/updates/foundationmodels — iOS 27 adds updated SystemLanguageModel, dynamic profiles/multimodal capabilities, and `LanguageModel` provider abstraction.
- Apple iOS 27 overview: https://developer.apple.com/ios/whats-new/ — Foundation Models supports Apple/on-device/cloud/custom providers conforming to `LanguageModel`.
- Apple Core AI: https://developer.apple.com/documentation/coreai/ and https://developer.apple.com/documentation/foundationmodels/running-a-core-ai-model-in-a-foundation-models-session — `.aimodel`, device specialization, and `CoreAILanguageModel` integration with Foundation Models.
- GRDB: https://github.com/groue/GRDB.swift — research baseline `v7.11.1`; MIT; strong SQLite candidate only if it reduces Hanlin bridge complexity.
- Yams: https://github.com/jpsim/Yams — research baseline `6.2.2`; MIT; candidate for standards-correct Skill YAML frontmatter.
- swift-markdown: https://github.com/swiftlang/swift-markdown — research baseline `0.9.0`; official Swift project; optional structured Markdown parser.
- Runestone: https://github.com/simonbs/Runestone — research baseline `0.5.2`; MIT; optional code editor candidate.
- QuickJS-NG: https://github.com/quickjs-ng/quickjs — research baseline `v0.17.0`; MIT. Hanlin currently vendors `v0.16.1` with a small allocator patch.
- BeeWare Python Apple support: https://github.com/beeware/Python-Apple-support — research baseline `3.14-b11`; Hanlin lock currently used `3.14-b10`.
- ios_system: https://github.com/holzschu/ios_system — research baseline `v3.0.7`; Hanlin lock currently used `v3.0.5`.
- Node.js Mobile upstream: https://github.com/nodejs-mobile/nodejs-mobile — public latest release metadata is older than Hanlin's verified Node 24.5.0 mobile fork. Do not downgrade based on release badge alone.
- Hanlin Node fork source recorded in runtime lock: https://github.com/heylogin/nodejs-mobile
- NativeScript core: https://github.com/NativeScript/NativeScript — research baseline core release `9.1.2-core`; Hanlin iOS runtime currently pins `https://github.com/NativeScript/ios-spm.git` exact `9.1.0`, and a matching `ios-spm` 9.1.2 ref was not verified during research. Keep matched runtime/core closure.
- Expo stable/beta evidence: https://expo.dev/changelog/sdk-58-beta and https://expo.dev/changelog/sdk-57 — on 2026-10-04 SDK 58 was still beta with RN 0.88 RC; SDK 57 was stable, and Expo documents `expo@57.0.23` opt-in scene lifecycle support for Xcode 27/iOS 27. Re-check at implementation time and use only the newest stable closure.
- MarkdownUI: https://github.com/gonzalezreal/swift-markdown-ui — research baseline 2.4.1; already used.
- SWCompression: https://github.com/tsolomko/SWCompression — research baseline 4.9.1.
- SwiftSoup: https://github.com/scinfu/SwiftSoup — research baseline 2.13.9.
- ZIPFoundation: https://github.com/weichsel/ZIPFoundation — research baseline 0.9.20.
- RichTextKit: https://github.com/danielsaidi/RichTextKit — already used; keep while required.
- LaTeXSwiftUI: https://github.com/colinc86/LaTeXSwiftUI — research baseline 2.0.0; major migration from project 1.5.0.
- LLM.swift: https://github.com/eastriverlee/LLM.swift — research baseline 3.0.3; major migration from project 1.8.0.
- MLX Swift: https://github.com/ml-explore/mlx-swift and https://github.com/ml-explore/mlx-swift-lm — optional future local inference engine, not part of mandatory replacement.
- Apple swift-log: https://github.com/apple/swift-log — research baseline 1.15.1.
- Apple Swift Collections: https://github.com/apple/swift-collections — research baseline 1.7.1; keep transitive unless directly needed.
- Apple Swift Atomics: https://github.com/apple/swift-atomics — research baseline 1.3.1; keep transitive unless directly needed.
- Apple stable release evidence: https://developer.apple.com/news/releases/ — stable Xcode 27 (`27A266a`) and iOS/iPadOS 27 released 2026-09-14; later 27.x entries observed during research were beta while Xcode 27 remained stable. Xcode 27 release notes state Swift 6.4 and iOS 27 SDK.

### 9.5 Candidates explicitly evaluated and **not** selected as core replacements

- ManifoldKit: comprehensive full-stack AI framework, but overlaps the very layers Hanlin intentionally owns (agent loop, persistence, MCP, backends, RAG). Do not add a second full-stack architecture.
- Small/experimental ChatGPT UI packages: insufficient reason to replace Hanlin's richer product surface.
- Highlightr: do not introduce if upstream remains unmaintained; use current rendering or a maintained editor/highlighter evaluated with real fixtures.
- Mobile Forge: do not make it the Python 3.14 package strategy; current BeeWare/Python ecosystem must be evaluated against modern upstream tooling instead.



---

סוף המסמך.
