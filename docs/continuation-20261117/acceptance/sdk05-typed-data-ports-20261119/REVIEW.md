# SDK05 original typed DATA ports — unapplied review packet

Base: 8a505675eca035fbca3877afd1f8776f00f629d0.
The seven target files remained byte-identical in canonical HEAD 7e27ded6111f3e8f3fa793531bc29d9d7de3d5bc at 02:51:57 UTC.
Patch SHA256: d5d1c68abc74316408e0073f81f1079b8c015af8b07a3c9a37831358127cc9d5.
All seven Swift files parse under Swift 6.3.3. git apply --check passes.
These are source/syntax checks, not Apple compilation or behavioral acceptance.

## Actual product call routes

- Existing APIManager now conforms to HanlinCredentialResolver and HanlinMemoryStore. The normal remote model path uses the credential protocol before configuring its existing SDK engine. It validates the exact originally selected provider/model, original request/namespace and epoch again after the protocol await, then verifies the same original provider key and model selection before using the result.
- Existing automatic memory recall in both prompt builders, plus the original retrieve_memory tool, calls the memory protocol. No replacement engine, database, service, or request is created.
- The existing HanlinAppAgentSessionOwner admits a revocable original-request lease before engine creation. It retains the original ModelContainer and reuses the original conversation store's exact row/context validation, without constructing another store. Cancel/invalidation revokes the lease synchronously. Internal engine replacement preserves only the already admitted lease and checks its epoch after suspension.
- The existing AuthorizedAttachmentRegistry implements HanlinAttachmentStore on its single records dictionary. It can adopt original already-registered turn images into the actual HostSession without storing image bytes twice. Typed read/remove require exact namespace, native session identity, MIME and byte count, while retaining the original expiry, revocation, image validation and budgets.
- The original SessionOwner binds the actual tool adapter's image resolver after the real HostSession exists. It takes the currently admitted original row/UI run before the first await and rechecks the original row, session generation and same UI run after each await. This fixes the actual mismatch between original image registration's UI runID and the adapter's diagnostics roundID. A legacy resolver cannot bypass an already adopted HostSession binding.

## Existing memory schema and opt-ins

MemoryArchive.swift contains only id, content and timestamp. UserInfo.swift contains persisted useMemory and useCrossMemory (default true); there is no account/Space/conversation origin on a memory row. The cross-memory UI toggle is currently commented out, but a persisted false value must still be honored.

Every global read now requires both flags. Disabling either suppresses automatic recall and returns a denial through the original tool path. Existing explicit append requires useMemory; existing update requires both flags because it reads/modifies originless global rows. These are fresh checks on each operation, not a tool-catalog snapshot. The original save/update writer remains authoritative.

Typed replace deliberately throws APIManager.DataPortError.legacyMemoryReplacementUnsupported after scope validation and never mutates rows. It cannot implement a namespace-scoped replacement safely by deleting every legacy row. No row is relabelled or migrated automatically.

## Five meaningful added native methods

See native-selectors.json. All are additions to the existing HanlinAppAgentSessionOwnerTests suite:

1. Original credential port: real original APIKeys row; reject foreign provider/model/namespace and original request ID; stale epoch after rebind; deleted original conversation cannot return key or be recreated.
2. Original memory port: actual MemoryArchive/UserInfo rows; timestamp ordering; actual recall call; both opt-outs rechecked; original save_memory tool reports rejectedByCapability; no destructive replace; original append works; revoked owner cannot read/write.
3. Original request epoch: survives real initial Session/engine creation; cancellation while a replacement factory suspends invalidates admission and leaves canonical record bytes intact.
4. Original typed attachment actor: native image bytes; import/read/remove; reject foreign namespace/native session/MIME/size and wrong request turn; adopted record cannot be read through unbound legacy resolution.
5. Actual SDK tool adapter: original Session owner installs resolver; a real prepared native tool resolves original UI-run image while diagnostics uses a different ID; revoke blocks further resolution and no additional bytes are delivered.

The fifth method is an original product component regression, not a claim of full UI/Host acceptance or real OCR output.

## Affected existing validation

Rerun the original SessionOwner suite because session lifecycle and exact original-row validation changed. The prior 14 owner methods do not qualify for reuse solely on the new SHA.
Rerun original credential/provider SDK entry and memory/tool preparation coverage, and original AuthorizedAttachmentRegistry coverage in HanlinUnifiedHostServicesTests. SDK adapter tool execution/inline action regression is affected.
Tests outside the original DATA/Session/SDK adapter closure do not need broad reruns for this patch alone.

## Explicit remaining SDK05 limits

- Original APIKeys storage remains the original SwiftData field; this change is not a Keychain or plaintext-data migration.
- No CloudKit schema, account namespace, or account-switch notification is invented. local-personal-library remains the current namespace authority; actual account fencing and migration need their original owning lifecycle.
- MemoryStore.replace remains explicitly unsupported until a proven owned subset/migration exists.
- The real initial app image registration still uses the original legacy turn registration; the actual SDK read uses the typed port after authentic Session adoption. The typed import method is exercised by the native component contract; it is not falsely claimed as the app's pre-Session registration path.
- Separate Vision/TTS/model management credential and memory owners were not silently routed through this request owner.
- No physical-device file protection, CloudKit change/delete/account-switch, signed entitlements, process restart, all-device, or release acceptance is claimed.
