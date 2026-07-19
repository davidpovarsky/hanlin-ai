# Hanlin Agent Activity Runtime

This downstream-owned layer normalizes one provider run into three independent presentation paths while keeping the upstream `CherryHQ/hanlin-ai` integration surface narrow:

1. **Process UI** — chronological reasoning summaries, explicit progress, and tool activity.
2. **Result UI** — optional interactive cards approved by `ToolResultPresentationCoordinator` only when the tool supports a card and the model requests `result_presentation: "card"`.
3. **Evidence UI** — provenance extracted from retrieval results, independent of card presentation.

The shared runtime path is:

`provider stream → StreamData → HanlinStreamEventAdapter → AgentEvent → AgentRunCoordinator → AgentEventAccumulator → AgentRun → AgentRunTranscriptView`

A tool follows one orchestration path regardless of whether it is Native or original:

`tool call → process activity → execution → result decision → optional card → evidence extraction → final response → evidence summary`

## Final-answer selection

`AgentRun.transcriptItems` is the source of truth. `ChatMessages` group-owner text is persistence/render ownership only and is never used as a modern-run answer fallback.

At successful completion, `AgentTranscriptAccumulator` selects one final answer:

- use the last non-empty assistant segment already marked `final`, when present;
- otherwise promote the last non-empty assistant segment;
- mark every earlier non-empty assistant segment `interim` and `collapseIntoThinking`;
- mark the selected segment `final` and `remainInChat`;
- derive `run.finalAnswer` from that segment only.

Decoded completed runs are normalized in memory with the same rule. Missing transcript text stays empty; no legacy owner text is substituted. Failed and cancelled runs do not promote incomplete text.

## Semantic events versus transport telemetry

`OperationalEventClassifier` treats `Processing`, `Sending request`, `Waiting for model response`, request preparation/sending, parsing, stream open/close, first-token waits, retries, and unknown operational states as diagnostics-only telemetry. These values:

- do not create transcript or display activities;
- do not end an answer segment;
- remain available through local diagnostics metadata.

Only semantic events can end an active assistant segment: a real tool lifecycle event, explicit `report_progress`, visible reasoning item, search/source action, model round transition, or provider item boundary.

## Search activity

Actual queries are kept separately from returned search text. `APIManager` captures queries in execution order; `HanlinStreamEventAdapter` forwards them as search metadata; and the accumulator trims and deduplicates normalized duplicates without combining distinct queries.

`AgentActivityStep.searchProviderName` stores the provider once. Each `AgentActivitySource` stores its own title, URL, domain, optional snippet, and provider metadata. Source labels resolve in this order: meaningful title, domain/host, then the localized `Source` fallback. A search-engine name such as LangSearch is never the primary label for every source.

Thinking shows up to eight query chips and ten source rows before `Show more`, with the provider rendered once as secondary metadata.

## Lightweight inline process

While a run is live, transcript items remain chronological and selectable. After completion, the process starts collapsed behind the localized `Worked for …` row. Tapping that row expands or collapses `AgentInlineProcessView` in place, respecting Reduce Motion.

Inline content is deliberately lightweight:

- included: interim assistant text, visible reasoning summaries, explicit progress, tool titles/summaries, and short failed/cancelled states;
- excluded: final answer, tool arguments, input/output payloads, JSON, query chips, source lists, Evidence rows, Result cards, maps, WebViews, and every `NativeUIRenderer`.

Tapping a tool row opens the single Thinking sheet with the activity ID. The sheet scrolls to and highlights that activity. It may show safe query/source/input/output details, but never Result UI or Evidence UI.

## Evidence model and extraction

Schema version 4 persists `[AgentEvidenceItem]` on `AgentRun`. Each item records kind, tool/call provenance, ordering metadata, title and safe metadata, URL/deep link/reference/external ID, short snippet, timestamp, and whether it was returned to the model and used in a completed run. Older schemas decode missing evidence as `[]`.

Evidence is created locally from results already returned by tools. It is never added to provider prompts or tool schemas. Evidence is extracted only for successful retrieval/read/query results that returned identifiable information to the model. Write-only tools, calculator output, transport telemetry, empty results, and failed lookups do not create evidence.

Current extraction supports:

- web search and read resources;
- Wikipedia search and summary blocks;
- Sefaria search results and exact references;
- GitHub repository/file/commit URLs (including results returned through generic retrieval tools);
- files, documents, and knowledge retrieval;
- reminder and calendar reads;
- generic descriptors for future email, contact, database, and retrieval tools.

Native tools declare `ToolEvidenceDescriptor` on their existing `ToolPresentationProfile`. Original tools receive descriptors from `LegacyToolPresentationAdapter`. Both feed the same `AgentEvidenceExtractor`; there is no second orchestration runtime.

`result_presentation: "none"` suppresses only Result UI. The underlying Native blocks or explicit retrieval items still feed Evidence extraction.

## Deduplication and legacy resources

`AgentEvidenceDeduplicator` uses kind-specific canonical keys: normalized URL for web, language/page identity for Wikipedia when available, normalized Sefaria reference, GitHub identity/path/SHA, and stable external IDs for reminders, calendar, email, contacts, and documents. Safe URL normalization removes fragments and common tracking parameters without changing the URL used for opening.

Repeated evidence is displayed once while retaining returned/used state and the first known call provenance.

`LegacyResourcesEvidenceAdapter` converts historical `[Resource]` values at display time. It does not migrate the database. Modern schema-4 runs use `AgentRun.evidenceItems`; older runs may combine persisted evidence with adapted resources. The old expandable `resourcesView()` is removed, so the modern Evidence UI is never duplicated.

## Evidence presentation

After a completed final answer, `AgentEvidenceSummaryView` renders a small secondary button with a localized count. It never appears inside Thinking, Result cards, or inline process content.

The button opens `AgentEvidenceSheet`, a `NavigationStack` sheet with medium/large detents, grouped lazy rows, readable metadata, short snippets, and verified Open/Copy actions. The sheet supports web, Wikipedia, Sefaria, GitHub, documents, reminders, calendar, email, contacts, and other items without rendering Result cards.

Opening Thinking or Evidence does not modify chat following state. Inline expansion increments the chat layout revision, and evidence-count changes participate in `AgentRunScrollFingerprint`. The existing following/paused-by-user controller still decides whether a post-layout scroll is permitted.

## Persistence, retry, cancellation, and failure

- schema versions 1–4 remain readable;
- missing transcript/evidence arrays default safely;
- malformed completed transcript roles are normalized in memory;
- retry creates an isolated run, transcript, and evidence accumulator;
- cancellation keeps only evidence already returned to the model;
- failure preserves successful earlier evidence and never fabricates evidence for failed lookups.

## Diagnostics and privacy

Diagnostics include answer segment start/interim/final promotion, final selection, suppressed transport events, captured search queries/sources and label strategy, inline expansion, Thinking selection, Evidence extraction/deduplication/suppression, sheet presentation, and item opening.

Metadata-only mode records counts, kinds, lengths, IDs, decisions, and timings. It does not record API keys, credentials, hidden reasoning, full email/reminder bodies, or arbitrary raw tool payloads. Evidence objects never flow back to the model.

## Adding a retrieval tool

1. Register the tool through the existing Native catalog or original-tool path.
2. Supply the mandatory Process UI descriptor.
3. Add a `ToolEvidenceDescriptor` with the correct kind and `.automatic` or `.explicitExtractor` policy.
4. Return stable item IDs, titles, URLs/references, and only a short safe snippet.
5. Mark evidence returned only after the result is actually provided to the model.
6. Keep Result UI capability separate; supporting Evidence does not imply a card.
7. Add extraction, deduplication, persistence, and `result_presentation: none` regression tests.

## Upstream merge surface

Models, classification, accumulation, extraction, deduplication, inline UI, Evidence UI, inspector changes, and diagnostics live under `AI_HLY/Downstream/AgentActivity`. Unavoidable upstream-owned edits remain localized to:

- `APIManager.swift`: query capture, explicit calendar/reminder evidence, and event bridging;
- `ChatView.swift`: modern source-of-truth selection and layout-revision auto-follow hook;
- `ChatViewComponents.swift`: transcript/evidence placement and removal of duplicate legacy resources UI;
- Native Wikipedia/Sefaria catalog declarations: evidence descriptors;
- project/workflow files: the regression-test target and explicit manual verification.

`APIManager.swift` remains the largest merge-risk hotspot because the upstream tool switch is monolithic. Evidence logic itself stays outside that file.

## Verification boundary

`AI_HLYTests` covers final selection, malformed persisted transcript normalization, transport suppression, query/source labeling, inline exclusion policy, Evidence deduplication, and independence from Result UI. The manual GitHub Actions workflow runs the regression tests, builds the iOS 26 app with the newest available stable Xcode 26 installation on the runner, packages the unsigned IPA, and uploads logs.

Compilation and tests do not prove runtime UX, smooth scrolling, VoiceOver quality, RTL layout, source opening, permissions, or iPad behavior. Those still require the documented device scenarios.
