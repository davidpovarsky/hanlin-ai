# Hanlin Agent Activity Runtime

This downstream-owned layer normalizes one provider run into functional activity state and a chronological chat transcript. It keeps the customization isolated from the upstream `CherryHQ/hanlin-ai` chat implementation except for narrow stream, persistence, and rendering bridges.

## Runtime path

`provider stream → StreamData → HanlinStreamEventAdapter → AgentEvent → AgentRunCoordinator → AgentEventAccumulator → AgentRun → AgentRunTranscriptView`

`ChatView` creates one coordinator per assistant group. Recursive model rounds and tool executions feed that same run. During streaming, the current `AgentRun` stays in view state; it is persisted on completion, failure, or cancellation rather than writing the full transcript for every token.

## Steps and transcript items

`AgentRun.steps` remains the functional and diagnostic activity state used to compose the Thinking inspector. `AgentRun.transcriptItems` is the source of truth for chat ordering. Both are retained because a tool call/execution lifecycle may be composed into one display activity while the transcript must also place assistant text and user-visible results precisely between activities.

Every transcript item receives a monotonically increasing `sequence` from one counter. Timestamps are metadata and never determine ordering. Stable item IDs and in-place delta updates prevent one item per token and avoid regenerating identities during SwiftUI rendering.

Schema version 2 persists transcript items. Version 1 runs decode with an empty transcript and continue through the legacy display path. Malformed or unsupported run JSON returns no modern run and cannot crash chat history. Rendering legacy history never writes an automatic migration.

## Assistant text segmentation

`HanlinStreamEventAdapter` creates a new assistant text segment when content arrives without an active segment. Reasoning, progress, search, source work, or tool activity closes the preceding segment as `interim`; it remains visible while the run is live and collapses into Thinking afterward. At normal completion, the last non-empty active segment becomes `final`. `AgentRun.finalAnswer` is derived only from that final segment, never from the concatenation of interim narration.

Failed and cancelled runs close active segments without promoting partial text to a final answer. Retry creates a new group, run ID, adapter, and transcript; the earlier run remains persisted and cannot be mutated by later events.

## Tool activity versus user-visible result

A tool activity is lightweight process state: call ID, title, sanitized arguments, progress summary, status, duration, safe output preview, source count/list, and error summary. It collapses into Thinking and never renders a `NativeUIBlock`.

A user-visible tool result is a separate `userVisibleToolResult` transcript item created only when execution returns non-empty `NativeUIBlock` values. It receives the next transcript sequence and remains in chat after completion. Deduplication uses the call ID plus stable block IDs. Raw model tool output is not promoted to chat UI.

`AgentActivityStep.richResultBlocks` remains only for schema compatibility and raw persistence. `AgentDisplayActivity`, `AgentActivityStepView`, and `AgentActivityInspectorView` do not carry or render those blocks. The modern transcript result view is the only modern chat path that invokes `NativeUIToolResultContainer`.

Legacy map, calendar, health, code, knowledge, HTML, canvas, and other existing result fields stay connected to their original `ChatMessages` split. For a modern run, transcript-owned text, reasoning, tool content, and Native UI are suppressed in those split messages while legacy result views remain available.

## Group ownership and split markers

The first assistant message in a continuous group is the transcript owner. `ChatView` passes explicit `isAgentTranscriptOwner` and `isRenderedByAgentTranscript` flags. The owner renders `AgentRunTranscriptView` once; later `splitMarker` messages cannot render transcript text or Native UI again. Version 1 history continues through the legacy bubble path.

## Live and completed presentation

While running, transcript items render by sequence: visible reasoning/activity rows, narrative progress, interim assistant Markdown, user-visible result cards, and later assistant segments. Selecting an activity never expands the chat layout; it opens the run's single Thinking sheet.

After completion, reasoning, progress, tool activity, and interim assistant text collapse into one localized `Worked for …` row. The row opens the same sheet. User-visible result items and the final assistant segment remain in sequence below it. Runs with only an immediate final answer do not show an empty work summary.

The inspector receives an optional selected activity ID, uses `ScrollViewReader`, scrolls to the matching transcript item, and applies a subtle highlight. It limits queries to 8 and sources to 10 until `Show more` is selected. It never instantiates Native UI, maps, HTML, web views, or full search-result renderers.

## Adding a tool

1. Register the tool through the existing catalog/tool-list path and provide its structured schema.
2. Keep provider wire parsing in the provider/transport adapter and emit the existing tool lifecycle events.
3. Add a deterministic semantic title/icon mapping in `ToolPresentationRegistry` when the generic mapping is insufficient.
4. Return `NativeUIBlock` values only when the result is intentionally visible and actionable for the user.
5. Keep model-only output in `modelText`; a safe short process summary may be placed in `userText`, but `userText` alone does not create a chat result card.
6. Give blocks stable IDs so retry and duplicate delivery can be suppressed safely.

## Diagnostics and privacy

When full local diagnostics are enabled, the runtime traces transcript creation/completion, interim/final classification, visible-result insertion/deduplication, and inspector selection/open/scroll/close. Trace fields contain IDs, kinds, sequence, and status only. Hidden reasoning, transcript text, arguments, results, credentials, and secrets are not logged by these events.

## Performance rules

- No inline activity expansion in the chat scroll view.
- No `NativeUIRenderer` in activity rows or Thinking.
- No rich-result composition in `AgentActivityComposer`.
- No per-row sheet and no mutation of `AgentRun` from a view.
- No assistant-message ID churn to force a refresh.
- No explicit persistence write per streamed token.
- No horizontal nested activity scroller or large insertion animation.
- Stable transcript and source IDs drive every `ForEach`.

## Upstream merge surface

New models, accumulation, composition, inspector UI, diagnostics hooks, and transcript views live under `AI_HLY/Downstream/AgentActivity`. The unavoidable upstream-owned edits are limited to `StreamData`/tool lifecycle hooks in `APIManager`, one optional JSON field in `ChatMessages`, coordinator and group ownership in `ChatView`, and narrow rendering flags in `ChatViewComponents`. `APIManager.swift` remains the largest merge-risk hotspot because the upstream tool switch is monolithic.

## Verification boundary

Static validation can check sequence monotonicity, duplicate Native UI result keys, schema fallback, and forbidden renderer paths. GitHub Actions can verify compilation and IPA packaging when explicitly run. Neither static checks nor CI proves scrolling smoothness, absence of a runtime freeze, VoiceOver behavior, RTL layout, or iPad split-view behavior; those require the device scenarios in the final handoff.
