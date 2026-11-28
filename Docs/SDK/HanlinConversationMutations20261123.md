# Original conversation mutation integration — 2026-11-23

## Single implementation

The public context now exposes `renameConversation(_:title:announceChange:)`,
`setConversationPinned(_:isPinned:)`, `deleteConversation(_:)` and
`clearConversationHistory(_:)`. These methods delegate to
`HanlinConversationMutation`, which operates on the same original `ChatRecords`
and `ChatMessages` identities as Hanlin.

Original `ListView` pin/delete and appearance editing, the original chat title
editor, delayed automatic title generation, original temporary-chat cleanup,
and the original owner clear-history entry point all use this writer. The
original toolbar's Chinese/English information-message text, model display name,
role and insertion behavior are preserved. List appearance editing retains its
original metadata-only/empty-title behavior. No layout, renderer, animation
constant, replacement engine or second conversation store was introduced.

The existing `HanlinAppConversationStore.clearHistory` implementation is
unchanged: visible and canonical history share one save, an empty CAS revision
blocks late old canonical writes, and original draft/title/canvas/independent
saved excerpts remain intact. The same original temporary store is passed
through the owner, preserving ephemeral clear-history behavior.

## Original-row mutation lifetime

Before delete/clear, the writer validates the exact original object, container
and conversation UUID. It revokes the existing conversation lease and all weakly
registered original owners synchronously, covering preparation, history loading,
live streams, consent and idle inline tool authority. Authority is removed
before cancellation callbacks or asynchronous cleanup. Registrations contain no
replacement engine, persistence or account implementation.

The original UI and headless entry points attach cancellation to their existing
run lease. Revoked original projections ignore late chunks/errors/cancellation
writes, and completion throws instead of reinserting a deleted row. Older
release/cleanup tokens cannot revoke a newer admitted turn. Pending original
engine preparation checks the revoked registration after suspension, before a
Session can be installed/admitted.

Original inline Query tools also use this same per-conversation lease while
retaining their existing serialized execution. Inline callbacks are restored
synchronously on revocation; a delayed old task's cleanup is guarded by its exact
operation UUID and cannot clear newer callbacks or active-run fields. Rich
activity completion checks its original live Session and row lifetime before
saving.

Metadata mutations and deletion checkpoint prior edits, save once, roll back
their own uncommitted changes on failure, and throw the actual save error.
Original clear-history retains its existing checkpoint/rollback transaction.
Success notifications carry original object identity, so disappearing views do
not read deleted SwiftData fields or write draft state back into a detached row.
Retained headless controllers refresh after clear and are invalidated/evicted
after delete. An old controller cannot silently bind a recreated UUID.

## Focused native acceptance

Four added methods are in the existing selected embedding suite:

- `HanlinApplicationEmbeddingTests/conversationMetadataMutatesOnlyTheOriginalRowsAndPreservesAnnouncement`
- `HanlinApplicationEmbeddingTests/conversationDeletionRevokesPreparationAndRejectsLateProjection`
- `HanlinApplicationEmbeddingTests/conversationMutationRejectsAForeignContainerBeforeRevocation`
- `HanlinApplicationEmbeddingTests/conversationMetadataAndDeletionReturnSaveFailuresAndRollback`

The first checks real original row identity, draft/pin preservation, exact title
announcement and equal-name isolation. The second exercises actual original
preparation, synchronous revoke ordering, late stream/failure/cancellation
projection, cascade deletion and newer-token protection. The third proves a
foreign container is rejected before either account's owner can be revoked.
The fourth reopens a real original SwiftData store read-only and requires actual
rename/pin/delete save failures and rollback.

Two added methods are in the existing original owner suite:

- `HanlinAppAgentSessionOwnerTests/deletingConversationDuringOriginalEnginePreparationCannotAdmitLateSession`
- `HanlinAppAgentSessionOwnerTests/stoppingInlineToolReleasesOnlyItsLeaseBeforeNonCooperativeExecutorDrains`

It pauses the original injected engine factory, deletes the original row, then
resumes that factory. No late Session may install, and no original row/message
may reappear. Existing original clear-history tests now traverse the shared
writer and remain the relevant unchanged CAS/draft/canvas/bookmark/read-only/
temporary-store assertions.

## Verification boundary

All ten changed/new Swift source/test files passed Oracle Swift syntax parsing;
`git diff --check` passed. These checks do not establish native SwiftData,
SwiftUI, Keychain, runtime or visual acceptance. No CI was dispatched by this
lane. The six new methods and affected original owner/projection/UI closure
require the parent's integrated Apple gate; no prior receipt is relabeled as a
test of these new changes.

The source changes add two original application files, so regenerate the
aggregate application manifest before the combined native compile. They do not
change standalone AgentCore, Host Contracts, ChatUI or Lorvex's selected package
closure.

## Review follow-up: ordinary Stop and detached temporary title edits

The owner retains its current inline operation UUID and exact run lease. Ordinary
Stop revokes/releases that lease synchronously before waiting for a tool that
ignores cancellation. Its old defer remains token-guarded and cannot release a
newly admitted lease. The native regression pauses the actual injected native
executor, approves only its synthetic tool, stops the owner, admits the next
lease while the old executor is still paused, then drains the old executor and
asserts it cannot emit more activity or release the new lease. It cleans up only
its uniquely named synthetic approval grant.

The manual title-edit path now passes its original temporary-chat flag as well.
The existing metadata regression verifies that renaming a detached temporary
row keeps it ephemeral and inserts no persistent conversation/message.
