# iPad stability and TestFlight handoff â€” 2026-11-21

Baseline: `5534d6b249518d29efda6c2a43f4eacbfbc2b973`.
Branch: `codex/hanlin-ipad-stability-20261121`.
Owner request: fix typing, streaming, Morph layout, tool activity and design consistency; update Asana and ship a new device build with the previous known-good native runtime. No simulator tests in this upload.

## Changes in the original chat

- Draft edits remain in the existing observable draft owner. A small child observes its revision and persists after 500 ms. ChatView no longer observes the text to republish its whole composer endpoint, and ChatViewBottom no longer writes SwiftData for each keystroke.
- Draft state still flushes through the original lifecycle path. The native editor preserves owner/revision identity, marked text, selection and exact Unicode bytes. It can accept the next draft while the response streams.
- Native TextKit measurements are cached across the native edit and SwiftUI acknowledgement. Deferred height writes are cancelled or rejected when the view, owner or layout changes. TextKit2 stops after seven valid contiguous visual lines, enough to prove the six-line limit.
- The Morph remains the approved shared GlassEffectContainer with three stable glass identities. Its input uses intrinsic height, geometry updates have a threshold, and competing host-wide animations were removed.
- AnyLayout retains one model picker and one action cluster when the composer switches between one and two rows.
- The production stream buffer publishes the first plain delta immediately, combines adjacent plain deltas for at most 50 ms, and flushes before every tool/approval/round/metadata/error event. Finalization flushes the tail; cancelled or replaced runs cannot publish stale content.
- The activity projection no longer appends reasoning a second time. Expensive tool-result projection and durable run snapshots are separated from ordinary answer tokens.
- Pending approval belongs to its actual call row; completion reflects execution, not permission or completion of provider arguments.
- The message context-menu preview receives a bounded explicit width.
- 101 sensory feedback call sites now use the central synchronous UIKit bridge, and response completion has one observer instead of one per visible message. This removes the LocationBasedFeedbackAdaptor route seen in the supplied crash. It does not establish the exact upstream crash cause or prove device crash freedom.

Historical activity reads now use a per-view non-observable cache (64 entries /16 MiB source JSON) and a lazy first-run lookup. Exact UTF-8 changes invalidate the value; malformed results are negatively cached; nil rows do not evict useful entries. Actual production cache compile/link/run passed17 focused portable checks, including no retained model objects.

## Design catalogue

See `NATIVE_UI_CATALOG.md`, `native-ui-inventory.json` and `design-catalog-migration.json` in this directory. The app and reusable packages consume HanlinTypography and HanlinControlMetrics. Original named adaptive colors remain authoritative. Inline model/Skills search uses UISearchTextField; model management uses searchable. The live catalogue is available from the existing diagnostic settings.

## Verification completed before device archive

- Actual production HanlinChatStreamBuffer compiled with Swift 6 on Windows and passed nine checks. Opaque platform payload types were substituted only in a temporary DTO; production buffering logic was unchanged.
- Checks cover first publication, batching, approval ordering, reasoning/answer boundaries, round boundaries, partial text before error, a silent provider's pending tail, cancellation, and exact preservation of 5,000 multilingual deltas.
- Root Swift source syntax parse passed. This is not Apple framework typechecking.
- Release route reports thirteen TestFlight readiness checks passed; three production Python recovery regressions passed. See the release/streaming evidence for the corresponding commands.
- Apple framework compilation, signing, packaged native identities, upload and processing remain gates of the new device archive.
- Simulator and physical-device UI/performance acceptance: NOT RUN in this source stage. No synthetic screenshots are represented as app evidence.

Reproduce the portable stream checks:
```
py -3 Scripts/CI/verify_chat_stream_buffer.py
```

## Native runtime and upload

Reuse native artifact run `42926628418`, without rebuilding the engines or reusing the old IPA. The current Python runner resource is staged from this source checkout alongside those native frameworks.

Dispatch after the integrated commit is pushed:
```
gh workflow run 310046367 --repo davidpovarsky/hanlin-ai --ref codex/hanlin-ipad-stability-20261121 -f testflight_upload=true -f target_validation_group=testflight_device_upload -f runtime_bundle_artifact_run_id=42926628418 -f runtime_bundle_only=false -f runtime_publish_release=false -f testflight_audience_source_build=143801
```

The existing workflow selector forwards the explicit no-simulator mode to the reusable TestFlight workflow without exceeding GitHub's workflow input limit. App/device compilation, signature, entitlement, runtime identity, privacy and upload validation remain active. A fresh Extended Virtual Addressing distribution profile uses the previous successful upload's signing route.

## Owner acceptance on the iPad

The existing Morph/V17/device QA tasks remain open for actual device confirmation. Check long Hebrew/mixed drafts, fast typing during a response, six-line wrapping, split-view resizing, keyboard show/hide, tool subpage navigation and model selection. Check real search/tool execution, one-time allow/deny, cancel/continue, sources and details, long-press preview, scrolling/selection and reduced motion. A successful archive or upload does not close these visual/performance contracts.

Asana master: https://app.asana.com/0/1219603102275846/1220776535218599
