# Provider credential compatibility phase — unapplied proposal

## Status

Prepared against Hanlin source 048e431cc55b10290c03ec4b2c0162e5f9dfcf9c. The original source inputs still match checked HEAD ce2fb04e8a266759f6c9eed70fd2dda02029720d byte for byte. Root remains the sole canonical source writer.

credential-compatibility-phase.diff is the reviewable first phase. It changes 22 Swift files. git apply --check passed on the canonical checkout. Windows Swift 6.3.3 parsed all 22 changed files. These are source/syntax checks, not an Apple typecheck or native acceptance.

secure-write-activation-DO-NOT-APPLY.diff is a separate two-call-site proposal against phase1. Its apply check passed against the isolated proposed tree. It is NOT included in phase1, not applied, and not release-ready. It must wait for concrete older-host and cross-device rollout handling. No runtime UI approval switch was added.

Native scope: 11 new methods / 14 expanded cases, all NOT_RUN. Exact selectors are in native-selectors.txt. No CI operation, canonical edit, account action, secret migration, user-credential read, or Asana update was performed for this proposal.

## Original requirement and owner findings

Original SDK05 task 1220542199999956 calls for host-owned credentials, existing original stores/owners, reversible migrations/checkpoints, account/workspace/Space/app isolation, signed App Groups/Keychain boundaries, and backup/rollback/erasure behavior. It does not specify device-only storage for provider keys.

AppDataManager in AI_HLY/AI_HLY.swift includes APIKeys, SearchKeys and ToolKeys in its existing ModelContainer. Production uses CloudKit .automatic; native fixtures disable CloudKit. All three original key properties are ordinary String fields. Their model source files, container configuration, CloudKit container, bundle IDs and entitlements are unchanged by the proposal.

The app and Translation extension already declare group.com.itorah.chavrusachat and group.com.itorah.shared. These source declarations are not a signed cross-process proof. The old compact publisher writes the selected secret into the original App Group ScriptingExtensions/compact-agent-config.json; the Translation extension reads it through HanlinCompactAgentClient. That file route must be covered before any reference-only adoption can be called complete.

There is no original provider-specific local-only policy. Existing Runtime/MCP ThisDeviceOnly policies belong to different stores and do not define provider behavior. Existing CloudKit device access cannot be preserved merely by replacing a field with a device-only reference.

## What phase1 actually changes

- All original request readers resolve a legacy value or a versioned handle. A missing, malformed, wrong-kind or unsupported handle is never returned as the provider secret. The typed APIManager port retains its original namespace, request, owner epoch and model checks. The check after its await resolves the current original row again and compares exact UTF-8 bytes.
- The four original secret editors keep typed values in a transient draft. Existing fields change only on explicit Save. Parent-owned Search/Map/Weather drafts are discarded on sheet dismissal, including swipe dismissal. Failed initial resolution cannot silently become an empty save. Stale drafts/records fail before staging or committing.
- Existing legacy rows still save their original String representation. New custom providers still use that representation. These production routes call saveCompatible / insertCompatible, so phase1 does not activate handle-format persistence for current users. Already-secured rows are not downgraded to plaintext when edited.
- After a verified original-row commit, the draft records the new stored representation. Compact publication is a separate outcome: failure explicitly says the key was saved, offers a publication-only retry, and labels dismissal Close. Retry cannot recommit the key.
- The original selected compact configuration is refreshed after an existing API editor Save. It retains legacy behavior for legacy records. For a secured record it stores an empty legacy apiKey plus a separate optional credentialReference. Older compact clients therefore see an unconfigured empty key, not a handle masquerading as a secret.
- The current Translation host injects its own Keychain policy into the generic compact client. The client reloads the shared file and resolves at every request instead of retaining an old plaintext configuration indefinitely. Package code contains no new hardcoded service/access group.
- Automatic search reconciliation preserves the selected manual provider while a stored reference is unavailable. A delayed Keychain item does not silently switch the original stored selection to the keyless provider. Request-time resolution remains mandatory.

This phase is preparatory compatibility plus a concrete editor persistence fix. Legacy secrets continue to exist in the original SwiftData/CloudKit representation and in legacy compact configurations. It does NOT complete provider secret migration or SDK05.

Model management receives an explicit transient provider configuration from the secret editor. Discovery and capability probes use that configuration, including an explicitly empty credential, without re-reading or persisting the old row value. Their original request pipeline has an explicitly scoped URLSession for bounded consumer tests; production defaults remain URLSession.shared.

## Staged secure writer and recovery

The generic mechanism uses SecItemAdd/CopyMatching and an opaque versioned UUID handle, not an Apple persistent reference. The host provides the service, access group, synchronization and accessibility. Proposed production policy is synchronizable AfterFirstUnlock in the original shared group; native synthetic tests inject a unique service, no shared group and synchronization false.

Each new immutable Keychain payload contains the new secret and the exact previous stored representation. That predecessor can be a legacy value or another handle. Both remain inside Keychain; no plaintext migration journal or second model store is introduced. The new payload's full readback is compared byte for byte before its handle is returned. No SecItemUpdate/Delete is used in production.

The original row is checked before checkpointing other pending edits. The secure writer rechecks the original current/durable row after staging. It writes the handle only after Keychain verification, saves the original ModelContext, and verifies the original persistent identifier/value through a fresh context. A save failure rolls the context back. An uncertain post-commit readback never triggers speculative deletion or an automatic replacement with an older value.

Explicit restorePrevious reuses the same original row and keeps the current Keychain generation. It never runs at startup or on an ordinary read. Restoring a legacy predecessor deliberately restores the earlier representation for recovery; it is not a forensic erasure claim.

Local expected-value checks do not establish an atomic compare-and-swap across CloudKit replicas or independent processes. The original schema has no credential revision/lease. No account identity or new CloudKit schema was invented to conceal that limitation.

## Cross-device activation remains separate

The activation overlay routes the two explicit production Save/insert entry points to the staged secure writer. Before applying it:

1. Old full-host binaries still interpret APIKeys.key, SearchKeys.key and ToolKeys.key as raw secrets. They cannot consume handles. An old client may also overwrite a handle with a legacy value.
2. CloudKit and iCloud Keychain do not provide a joint transaction. A row can arrive before its item; iCloud Keychain may be disabled independently of CloudKit. Local readback cannot prove availability on another device.
3. Synchronizable items must avoid ThisDeviceOnly accessibility. Proposed AfterFirstUnlock retains background-access capability and supports encrypted-backup migration, but real signed device/sync/restore behavior has not been tested.
4. The original App Group is already shared by the existing products/extensions. Source entitlements do not prove the active provisioning/signing identity, nor introduce account/Space isolation.
5. Retained generations permit recovery but do not implement orphan cleanup, account logout/erase, Keychain/iCloud erasure, backup expiry, or SQLite/WAL sanitization.

Do not publish the activation overlay as completion of these gates. No credentials need to be read or migrated to review and test phase1.

## Native verification

New methods in the original HanlinAppAgentSessionOwnerTests suite:

| Method | Expanded cases | Evidence it must establish |
|---|---:|---|
| originalProviderCredentialRowsReopenAndRecoverWithoutSchemaChanges(kind:) | 3 | Actual APIKeys/SearchKeys/ToolKeys disk rows retain identity, reopen with resolved Keychain values, and explicitly recover their legacy predecessor without deleting a generation. |
| originalCredentialEditorRemainsTransientAndLegacyCompatible() | 1 | Draft typing/cancellation do not write the original context; explicit legacy Save stays legacy, and a stale draft cannot overwrite it. |
| originalCredentialStaleContextCannotCheckpointOverNewerSavedValue() | 1 | An independent original ModelContext's newer credential survives a stale editor with unrelated unsaved URL changes. |
| originalSecuredCredentialRotationRetainsPredecessorAndRejectsStaleDraft() | 1 | A secured edit creates a new generation, retains its predecessor, rejects stale edits and blocks untouched empty saves after a failed read. |
| originalDiscoveryAndProbesUseUnsavedCredentialWithoutImplicitFallback(storedKey:) | 2 | Real original discovery/probe request construction uses the unsaved draft for first entry and rotation; explicit empty/no override/foreign provider semantics are checked through a scoped in-process transport, with no network or persistence. |
| originalCredentialCommitSurvivesPublicationFailureAndRetryDoesNotResave() | 1 | Real original-row commit survives an actual file publication failure, returns the saved/needs-retry outcome, and publication-only retry preserves reference, timestamp and generation count. |
| originalCredentialStageFailureLeavesOriginalDiskRowUnchanged() | 1 | Actual SecItemAdd rejection for an invalid explicit access group leaves the original disk row unchanged. |
| originalCredentialReadOnlySaveRetainsStagedRecoveryWithoutReplacingLegacyRow() | 1 | Actual Keychain staging succeeds; original read-only SwiftData save fails; rollback preserves the original row and retains recovery data. |
| originalCredentialHandlesFailClosedAndPreserveCurrentRequestAuthority() | 1 | Original typed credential port resolves actual Keychain data, rejects wrong-kind/future/missing handles, distinguishes canonically equivalent but byte-different secrets, and respects owner revocation. |
| originalSecuredSearchSelectionSurvivesUnavailableKeychain() | 1 | Actual original migration does not activate another provider because a reference is temporarily unavailable. |
| originalCompactPublisherExportsOnlySecuredReferenceAndRetainsLegacyCompatibility() | 1 | Actual original publisher/file store retains legacy interoperability, emits no plaintext for a secured row, requires injected resolution, and does not delete a shared credential when config is cleared. |

The fixture operates only on generated synthetic strings, a unique non-synchronizable Keychain service and a temporary original SwiftData file. Its explicit cleanup is scoped to that unique service/directory. Production code has no item-deletion path.

Retain the existing originalCredentialPortRejectsForeignModelNamespaceRequestAndDeletedOrigin() native control. Existing HanlinScriptExtensions package compactAgentConfigStoreLifecycle() is a separate unchanged legacy round-trip control. The Apple typecheck must cover both the app and Translation extension.

## Primary API evidence

Six official Apple DocC responses were retrieved with HTTP 200 and hashed in official-api/receipt.json; full responses remain external evidence.

- [Keychain sharing](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps): existing App Group names can serve as Keychain access groups without adding them to the Keychain Access Groups entitlement. Explicit empty groups are invalid; matching source entitlements still require actual signed verification.
- [Synchronizable items](https://developer.apple.com/documentation/security/ksecattrsynchronizable): synchronization must be explicitly requested; ThisDeviceOnly accessibility and persistent references are unsuitable for cross-device items. Updates/deletes can affect all copies.
- [AfterFirstUnlock](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlock): supports access after the first unlock and migration through encrypted backups.
- [Data Protection Keychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain): explicitly selects the data-protection implementation on macOS; safe on other Apple platforms.
- [PersistentModel](https://developer.apple.com/documentation/swiftdata/persistentmodel): original modelContext, persistentModelID and isDeleted are public APIs.
- [ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext): original save/rollback/independent contexts support the scoped persistence checks; none is a cross-device transaction guarantee.

## Material limits

No Apple typecheck, Security execution, SwiftData execution, UI interaction, signed App Group transfer, physical-device protection, cross-device iCloud Keychain/CloudKit synchronization, or release acceptance has been run for this packet. Windows parsing cannot establish them. The invalid-access-group and read-only-store tests are intentionally real failures; if the native environment behaves differently, inspect that evidence instead of weakening them.

## Review revision

Version1 source/report/evidence is preserved in review-v1-434dce8e.zip (SHA256 6cc4f479e5d01dcbd3338e33ac06f69fea223373218a3756eb3a2d4e53215293). Version2 fixes the independently observed unsaved-model-discovery regression and the misleading post-commit compact-publication failure outcome. The activation overlay remains inactive and requires a concrete rollout design; it is not part of this repair.
