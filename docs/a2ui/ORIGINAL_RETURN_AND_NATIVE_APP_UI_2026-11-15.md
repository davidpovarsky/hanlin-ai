# Original return navigation and native app UI controls

Required joint SDK dependency:c7905d8489394ccc3f38236fb24e14fe498f0a52, including its7df/da2f
composition/bootstrap source and the original app owner/restore contracts. Integration owns
the combined graph, real SDK/Platform/Split leaves and product dependencies. This branch does
not duplicate the SDK coordinator, root onOpenURL dispatcher, mailbox, store or APIManager.

## Existing navigation consumption

MainTab observes the actual coordinator's `acceptedOrigin(forReceivingWindowID:)` and selects the existing Chats
tab. ListView retains the full SAME SplitBridgeRequest through the existing wide/compact routes,
resolves request.chat with a fresh exact SwiftData fetch, and rejects missing/ambiguous/temporary
rows. It neither recreates a chat nor falls back to the selected/default conversation. The normal
default-selection paths are suppressed while reporting an unavailable original.

The actual appearing ChatView re-resolves the original row, verifies object/context identity and
the workspace's original chat selection, and reports mount completion. Both UI callbacks require
full request equality against the pending/coordinator delivery. Only then does the parent call
acknowledgeAcceptedOrigin(requestID: request.id, receivingWindowID: receivingWindowID); a late old mount cannot erase a newer delivery.
The same exact-ID acknowledgement runs after an unavailable mount. No UI code parses a URL,
accepts a mailbox again, decodes the canonical row reference, creates a Session or rechecks a
different permission registry. request.session is the mapped original SDK Session UUID; it is
never compared to sceneID. Cold receipt reconciliation stays with SDK composition. Temporary
Split dispatch and cold process/device acceptance remain unsupported/unverified in this tranche.

The SDK root supplies the actual per-WindowGroup content token through
`hanlinAIReceivingWindowID`; nil or another owner produces no delivery/failure/ACK. ListView
captures that same token with the full pending request and checks both again before ACK.
ChatView likewise checks the token-filtered full request before/after fresh original-row
resolution. No new scene registry, first/current-window selection or SDK-session mapping exists.
This tranche returns the original conversation in the window that received the link; it does
not promise return to the original originating window or completed multi-window acceptance.

Token-filtered transport failures observed while MainTab is active receive a generic native alert; an
accepted request whose original row disappears before mount receives the ListView unavailable
label and exact acknowledgement. No raw payload/error details are presented as diagnostics.

## Real app fixture assertions authored, NOT_RUN

Four `AI_HLYUITests/HanlinNativeA2UIChatUITests` cases consume the SDK's explicit
HANLIN_NATIVE_A2UI_ACCEPTANCE + HANLIN_NATIVE_A2UI_FIXTURE_PLAN port. They use the actual native
schema request, Responses parser, pure official validator, Session/Host/owner, original ChatView,
original assistant rows and canonical in-memory store. The shared valid JSONL frames are wrapped
in complete native parts; message/run/row identities remain Host-issued. No legacy acceptance
flag, separate renderer, direct SDK callback or provider engine is installed by the tests.

Cases cover original form edit/submit with the actual original Host continuation and edited
value checked by the HTTP fixture, preservation/nontransmission of an unsent composer draft,
existing expanded Surface dismissal followed by an authorized original form submission,
same-process reopen before any second model request with historical form controls disabled and
local media enabled, and Surface-only output in the original assistant row. Assertions retain
screenshots/AX. The DEBUG/simulator-only status view exposes actual attempt count/failure and
original chat UUID, refreshed on the original UI run's start/end and initial appearance.
Both rejected attempts and failures must be checked; UI content alone cannot certify a request.

These are authored controls, not native passes. Root in-memory/CloudKit.none isolation and HTTP
transport remain SDK-owned. Reopen is within one process, not cold persistence. Split dispatch
requires a persistent conversation and is not enabled by this A2UI in-memory fixture.

## Validation boundary

Local enabled Swift syntax and whitespace checks passed. MainTab/ListView/ChatView/resolver,
bootstrap status and all four original-app XCUITests require compilation/execution of the coherent
enabled app graph AFTER the existing Runtime canonical prerequisite is resolved. No full app
retry is dispatched for that same blocker. Native media component UI runs remain independent:
they do not establish this navigation, APIManager/SwiftData or app-fixture path. The later stable
SDK Session/Host association dependency must be assessed before consumer/unit reruns; the prior
d1-backed15 cases retain their original version and cannot be relabeled as the combined graph.
