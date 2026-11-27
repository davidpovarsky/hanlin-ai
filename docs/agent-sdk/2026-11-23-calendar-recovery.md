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

## Calendar operations and saved-item navigation — 2026-11-25

Build 149001 diagnostics showed a different failure from the earlier crash:
the model reported a reminder-note update after only `save_memory`, then used
a create-only calendar tool to create a second reminder. The end-date filter
also excluded afternoon reminders on the requested final day.

### Shared operation contract

`manage_calendar` now delegates to the same `HanlinAppleCalendarService`.
Its schema exposes 24 public EventKit operations:

| Domain | Operations |
| --- | --- |
| Access | `authorization_status`, `request_access` (full; write-only for events) |
| Accounts | `list_sources`, `get_source`, `refresh` |
| Calendars and reminder lists | `list_calendars`, `get_calendar`, `default_calendar`, `create_calendar`, `update_calendar`, `delete_calendar` |
| Events | `list_events`, `get_event`, `create_event`, `update_event`, `delete_event` |
| Reminders | `list_reminders`, `get_reminder`, `create_reminder`, `update_reminder`, `delete_reminder`, `complete_reminder`, `reopen_reminder` |
| External IDs | `find_by_external_identifier` |

The writable item schema includes title, destination calendar/list, notes,
location text, associated URL, timezone, event dates/all-day/availability,
reminder start/due date components and timestamps/priority/completion,
structured event location, arrays of time/geofence alarms, and complete
recurrence rules (frequency, interval, weekdays/ordinals, month days, year
months/weeks/days, set positions, end date or occurrence count). Calendar
creation exposes account/source, title, and color; existing calendar updates
preserve their original source.

Updates are patches. Omitted fields are retained; `clear_fields` explicitly
removes optional values, and empty arrays remove alarms or recurrence.
Changing `item.calendar_identifier` moves an item after validating both source
and destination access. Update, delete, complete, and reopen require a real
identifier; no missing-item operation creates a replacement. Recurring event
selection uses the occurrence date and the explicit `this_event` /
`future_events` scope.

Each data-changing operation commits within its invocation. A successful
receipt carries `operation`, `committed: true`, and the actual saved item
identifier and fields. Failed writes return the existing structured error
outcome and no success card. Cancellation after a successful commit cannot
turn it into a retry invitation. Pending EventKit commits/reset are kept
inside the service, not exposed as state that a subsequent model turn must
remember to finish. Existing callback cancellation remains the fetch owner.

Personal reads and writes retain the existing consent system, scoped by the
actual operation and entity type; only the permission-status lookup is
nonsensitive. Apple Calendar/Reminders permission prompts remain authoritative.
The app declares the write-only Calendar purpose string as well as full access.

Read-only EventKit fields are returned, not advertised as writable: identities,
creation/modification timestamps, account/source properties, calendar
capabilities, attendees/organizer/status, recurrence metadata, occurrence
information, and birthday contact identity. Apple Reminders tags, subtasks,
assignment, sharing administration, and invitation sending are not public
writable iOS EventKit APIs. Mac-only alarm email/sound APIs are not exposed.

### Dates, action reporting, and UI

Date-only searches use local-calendar arithmetic and the half-open interval
from the first day's midnight to the following midnight after the final day.
This includes a 15:30 reminder on the requested end date, excludes the following
day and previous-day padding, and handles 23/25-hour DST days. Timestamp search
bounds are exact and half-open. Reminder searches expose completion filtering
and due/completion date semantics; event/reminder lists report pagination and
total/truncated counts.

The two old tools remain available. `write_system_event` is explicitly
create-only and now returns an identifiable committed receipt.
`search_calendar_and_reminders` includes actual item IDs. Memory and calendar
skills explicitly distinguish a memory save from a calendar update and require
a successful receipt for every action claimed in a final answer. This improves
the model's evidence contract; it is not a mathematical guarantee against every
possible incorrect natural-language claim.

Every original event/reminder card has an **Open** action. It resolves the
actual stored identifier again, never the title. Events use Apple's
`EKEventViewController`; reminders use a native form populated by a fresh
EventKit lookup. Missing records and denied access are shown honestly.
Historical `EventItem.calendarIdentifier` values are decoded as item IDs;
new records separately store item ID, calendar/list ID, and occurrence date.
The former generic `calshow://` action has been removed.

Apple documents this exact event viewer inside the host app. No public
documented external Calendar/Reminders URL contract for an arbitrary item ID
was found, so this implementation does **not** claim an exact external deep
link or ship an unverified private URL scheme. The associated EventKit
`url` field is user content, not such a navigation URL.

### Verification for this change

Evidence: [calendar-149001-fixes-20261125](evidence/calendar-149001-fixes-20261125/receipt.json).

- **EXECUTED_PASS:** exact copied request/callback sources on Scaleway Mac,
  Swift 6: 20 tests in 3 suites, including parametrized malformed-input cases,
  final-day afternoon/DST regressions, required update identifiers, explicit
  clear versus omitted fields, and recurrence/alarm validation.
- **EXECUTED_PASS:** actual shared EventKit source typechecked against
  iPhoneOS 27, arm64, Swift 6 complete concurrency checking; final run exit 0,
  no diagnostics.
- **EXECUTED_PASS:** Swift frontend parse for the new app schema, service
  adapter, Open UI, and app test additions. This is syntax evidence only.
- **NOT_RUN in this lane:** full app integration, dispatcher/consent schema
  tests, and two newly added real-EventKit simulator mutation cases. The root
  integration owner is their designated runner.
- **NOT_OBSERVED:** physical-device interaction and App Store Connect delivery
  of this source. The root release owner reports these independently.

### Primary API references

- [EKEventStore](https://developer.apple.com/documentation/eventkit/ekeventstore)
- [Creating events and reminders](https://developer.apple.com/documentation/eventkit/creating-events-and-reminders)
- [Calendar access levels and EventKitUI](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui)
- [EventKit UI](https://developer.apple.com/documentation/EventKitUI)
- [EKEventViewController.event](https://developer.apple.com/documentation/eventkitui/ekeventviewcontroller/event)

Installed Xcode 27 SDK headers and the native typecheck are the authority for
the concrete Swift declarations used here.
