# Original-chat streaming and scrolling

The existing 80ms scheduling interval was a trailing debounce: every visual
request cancelled and recreated the pending task. Requests spaced more closely
than 80ms could therefore postpone the actual scroll until streaming stopped.
The log's request count was not an actual ScrollViewReader operation count.

The controller now owns one fixed pending window, merges animation/explicit-jump
intent, and invokes the latest action once. Touch, text selection, source reveal,
view disappearance and a new run cancel the pending identity. A cancelled timer
cannot clear or invoke a newer timer. Existing manual-bottom and explicit-jump
behavior is preserved. Diagnostic `autoFollowScrollPerformed` reports accepted
request, performed and coalesced counts at dispatch to ScrollViewReader;
cancelled work is not reported as a completed scroll.

ChatView now schedules ordinary following from rounded content/viewport/inset
geometry changes. Token fingerprints and Markdown render callbacks no longer
request scrolling independently of measured layout. Scroll offset is deliberately
absent from that geometry value, so scrolling does not request another scroll.
The source-reveal callback still scrolls to the original matched source. Manual
interaction pauses following when the user ends away from the bottom; expanding
or horizontally interacting with a code preview does not remove this policy.

Four deterministic gate-controlled unit cases cover sustained coalescing,
animation merging, touch cancellation/stale ownership, selection/explicit resume,
and replacement by a new run. They do not use wall-clock timing assertions.
All four actual scroll cases passed in app run43267408632 at67e42a74. The actual
stop/new-run UI case also passed (78s). The overall run failed on the separately
documented code-fence source-toggle query; it is not a full UI/performance pass.

## Renderer API audit

At pinned SwiftStreamingMarkdown `f59bd0d`, both MarkdownView and
StreamedMarkdownView parse each complete growing source snapshot through
MarkdownParserImpl. The streamed view is not an incremental-delta parser.
Both accept the listener/config and use DocumentView, which owns block identity
and the existing selection hook. No view replacement has been made on the basis
of its name. The required 5/20/60 tps, 10k/50k-character same-device benchmark,
pixel-visible first token, signposts, CPU/memory/FPS, VoiceOver and physical iPad
acceptance remain open in CHATUX-11. This scheduling correction is not a claim
that those performance budgets passed.

## Diagnostic processing microcheck

Capture run43268755136 passed15 correctness cases in78.975s wall time with all15
Swift Testing cases starting concurrently in an isolated iPhone27.0 package.
Older app run43255791263 used a different iPad27.2/test execution setup. Its
durations are not a controlled before/after stream-latency comparison.

A same-process Windows Swift6.3.3 `-O` microcheck compiled the actual oldb667a281
and currentf2e7c584 redactor bodies (only the old enum name was changed to load
both). For300 identical metadata records including final JSON serialization:
baseline0.205825s/current0.207314s; byte-count checksum matched. This narrow
portable check does not explain total Apple journal/disk/queue scheduling time,
prove responsive streaming, or replace required serial native/device profiling.
Artifacts: `build/RedactorBenchmark/{Baseline.swift,main.swift,results.txt}`.
