# Actual AI Split origin composition (source, app verification pending)

This follow-on depends jointly on SDK Host association d80e1558/364f10a6 and Split leaf/product
source a45e203c5989e3a43c53c2f9eeecac27ea769a30. The Split-owned files are not copied or forked
here. Manager owns coherent target/product linkage. No new conversation database, permission
registry, MiniApp runtime or model loop is introduced. Original shared leaves remain Split-owned.

The sole new tool is open_mini_app in the existing application Host catalog/Session dispatch.
It is exposed only with the original application tool adapter in an existing persisted SwiftData
conversation. Temporary conversation dispatch is explicitly unavailable in this first tranche; it
must not advertise a durable cold-return path for transient-only metadata. Its model input permits only target
hanlin.demo.swift-parity, action share.value and payload. Original caller, actual SDK Session UUID
(mapped explicitly to HanlinAppSessionID), chat, requestID, expiry, installed package/generation,
canonical call/result identity and original response row are issued by the Host. It verifies the
original bytes and exact portable value, live canonical target metadata and original existing
MiniApp authorization. Support for arbitrary MiniApps/actions is not advertised.

Before OS open, Session.associateHostInvocation commits one bounded versioned opaque origin
reference through the SAME ordered persistence tail. It contains existing immutable call/result/
row identities and a hash of the original SplitBridgeRequest, not payloads or permission. The
actual resultID was already reserved by the Dispatcher. No store.save competes with an active
Session. Cancellation/deadline revokes locally before mailbox cancellation; started effects remain
uncertain, never retry/rollback. IO failure is exposed. Pending calls/tombstones are bounded64.

On return, transport performs strict URL parsing, exact mailbox preview and current-origin checks.
The coordinator releases the original Host completion FIRST. It then awaits the existing
onHostResult callback, which runs only after actual canonical receipt save and fresh context.
Only then can transport recheck, accept once and call navigate. This ordering avoids waiting for
a callback whose own tool completion was still held. Duplicate returns share completion/receipt;
changed input/outcome, deleted origin, cancellation, deadline or failed save never navigate.

Cold return resolves the original association and SAME private historical-row decoder using the
existing row store and actual personal-library namespace. It verifies the complete request hash,
original canonical Session/run/step/call/result/row and explicit app-session mapping. It creates no
Session/Host/engine/grants. The existing store adapter can append only a metadata receipt under
CAS while no registered Session is running; exact existing receipt/digest deduplicates. This is
historical reconciliation, not model continuation or a second effect. Interrupted work and
cancelled mailbox states retain original conservative transport semantics.

## Exact receiving-window UI seam (A2UI owner)

The root wraps actual WindowGroup content in HanlinAIReceivingWindowRoot. Its private State UUID
belongs to that window's view hierarchy, NOT the App singleton or ChatView sessionScopeID. It is
provided as `@Environment(\.hanlinAIReceivingWindowID) var receivingWindowID: UUID?` (default nil).
Apple documents separate State storage for each WindowGroup window:
https://developer.apple.com/documentation/swiftui/windowgroup.md (lines61-63).

Root onOpenURL calls `claimReturn(_:receivingWindowID:) -> UUID?` synchronously BEFORE creating
Task/await, then passes that exact nonce/window to receiveReturn. One process delivery slot is
reserved through acceptance/mount ACK. Missing owner, duplicate/different-window reception or
another in-flight delivery is unavailable; no window list/first-window/current-chat fallback is
used. The existing durable mailbox/receipt is retained. First tranche guarantees only the actual
OS-receiving AI window; original-window and multi-window acceptance remain OPEN.

`@MainActor @Observable HanlinAppSplitOriginCoordinator.shared` exposes to A2UI:

- `func acceptedOrigin(forReceivingWindowID: UUID?) -> SplitBridgeRequest?`
- `func acknowledgeAcceptedOrigin(requestID: UUID, receivingWindowID: UUID?)`
- `func failure(forReceivingWindowID: UUID?) -> SplitBridgeFailure?`

The unfiltered acceptedOrigin storage is PRIVATE. Only the matching window can read the SAME
original SplitBridgeRequest or ACK it. Read the filtered value in the MainTab hierarchy; route
outside View.body and repeat the filter after any mount await. ACK only after mounting the exact
existing request.chat. A stale request/window/nonce or old ACK cannot erase a newer delivery.
SDK Session IDs are never compared to receiving window IDs or existing ChatView scene IDs.
No request DTO, conversation store, grants or new window is created by this routing state.

UI navigation/mount acknowledgement remains A2UI-owned. Root preserves vision/study/other existing
routes. Added component controls cover pre-await exclusive claim, missing/different owner,
wrong-window/old ACK, old receive task and deleted origin. They remain authored NOT_RUN pending
actual app compilation; this is not a physical multi-window or original-scene acceptance claim.

## Verification boundary

Source syntax and diff checks pass. New actual Session association controls passed in separate
Apple run43743854538 at exact364f10a6:27 EXECUTED_PASS (20 Session,6 Context,1 Dispatcher),
iOS compile PASS. Authenticated ledger retains exact hashes/xcresult IDs/locks/toolchain. schema-only43742612086 does not cover this follow-on. The readonly isRunning accessor compiled in the later exact7df writer/iOS proof43745924452;
its actual app consumer/composition still needs combined app compilation. Nine owner/store/Host controls and eight Split composition controls remain authored NOT_RUN. Actual Split dispatch/save-before-accept/race/cancel/
duplicate/deleted/deadline controls, original XCUITest, two-app cold process, signed group and
physical device acceptance remain OPEN; injected open/target seams are not device proof.

The DTO fingerprint now uses the approved exact JSON parser/writer facade with scalar key ordering
and normalized exact decimals; no portable projection sits between existing DTO encoding and hash.
An actual row-store receipt-dedup control compares9007199254740992/9007199254740993 outcomes under
the same original invocation/result/request and requires typed conflict with unchanged stored bytes.
This app control and the acknowledgement/remount-state control are authored NOT_RUN until app
compilation; a separate exact writer case+iOS compile is the only new package proof obligation.

## Authored actual app component controls (NOT_RUN)

HanlinAppSplitOriginTests adds eight bounded controls using the actual app Session owner, original
ChatRecords+assistant ChatMessages, original SDK model loop/Host dispatch/ordered writer,
coordinator, mailbox, transport and durable receiver. The OS open/target metadata and receiver
operation result are explicit fixtures. They verify durable association before OS-open observation,
actual original Session/run/row mapping, receipt committed before one-time acceptance, same-engine
tool continuation and duplicate return; cancellation DURING the awaited OS open (no lost waiter),
cancellation after executing receiver (outcomeUnknown); deleted original without recreation or
mailbox accept; and expired context before target/store lookup. Async probe/stream waits are
bounded8s. This is not a live broker effect, signed-group or two-process/device test. The test
requires the actual Split a45 parity descriptor/action source and products, never a copied DTO.

An actual source review caught a cancellation window while UIApplication.open was suspended:
local revocation could occur before any Host waiter existed. The coordinator now rechecks task/
local cancellation after dispatch and immediately before installing that continuation, so a
cancelled origin cannot install a waiter after its timer/owner was already revoked. Known
admission failures return notDispatched; possible post-dispatch cancellation/IO stays uncertain.

Live/cold context also fetches the actual original assistant ChatMessages by its immutable ID and
checks role+original conversation relation after awaits. A missing/deleted/reparented message cannot
retarget another row merely because its conversation still exists; a sixth component control covers
this independently of conversation deletion. This app still uses the actual personal-library
namespace. No authenticated multi-account/iCloud-account-switch readiness is claimed; that DATA
boundary remains OPEN rather than inventing an account registry or silently migrating old rows.

Cold-write exclusion tracks every actual Session ID, including several scenes over one conversation,
using bounded256 weak references. A later idle/failed owner cannot hide an earlier running writer.
Registration fails closed before installing an owner when capacity is exhausted. A seventh app
control starts the real pending original call, registers a second owner rejected by the existing
unresolved-write gate, and requires that the original active writer still excludes cold saves.

Exact writer run43745924452 at7dfd30b7 executed the one new writer case and iOS AgentCore compile,
both passed. Raw ZIP SHA256/all CRCs plus245 source hashes against Git+tar are authenticated in
evidence/exact-writer-43745924452.json. It does not execute the conflicting-outcome row test or
any app/UI control; no app acceptance is inferred from that pure case.

Settled-live receipt reconciliation is also final even if no later cold-reference entry exists:
the store deduplicates the latest original canonical identity/result first and rejects changed
settled outcomes. Only an explicitly matching provisional uncertain reference may transition to a
verified hashed result once. Live duplicate request/response comparison uses exact fingerprints
as well as typed identity, avoiding Swift String canonical-equivalence shortcuts. The ninth actual
store control covers live-without-cold-marker and provisional-to-final paths using conflicting
large integers AND K/Kelvin outcomes, requiring unchanged bytes after the conflict. It is authored
NOT_RUN, not represented by the pure exact-writer case.

Receiving-root disappearance revokes only its own UI claim. It does not cancel/retry the business
operation or infer an original Scene ID. If canonical receipt save outlives that view, a matching
claim nonce is required again before mailbox acceptance; the receipt remains stored on failure.
Another window's disappearance cannot erase this delivery. The wrapper's existing State/content
code passed standalone Mac SwiftUI typecheck atc7905d84 in toolkit43749408559 (0 runtime tests,
no app graph); after adding its disappearance callback, the changed file needs its own fresh
focused typecheck. Neither preflight substitutes for enabled iOS app/scene XCUITest.
