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
new real-session/renderer component tests plus four affected projection tests at source `9ac4ede8`.
Run [43731062935](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43731062935)
passed **8/8** on actual macOS/Xcode27.2/Swift6.4.2 in311s. Artifact `14169065648`, SHA256
`e2ed1f3facbaccc557d315e26970478d0ae921a3e8ebae7a83b2b96c16abc4ae` retains the xcresult,
original package/input hashes and both immutable SDK sibling tree IDs. See
`evidence/sdk-consumer-43731062935.json`. No UI, native effect or live-model acceptance is inferred.

The subsequent identity/budget correction keys model owners by `(run, message, part)` while
preserving tool slot semantics. Same-part UUIDs in different canonical messages no longer collide.
`discard(originalKey)` revokes that exact SDK origin before removing its owner; view disappearance
is not deletion. Completion-only and rejected runs also count toward a64-run lifetime limit;
exhaustion revokes the adapter while leaving canonical transcript bytes and plain text intact.
This bounds EOF/tombstone/mode metadata as well as content. A replacement adapter/session may
rehydrate the transcript read-only, never restore old native admission.

The next operation selects six consumer controls (the four original controls plus a65-run
completion budget and same-part-ID/two-message isolation) and17 affected ownership controls.
The shared owner slot change affects all17; unaffected direct SDK/producer/media cases are not
rerun. This23-case native operation is pending at this source commit. It does not refresh the
separate media passes or claim an aggregate full-app acceptance.

Main-app session ownership/environment wiring, a supported live schema-response provider path,
native host effects, XCUITest, saved local form state, physical-device/RTL/AX acceptance remain OPEN.
The SDK-injected fixture stream in this proof is explicitly not real-model acceptance.
