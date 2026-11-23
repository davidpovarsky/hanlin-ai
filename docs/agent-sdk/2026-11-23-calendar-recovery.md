# Shared calendar recovery — 2026-11-23

## Implementation

The original Hanlin Calendar/Reminders tool now runs through `HanlinAppleCalendarService` in `HanlinScriptDeviceServices`. The app's old 392-line EventKit implementation is a small value adapter. SDK hosts and Hanlin use the same validation, authorization, fetch, write, filtering and callback-lifetime implementation.

- `HanlinCalendarSearchRequest` and `HanlinCalendarWriteRequest` validate model input before EventKit. A reversed range produces a structured invalid-arguments result instead of reaching Foundation's trapping `DateInterval` initializer. Malformed supplied dates no longer silently become unbounded searches. Nonfinite dates and overflowing alarm input are rejected.
- Calendar and reminder access are requested only for the selected entity types. Empty EventKit titles are mapped safely, and reminder snapshots reject a missing calendar instead of dereferencing it.
- A shared callback owner completes once on success, error, cancellation or a 30-second deadline. It cancels the actual reminder fetch token, resumes the waiting task itself, and ignores late or duplicate callbacks. This is necessary because EventKit does not invoke a cancelled reminder fetch's completion handler.
- Broad calendar searches are split into predicates shorter than EventKit's four-year maximum. The original default searches five years before and five years after now; a single predicate previously omitted the present and future. Recurring occurrences are retained while duplicate boundary results are removed.
- The original legacy dispatcher converts validation, authorization, availability, cancellation and timeout failures into `NativeToolResult` outcomes and diagnostics. Failed writes do not append event cards or report success. A write that has committed remains successful if cancellation arrives after the commit.
- The original event values, presentation formatting and calendar/reminder filtering behavior remain at their existing app seam. No interface was rebuilt.

## Evidence and acceptance

Evidence is in [calendar-recovery-2026-11-23](evidence/calendar-recovery-2026-11-23/receipt.json). The receipt records source hashes, exact commands, environment, scope and unexecuted gates.

| Gate | Result | Scope |
| --- | --- | --- |
| Original reversed `DateInterval` expression | Reproduced SIGTRAP | Real Foundation expression, Linux Swift subprocess |
| Original `Int.max * 60` alarm expression | Reproduced SIGTRAP | Real integer overflow, Linux Swift subprocess |
| Portable request and callback regressions | PASS, 12 methods / 17 cases | Exact Foundation-only SDK sources, Swift 6 mode |
| Added range-partition regression | PASS, 1 method / 1 case | Covers present/future, bounded contiguous predicates |
| Swift frontend parse | PASS, 7 files | Syntax only, not Apple framework typechecking |
| Native app dispatcher regressions | NOT_RUN here | `AI_HLYTests/CalendarToolTests`, 4 methods / 6 cases; shared Apple gate |
| Physical Calendar/Reminders UI and supplied crash | NOT_RUN here | Requires Apple runtime and matching diagnostics |

The first portable run's twelve methods were reused after adding the independent predicate-partition helper and thirteenth test. Only the new test was executed again; no existing exercised method or test body changed in that addition. This avoids repeating accepted tests without a concrete change in their scope. The first compile attempt required correcting a missing `try` inside Testing's `#require`; no tests ran in that unsuccessful compile attempt. The retained pass logs are the executed results after correction.

The native tests exercise the actual original dispatcher with an injected EventKit boundary. They verify that reversed/malformed arguments never invoke the executor, denied/timeout/cancelled reads return structured outcomes, a subsequent call succeeds, and a failed write cannot appear committed. They are prepared for the integration owner's Apple run; Linux syntax checking is not a substitute.

## Diagnostic limitation

The visible attachment was `TestFlight – ChavrusaChat 0.7.3 (147501).crash` from 2026-11-22. Its main-thread SIGABRT stack runs through `CALayer.setBounds`, `UIScrollView.setContentOffset`, and SwiftUI `HostingScrollView.updateContext` / `didMoveToWindow`. The examined stack contains no EventKit frame and provides no exception reason. The two reproduced calendar defects and the never-ending callback are independently code-proven issues, but they do **not** establish the root cause of that physical crash. No newer calendar-specific attachment was visible during this lane.

The callback deadline cannot interrupt an already-running synchronous `EKEventStore.events(matching:)` call; cancellation/deadline checks occur between bounded predicates. Authorization prompts may remain visible after the Swift request has timed out because EventKit exposes no cancellation token for that prompt. Late completions are ignored safely.

## Platform references

- [Apple: cancelFetchRequest](https://developer.apple.com/documentation/eventkit/ekeventstore/cancelfetchrequest(_:)): cancelling a fetch suppresses its completion handler.
- [Apple: predicateForEvents](https://developer.apple.com/documentation/eventkit/ekeventstore/predicateforevents(withstart:end:calendars:)): a single predicate is limited to four years.
- [Apple: EKEventStore](https://developer.apple.com/documentation/eventkit/ekeventstore): full-access authorization, reminder fetch token and event store operations.

No manifest, Xcode project, chat presentation, or unrelated lifecycle source was changed by this lane.


## Native EventKit continuation acceptance (source ready)

A focused original-app method now seeds three owned real EventKit events at -4, 0 and +4 years plus one real reminder in the CI job's freshly created simulator. It invokes the production calendar executor through the existing canonical authority and app session owner, checks the full default date window, invalid-range recovery, pre-dispatch cancellation recovery, a second turn through the same engine, released conversation lease, and original history reopening. Only deterministic model text is supplied; EventKit and the original calendar dispatcher are not replaced.

The CI hook grants calendar/reminder access only for this selected method or its containing suite, after the existing owned-simulator and original xctestrun identity checks. Cleanup removes only the fixture's saved records. This method is NOT_RUN until actual Apple evidence is attached; Swift parse and two admission controls PASS are source qualification only. It does not claim a cancelled already-stalled native callback or physical-device crash reproduction. See evidence/calendar-native-acceptance-20261123/source-receipt.json.
