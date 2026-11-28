# R2 review: owner drain with exact successful history-clear recovery

R1 remains immutable in candidate-r1. Root review found that a legitimate active clear can make the old producer's final CAS save fail with storeConflict; retaining that error forever would block the same owner. R1 is therefore not approved for integration.

R2 keeps the same real producer/persistence join and unchanged Session.invalidate(), but adds a narrowly scoped owner exception for an actual successful clear-history transaction. The owner captures its current Session, requires that the active Session belongs to the same original store/conversation/namespace, cancels authority, and retains that exact pending invalidation task. Only after the unchanged HanlinConversationMutation.clearHistory succeeds does it capture the real empty canonical record and actual replacement message.

A five-line internal synchronous accessor on HanlinAppConversationStore calls its existing original-record decoder/identity guards. The async load method and every existing store operation are byte-identical. The accessor permits an exact persistent or temporary CAS snapshot without yielding between the real clear and receipt capture.

The recovery wrapper belongs to that owner and awaits the original pending task. If it succeeds, there is no error to recover. If it fails, the wrapper accepts only HanlinHostError.storeConflict, with the same owner still holding that store, no new Session installed, the exact captured retiring Session no longer running, and the exact store/row/context/temporary identity unchanged. It then synchronously rereads the canonical record and requires equality to the captured successful empty revision, plus the same sole replacement-message object belonging to the same row. Any different failure, failed clear, changed record/replacement, missing/deleted row, changed store, or still-running writer remains an error.

The old Session's failed persistence task is never reset. The positive regression calls invalidateAndDrain on that old Session again and still requires its original storeConflict. Only the owner with the exact successful clear receipt may admit a fresh writer of the newer revision. The two original coordinator writer guards remain unchanged, so this cannot admit a competing owner/writer.

R2 also repeats the existing original-row identity check after internal invalidation even when dataAccess is nil, before constructing the next engine. A dedicated regression deletes the actual SwiftData row during the original invalidation callback and verifies that engine construction is never reached.

## Added controls relative to R1

- Active clear followed immediately by the same owner's new request, parameterized over persistent and temporary storage. It requires actual old CAS failure, actual producer drain, a fresh Session, successful new canonical write, and no old canonical run resurrection; temporary rows remain uninserted.
- Changed or failed active clear remains rejecting. Both store modes exercise a second clear changing the exact receipt before asynchronous cleanup. The persistent mode also exercises an unsupported canonical-record failure from the original decoder, which must not be forgiven.
- Deletion during internal invalidation with nil dataAccess fails before engine construction.

The six R1 regressions remain. Total additions are nine method definitions, with eleven semantic invocations across package and app tests. No original assertion body or test limit changed. Every new method has the existing one-minute test limit style.

## Verification and limits

This is uncompiled source. The complete original Session and store recover by removing only their additive APIs. Both original test files recover by removing added blocks. Both coordinator guards are exact. The fifth changed path also has zero intersection with the accepted SDK396/Host99 sets and no canonical audit reference; HanlinPlatform and its actual619 tree remain unchanged.

Actual original AgentSessionTests (25 source definitions) and future original90 app coverage remain required. The original90 request selects the whole owner suite and unchanged conversation supersession case. No native gate, compiler, runtime, new SDK producer, or private signing action ran for this candidate.
