# Foreground transport v1 — approved 2026-11-15

K/L implementation contract supplied by the active manager. This uses the existing App Group; no new signing capability, Keychain group/key, domain/AASA, permission authority or conversation store is introduced. Live state is never migrated by this adapter.

## Wake format and identity

- MiniApps: `hanlinminiapps://split/v1/open/<lowercase-request-UUID>`.
- AI: `chavrusachat://split/v1/return/<lowercase-request-UUID>`.

`SplitForegroundRoute` accepts only the exact scheme/host/version/direction/UUID roundtrip. Userinfo, port, query, fragment, encoded path variants and appended path/payload are rejected. A URL supplies only an opaque reference. Native product bundle IDs are not logical canonical MiniApp IDs and must not be converted into caller/target authority.

The existing AI chavrusachat scheme and maktabah query entry remain intact; MiniApps registers its own scheme. Queries for the companion schemes are declared. Scheme registration and an OS open result cannot prove the handler's identity: another app can register the same scheme. Authority/result completion must come from the matching mailbox record. Missing/hijacked handlers can produce failure/timeout, never result completion from URL contents. See Apple's [custom scheme documentation](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app.md) and [URL query behavior](https://developer.apple.com/documentation/uikit/uiapplication/canopenurl(_:).md).

## Trusted group principal

The manager explicitly accepts all first-party apps/extensions actually entitled to `group.com.itorah.chavrusachat` as one trusted principal for this transport. There is **no per-app writer authentication claim**. A file's caller/target/bundle fields and its product folder do not establish cryptographic app identity. An arbitrary external URL sender is not a group member and cannot create an authorized request merely by supplying a UUID.

`HanlinSplitMailbox.init()` resolves that OS container. Its internal injected initializer is used by owned tests. The fixed root is `<trustedGroup>/HanlinSplit/v1`, separate from both extension stores. Each transaction checks all fixed namespace ancestors, then reuses `HanlinScriptExtensionStore`'s original traversal/no-follow guard and interprocess lock through `transactManagedState`. That bounded canonical IO helper accepts a restricted JSON basename, rejects lock/traversal paths and symlinks/nonregular files, and atomically replaces state with exact readback. It does not delete state or reset corruption. This is process-level recovery, not verified power-loss durability.

The single mailbox.json contains version1 sender ledger and receiver database. Both are fully validated before/after every operation; receiver records must equal the original immutable sender request. The complete encoded state is bounded to16MiB, individual requests/returns to the existing64KiB codec bound, and existing128 receiver/1024 sender capacities still apply. Capacity/corruption errors fail explicitly; there is no automatic historical record pruning or state migration in this tranche.

## Admission, execution, return

1. Sender composition obtains current canonical descriptor/package/generation, active origin session/chat and existing host/OS authorization. It durably begins+dispatches before opening the companion URL. Failure to open must finish that dispatch with companionMissing; open success alone is dispatch, not completion.
2. Receiver resolves the reference from the trusted group mailbox, then uses the existing `SplitDurableReceiver`, current catalog/package/context/schema and original authority. No URL field supplies those values. Persist a unique attempt before calling the existing broker/engine; do not create a second runtime.
3. Interrupted executing attempts remain outcomeUnknown. Reopen/redelivery cannot grant another attempt. Reconciliation requires the existing executor's actual result, never a guessed success. Reserved/completed records retain their existing semantics.
4. Return lookup requires a completed receiver record exactly equal to the sender request. `acceptCompleted` compares the current canonical context and invokes the original ledger's one-time acceptance. The historical API argument named authenticatedSender is adapted under the explicit trusted-group policy: it means this matching target record came through the trusted group principal, not proof of a native app writer. Origin chat/session come from the original durable request, never the currently selected chat or URL.

## Current evidence and remaining composition

42 strict route/sender-database/cancellation cases executed locally on Windows Swift6.3.3 using actual contract/core sources, recorded in foreground-results.json with original compiler/source/output/log lineage. They are not Apple URL behavior or app acceptance. The next focused workflow also executes these42 on its actual Mac toolchain and retains raw proof independently.

Twelve hosted mailbox/return tests are authored, including: independent adapter reopen/one-time exact origin; missing/wrong origin; interrupted attempt; simultaneous receiver instances; companion missing; corruption retention; namespace/slot links preserving AI bytes; exact byte limit/traversal/lock-name rejection. These are **NOT_RUN** until native execution. Five extension-storage tests and four app UI cases remain separately required. The17 hosted cases are NOT_RUN; the separate Mac38 pass atc90b553a does not claim the four newly added cancellation cases executed on Mac. Adapter reopen/concurrent instances are not a two-app cold-process/provisioning test.

The production adapter, strict URL registrations, MiniApps onOpenURL/presentation/cancel/return controls and original broker path now exist in source. The AI Session/Composer owner still must install the concrete original-origin consumer described below. Native compilation and actual two-app acceptance remain blocked/open. No disconnected callback, source-only target, unit fixture or OS open result is reported as cross-app completion. Actual two-app cold launch/return, deleted/stale origin, iPad/RTL, signed group access, physical device and complete migration/278-capability acceptance remain OPEN.

## Concrete AI owner handoff

`HanlinSplitForegroundTransport` is a shared leaf with no Agent SDK/model/store dependency. The AI application owner implements `HanlinSplitOriginalOrigin` over its existing canonical Session, Host receipts and conversation row:

- `currentContext(for:)` resolves the original existing chat/session/account and current canonical target metadata+authority. It cannot substitute the selected chat, manufacture a Session from a stored reference, or restore old grants. MiniApps exports current descriptor/package/generation snapshots through the same mailbox; the receiver rechecks its own actual registry before action execution. The export is discovery, not a second installed registry.
- `persistVerifiedResult` commits into the original conversation/Host receipt path, idempotently by full request+origin. Return handling previews validated completed data, awaits this save, reevaluates the current context, then commits one-time mailbox acceptance. A conversation-save failure leaves the result retryable; an existing receipt deduplicates a retry after mailbox IO failure.
- `navigateToOriginalConversation` receives the accepted immutable original request after both commits. Deleted origin means unavailable; it must never create another chat or route to the current selection.
- The original owner must call transport.invalidate(reference) on account/session/run cancellation/invalidation. This atomically revokes the sender and interrupts any reserved/executing receiver. Already-executing work remains outcomeUnknown; cancellation never proves absence of a side effect. No URL cancellation endpoint or new permission engine exists.

Production dispatch durably records admission before UIApplication.open. A false OS result records companionMissing; a true result is dispatch only. The MiniApps return button reevaluates current package/generation/descriptor authority, reserves the existing receiver's one-time attempt, calls the original requestBroker, commits the original typed result, and opens only the opaque return hint. Executor failure is conservatively outcomeUnknown; no action is retried automatically. The MiniApps UI can close/cancel a pending reservation. Swift Parity's already-registered share.value route is now declared in its canonical descriptor (revision2), with its existing inter-app.share capability and no new handler/engine.

The AI App entry point, Composer/Session consumer, actual invocation-to-receipt association and exact-chat navigation are an explicit integration handoff, not implemented by a substitute store or hidden UI callback here. Manager owns the coherent AI SDK linkage/source registration in the integration worktree; Split adds no parallel SDK package/product links. Current MiniApps target shares60 original/leaf host source files and no Agent SDK engine/model/chat-record products.
