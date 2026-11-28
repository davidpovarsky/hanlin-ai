# Hanlin Agent Activity Runtime

This downstream-owned layer normalizes one provider run into functional activity state and a chronological chat transcript. It keeps the customization isolated from the upstream `CherryHQ/hanlin-ai` chat implementation except for narrow stream, persistence, and rendering bridges.

## Runtime path

`tool schema → tool call → ToolInvocationMetadataExtractor → AgentToolCall → process activity → execution → ToolResultPresentationCoordinator → optional result → transcript`

Provider events use one shared path: `provider stream → StreamData → HanlinStreamEventAdapter → AgentEvent → AgentRunCoordinator → AgentEventAccumulator → AgentRun → AgentRunTranscriptView`.

`ChatView` creates one coordinator per assistant group. Recursive model rounds and tool executions feed that same run. During streaming, the current `AgentRun` stays in view state; it is persisted on completion, failure, or cancellation rather than writing the full transcript for every token.

## Steps and transcript items

`AgentRun.steps` remains the functional and diagnostic activity state used to compose the Thinking inspector. `AgentRun.transcriptItems` is the source of truth for chat ordering. Both are retained because a tool call/execution lifecycle may be composed into one display activity while the transcript must also place assistant text and user-visible results precisely between activities.

Every transcript item receives a monotonically increasing `sequence` from one counter. Timestamps are metadata and never determine ordering. Stable item IDs and in-place delta updates prevent one item per token and avoid regenerating identities during SwiftUI rendering.

Schema version 3 persists the presentation request, resolved profile, effective renderer, and result item. Versions 1 and 2 remain readable; already-persisted result cards are not hidden merely because their historical calls have no `result_presentation` value. Malformed or unsupported run JSON returns no modern run and cannot crash chat history. Rendering legacy history never writes an automatic migration.

## Sticky auto-follow

`ChatAutoFollowController` owns an explicit `following` / `pausedByUser` state machine. A new send or retry starts in `following`. `AgentRunScrollFingerprint` observes structural transcript changes, active text growth, visible results, final-answer growth, and completion without hashing or JSON-encoding the transcript and without changing message IDs.

Fingerprint updates are coalesced into one replaceable 80 ms main-actor task so streaming does not queue one scroll per token. Text growth scrolls without animation; structural insertions use a short ease-out. SwiftUI scroll phases distinguish a user drag from layout growth or programmatic animation. A drag that ends away from the bottom pauses following, manual arrival at the bottom or the down button resumes it, and opening Thinking does not change the mode. Cancellation clears the pending task.

## Assistant text segmentation

`HanlinStreamEventAdapter` creates a new assistant text segment when content arrives without an active segment. Reasoning, progress, search, source work, or tool activity closes the preceding segment as `interim`; it remains visible while the run is live and collapses into Thinking afterward. At normal completion, the last non-empty active segment becomes `final`. `AgentRun.finalAnswer` is derived only from that final segment, never from the concatenation of interim narration.

Failed and cancelled runs close active segments without promoting partial text to a final answer. Retry creates a new group, run ID, adapter, and transcript; the earlier run remains persisted and cannot be mutated by later events.

## Tool activity versus user-visible result

A tool activity is lightweight process state: call ID, title, sanitized arguments, progress summary, status, duration, safe output preview, source count/list, and error summary. It collapses into Thinking and never renders a `NativeUIBlock`.

A user-visible tool result is a separate `userVisibleToolResult` transcript item created only after `ToolResultPresentationCoordinator` approves it. New calls default to no card: the model must send `result_presentation: "card"`, the registered profile must support a result renderer, and a payload must exist. It receives the next transcript sequence and remains in chat after completion. Deduplication uses the call ID, renderer, and stable block IDs. Raw model tool output is not promoted to chat UI.

`AgentActivityStep.richResultBlocks` remains only for schema compatibility and raw persistence. `AgentDisplayActivity`, `AgentActivityStepView`, and `AgentActivityInspectorView` do not carry or render those blocks. `AgentTranscriptToolResultView` chooses `ModernNativeToolResultRenderer` for Native profiles and the existing renderer for historical or original profiles.

Legacy map, calendar, health, code, knowledge, HTML, canvas, source, and other existing result fields stay connected to their original `ChatMessages` split. They still pass through the same metadata extraction and coordinator decision, but use `legacyExisting`; suppressed payload snapshots are restored before the UI stream is emitted. Native blocks use only the transcript path, preventing a second copy in `ChatMessages.nativeUIBlocks`.

## Process UI and Result UI

Process UI is mandatory and independent of card presentation. Every profile supplies an activity kind, icon, running/completed/failed titles, and an allowlist of arguments safe to show. Native entries register an explicit profile. Original tools resolve through `LegacyToolPresentationAdapter`; semantic and generic profiles are fallbacks only. The shared activity rows and Thinking timeline never render result cards, maps, WebViews, or recursive Native UI.

Result UI is optional. The model can request only `none` or `card`; it cannot choose a renderer, color, URL, HTML, SwiftUI, or buttons. Native profiles select `modernNative`, while original profiles with an existing result view select `legacyExisting`. Profiles without result capability do not receive the schema property. The general schema decorator preserves existing properties and required fields across OpenAI `parameters`, Anthropic `input_schema`, and Gemini-style `parameters`.

## Group ownership and split markers

The first assistant message in a continuous group is the transcript owner. `ChatView` passes explicit `isAgentTranscriptOwner` and `isRenderedByAgentTranscript` flags. The owner renders `AgentRunTranscriptView` once; later `splitMarker` messages cannot render transcript text or Native UI again. Version 1 history continues through the legacy bubble path.

## Live and completed presentation

While running, transcript items render by sequence: visible reasoning/activity rows, narrative progress, interim assistant Markdown, user-visible result cards, and later assistant segments. Selecting an activity never expands the chat layout; it opens the run's single Thinking sheet.

After completion, reasoning, progress, tool activity, and interim assistant text collapse into one localized `Worked for …` row. The row opens the same sheet. User-visible result items and the final assistant segment remain in sequence below it. Runs with only an immediate final answer do not show an empty work summary.

The inspector receives an optional selected activity ID, uses `ScrollViewReader`, scrolls to the matching transcript item, and applies a subtle highlight. It limits queries to 8 and sources to 10 until `Show more` is selected. It never instantiates Native UI, maps, HTML, web views, or full search-result renderers.

## Adding a tool

1. Register the tool through the existing catalog/tool-list path and provide its structured schema.
2. Give a Native catalog entry an explicit `ToolPresentationProfile`; add original-tool capability to `LegacyToolPresentationAdapter` only when an existing legacy result view really exists.
3. Always provide a Process UI descriptor. Use `result: nil` and `.never` when the tool has no result UI.
4. Keep provider wire parsing in the provider adapter and normalize into one `AgentToolCall`; never create provider-specific metadata stores.
5. For a card-capable Native tool, return narrow, safe `NativeUIBlock` data and use a `modernNative` descriptor. To add a new card form, extend `ModernNativeToolResultRenderer`; do not put its renderer in Thinking.
6. Keep model-only output in `modelText`. A safe short process summary may be placed in `userText`, but neither value alone creates a card.
7. Give blocks stable IDs so retry and duplicate delivery can be suppressed safely. Never manually insert the same result into transcript and `ChatMessages`.

## Diagnostics and privacy

Diagnostics record the resolved profile, requested/effective result presentation, renderer, suppression reason, schema tool count/estimated tokens, and auto-follow pause/resume/scroll decisions. Metadata-only mode never stores full result content, hidden reasoning, credentials, or secrets. Argument logging uses the post-extraction JSON plus the existing redactor; `progress_summary` and `result_presentation` never reach tool execution.

## Performance rules

- No inline activity expansion in the chat scroll view.
- No `NativeUIRenderer` in activity rows or Thinking.
- No rich-result composition in `AgentActivityComposer`.
- No per-row sheet and no mutation of `AgentRun` from a view.
- No assistant-message ID churn to force a refresh.
- No full transcript hashing or JSON encoding for scroll decisions.
- No unbounded delayed scroll operations or spring animation per token.
- No explicit persistence write per streamed token.
- No horizontal nested activity scroller or large insertion animation.
- Stable transcript and source IDs drive every `ForEach`.

## Upstream merge surface

New scrolling, presentation, accumulation, composition, inspector UI, diagnostics hooks, and transcript views live under `AI_HLY/Downstream/AgentActivity`; modern cards live under `AI_HLY/NativeAgentExtensions/Presentation`. The unavoidable upstream-owned edits are limited to schema/tool lifecycle hooks in `APIManager`, auto-follow/group ownership in `ChatView`, and narrow result bridges in `ChatViewComponents`. `APIManager.swift` remains the largest merge-risk hotspot because the upstream tool switch is monolithic.

## Verification boundary

The project has no test target. Pure Swift validation helpers cover the auto-follow transitions, metadata removal, safe enum fallback, and card decision prerequisites without running a production self-test. Static checks also cover sequence monotonicity, duplicate result keys, schema fallback, and forbidden renderer paths. GitHub Actions can verify compilation and IPA packaging when explicitly run. Neither static checks nor CI proves scrolling smoothness, absence of a runtime freeze, VoiceOver behavior, RTL layout, or iPad split-view behavior; those require the device scenarios in the final handoff.
