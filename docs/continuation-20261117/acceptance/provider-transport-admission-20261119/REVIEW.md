# Original provider transport admission — review packet

Status: unapplied proposal against 25c28ae8981eceba18a2beb648da5d1a7660ac63. Native NOT_RUN. Canonical source and frozen credential phase1/phase2 packets are unchanged.

## Concrete defect

The current original APIManager resolves its selected key through the typed credential port and rechecks owner/key authority. It subsequently awaits tool preparation, catalog visibility and diagnostics before sending. Those checks precede the suspension rather than the actual network start.

In the SDK route, HanlinAISDKProviderFactory.makeFetch awaits onRequest and then enters URLSession.bytes without another host admission. APIManager creates that fetch inside engineFactory, capturing the current manager, runID, tool adapter and diagnostics. HanlinAppAgentSessionOwner intentionally reuses the engine across matching turns, so merely adding a fixed guard to the old factory would retain the first turn's lease and callbacks.

The direct route also starts its URLSession in an existing detached producer. A guard outside that producer would leave an additional scheduling gap.

These are source-established gaps. This packet makes no claim that a real user credential was observed leaving a revoked request.

## Exact patch

original-provider-transport-admission.diff
45,183 bytes
SHA256 c03136b216e123b665ba3eb04dabdf4bbca05847286757b99716858da47cd2f1

Seven changed Swift files:

- AI_HLY/Services/ChatServices/APIManager.swift
- AI_HLY/Downstream/ChatCore/HanlinAppAgentSessionOwner.swift
- AI_HLYTests/HanlinAppAgentSessionOwnerTests.swift
- Packages/HanlinAgentSDK/Sources/HanlinAgentCore/HanlinAgentSession.swift
- Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKAgentEngine.swift
- Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKProviderFactory.swift
- Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinChatEngine.swift

## Smallest complete boundary used here

1. HanlinChatRequestAdmission is a generic asynchronous throwing callback. The SDK fetch invokes it AFTER awaited request diagnostics and immediately before starting the actual transport, with cancellation checks on both sides.
2. The direct ChatEngine invokes the same callback inside its existing detached producer before URLSession.bytes. Rejected admission emits no transport-start observation. Existing cancellation mapping and stream parsing stay in place.
3. APIManager captures the original DataAccess epoch, model, provider PersistentIdentifier, exact stored credential representation, endpoint and API kind. The admission callback holds the manager weakly and revalidates that original lease.
4. It checks the original managed row AND a fresh read from the same original SwiftData container, then resolves/matches the actual current Keychain credential. A change from another context cannot be authorized solely by a cached managed object. No account identifier or alternate store is introduced.
5. HanlinAISDKTurnTransport carries one stream's fetch. Optional parameters pass it through the existing owner, Session and engine. The engine/agent loop remains the same retained instance; only that turn's provider uses the supplied fetch. Old streams keep their own immutable callbacks and cannot borrow a newly installed manager or epoch.
6. An explicitly injected provider owns its transport. The new per-turn option fails closed for that constructor instead of silently replacing its model with a network provider.
7. Engine configuration matching compares opaque credential UTF-8 bytes, preserving the exact-byte invariant already used by the credential store.

The internal bindDataAccess method returns the already-created DataAccess receipt and is marked discardable. This lets the actual caller pass the same admitted lease to the original owner; it does not create another authority or bypass the owner.

The original diagnostic closures are created for every SDK invocation rather than only when engineFactory first runs. They still use the existing recorder, round adapter, UI run and transport journal. No diagnostics are treated as authorization identities.

All new shared APIs are optional with nil defaults. Existing SDK clients and injected-provider streams without a new turn transport keep their current routes. Host identity, authorization and SwiftData dependencies remain confined to the original app owner.

## Adversarial native evidence prepared

All tests are in the original HanlinAppAgentSessionOwnerTests suite and use the original owner/APIManager, original disk SwiftData schemas, actual Security APIs in a unique synthetic service, actual URLSession with an injected URLProtocol, and the production transport functions. The URLProtocol intercepts every URL, so synthetic credentials cannot escape to an external provider.

The negative request is built by the original HanlinChatRequestBuilder, contains an actual synthetic Authorization header and a nonempty synthetic prompt body, and is already prepared before the diagnostic pause. Tests require zero URLProtocol starts after the specified change.

| Method | Cases | Boundary |
| --- | ---: | --- |
| originalProviderAdmissionRejectsChangesDuringDiagnosticAwait(change:) | 7 | Pause the actual fetch's onRequest; revoke owner, rotate key in another context, rotate to a new reference with the same secret, change endpoint in another context, delete original conversation, rebind the original owner epoch, or cancel the task. Only the cancellation control expects CancellationError; the authority/state controls require staleContext. Every control requires zero transport starts. |
| originalDirectTransportRechecksOwnerInsideItsProducer() | 1 | Pause the direct producer's final admission, revoke its actual owner, resume and require staleContext plus zero network starts. |
| originalReusedSDKEngineUsesEachTurnsManagerAndTransport() | 1 | Run two real SDK turns, two APIManagers and two transport callback sets through one retained owner/Session/engine. Require exactly one engine creation, same HostSession identity, actual visible SSE output on each turn, exactly two original transport requests and callbacks [1,2]. Keep the old manager alive and prove its prior lease rejects after the second bind. After completion prove the engine does not retain the last manager. |
| originalInjectedProviderCannotBeReplacedByTurnTransport() | 1 | An explicitly injected original model rejects a proposed network turn transport before any network start. No provider substitution is accepted. |

New methods 4 / expanded cases 10. Native NOT_RUN.

native-new-selectors.txt contains those four exact selectors.
native-retained-provider-selectors.txt retains the complete phase1/phase2 provider lane plus these methods: 23 selectors / 38 planned expanded cases. It is a provider subset, not a replacement for the existing full DATA, memory, clear-history, secret rollback or split-ownership acceptance lanes.

## Authentication and local validation

- All original inputs were copied from exact published 25c28 Git objects.
- All seven changed inputs still equal canonical source at validation time.
- git apply --check succeeds without applying anything.
- Windows Swift6.3.3 -frontend -parse succeeds for all seven changed Swift files.
- Pinned SwiftAISDK e7bf34111e603ca977becd007dd4e5bb109af857 was inspected through an existing immutable local Git object. Sources/AISDKProviderUtils/FetchFunction.swift declares FetchResponse:Sendable and FetchFunction=@Sendable(URLRequest)asyncthrows->FetchResponse. Its blob SHA256 is 5d3e4c4bb2082fc86ae3c8c23b476d90b052b316a544d3fcd1f20af4ec02ad3c. No SDK checkout was fetched or modified.

The syntax result is not Apple SDK typechecking, native execution or transport acceptance. The actual guarded network tests must run on the proposed source. No test result was inferred from phase1 status or another SHA.

## Review limits

The boundary denies a request whose original authority or provider state changed before final admission, including during diagnostic suspension. It does not claim an atomic transaction across SwiftData, Keychain and network sockets, or retroactive recall of a request already admitted/started. Existing stream cancellation remains responsible after admission.

This patch does not invent missing account/logout/CloudKit-owner lifecycle. It checks the already-existing original owner lease and container. The original SDK05 account isolation, synchronization, protected-store and erasure gates remain separate.

Phase1 native 44456578432 remains under the parent's existing observer. The only child status query was saved in phase1-native-status-first.json, where its planner succeeded and its native iPad job was still queued. This packet starts no watcher or CI job, reads no real user credential and modifies no canonical source.
