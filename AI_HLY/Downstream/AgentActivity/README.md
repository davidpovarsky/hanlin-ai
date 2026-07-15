# Hanlin Agent Activity Runtime

This directory is the downstream-owned normalization and presentation layer for one assistant run. It deliberately keeps provider and product customizations out of the upstream chat model and views except for narrow integration points.

## Architecture

The runtime follows this path:

`provider stream → StreamData → HanlinStreamEventAdapter → AgentEvent → AgentRunCoordinator → AgentEventAccumulator → AgentRun → SwiftUI timeline`

`ChatView` creates exactly one coordinator for an assistant group. Recursive model requests and every tool used by that group feed the same run. Views receive a persisted `AgentRun`; they never parse provider JSON.

## AgentEvent protocol

`AgentEvent` describes run, visible reasoning, progress, tool-call, tool-execution, search, final-answer, failure, and cancellation transitions. External call IDs are retained. Deltas update existing items, so streaming does not create one persisted step per token. Events are ignored after the run leaves the running state, which prevents an old request from mutating a later retry.

## Provider adapters and capabilities

The current remote transport in `APIManager` is OpenAI-compatible for every configured cloud provider. `HanlinStreamEventAdapter` normalizes its `StreamData` output. Local LLM requests remain answer-only because the repository does not expose a verified structured native-tool protocol for them.

`ProviderCapabilities` derives detailed behavior from the existing `AllModels` flags and provider identity. Tool schemas and `report_progress` are only sent when native tool calling is enabled. Visible reasoning is recorded only from explicit provider reasoning fields or the existing visible-thinking stream; the runtime never synthesizes chain-of-thought.

When adding a provider, keep its wire parsing in its transport adapter and emit the existing `AgentEvent` cases. Do not add provider JSON parsing to a view.

## `progress_summary`

`ToolSchemaDecorator` adds the flat `progress_summary` property at the central tool-list boundary. It supports OpenAI-compatible `function.parameters`, Anthropic-style `input_schema`, and Gemini-style top-level `parameters` shapes without changing existing names, descriptions, properties, or required fields.

The value is optional inside Swift. `ToolProgressSummary` removes it before legacy or Native tool decoding and retains the original and sanitized JSON separately in `AgentToolCall`. `ProgressSummarySanitizer` trims and folds whitespace, limits length, and rejects empty text, raw JSON, URLs, credential-like material, system-prompt text, and internal-policy text.

## `report_progress`

`report_progress` is a virtual schema appended after real tools. It is never registered with or executed by `NativeToolCatalog`. `APIManager` converts it directly into a progress event and returns `Progress update delivered.` to the model. `ReportProgressController` rejects empty, duplicate, rapid, excessive, and latest-tool-summary-equivalent updates.

## Tool execution lifecycle

A completed structured tool request becomes a tool-call step and a separate execution step. The tool receives only sanitized arguments. Execution completion records safe user/model output, duration, and `NativeUIBlock` results. Native tools continue to use the existing enabled-state checks, locale, redacted tracing, result model, and actions.

To add a tool, register or build it through the existing catalog/tool-list path. Give it a canonical structured schema. The central decorator and argument separator then apply automatically. Add a deterministic mapping to `ToolPresentationRegistry` when the generic “Using a tool” presentation is insufficient.

## Persistence and legacy history

`ChatMessages` owns one optional `agentRunJSON` field. Encoding and decoding live in `AgentActivityPersistence.swift`; malformed, missing, or unsupported data returns `nil` without crashing. The first assistant message in a group owns the run. Existing `nativeUIBlocksJSON` remains unchanged.

When stored activity is absent, `LegacyAgentActivityAdapter` builds a display-only timeline from reasoning, tool output, sources, documents, code, and Native UI blocks. It never writes a migration during rendering and does not claim that legacy ordering is exact.

## UI

`AgentActivitySummaryView` displays a compact running/completed/failed/cancelled state and up to four recent steps. Its inspector uses a `NavigationStack`, medium/large sheet detents, a vertical timeline, disclosure groups, selectable input/output, query chips, sources, and the existing expanded `NativeUIRenderer`. When an `AgentRun` is present, the old reasoning, tool-content, and operational loaders are suppressed.

The views use localized strings, leading alignment, Dynamic Type fonts, non-color status symbols, VoiceOver labels/values, selectable long content, and Reduce Motion awareness.

## Security

Model progress text is untrusted. It is sanitized before display, never forwarded to a real tool, and is not added to tracing. Tool errors pass through `AgentSafeError`, which redacts common secret/token forms and limits displayed length. Raw provider or arguments JSON is not rendered by the activity UI.

## Merge risks

New behavior is isolated here. The unavoidable upstream edits are limited to:

- one optional persistence property in `ChatMessages`;
- event metadata on `StreamData` and central request/tool lifecycle hooks in `APIManager`;
- coordinator ownership in `ChatView`;
- one activity input and duplicate-UI guards in `ChatBubbleView`;
- schema decoration and defensive argument sanitization in `NativeToolBridge`;
- localized catalog entries.

The largest remaining merge risk is `APIManager.swift`, whose existing monolithic tool switch is an upstream-owned hotspot. The activity runtime avoids copying that switch and wraps only its common entry and exit points.

## Verification boundary

This implementation was prepared on Windows. No Xcode SDK build, compiler diagnostic pass, simulator/device run, SwiftData/CloudKit migration test, VoiceOver device test, RTL screenshot review, cancellation stress test, or provider live request was performed here. CI is intentionally not run unless explicitly requested.
