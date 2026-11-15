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

## Exact UI seam (A2UI owner)

`@MainActor @Observable final class HanlinAppSplitOriginCoordinator` exposes:

- `static let shared: HanlinAppSplitOriginCoordinator`
- `private(set) var acceptedOrigin: SplitBridgeRequest?`
- `private(set) var lastFailure: SplitBridgeFailure?`
- `func acknowledgeAcceptedOrigin(requestID: UUID)` clears only a matching accepted ID, without
  consuming mailbox again; an older asynchronous mount cannot erase a newer delivery.

A2UI may retain shared and observe acceptedOrigin outside View.body navigation mutation. The
value is the SAME SplitBridgeRequest from navigateToOriginalConversation after save/fresh check/
one-time accept. Resolve request.chat to exactly one EXISTING row again at mount; no selected-chat
fallback or recreation. request.session is explicitly the original SDK Session UUID, NOT sceneID.
The SDK owns root .onOpenURL. Existing vision/study branches are preserved; other existing routes
are untouched. UI navigation/mount acknowledgement remains A2UI-owned.

## Verification boundary

Source syntax and diff checks pass. New actual Session association controls passed in separate
Apple run43743854538 at exact364f10a6:27 EXECUTED_PASS (20 Session,6 Context,1 Dispatcher),
iOS compile PASS. Authenticated ledger retains exact hashes/xcresult IDs/locks/toolchain. schema-only43742612086 does not cover this follow-on. The readonly isRunning
accessor and actual app composition still need combined app compilation. Six prior actual app
component controls remain authored NOT_RUN. Actual Split dispatch/save-before-accept/race/cancel/
duplicate/deleted/deadline controls, original XCUITest, two-app cold process, signed group and
physical device acceptance remain OPEN; injected open/target seams are not device proof.

The DTO fingerprint now uses the approved exact JSON parser/writer facade with scalar key ordering
and normalized exact decimals; no portable projection sits between existing DTO encoding and hash.
An actual row-store receipt-dedup control compares9007199254740992/9007199254740993 outcomes under
the same original invocation/result/request and requires typed conflict with unchanged stored bytes.
This app control and the acknowledgement/remount-state control are authored NOT_RUN until app
compilation; a separate exact writer case+iOS compile is the only new package proof obligation.
