# Canonical SDK presentation consumer

`HanlinA2UIAgentPresentationAdapter` consumes actual `HanlinAgentEvent` from SDK snapshot
`18813519eada1db152bd206d5c7bd922ddc987ee`. It imports the public canonical products;
there is no replacement core, transcript, provider envelope, or prose/fenced-JSON inference.
Its bounded transient projection keeps `(runID, messageID, partID)` identity and the original
immutable host session/context. Official A2UI admission precedes SDK interaction admission.
Rejected complete frames become unavailable presentation while canonical stored bytes remain intact.

The application session owner must:

1. Forward events from its one `HanlinAgentSession` stream to `receive`.
2. Forward `onRunCompletion` to `completed` and invalidation to `invalidate` without replacing
   other consumers of those callback slots.
3. After the successful `for try await` loop drains, call `producerStreamDrained(runID:)`.
   The SDK producer completion callback can arrive **before buffered consumer events**.
   Completion latches successful EOF; sealing input directly in that callback loses valid content.
   Cancellation/failure/invalidation revoke immediately.
4. Inject `source` and the existing A2UI result store into the existing presentation environment.
   Before an asynchronous action continuation, check `isCurrent(originalKey)` and call the same
   SDK session's `continueInteraction` with the original request. Native host policy remains authoritative.
5. Replay only canonical `record.structuredEntries`; replay never admits interaction. The current
   slice replays model bytes, not local unsent form edits. Deletion/context change must invalidate
   the original session and its adapter.

The new manual `a2ui_sdk_consumer` route archives the immutable SDK and literal sibling Platform
from the same Git SHA, records both Git tree IDs, and resolves the original producer revision
`e7bf34111e603ca977becd007dd4e5bb109af857` plus official A2UI revision
`3ed9601862ecc78027e20ac80ad8b1b98a5d9079`. It compiles real consumer sources and selects four
new real-session/renderer component tests plus four affected projection tests. It does not repeat
the unaffected SDK/producer suites or media tests. Local syntax and proof-validator checks passed;
native typecheck/test execution is pending at this source commit.

Main-app session ownership/environment wiring, a supported live schema-response provider path,
native host effects, XCUITest, saved local form state, physical-device/RTL/AX acceptance remain OPEN.
The SDK-injected fixture stream in this proof is explicitly not real-model acceptance.
