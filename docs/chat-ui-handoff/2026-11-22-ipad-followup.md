# iPad follow-up after TestFlight 145401 — 22 November 2026

## Delivery state

Candidate implementation is integrated on `codex/hanlin-ipad-followup-20261122`, based on `f49b81fd7b1654b2b0486dddbd8972d400ba6c29`. Release archive, upload and physical acceptance are not yet complete. This document will record the actual release receipt after upload; the prior 145401 delivery is not evidence for this candidate.

User authorization covers the eleven reported regressions, Asana updates and TestFlight delivery. The release must reuse native Runtime producer `42926628418`, use `testflight_device_upload`, and skip simulator tests during upload. Preserve the original Morph plus geometry and Liquid Glass identity.

## Reported issues and implementation

| Report | Change and cause | Acceptance boundary |
|---|---|---|
| 1. Controls escape the input glass when its origin moves | One local layout result owns editor height, one controls row, input glass and remaining panel budget. Removed independent asynchronous input/editor measurements and redundant global keyboard subtraction. Native model-search focus retains a scoped keyboard-owner lease until the popover actually dismisses. | Portable geometry passed; physical keyboard/window-origin transitions remain open. |
| 2. Internal Using Tools / Loading skill stages | Visibility requires an actual tool invocation identity. Internal discovery, Skill loading, metadata and generic progress stages remain in canonical history but do not become user-facing tool rows. Legacy projection applies the same exclusion. | Production lifetime/visibility checks passed; real-provider visual acceptance remains open. |
| 3. Preparing your answer persists | Removed the generic assistant operational footer and standalone status. Active shimmer is attributed only to real visible operation paths; a collapsed ancestor may represent its running descendants. Completed history has no active shimmer. | Production header/motion policy checks passed. |
| 4. Expanded composer title / Done and always-visible expand | Removed the extra title/Done row. The inverse collapse icon occupies the upper corner; expand/collapse appears only for a nonempty draft. The native editor remains the same mounted instance. | Source and geometry verified; touch/focus acceptance remains open. |
| 5. get_route rejects input | The Host compared exact decimal input against a lossy binary64 portable DTO; the metadata extractor also used Foundation number reserialization. Validate original bytes against the original schema, separately prove the DTO is its deterministic projection, remove only top-level metadata with the bounded exact JSON parser/writer, and compare original business input to actual executor input. Execution still consumes the original retained value, never the DTO. | Exact-input domain tests and archive must pass; no live route request is claimed by offline checks. |
| 6. Model moves above controls at narrow width | Removed the alternate vertical controls layout. One 44pt bottom row owns every control, and the model title compresses/truncates within its allocation. | 384 geometry scenarios / 1,955 assertions passed. |
| 7. Blank / misplaced model popover | Explicit local bounds for the real toolbar source item; hosting safe area applies the container without subtracting the keyboard twice. A tokenized presentation lease preserves compact keyboard ownership when focus moves to model search; an old dismissal cannot clear a newer owner. | Apple native zoom/popover and real-device layout remain acceptance work. |
| 8. Tool panel disconnects from plus | The panel and input consume one local geometry budget. Original 52pt launcher, bottom alignment, glass IDs/material, 10pt input-to-plus gap, 13pt panel-to-input gap and 32pt merge distance are preserved. | Geometry/source verified, not a physical visual-equivalence claim. |
| 9. Selection stops at paragraph/rich-part boundaries | A single native text document spans original Markdown parts and rich blocks, with public TextKit 2 view attachments. Copy/save expands atomic rich positions to exact source payloads. Existing rich rendering/actions, stable IDs, streamed tail editing and a one-second stationary preview hold are retained. Nested URL/citation taps use public text geometry and accessibility actions. | 41 portable boundary checks and syntax passed. UIKit gesture, RTL, rich sizing and interaction acceptance remain open. |
| 10. Repeated approvals and missing presentation metadata | Sensitive actions use manifest-derived consent policy. Explicit approval persists locally across conversations, scoped to app/account/workspace/provider/tool/manifest/permission identity. Current route and grants are checked again at dispatch. Settings can revoke one or all grants. Optional manifest `systemImage` and `search`/`execution`/`common` animation presets have a shared tools fallback. | Portable policy/store/schema tests and archive must pass. Original OS permissions and other capability authorities remain effective. |
| 11. Background conversation stalls | Admission now starts before attachment-preparation awaits. A bounded UIKit lease bridges asynchronous continued-processing admission; the scheduler attaches to the existing producer. MCP background cleanup no longer stops workers owned by an admitted operation. Real work receipts/output advance finite progress, and a completed nested stream no longer cancels the root conversation. | 118 production ownership/progress/real-stream termination checks passed. Apple OS admission, long background runtime and cancellation remain physical-device acceptance. |

## Approval and manifest contract

The portable JSON value is only a projection. MCP additionally verifies its actual binary64 wire projection at preflight and immediately before the client call; unsupported remote precision is rejected before dispatch instead of being silently rounded. This does not alter the corrected native map path.

Only manifest-declared sensitive operations require Hanlin consent. Existing risk declarations also count as manifest sensitivity. Mixed-action tools may declare their exact read-only actions as non-sensitive. Public map/search lookups do not acquire a Hanlin confirmation merely because they are tools. Mandatory iOS permissions still apply.

A remembered grant is deliberately independent of conversation, run and call IDs. It is invalidated by changes to the authorized provider/credential references, manifest/schema, declared capability or selected delegated identity fields. Revocation is read at the actual dispatch boundary. Historical allow-once receipts are not silently upgraded into persistent authority. Provider-only requests without a verified Host scope retain one-use semantics.

Illustrative descriptor fields, under the existing tool descriptor and its presentation section:

```json
{
  "approval": {
    "requiresApproval": true,
    "actionParameter": "action",
    "nonSensitiveActions": ["list", "status"],
    "scopeParameters": ["server", "tool_name"]
  },
  "presentation": {
    "executionPresentation": {
      "systemImage": "magnifyingglass",
      "animation": "search"
    }
  }
}
```

Animation metadata selects host-rendered presets; it cannot execute animation code. Absent an icon definition, the display uses `wrench.and.screwdriver`. Built-in profiles explicitly supply their declared icon/family instead of guessing behavior from an arbitrary alias.

## Background behavior and platform limits

The continuation belongs to the existing foreground user-started operation. No admission callback replays model calls or side effects. Native Cancel and resource expiry interrupt that same owner; the original first cause and partial results are retained. A normal `.finished` stream event does not cancel its producer or ancestor; only `.cancelled` stops its producer, and only the root stream owns run cancellation.

Apple documents continued processing for user-started CPU/network work, with resource-dependent admission and expiration/cancellation. Live Activity display alone is not an execution entitlement. The temporary UIKit task is a bounded admission bridge, not an unlimited background mode. The system can still terminate or expire work, and force-quitting the app ends execution. No configured server-side continuation is assumed.

A negative `Progress.totalUnitCount` makes `fractionCompleted` remain zero. The revised progress tracks actual discovered work units plus pending finalization and reports actual processed bytes. Reading a snapshot, elapsed time and repeated journal receipts never manufacture progress. This is not an estimate of eventual answer length or elapsed completion percentage.

Primary references:

- [Apple: Performing long-running tasks on iOS and iPadOS](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)
- [Apple: Progress.isIndeterminate](https://developer.apple.com/documentation/foundation/progress/isindeterminate)
- [Apple: beginBackgroundTask with expiration handler](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(withname:expirationhandler:))
- [Apple Developer Forums: continued-processing behavior and progress](https://developer.apple.com/forums/thread/840384)

## Verification record

| Check | Observed result | Scope |
|---|---|---|
| Actual composer geometry and metrics | PASS: 384 scenarios / 1,955 assertions | Portable Swift 6.3.3, not UIKit layout execution. |
| Actual activity visibility/lifetime/motion policy | PASS: 160 checks, `job_2bedd1c6031f` | Initial `job_eda1c88fe729` timed out; the completed focused retry is the result. |
| Actual continuation owner, progress and Foundation stream termination | PASS: 118 checks, `job_19e4df45ff63` | Swift 6 strict concurrency, warnings as errors; includes real `.finished` and `.cancelled` callbacks. Earlier 112-check result is superseded by this expanded regression. |
| Markdown part/rich boundary behavior | PASS: 41 checks, `job_270d20ad89c2` | Foundation boundary checks; UIKit tests authored but not run. |
| Swift syntax | Root 15 integration files; renderer18 and app5 surfaces; policy27 files; final scoped deltas passed | Parsing is not Apple-framework type checking. |
| Root whitespace | Initial combined parse/check job found3 introduced whitespace errors, fixed; follow-up passed | No broad reformat of unrelated existing whitespace. |
| Exact input / approval / metadata | PASS: 17 tests in3 suites, Swift subprocess exit0, `job_3c5caf9c7fd0` | First run passed16/17: the portable package had a different resource bundle name. Reused compiled cache and the existing DEBUG resource hook with unchanged production resources; all9 pinned resource hash checks and original test expectations retained. Wrapper later hit a Windows console Unicode-print error after saving the passing receipt; output escaping fixed without changing production or rerunning passed tests. |
| Apple archive / signed export / upload | Pending | Actual release receipt must be recorded. |
| Simulator execution in upload | Prohibited by user; must be skipped | Verify workflow job/step metadata. |
| Physical iPad acceptance | OPEN | User tests narrow/wide, keyboard, expansion, popup, selection, maps, background/return and tool collapse. |

Detailed evidence is stored under `2026-11-22-followup-evidence/`, plus the selection follow-up receipt `2026-11-22-evidence/selection-cross-block-followup.json`. Source hashes identify consumed files; working-tree hashes can differ from Git blobs solely through configured line-ending normalization. A successful archive or portable test does not establish visual parity or absence of device crashes.

## Release route

Use workflow `310046367` (`build-ios26-unsigned-ipa.yml`) with:

```text
testflight_upload=true
target_validation_group=testflight_device_upload
runtime_bundle_artifact_run_id=42926628418
runtime_bundle_only=false
runtime_publish_release=false
testflight_audience_source_build=143801
```

Renderer revision `dcef24e2254d3ef6db74b6c30a926d6ea20ae18d` was committed, pushed and independently read back from its remote branch; all3 app pins now reference that exact revision. Record app source SHA, renderer SHA, workflow ID/run/attempt, build number, IPA/runtime receipts, Apple's processing state and internal audience readiness. Do not reuse the prior145401 receipt as the result of this follow-up.
