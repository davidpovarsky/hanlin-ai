# SDK05 clear-history repair — unapplied proposal

## Finding and intended behavior

The existing ChatView clear-history confirmation calls newConversation(). At source 1480b347f519073b384cd86f7efc506e9c2d1aab, that method deletes the visible ChatMessages rows and inserts a success message, while ChatRecords.agentSDKRecordData and the current SDK owner remain intact. Canonical transcript entries, tool correlations and presentation references can consequently survive a clear operation and be loaded again by the original SDK owner/store.

This proposal changes that existing action. It introduces no account service, new database, schema property, provider, credential migration or entitlement.

## Files and behavior

- HanlinAppConversationStore: a synchronous reader keeps read/revision-check/write in one MainActor operation. The async protocol remains unchanged. Clear history removes the legacy messages, replaces their preview and installs an empty canonical record in the same save. The empty record contains only the existing format/namespace/conversation/revision fields; it has no model, draft or entries.
- Revision barrier: clearing an existing record advances its revision by one. Clearing before the producer's first save writes empty revision zero. An old producer still expecting nil cannot create its old snapshot afterwards; a producer expecting the prior non-nil revision also fails CAS. A new writer that has read the cleared revision remains able to append a new turn.
- HanlinAppAgentSessionOwner: the original owner synchronously cancels/revokes authority before changing visible or canonical data, then calls its existing store. Successful clear discards row bindings and inline presentation state. A failed clear retains the old history data while the cancelled authority stays revoked.
- ChatView: the existing destructive confirmation uses this path. Current generation is cancelled first when responding. It updates the visible success state only after the store save succeeds; failures show a generic error with no raw storage details. Draft saving is cancelled before the operation.
- The current unsent draft, conversation title, current independent Canvas and independently saved excerpts are preserved. The original preview is replaced with the clear marker, so a prior transcript preview does not remain in the list.
- A never-inserted temporary conversation stays in memory. Its original transient canonical store receives the same revision barrier.

## Save failure handling

The store validates existing metadata and available revision before mutation. It checkpoints pre-existing pending context edits, if any, before beginning the destructive changes. It then performs the history mutation and final save without an await. A failed final save calls the documented ModelContext.rollback(), which returns the changed history to the checkpoint while preserving unrelated edits already checkpointed.

Unknown future canonical formats, corrupt metadata, a foreign namespace and exhausted revisions are not silently discarded. The action fails and shows no success marker. An unknown account or backup is not treated as authorization to erase it.

## Authored native checks

Five methods, seven expanded cases, in the existing HanlinAppAgentSessionOwnerTests:

1. clearHistoryCommitsCanonicalBarrierAndVisibleReplacementToOriginalDiskStore(): an actual disk-backed SwiftData container is closed and reopened. Canonical entries/model/draft and old visible messages/preview are gone; title, current draft, Canvas, independent saved excerpt and an unrelated pending insert remain. A previously admitted DataAccess lease is revoked.
2. clearHistoryRejectsAlreadySuspendedOriginalStoreWriter(hadCanonicalRecord:): false/true cases pause a real original-store writer after reading the previous revision and before save. Clearing installs the barrier, releasing the actual suspension yields storeConflict, and a new writer using the barrier revision succeeds. There are no timing sleeps or substituted store results.
3. clearHistorySaveFailureRestoresOriginalDiskContentWithoutSuccessMarker(): opens the real original disk store with allowsSave:false, attempts the same operation, then verifies rollback and another writable reopen preserve both canonical and visible content.
4. temporaryClearHistoryDropsOriginalSessionHistoryWithoutInsertingStoreRows(): uses the actual original Session/engine/store path with the existing component provider, clears its transient history, verifies read-only history replay is empty and no SwiftData conversation or message rows were inserted.
5. clearHistoryPreservesUnrecognizedOrExhaustedCanonicalRecord(futureFormat:): future-format and UInt64.max cases preserve original bytes, preview and visible messages.

The first record in a native run is a fixture, not a production account or live external provider. These are intended native persistence/regression tests, not a claim of physical Apple security or account acceptance.

## Validation performed

- Four proposed Swift files pass Swift 6.3.3 frontend parsing on Windows.
- git apply --check succeeds against the recorded canonical files.
- Every canonical source file remains byte-for-byte unchanged.
- Actual SwiftData execution, Apple compiler type checking and UI execution have not run. The two parameterized methods must be selected with their real argument labels; exact selectors are in validation.json.
- Since the synchronous record reader affects original load/save/delete paths, retain the existing store conflict/foreign scope/deletion, disk reopen and temporary cancellation regressions when selecting the next native acceptance. Do not claim older native results executed on this proposal.

## API verification

Five official Apple DocC resources were retrieved successfully and retained under official-api with hashes and declarations. They confirm the readonly ModelConfiguration initializer and defaults, PersistentModel.modelContext, ModelContext.rollback, and the default/automatic app-group configuration. The installed Apple compiler remains the final typecheck authority; no additional native run was dispatched by this agent.

- https://developer.apple.com/documentation/swiftdata/modelconfiguration/init(_:schema:url:allowssave:cloudkitdatabase:)
- https://developer.apple.com/documentation/swiftdata/modelcontext/rollback()
- https://developer.apple.com/documentation/swiftdata/persistentmodel/modelcontext

## Scope limits

This is logical clearing in the selected original conversation owner/store. It does not implement account logout, CloudKit identity fencing, revocation of every other mounted-window presentation cache, a product-wide erase action, backup expiry, or forensic SQLite/WAL erasure. The package-level ConversationStore.delete contract remains unchanged; the user clear action uses the explicit empty revision barrier so it does not reopen a nil/create hole.

The source review identifies broader SDK05 gaps in OWNER_AUDIT.md. Those remain open. No source patch was applied, no CI was dispatched or cancelled, and no live user data or credentials were modified.
